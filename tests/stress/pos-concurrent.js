// tests/stress/pos-concurrent.js
// Clone-only POS posting stress harness.
// Uses the deployed create_auto_journal(uuid,text,text,date,jsonb,text,text,text)
// contract and provisions a synthetic authenticated identity on the isolated clone.

import { createClient } from '@supabase/supabase-js';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { performance } from 'node:perf_hooks';

const CLONE_REF = 'txwzhesvcjftybrlhnzs';
const BLOCKED_REFS = new Set(['cztlmwzfrhyafgawphgw']);
const REQUEST_TIMEOUT_MS = 30_000;
const START = '<!-- STRESS_METRICS_START -->';
const END = '<!-- STRESS_METRICS_END -->';
const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(SCRIPT_DIR, '../..');

function parseProfileArgs(argv) {
  let vus = Number(process.env.STRESS_VUS || 50);
  let durationSeconds = Number(process.env.STRESS_DURATION_SECONDS || 600);

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    if (arg === '--help' || arg === '-h') {
      console.log('Usage: node pos-concurrent.js [--vus=N] [--duration=SECONDS]');
      console.log('Defaults: --vus=50 --duration=600. Environment overrides: STRESS_VUS, STRESS_DURATION_SECONDS.');
      process.exit(0);
    }
    const match = arg.match(/^--(vus|duration)(?:=(.*))?$/);
    if (!match) throw new Error('Unknown argument: ' + arg + '. Use --vus=N and --duration=SECONDS.');
    const name = match[1];
    let raw = match[2];
    if (raw === undefined) {
      const next = argv[i + 1];
      if (next === undefined || next.startsWith('--')) throw new Error('Missing value for --' + name + '.');
      raw = next;
      i += 1;
    }
    if (!/^\d+$/.test(raw) || Number(raw) < 1) throw new Error('--' + name + ' must be a positive integer.');
    if (name === 'vus') vus = Number(raw);
    else durationSeconds = Number(raw);
  }
  return { VUS: vus, DURATION_SECONDS: durationSeconds };
}

const { VUS, DURATION_SECONDS } = parseProfileArgs(process.argv.slice(2));

function requiredEnv(name) {
  const value = process.env[name] && process.env[name].trim();
  if (!value) throw new Error('Missing required environment variable: ' + name);
  return value;
}

function guardClone(urlText) {
  if (process.env.STRESS_ENV !== 'clone') throw new Error('Refusing to run: STRESS_ENV=clone is required.');
  const url = new URL(urlText);
  const host = url.hostname.toLowerCase();
  const match = host.match(/^([a-z0-9-]+)\.supabase\.co$/);
  if (!match) throw new Error('Refusing to run against an unknown/custom Supabase host.');
  const ref = match[1];
  if (ref !== CLONE_REF || ref !== requiredEnv('STRESS_CLONE_PROJECT_REF')) {
    throw new Error('Refusing to run: URL must identify the authorized clone ' + CLONE_REF + '.');
  }
  const blocked = new Set(BLOCKED_REFS);
  for (const item of (process.env.SUPABASE_PROD_PROJECT_REF || '').split(',').map((x) => x.trim()).filter(Boolean)) {
    blocked.add(item);
  }
  if (blocked.has(ref)) throw new Error('Refusing to run against a live/protected project ref.');
  return ref;
}

function timeoutFetch(input, init = {}) {
  const deadline = AbortSignal.timeout(REQUEST_TIMEOUT_MS);
  const signal = init.signal ? AbortSignal.any([init.signal, deadline]) : deadline;
  return fetch(input, { ...init, signal });
}

function failQuery(label, error) {
  if (error) throw new Error(label + ': ' + (error.message || String(error)));
}

