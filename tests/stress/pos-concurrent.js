import { createClient } from '@supabase/supabase-js';
import crypto from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { performance } from 'node:perf_hooks';

const BLOCKED_LIVE_REFS = new Set(['cztlmwzfrhyafgawphgw']);
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
    if (!match) {
      throw new Error('Unknown argument: ' + arg + '. Usage: node pos-concurrent.js [--vus=N] [--duration=SECONDS]');
    }

    const name = match[1];
    let raw = match[2];
    if (raw === undefined) {
      const next = argv[i + 1];
      if (next === undefined || next.startsWith('--')) {
        throw new Error('Missing value for --' + name + '.');
      }
      raw = next;
      i += 1;
    }
    if (!/^\d+$/.test(raw)) {
      throw new Error('--' + name + ' must be a positive integer.');
    }

    if (name === 'vus') vus = Number(raw);
    else durationSeconds = Number(raw);
  }

  return { VUS: vus, DURATION_SECONDS: durationSeconds };
}

const { VUS, DURATION_SECONDS } = parseProfileArgs(process.argv.slice(2));

function env(name) {
  const value = process.env[name]?.trim();
  if (!value) throw new Error('Missing required environment variable: ' + name);
  return value;
}

function envFirst(names) {
  for (const name of names) {
    const value = process.env[name]?.trim();
    if (value) return value;
  }
  throw new Error('Missing required environment variable: ' + names.join(' or '));
}

function guardClone(urlText) {
  if (process.env.STRESS_ENV !== 'clone') {
    throw new Error('Refusing to run: set STRESS_ENV=clone only for an isolated clone.');
  }
  const url = new URL(urlText);
  const host = url.hostname.toLowerCase();
  const local = ['localhost', '127.0.0.1', '::1'].includes(host);
  const match = host.match(/^([a-z0-9-]+)\.supabase\.co$/);
  if (!local && !match) throw new Error('Refusing to run against an unknown/custom host.');
  const ref = local ? 'local' : match[1];
  if (ref !== env('STRESS_CLONE_PROJECT_REF')) {
    throw new Error('Refusing to run: URL project ref does not match STRESS_CLONE_PROJECT_REF.');
  }
  const blocked = new Set(BLOCKED_LIVE_REFS);
  for (const item of (process.env.SUPABASE_PROD_PROJECT_REF || '').split(',').map((x) => x.trim()).filter(Boolean)) {
    blocked.add(item);
  }
  if (blocked.has(ref)) throw new Error('Refusing to run against a live/protected project ref.');
  return ref;
}

function percentile(values, p) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.max(0, Math.ceil(p * sorted.length / 100) - 1)];
}

function ms(value) {
  return value == null ? 'N/A' : value.toFixed(2) + ' ms';
}

function timeoutFetch(input, init = {}) {
  const timeout = AbortSignal.timeout(REQUEST_TIMEOUT_MS);
  const signal = init.signal ? AbortSignal.any([init.signal, timeout]) : timeout;
  return fetch(input, { ...init, signal });
}

async function exactDuplicateCount(admin) {
  const { count, error } = await admin
    .from('v_stress_validation')
    .select('tenant_id, transaction_ref, journal_count', { count: 'exact', head: true });
  if (error) throw new Error('v_stress_validation query failed: ' + error.message);
  if (count == null) throw new Error('Duplicate count was not exact; validation is inconclusive.');
  return count;
}

