import http from 'k6';
import { check, fail } from 'k6';
import { Counter } from 'k6/metrics';

const baseUrl = (__ENV.BASE_URL || '').replace(/\/+$/, '');
const token = __ENV.K6_AUTH_TOKEN || '';
const tenantId = __ENV.K6_TENANT_ID || '';
const devicePrefix = __ENV.K6_DEVICE_ID_PREFIX || '';
const productId = __ENV.K6_PRODUCT_ID || 'phase6-k6-product';
const runId = __ENV.K6_RUN_ID || ('phase6-' + Date.now());
const submitted = new Counter('offline_sync_events_submitted');
const accepted = new Counter('offline_sync_events_accepted');

if (!baseUrl || !token || !tenantId || !devicePrefix) {
  throw new Error('BASE_URL, K6_AUTH_TOKEN, K6_TENANT_ID and K6_DEVICE_ID_PREFIX are required.');
}

export const options = {
  scenarios: {
    offline_sync_reconnect_burst: {
      executor: 'shared-iterations',
      vus: 50,
      iterations: 50,
      maxDuration: '180s',
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<2000'],
    checks: ['rate>0.99'],
  },
};

function saleEvent(vu, index) {
  const id = runId + '-device-' + vu + '-sale-' + index;
  return {
    id,
    idempotency_key: id,
    entity_type: 'sale',
    entity_id: id,
    payload: {
      sale_id: id,
      transaction_id: id,
      payment_method: 'cash',
      occurred_at_utc: new Date().toISOString(),
      business_date: new Date().toISOString().slice(0, 10),
      grand_total: 1000,
      ppn_amount: 0,
      transaction_discount_amount: 0,
      items: [{
        product_id: productId,
        quantity: 1,
        unit_price: 1000,
        item_discount_amount: 0,
      }],
    },
  };
}

export default function () {
  const events = [0, 1, 2, 3].map((i) => saleEvent(__VU, i));
  submitted.add(events.length);
  const response = http.post(baseUrl + '/api/v1/sync', JSON.stringify({
    tenant_id: tenantId,
    device_id: devicePrefix + __VU,
    batch_id: runId + '-device-' + __VU,
    events,
  }), {
    headers: {
      Authorization: 'Bearer ' + token,
      'Content-Type': 'application/json',
      Accept: 'application/json',
      Host: 'central.test',
      'X-Request-Id': runId + '-device-' + __VU,
    },
    tags: { endpoint: 'offline-sync-burst' },
    timeout: '45s',
  });

  let result = null;
  try { result = response.json(); } catch (_) { result = null; }
  const acceptedIds = result && Array.isArray(result.accepted_event_ids)
    ? result.accepted_event_ids : [];
  const uniqueAccepted = new Set(acceptedIds);
  const allAccepted = events.every((event) => uniqueAccepted.has(event.id));
  const noConflicts = result && Array.isArray(result.conflicts) && result.conflicts.length === 0;

  const ok = check(response, {
    'sync endpoint returns 200': (r) => r.status === 200,
    'all 4 events receive durable acceptance': () => allAccepted,
    'accepted IDs are unique': () => uniqueAccepted.size === acceptedIds.length,
    'no conflicts returned': () => noConflicts,
  });
  if (ok && allAccepted) accepted.add(events.length);
  if (response.status === 404) fail('POST /api/v1/sync was not registered or central host routing was rejected.');
}

export function handleSummary(data) {
  return {
    'docs/evidence/k6-offline-sync-burst-summary.json': JSON.stringify({
      run_id: runId,
      scenario: '50 devices reconnect simultaneously, 4 sale events/device, 200 events total',
      http_req_failed: data.metrics.http_req_failed,
      http_req_duration: data.metrics.http_req_duration,
      checks: data.metrics.checks,
      offline_sync_events_submitted: data.metrics.offline_sync_events_submitted,
      offline_sync_events_accepted: data.metrics.offline_sync_events_accepted,
      result: data.metrics.http_req_failed && data.metrics.http_req_failed.values.rate < 0.01 ? 'thresholds-evaluated' : 'check-failed',
      limitation: 'CI runner results do not constitute KVM2 host high-water evidence or a tenant-capacity/SLA claim.',
    }, null, 2) + '\n',
    stdout: 'k6 offline-sync burst summary written to docs/evidence/k6-offline-sync-burst-summary.json\n',
  };
}