async function chooseStressTenant(admin) {
  const preferred = (process.env.STRESS_TENANT_NAME || 'TENANT_B_TEST').trim();
  const allowed = ['TENANT_B_TEST', 'STRESS_TEST_TENANT'];
  if (!allowed.includes(preferred)) throw new Error('STRESS_TENANT_NAME must be TENANT_B_TEST or STRESS_TEST_TENANT.');
  const candidates = [preferred, ...allowed.filter((name) => name !== preferred)];
  for (const name of candidates) {
    const result = await admin.from('accounting_tenants')
      .select('tenant_id,name,status')
      .eq('name', name)
      .maybeSingle();
    failQuery('Stress tenant lookup failed', result.error);
    if (result.data) {
      if (result.data.status !== 'active') throw new Error('Stress tenant exists but is not active: ' + name);
      return result.data;
    }
  }
  throw new Error('No TENANT_B_TEST or STRESS_TEST_TENANT exists; run the clone-only fixture step first.');
}

async function ensurePosTenantMapping(admin, accountingTenantId, userId) {
  const mapResult = await admin.from('pos_accounting_tenant_map')
    .select('pos_tenant_id,is_active')
    .eq('accounting_tenant_id', accountingTenantId);
  failQuery('POS/accounting tenant-map lookup failed', mapResult.error);
  const rows = mapResult.data || [];
  const active = rows.filter((row) => row.is_active);
  if (active.length > 1) throw new Error('More than one active POS mapping exists for the stress accounting tenant.');
  if (active.length === 1) {
    const tenantResult = await admin.from('tenants')
      .select('tenant_id')
      .eq('tenant_id', active[0].pos_tenant_id)
      .maybeSingle();
    failQuery('Mapped POS tenant verification failed', tenantResult.error);
    if (!tenantResult.data) throw new Error('Active POS/accounting map points to a missing public.tenants row.');
    return active[0].pos_tenant_id;
  }
  if (rows.length > 0) throw new Error('Stress tenant has an inactive POS/accounting map; refusing to silently reactivate it.');

  const posTenantId = 'STRESS_' + crypto.randomUUID().replace(/-/g, '').slice(0, 16).toUpperCase();
  const tenantInsert = await admin.from('tenants').insert({
    tenant_id: posTenantId,
    toko_name: 'Clone-only Stress Test Tenant',
    paket: 'basic',
    package_id: 'com.btp.uat',
    features: { pos: true, akuntansi: true },
    max_user: 100,
    is_blocked: false,
    status: 'active'
  });
  failQuery('Could not create clone-only POS tenant configuration', tenantInsert.error);

  const mapInsert = await admin.from('pos_accounting_tenant_map').insert({
    pos_tenant_id: posTenantId,
    accounting_tenant_id: accountingTenantId,
    is_active: true,
    created_by: userId
  });
  failQuery('Could not create clone-only POS/accounting tenant map', mapInsert.error);
  return posTenantId;
}

async function provisionIdentity(admin, anonClient, tenant) {
  const email = 'stress-' + crypto.randomUUID() + '@berkah.test';
  const password = crypto.randomBytes(32).toString('base64url');
  const created = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    app_metadata: { clone_stress_fixture: true }
  });
  failQuery('Could not create synthetic clone-only auth user', created.error);
  if (!created.data || !created.data.user || !created.data.user.id) {
    throw new Error('Auth admin did not return a user id for the stress fixture.');
  }
  const userId = created.data.user.id;

  const accountingMembership = await admin.from('accounting_memberships').insert({
    tenant_id: tenant.tenant_id,
    user_id: userId,
    role: 'owner',
    is_active: true
  });
  failQuery('Could not create active accounting membership for the synthetic user', accountingMembership.error);

  const posTenantId = await ensurePosTenantMapping(admin, tenant.tenant_id, userId);
  const deviceId = 'stress-device-' + crypto.randomUUID();
  const deviceInsert = await admin.from('devices').insert({
    device_id: deviceId,
    user_id: userId,
    tenant_id: posTenantId,
    platform: 'android_direct',
    app_version: 'stress-harness/2',
    package_id: 'com.btp.uat',
    hardware_mode: 'SIMULATED'
  });
  failQuery('Could not bind the stress device to the synthetic auth user', deviceInsert.error);

  const posMembershipCount = await admin.from('pos_memberships')
    .select('user_id', { count: 'exact', head: true });
  failQuery('Could not inspect public.pos_memberships', posMembershipCount.error);
  const wasEmpty = posMembershipCount.count === 0;
  const posMembershipInsert = await admin.from('pos_memberships').insert({
    tenant_id: posTenantId,
    user_id: userId,
    role: 'owner',
    is_active: true
  });
  failQuery('Could not create active public POS membership for the stress identity', posMembershipInsert.error);
  if (wasEmpty) console.log('Provisioned the first public.pos_memberships row for the clone-only stress identity.');

  const signIn = await anonClient.auth.signInWithPassword({ email, password });
  failQuery('Could not obtain a genuine authenticated session for the stress identity', signIn.error);
  if (!signIn.data || !signIn.data.session || !signIn.data.user || signIn.data.user.id !== userId) {
    throw new Error('Stress sign-in did not return the expected authenticated user.');
  }
  return { userId, deviceId, posTenantId };
}