async function validateBalances(admin, tenantId, everyRef, successfulRefs) {
  const rows = [];
  const refs = [...new Set(everyRef)];
  for (let i = 0; i < refs.length; i += 100) {
    const { data, error } = await admin
      .from('accounting_journals')
      .select('tenant_id, transaction_ref, total_debit, total_credit')
      .eq('tenant_id', tenantId)
      .in('transaction_ref', refs.slice(i, i + 100));
    if (error) throw new Error('Journal balance query failed: ' + error.message);
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
  const url = env('SUPABASE_URL');
  const projectRef = guardClone(url);
  const anonKey = env('SUPABASE_ANON_KEY');
  const accessToken = env('SUPABASE_ACCESS_TOKEN');
  const serviceRoleKey = env('SUPABASE_SERVICE_ROLE_KEY');
  const tenantId = env('STRESS_TENANT_ID');
  const boundDevice = envFirst(['TEST_DEVICE_ID', 'STRESS_DEVICE_ID']);

  if (!Number.isSafeInteger(VUS) || VUS < 1 || !Number.isSafeInteger(DURATION_SECONDS) || DURATION_SECONDS < 1) {
    throw new Error('STRESS_VUS/--vus and STRESS_DURATION_SECONDS/--duration must be positive integers.');
  }
  const rpc = createClient(url, anonKey, {
    accessToken: async () => accessToken,
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    global: { fetch: timeoutFetch },
  });
  const admin = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    global: { fetch: timeoutFetch },
  });

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
  let waves = 0;

  console.log('Clone target ref: ' + projectRef);
  console.log('Running ' + VUS + ' concurrent RPC calls per wave for ' + DURATION_SECONDS + ' seconds.');
  console.log('Calls use supabase.rpc(create_auto_journal) with JUAL_TUNAI.');

  while (performance.now() < deadline) {
    waves += 1;
    const wave = Array.from({ length: VUS }, () => {
      if (performance.now() >= deadline) return null;
      const ref = crypto.randomUUID();
      allRefs.push(ref);
      return (async () => {
        const started = performance.now();
        let ok = false;
        try {
          const { error } = await rpc.rpc('create_auto_journal', {
            p_tenant_id: tenantId,
            p_transaction_type: 'JUAL_TUNAI',
            p_transaction_ref: ref,
            p_payload: { qty: 1 },
            p_device_id: boundDevice,
          });
          if (error) {
            failed += 1;
            if (errors.length < 20) errors.push({ code: error.code || 'RPC_ERROR', message: error.message || 'RPC failed' });
          } else {
            ok = true;
            succeeded += 1;
            successfulRefs.push(ref);
          }
        } catch (error) {
          failed += 1;
          if (errors.length < 20) errors.push({ code: error.code || 'REQUEST_ERROR', message: error.message || String(error) });
        } finally {
          allLatencies.push(performance.now() - started);
          if (ok) successfulLatencies.push(allLatencies[allLatencies.length - 1]);
        }
      })();
    }).filter(Boolean);
    await Promise.all(wave);
  }

  const elapsed = (performance.now() - startClock) / 1000;
  let duplicates = null;
  let balance = null;
  let validationError = null;
  try {
    duplicates = await exactDuplicateCount(admin);
    balance = await validateBalances(admin, tenantId, allRefs, successfulRefs);
  } catch (error) {
    validationError = error.message || String(error);
  }

  const finishedAt = new Date();
  const p95 = percentile(allLatencies, 95);
  const p99 = percentile(allLatencies, 99);
  const successP95 = percentile(successfulLatencies, 95);
  const successP99 = percentile(successfulLatencies, 99);
  const missing = balance ? balance.missing.length : null;
  const unbalanced = balance ? balance.unbalanced.length : null;
  const passed = allLatencies.length > 0 && failed === 0 && duplicates === 0 &&
    validationError === null && missing === 0 && unbalanced === 0;
  const errorReport = errors.length
    ? errors.slice(0, 5).map((e) => '- ' + e.code + ': ' + e.message.replace(/\s+/g, ' ').slice(0, 200)).join('\n')
    : 'None';
  const report = [
    '## Run ' + startedAt.toISOString(),
    '',
    '- **Status:** ' + (passed ? 'PASS' : 'FAIL'),
    '- **Target:** clone project ref ' + projectRef + ' (tenant/device identifiers omitted)',
    '- **Profile:** ' + VUS + ' concurrent RPCs per wave; configured ' + DURATION_SECONDS + 's; elapsed ' + elapsed.toFixed(2) + 's; waves ' + waves,
    '- **Started / finished UTC:** ' + startedAt.toISOString() + ' / ' + finishedAt.toISOString(),
    '- **RPC attempts:** ' + allLatencies.length + '; successful ' + succeeded + '; failed ' + failed,
    '- **Latency, all outcomes:** p95 ' + ms(p95) + '; p99 ' + ms(p99) + '; samples ' + allLatencies.length,
    '- **Latency, successful RPCs:** p95 ' + ms(successP95) + '; p99 ' + ms(successP99) + '; samples ' + successfulLatencies.length,
    '- **Duplicate groups in v_stress_validation:** ' + (duplicates == null ? 'VALIDATION ERROR' : duplicates),
    '- **Balance validation:** checked rows ' + (balance ? balance.rows : 'N/A') + '; missing refs ' + (missing == null ? 'N/A' : missing) + '; unbalanced rows ' + (unbalanced == null ? 'N/A' : unbalanced),
    '- **Validation error:** ' + (validationError ? validationError.replace(/\s+/g, ' ') : 'None'),
    '- **RPC error samples (maximum 5 shown):**',
    errorReport,
  ].join('\n');

  const target = await appendMetrics(report);
  console.log(report);
  console.log('Metrics written to ' + target);
  if (!passed) process.exitCode = 1;
}

main().catch((error) => {
  console.error(error.message || error);
  process.exitCode = 1;
});