async function ensureSelfTaxProfile(admin, tenantId, profileTemplateTenantId, businessDate, userId, deviceId) {
  const ownResult = await admin.from('tax_parties')
    .select('party_id,is_pkp,certificate_status')
    .eq('tenant_id', tenantId)
    .eq('party_kind', 'SELF')
    .lte('valid_from', businessDate)
    .or('valid_to.is.null,valid_to.gte.' + businessDate);
  failQuery('Tenant SELF tax profile lookup failed', ownResult.error);

  const ownRows = ownResult.data || [];
  const eligible = ownRows.filter((row) =>
    (row.is_pkp === true && row.certificate_status === 'VALID') ||
    (row.is_pkp === false && ['VALID', 'NOT_REQUIRED'].includes(row.certificate_status))
  );
  if (eligible.length === 1 && ownRows.length === 1) return;
  if (ownRows.length > 0) {
    throw new Error('TENANT_B_TEST has an overlapping SELF tax-party fixture that is not uniquely eligible; refusing to overwrite it.');
  }

  let templateQuery = admin.from('tax_parties')
    .select('is_pkp,tax_regime,taxpayer_type,legal_basis,valid_from,valid_to,certificate_status,turnover_eligibility,tax_object,is_withholding_agent')
    .eq('party_kind', 'SELF')
    .eq('is_pkp', false)
    .eq('certificate_status', 'NOT_REQUIRED')
    .lte('valid_from', businessDate)
    .or('valid_to.is.null,valid_to.gte.' + businessDate)
    .limit(1);
  if (profileTemplateTenantId) templateQuery = templateQuery.eq('tenant_id', profileTemplateTenantId);
  let templateResult = await templateQuery.maybeSingle();
  failQuery('Could not load a non-personal tax fixture template', templateResult.error);
  if (!templateResult.data && profileTemplateTenantId) {
    templateResult = await admin.from('tax_parties')
      .select('is_pkp,tax_regime,taxpayer_type,legal_basis,valid_from,valid_to,certificate_status,turnover_eligibility,tax_object,is_withholding_agent')
      .eq('party_kind', 'SELF')
      .eq('is_pkp', false)
      .eq('certificate_status', 'NOT_REQUIRED')
      .lte('valid_from', businessDate)
      .or('valid_to.is.null,valid_to.gte.' + businessDate)
      .limit(1)
      .maybeSingle();
    failQuery('Could not load a non-personal tax fixture template', templateResult.error);
  }
  if (!templateResult.data) throw new Error('No valid non-PKP SELF tax template exists on the clone; refusing to invent tax-regime values.');

  const source = templateResult.data;
  const insert = await admin.from('tax_parties').insert({
    tenant_id: tenantId,
    party_kind: 'SELF',
    display_name: 'Clone-only Stress Test Tenant',
    npwp: null,
    nik: null,
    nitku: null,
    is_pkp: false,
    tax_regime: source.tax_regime,
    legal_basis: 'Clone-only automated transaction test',
    taxpayer_type: source.taxpayer_type,
    valid_from: businessDate,
    valid_to: null,
    certificate_status: 'NOT_REQUIRED',
    turnover_eligibility: source.turnover_eligibility,
    tax_object: source.tax_object,
    metadata: { clone_stress_fixture: true },
    actor_user_id: userId,
    device_id: deviceId,
    reason: '50-VU acceptance stress fixture',
    is_withholding_agent: false
  }).select('party_id').single();
  failQuery('Could not create synthetic SELF tax profile for the test tenant', insert.error);
}

async function ensureServiceProfile(admin, tenantId, businessDate, userId, deviceId) {
  const existing = await admin.from('service_tax_profiles')
    .select('service_profile_id,unit_price')
    .eq('tenant_id', tenantId)
    .eq('unit_price', 10000)
    .lte('valid_from', businessDate)
    .or('valid_to.is.null,valid_to.gte.' + businessDate)
    .limit(1)
    .maybeSingle();
  failQuery('Tenant service-tax profile lookup failed', existing.error);
  if (existing.data) return existing.data.service_profile_id;

  const sourceResult = await admin.from('service_tax_profiles')
    .select('tenant_id,vat_exempt,vat_object_code,legal_basis,pph23_object_code,umkm_final_eligible')
    .eq('unit_price', 10000)
    .lte('valid_from', businessDate)
    .or('valid_to.is.null,valid_to.gte.' + businessDate)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  failQuery('Could not load a service-tax fixture template', sourceResult.error);
  if (!sourceResult.data) throw new Error('No valid service-tax template priced at IDR 10,000 exists on the clone.');

  const source = sourceResult.data;
  const inserted = await admin.from('service_tax_profiles').insert({
    tenant_id: tenantId,
    service_code: 'STRESS-' + crypto.randomUUID().replace(/-/g, '').slice(0, 12).toUpperCase(),
    name_id: 'Clone-only Stress Test Service',
    vat_exempt: source.vat_exempt,
    vat_object_code: source.vat_object_code,
    valid_from: businessDate,
    valid_to: null,
    legal_basis: 'Clone-only automated transaction test',
    actor_user_id: userId,
    device_id: deviceId,
    reason: '50-VU acceptance stress fixture',
    unit_price: 10000,
    pph23_object_code: source.pph23_object_code,
    umkm_final_eligible: source.umkm_final_eligible
  }).select('service_profile_id').single();
  failQuery('Could not create service-tax profile for the test tenant', inserted.error);
  return inserted.data.service_profile_id;
}

async function ensureOpenBusinessDate(admin, tenantId, businessDate) {
  const result = await admin.from('accounting_periods')
    .select('period_start,period_end,status')
    .eq('tenant_id', tenantId)
    .lte('period_start', businessDate)
    .gte('period_end', businessDate);
  failQuery('Could not validate the stress business date against accounting periods', result.error);
  const closed = (result.data || []).filter((row) => row.status !== 'open');
  if (closed.length > 0) throw new Error('Stress business date falls in a closed accounting period; refusing to post.');
}

function percentile(values, p) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.max(0, Math.ceil(p * sorted.length / 100) - 1)];
}

function ms(value) {
  return value == null ? 'N/A' : value.toFixed(2) + ' ms';
}

async function exactDuplicateCount(admin) {
  const { count, error } = await admin.from('v_stress_validation')
    .select('tenant_id,transaction_ref,journal_count', { count: 'exact', head: true });
  failQuery('v_stress_validation query failed', error);
  if (count == null) throw new Error('Duplicate count was not exact; validation is inconclusive.');
  return count;
}

async function validateBalances(admin, tenantId, everyRef, successfulRefs) {
  const rows = [];
  const refs = [...new Set(everyRef)];
  for (let i = 0; i < refs.length; i += 100) {
    const { data, error } = await admin.from('accounting_journals')
      .select('tenant_id,transaction_ref,total_debit,total_credit')
      .eq('tenant_id', tenantId)
      .in('transaction_ref', refs.slice(i, i + 100));
    failQuery('Journal balance query failed', error);
    rows.push(...(data || []));
  }
  const found = new Set(rows.map((row) => row.transaction_ref));
  const unbalanced = rows.filter((row) =>
    row.total_debit == null ||
    row.total_credit == null ||
    Number(row.total_debit) !== Number(row.total_credit)
  );
  const missing = [...new Set(successfulRefs)].filter((ref) => !found.has(ref));
  return { rows: rows.length, unbalanced, missing };
}

async function validateConsistency(admin) {
  const { data, error } = await admin.rpc('validate_journal_consistency');
  failQuery('validate_journal_consistency RPC failed', error);
  if (!Array.isArray(data)) throw new Error('validate_journal_consistency returned an unexpected result.');
  return data.length;
}

async function appendMetrics(report) {
  const defaultTarget = path.join(REPO_ROOT, 'docs/audit/03-stress-metrics.md');
  const target = path.resolve(process.env.STRESS_METRICS_PATH || defaultTarget);
  await fs.mkdir(path.dirname(target), { recursive: true });
  let current;
  try {
    current = await fs.readFile(target, 'utf8');
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
    current = '# POS Concurrent Stress Metrics\n\n' + START + '\n_No stress run recorded yet._\n' + END + '\n';
  }
  const a = current.indexOf(START);
  const b = current.indexOf(END);
  if (a < 0 || b < a) throw new Error('Metrics file is missing its generated-report markers.');
  const previous = current.slice(a + START.length, b).trim();
  const retained = previous === '_No stress run recorded yet._' ? '' : previous;
  const combined = [retained, report.trim()].filter(Boolean).join('\n\n---\n\n');
  await fs.writeFile(target, current.slice(0, a + START.length) + '\n' + combined + '\n' + current.slice(b), 'utf8');
  return target;
}

async function main() {
  const url = requiredEnv('SUPABASE_URL');
  const projectRef = guardClone(url);
  const anonKey = requiredEnv('SUPABASE_ANON_KEY');
  const serviceRoleKey = requiredEnv('SUPABASE_SERVICE_ROLE_KEY');
  if (!Number.isSafeInteger(VUS) || VUS < 1 || !Number.isSafeInteger(DURATION_SECONDS) || DURATION_SECONDS < 1) {
    throw new Error('STRESS_VUS/--vus and STRESS_DURATION_SECONDS/--duration must be positive integers.');
  }

  const clientOptions = {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    global: { fetch: timeoutFetch }
  };
  const anonClient = createClient(url, anonKey, clientOptions);
  const admin = createClient(url, serviceRoleKey, clientOptions);
  const tenant = await chooseStressTenant(admin);
  const businessDate = new Date().toISOString().slice(0, 10);
  const identity = await provisionIdentity(admin, anonClient, tenant);
  const { userId, deviceId } = identity;
  await ensureOpenBusinessDate(admin, tenant.tenant_id, businessDate);

  const templateProfile = await admin.from('service_tax_profiles')
    .select('tenant_id')
    .eq('unit_price', 10000)
    .lte('valid_from', businessDate)
    .or('valid_to.is.null,valid_to.gte.' + businessDate)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();
  failQuery('Service-tax template tenant lookup failed', templateProfile.error);
  await ensureSelfTaxProfile(admin, tenant.tenant_id, templateProfile.data && templateProfile.data.tenant_id, businessDate, userId, deviceId);
  const serviceProfileId = await ensureServiceProfile(admin, tenant.tenant_id, businessDate, userId, deviceId);

  console.log('Clone target ref: ' + projectRef);
  console.log('Test tenant: ' + tenant.name + '; authenticated identity, active accounting/POS membership, and bound device provisioned on clone.');
  console.log('Using service_tax_profiles for the service line; no financial records were copied from the source project.');
  console.log('Running ' + VUS + ' concurrent RPC calls per wave for ' + DURATION_SECONDS + ' seconds.');

  const startedAt = new Date();
  const startClock = performance.now();
  const deadline = startClock + DURATION_SECONDS * 1000;
  const allLatencies = [];
  const successfulLatencies = [];
  const allRefs = [];
  const successfulRefs = [];
  const errors = [];
  let succeeded = 0;
  let failed = 0;

  async function runVU(vuId) {
    while (performance.now() < deadline) {
      const ref = 'STRESS-' + vuId + '-' + crypto.randomUUID();
      allRefs.push(ref);
      const started = performance.now();
      try {
        const { error } = await anonClient.rpc('create_auto_journal', {
          p_tenant_id: tenant.tenant_id,
          p_transaction_type: 'JUAL_TUNAI',
          p_transaction_ref: ref,
          p_business_date: businessDate,
          p_facts: {
            lines: [{
              qty: 1,
              kind: 'SERVICE',
              amount: 10000,
              line_key: ref,
              service_profile_id: serviceProfileId
            }]
          },
          p_device_id: deviceId,
          p_app_version: 'stress-harness/2',
          p_reason: '50-VU acceptance stress'
        });
        if (error) {
          failed += 1;
          if (errors.length < 20) errors.push({ code: error.code || 'RPC_ERROR', message: error.message || 'RPC failed' });
        } else {
          succeeded += 1;
          successfulRefs.push(ref);
          successfulLatencies.push(performance.now() - started);
        }
      } catch (error) {
        failed += 1;
        if (errors.length < 20) errors.push({ code: error.code || 'REQUEST_ERROR', message: error.message || String(error) });
      } finally {
        allLatencies.push(performance.now() - started);
      }

      if (performance.now() < deadline) {
        await new Promise((resolve) => setTimeout(resolve, 50 + Math.random() * 150));
      }
    }
  }

  await Promise.all(Array.from({ length: VUS }, (_, index) => runVU(index + 1)));

  const elapsed = (performance.now() - startClock) / 1000;
  let duplicates = null;
  let balance = null;
  let consistencyIssues = null;
  let validationError = null;
  try {
    duplicates = await exactDuplicateCount(admin);
    balance = await validateBalances(admin, tenant.tenant_id, allRefs, successfulRefs);
    consistencyIssues = await validateConsistency(admin);
  } catch (error) {
    validationError = error.message || String(error);
  }

  const finishedAt = new Date();
  const p95 = percentile(allLatencies, 95);
  const p99 = percentile(allLatencies, 99);
  const successP95 = percentile(successfulLatencies, 95);
  const successP99 = percentile(successfulLatencies, 99);
  const attempts = allLatencies.length;
  const failureRate = attempts > 0 ? failed / attempts : 1;
  const missing = balance ? balance.missing.length : null;
  const unbalanced = balance ? balance.unbalanced.length : null;
  const passed = attempts > 0 &&
    failureRate < 0.01 &&
    duplicates === 0 &&
    validationError === null &&
    consistencyIssues === 0 &&
    missing === 0 &&
    unbalanced === 0;

  const errorReport = errors.length
    ? errors.slice(0, 5).map((e) => '- ' + e.code + ': ' + e.message.replace(/\s+/g, ' ').slice(0, 200)).join('\n')
    : 'None';
  const report = [
    '## Run ' + startedAt.toISOString(),
    '',
    '- **Status:** ' + (passed ? 'PASS' : 'FAIL'),
    '- **Target:** clone project ref ' + projectRef + '; test tenant ' + tenant.name + ' (user/device identifiers omitted)',
    '- **Profile:** ' + VUS + ' persistent virtual users; configured ' + DURATION_SECONDS + 's; elapsed ' + elapsed.toFixed(2) + 's',
    '- **Started / finished UTC:** ' + startedAt.toISOString() + ' / ' + finishedAt.toISOString(),
    '- **RPC attempts:** ' + attempts + '; successful ' + succeeded + '; failed ' + failed + '; failure rate ' + (failureRate * 100).toFixed(3) + '%',
    '- **Latency, all outcomes:** p95 ' + ms(p95) + '; p99 ' + ms(p99) + '; samples ' + attempts,
    '- **Latency, successful RPCs:** p95 ' + ms(successP95) + '; p99 ' + ms(successP99) + '; samples ' + successfulLatencies.length,
    '- **Duplicate groups in v_stress_validation:** ' + (duplicates == null ? 'VALIDATION ERROR' : duplicates),
    '- **Balance validation:** checked rows ' + (balance ? balance.rows : 'N/A') + '; missing refs ' + (missing == null ? 'N/A' : missing) + '; unbalanced rows ' + (unbalanced == null ? 'N/A' : unbalanced),
    '- **validate_journal_consistency issues:** ' + (consistencyIssues == null ? 'N/A' : consistencyIssues),
    '- **Validation error:** ' + (validationError ? validationError.replace(/\s+/g, ' ') : 'None'),
    '- **RPC error samples (maximum 5 shown):**',
    errorReport
  ].join('\n');

  const target = await appendMetrics(report);
  console.log(report);
  console.log('Metrics written to ' + target);
  if (!passed) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error.message || String(error));
  process.exitCode = 1;
});
