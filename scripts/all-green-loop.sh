#!/usr/bin/env bash
set -euo pipefail
SOURCE_REF="cztlmwzfrhyafgawphgw"
CLONE_REF="txwzhesvcjftybrlhnzs"
EXPECTED_CONFIG_COUNT=352
EXPECTED_KEYSET_MD5="1fd3d64219ecc7c333453c20da80e295"
EXPECTED_AAB_SHA256="4ff5661bcd64d75c216c176dd3db49d0b26905243b0ec0e72390b558dd136871"
EXPECTED_CRASH_JOURNAL_ID="21e09fe8-ccd9-4055-9da1-f7ea3d4b20e1"
EXPECTED_MAP_COUNT=21
EXPECTED_SOURCE_SUM=502300
EXPECTED_CLONE_TEST_SUM=30500
BASELINE_SOURCE_SUM=""
BASELINE_CLONE_TEST_SUM=""
BASELINE_CLONE_TOTAL_SUM=""
MAX_ATTEMPTS="${ALL_GREEN_MAX_ATTEMPTS:-1}"
MODE=""
for arg in "$@"; do
  case "$arg" in
    --validate-only|--full) [[ -z "$MODE" ]] || { echo "Choose one mode only" >&2; exit 2; }; MODE="$arg" ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done
[[ -n "$MODE" ]] || { echo "Usage: $0 --validate-only | --full" >&2; exit 2; }
[[ "$MAX_ATTEMPTS" =~ ^[1-9][0-9]*$ ]] || { echo "ALL_GREEN_MAX_ATTEMPTS must be positive" >&2; exit 2; }
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MAP_FILE="$ROOT/docs/audit/transaction-type-map.expected.tsv"
RLS_MIGRATION="$ROOT/supabase/migrations/202610100002_fix_rls_tenant_links.sql"
HELPERS_FILE="$ROOT/supabase/migrations/staging_clone_rls_test_helpers.sql"
LOG_FILE="${ALL_GREEN_LOG_FILE:-${TMPDIR:-/tmp}/berkah-all-green-loop.log}"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -a "$LOG_FILE") 2>&1
log() { printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"; }
fatal() { log "FATAL: $*"; exit 2; }
declare -A STATUS=() DETAIL=()
FAILURES=0
STRESS_EXECUTED=0
pass_check() { STATUS["$1"]="PASS"; DETAIL["$1"]="$2"; log "CHECK $1 PASS: $2"; }
fail_check() { STATUS["$1"]="FAIL"; DETAIL["$1"]="$2"; FAILURES=$((FAILURES+1)); log "CHECK $1 FAIL: $2"; }
skip_check() { STATUS["$1"]="SKIP"; DETAIL["$1"]="$2"; log "CHECK $1 SKIP: $2"; }
require_env() { local n; for n in "$@"; do [[ -n "${!n:-}" ]] || fatal "required environment variable $n is unset; value not logged"; done; }
check_deps() {
  local d; local deps=(psql supabase sha256sum awk)
  [[ "$MODE" != "--full" ]] || deps+=(curl jq openssl node timeout)
  for d in "${deps[@]}"; do command -v "$d" >/dev/null 2>&1 || fatal "missing command: $d"; done
}
sql_source() { psql "$SOURCE_DB_URL" -X -qAt -v ON_ERROR_STOP=1 -c "$1"; }
sql_clone() { psql "$CLONE_DB_URL" -X -qAt -v ON_ERROR_STOP=1 -c "$1"; }
sql_clone_vars() { psql "$CLONE_DB_URL" -X -qAt -v ON_ERROR_STOP=1 "$@"; }
check_endpoint_ids() {
  require_env SOURCE_DB_URL CLONE_DB_URL
  [[ "$SOURCE_DB_URL" == *"$SOURCE_REF"* && "$SOURCE_DB_URL" != *"$CLONE_REF"* ]] || fatal "SOURCE_DB_URL ref validation failed"
  [[ "$CLONE_DB_URL" == *"$CLONE_REF"* && "$CLONE_DB_URL" != *"$SOURCE_REF"* ]] || fatal "CLONE_DB_URL ref validation failed"
  log "Validated source=$SOURCE_REF (read only), clone=$CLONE_REF (only write target)"
}
sql_quote() { printf "'%s'" "$1"; }
expected_values() {
  local t r rule v=""
  while IFS=$'\t' read -r t r rule; do
    [[ -z "$t" || "$t" == "p_transaction_type" ]] && continue
    v+="${v:+,}($(sql_quote "$t"),$(sql_quote "$r"))"
  done < "$MAP_FILE"
  printf '%s' "$v"
}
create_auth_user_if_missing() {
  local email="$1" count pwd body code
  count="$(sql_clone "SELECT count(*) FROM auth.users WHERE lower(email)=lower($(sql_quote "$email"));")" || return 1
  [[ "$count" =~ ^[0-9]+$ ]] || return 1
  (( count > 0 )) && return 0
  pwd="$(openssl rand -hex 32)"
  body="$(jq -nc --arg email "$email" --arg password "$pwd" '{email:$email,password:$password,email_confirm:true,user_metadata:{all_green_loop_fixture:true}}')"
  code="$(curl -sS --output "${TMPDIR:-/tmp}/all-green-auth-response.json" --write-out '%{http_code}' -X POST \
    -H "apikey: $CLONE_SERVICE_KEY" -H "Authorization: Bearer $CLONE_SERVICE_KEY" -H 'Content-Type: application/json' \
    --data "$body" "https://$CLONE_REF.supabase.co/auth/v1/admin/users")" || return 1
  unset pwd body
  [[ "$code" =~ ^2[0-9][0-9]$ ]] && return 0
  count="$(sql_clone "SELECT count(*) FROM auth.users WHERE lower(email)=lower($(sql_quote "$email"));")" || return 1
  [[ "$count" == "1" ]]
}
ensure_proof_fixture() {
  local count
  count="$(sql_clone "SELECT count(*) FROM public.accounting_journals j JOIN public.accounting_tenants t USING(tenant_id) WHERE j.transaction_ref='PROOF-B-001' AND t.name='TENANT_B_TEST';")" || return 1
  [[ "$count" =~ ^[0-9]+$ ]] || return 1
  (( count > 0 )) && return 0
  create_auth_user_if_missing test_a@berkah.test || return 1
  create_auth_user_if_missing test_b@berkah.test || return 1
  psql "$CLONE_DB_URL" -X -v ON_ERROR_STOP=1 <<'SQL'
DO $fixture$
DECLARE ua uuid; ub uuid; tid uuid; jid uuid;
BEGIN
 SELECT id INTO STRICT ua FROM auth.users WHERE lower(email)='test_a@berkah.test';
 SELECT id INTO STRICT ub FROM auth.users WHERE lower(email)='test_b@berkah.test';
 tid := private.create_test_tenant('TENANT_B_TEST');
 INSERT INTO public.accounting_memberships(tenant_id,user_id,role,is_active)
 VALUES(tid,ua,'owner',true) ON CONFLICT(tenant_id,user_id) DO UPDATE SET role=EXCLUDED.role,is_active=true;
 INSERT INTO public.accounting_memberships(tenant_id,user_id,role,is_active)
 VALUES(tid,ub,'accountant',true) ON CONFLICT(tenant_id,user_id) DO UPDATE SET role=EXCLUDED.role,is_active=true;
 IF NOT EXISTS(SELECT 1 FROM public.accounting_coa WHERE account_code='1-1010')
 OR NOT EXISTS(SELECT 1 FROM public.accounting_coa WHERE account_code='3-3010') THEN
   RAISE EXCEPTION 'proof fixture canonical COA accounts missing';
 END IF;
 SELECT journal_id INTO jid FROM public.accounting_journals WHERE tenant_id=tid AND transaction_ref='PROOF-B-001';
 IF jid IS NULL THEN
   INSERT INTO public.accounting_journals(tenant_id,idempotency_key,request_fingerprint,transaction_ref,journal_date,description,source_type,total_debit,total_credit,actor_user_id,actor_subject,device_id,app_version)
   VALUES(tid,'proof:PROOF-B-001','{"kind":"all-green-tenant-isolation-proof"}','PROOF-B-001',CURRENT_DATE,'Tenant isolation proof','manual',1000,1000,ua,'all-green-loop:test_a','ALL_GREEN_LOOP_PROOF','all-green-loop/1')
   RETURNING journal_id INTO jid;
   INSERT INTO public.accounting_journal_lines(journal_id,tenant_id,line_no,account_code,debit,credit,memo)
   VALUES(jid,tid,1,'1-1010',1000,0,'Proof debit'),(jid,tid,2,'3-3010',0,1000,'Proof credit');
 END IF;
END
$fixture$;
SQL
}
apply_clone_assets() {
  [[ -f "$RLS_MIGRATION" && -f "$HELPERS_FILE" ]] || fatal "required RLS migration/helper missing"
  psql "$CLONE_DB_URL" -X -v ON_ERROR_STOP=1 -f "$RLS_MIGRATION"
  psql "$CLONE_DB_URL" -X -v ON_ERROR_STOP=1 -f "$HELPERS_FILE"
}
check_0() {
  local s c
  s="$(sql_source "SELECT count(*)::text||'|'||md5(string_agg(key,E'\n' ORDER BY key)) FROM public.app_config;")" || { fail_check 0 "source app_config query failed"; return; }
  c="$(sql_clone "SELECT count(*)::text||'|'||md5(string_agg(key,E'\n' ORDER BY key)) FROM public.app_config;")" || { fail_check 0 "clone app_config query failed"; return; }
  [[ "$s" == "$EXPECTED_CONFIG_COUNT|$EXPECTED_KEYSET_MD5" ]] || { fail_check 0 "source contract mismatch: $s"; return; }
  [[ "$c" == "$EXPECTED_CONFIG_COUNT|$EXPECTED_KEYSET_MD5" ]] || { fail_check 0 "clone contract mismatch: $c"; return; }
  [[ "$s" == "$c" ]] || { fail_check 0 "source/clone app_config differs"; return; }
  pass_check 0 "352 app_config keys and keyset MD5 match both endpoints"
}
check_1() {
  local n db missing outbox present
  [[ -f "$MAP_FILE" ]] || { fail_check 1 "manifest missing"; return; }
  n="$(awk -F '\t' 'NR>1 && NF==3 && $1!="" {n++} END {print n+0}' "$MAP_FILE")"
  [[ "$n" == "$EXPECTED_MAP_COUNT" ]] || { fail_check 1 "manifest count $n, expected 21"; return; }
  db="$(sql_clone "SELECT count(*) FROM public.transaction_type_map;")" || { fail_check 1 "transaction_type_map query failed"; return; }
  if [[ "$db" != "$EXPECTED_MAP_COUNT" ]]; then
    present="$(sql_clone "SELECT coalesce(string_agg(p_transaction_type,', ' ORDER BY p_transaction_type),'') FROM public.transaction_type_map;")" || present="unavailable"
    fail_check 1 "database mapping count $db expected 21; present types: $present"; return
  fi
  missing="$(sql_clone "WITH expected(p_transaction_type,expected_ref) AS (VALUES $(expected_values)) SELECT coalesce(string_agg(e.p_transaction_type||' => '||e.expected_ref,', ' ORDER BY e.p_transaction_type),'') FROM expected e LEFT JOIN public.transaction_type_map m ON m.p_transaction_type=e.p_transaction_type AND m.source_type=e.expected_ref WHERE m.p_transaction_type IS NULL;")" || { fail_check 1 "manifest comparison query failed"; return; }
  [[ -z "$missing" ]] || { fail_check 1 "mappings missing/wrong: $missing"; return; }
  outbox="$(sql_clone "SELECT count(*) FROM private.pos_outbox WHERE acked_at IS NULL;")" || { fail_check 1 "outbox query failed"; return; }
  [[ "$outbox" == "0" ]] || { fail_check 1 "unacknowledged outbox rows $outbox"; return; }
  pass_check 1 "all 21 mapping pairs exact; outbox drained"
}
check_2() {
  local r anon proof
  r="$(sql_clone "SELECT relrowsecurity::text FROM pg_class WHERE oid='private.tenant_accounting_links'::regclass;")" || { fail_check 2 "RLS inspection failed"; return; }
  [[ "$r" == true ]] || { fail_check 2 "RLS enabled flag is $r"; return; }
  anon="$(sql_clone "SET ROLE anon; SELECT count(*) FROM private.tenant_accounting_links; RESET ROLE;")" || { fail_check 2 "anon SQL failed; error is not zero"; return; }
  [[ "$anon" == 0 ]] || { fail_check 2 "anon visible rows=$anon"; return; }
  proof="$(sql_clone "SELECT count(*) FROM public.accounting_journals j JOIN public.accounting_tenants t USING(tenant_id) WHERE j.transaction_ref='PROOF-B-001' AND t.name='TENANT_B_TEST';")" || { fail_check 2 "proof query failed"; return; }
  [[ "$proof" == 1 ]] || { fail_check 2 "proof journal count=$proof"; return; }
  pass_check 2 "RLS enabled; anon query returns zero; proof journal exists exactly once"
}
check_3() {
  local runner="$ROOT/tests/stress/pos-concurrent.js" rows rc
  [[ "$MODE" == "--full" ]] || { skip_check 3 "stress is only allowed in --full"; return; }
  [[ -f "$runner" ]] || { fail_check 3 "tests/stress/pos-concurrent.js missing; refusing to fake PASS"; return; }
  STRESS_EXECUTED=1
  if env STRESS_ENV=clone STRESS_CLONE_PROJECT_REF="$CLONE_REF" SUPABASE_PROD_PROJECT_REF="$SOURCE_REF" STRESS_TENANT_NAME="${STRESS_TENANT_NAME:-TENANT_B_TEST}" SUPABASE_URL="https://$CLONE_REF.supabase.co" SUPABASE_ANON_KEY="$CLONE_ANON_KEY" SUPABASE_SERVICE_ROLE_KEY="$CLONE_SERVICE_KEY" timeout 610 node "$runner" --vus=50 --duration=600; then
    log "50-VU load process exited 0"
  else rc=$?; fail_check 3 "load test failed/timed out (exit $rc)"; return; fi
  rows="$(sql_clone "SELECT count(*) FROM public.v_stress_validation;")" || { fail_check 3 "validation view query failed"; return; }
  [[ "$rows" == 0 ]] || { fail_check 3 "validation view has $rows rows"; return; }
  pass_check 3 "50 VU for 600s exited 0 and validation view is empty"
}
crash_context() {
  sql_clone "SELECT tenant_id::text||'|'||transaction_type||'|'||business_date::text||'|'||coalesce(actor_user_id::text,'')||'|'||device_id||'|'||app_version||'|'||replace(reason,'|',' ')||'|'||replace(facts_snapshot::text,'|',' ') FROM public.accounting_transaction_evidence WHERE transaction_ref='CRASH-TEST-001' AND journal_id='$EXPECTED_CRASH_JOURNAL_ID';"
}
two_session_kill() {
  local tenant="$1" type="$2" date="$3" actor="$4" device="$5" app="$6" facts="$7"
  local exists killed rc j e logfile sql
  exists="$(sql_clone "SELECT count(*) FROM public.accounting_journals WHERE transaction_ref='KILL-2SESI-001';")" || return 1
  [[ "$exists" == 0 ]] || { log "KILL-2SESI-001 already exists; not overwriting"; return 1; }
  logfile="${TMPDIR:-/tmp}/berkah-kill-session-a.log"
  sql="BEGIN; SELECT set_config('request.jwt.claim.sub', :'actor', true); SELECT public.create_auto_journal(:'tenant'::uuid, :'type', 'KILL-2SESI-001', :'date'::date, :'facts'::jsonb, :'device', :'app', 'ALL GREEN two-session crash test'); SELECT pg_sleep(45) /* KILL-2SESI-001 */; COMMIT;"
  PGAPPNAME=berkah-all-green-kill-a psql "$CLONE_DB_URL" -X -v ON_ERROR_STOP=1 -v VERBOSITY=verbose -v actor="$actor" -v tenant="$tenant" -v type="$type" -v date="$date" -v facts="$facts" -v device="$device" -v app="$app" -c "$sql" >"$logfile" 2>&1 &
  local pid=$!
  sleep 3
  killed="$(sql_clone "SELECT count(*) FROM pg_stat_activity WHERE pid<>pg_backend_pid() AND application_name='berkah-all-green-kill-a' AND state='active' AND query LIKE '%KILL-2SESI-001%' AND pg_terminate_backend(pid);")" || { wait "$pid" 2>/dev/null || true; return 1; }
  set +e; wait "$pid"; rc=$?; set -e
  [[ "$killed" == 1 && "$rc" != 0 ]] || { log "backend termination mismatch: killed=$killed exit=$rc"; return 1; }
  grep -q '57P01' "$logfile" || { log "SQLSTATE 57P01 absent from $logfile"; return 1; }
  j="$(sql_clone "SELECT count(*) FROM public.accounting_journals WHERE transaction_ref='KILL-2SESI-001';")" || return 1
  e="$(sql_clone "SELECT count(*) FROM public.accounting_transaction_evidence WHERE transaction_ref='KILL-2SESI-001';")" || return 1
  [[ "$j" == 0 && "$e" == 0 ]] || { log "post-kill rows journals=$j evidence=$e"; return 1; }
}
check_4() {
  local fixture ctx tenant type date actor device app reason facts result id journals evidence consistency nulls
  fixture="$(sql_clone "SELECT count(*)::text||'|'||coalesce(string_agg(journal_id::text,','),'') FROM public.accounting_journals WHERE transaction_ref='CRASH-TEST-001' AND journal_id='$EXPECTED_CRASH_JOURNAL_ID';")" || { fail_check 4 "crash fixture query failed"; return; }
  [[ "$fixture" == "1|$EXPECTED_CRASH_JOURNAL_ID" ]] || { fail_check 4 "CRASH-TEST-001 fixture mismatch: $fixture"; return; }
  if [[ "$MODE" == "--full" ]]; then
    ctx="$(crash_context)" || { fail_check 4 "replay context query failed"; return; }
    [[ -n "$ctx" ]] || { fail_check 4 "crash replay context missing"; return; }
    IFS='|' read -r tenant type date actor device app reason facts <<< "$ctx"
    [[ -n "$actor" && -n "$facts" && -n "$device" ]] || { fail_check 4 "crash replay context incomplete"; return; }
    result="$(sql_clone_vars -v actor="$actor" -v tenant="$tenant" -v type="$type" -v date="$date" -v facts="$facts" -v device="$device" -v app="$app" -v reason="$reason" -c "SELECT set_config('request.jwt.claim.sub', :'actor', false); SELECT public.create_auto_journal(:'tenant'::uuid, :'type', 'CRASH-TEST-001', :'date'::date, :'facts'::jsonb, :'device', :'app', :'reason');")" || { fail_check 4 "idempotency retry failed"; return; }
    id="$(printf '%s\n' "$result" | tail -n 1)"
    [[ "$id" == "$EXPECTED_CRASH_JOURNAL_ID" ]] || { fail_check 4 "retry UUID is $id"; return; }
    two_session_kill "$tenant" "$type" "$date" "$actor" "$device" "$app" "$facts" || { fail_check 4 "two-session kill failed"; return; }
  else skip_check 4a "validate-only does not replay writes or kill a backend"; fi
  journals="$(sql_clone "SELECT count(*) FROM public.accounting_journals WHERE transaction_ref='KILL-2SESI-001';")" || { fail_check 4 "crash postcondition journal query failed"; return; }
  evidence="$(sql_clone "SELECT count(*) FROM public.accounting_transaction_evidence WHERE transaction_ref='KILL-2SESI-001';")" || { fail_check 4 "crash postcondition evidence query failed"; return; }
  [[ "$journals" == 0 && "$evidence" == 0 ]] || { fail_check 4 "rollback counts are $journals/$evidence"; return; }
  consistency="$(sql_clone "SELECT count(*) FROM public.validate_journal_consistency();")" || { fail_check 4 "consistency query failed"; return; }
  [[ "$consistency" == 0 ]] || { fail_check 4 "journal consistency issues=$consistency"; return; }
  nulls="$(sql_clone "SELECT count(*) FROM public.accounting_transaction_evidence WHERE journal_id IS NULL;")" || { fail_check 4 "evidence null query failed"; return; }
  [[ "$nulls" == 0 ]] || { fail_check 4 "null evidence journal links=$nulls"; return; }
  pass_check 4 "stable idempotency UUID, rollback, consistency and evidence links verified"
}
capture_provenance_baseline() {
  BASELINE_SOURCE_SUM="$(sql_source "SELECT coalesce(sum(debit),0) FROM public.accounting_journal_lines;")" || fatal "source debit sum query failed; provenance unavailable"
  BASELINE_CLONE_TEST_SUM="$(sql_clone "SELECT coalesce(sum(l.debit),0) FROM public.accounting_journal_lines l JOIN public.accounting_journals j USING(journal_id) WHERE j.transaction_ref <> 'PROOF-B-001';")" || fatal "clone test debit sum query failed; provenance unavailable"
  BASELINE_CLONE_TOTAL_SUM="$(sql_clone "SELECT coalesce(sum(debit),0) FROM public.accounting_journal_lines;")" || fatal "clone total debit sum query failed; provenance unavailable"
  [[ "$BASELINE_SOURCE_SUM" =~ ^[0-9]+$ && "$BASELINE_CLONE_TEST_SUM" =~ ^[0-9]+$ && "$BASELINE_CLONE_TOTAL_SUM" =~ ^[0-9]+$ ]] || fatal "debit sums are not nonnegative integers"
  log "Captured pre-load sums: source=$BASELINE_SOURCE_SUM clone_test_excluding_PROOF_B_001=$BASELINE_CLONE_TEST_SUM clone_total=$BASELINE_CLONE_TOTAL_SUM"
}
check_5() {
  local tmp sha diff
  tmp="$(mktemp "${TMPDIR:-/tmp}/berkah-schema.XXXXXX.sql")"
  if ! supabase db dump --db-url "$SOURCE_DB_URL" -f "$tmp"; then
    rm -f "$tmp"; fail_check 5 "source schema-only dump failed"; return
  fi
  sha="$(sha256sum "$tmp" | awk '{print $1}')"; rm -f "$tmp"
  diff=$((BASELINE_SOURCE_SUM - BASELINE_CLONE_TEST_SUM))
  mkdir -p "$ROOT/docs/audit"
  {
    printf 'status=NOT_ALL_GREEN\ngenerated_at_utc=%s\nsource_ref=%s\nclone_ref=%s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$SOURCE_REF" "$CLONE_REF"
    printf 'app_config_count=%s\nmd5_keyset=%s\nsource_sum=%s\nclone_test_sum=%s\ndiff=%s\nclassification=expected_for_test_clone\n' "$EXPECTED_CONFIG_COUNT" "$EXPECTED_KEYSET_MD5" "$BASELINE_SOURCE_SUM" "$BASELINE_CLONE_TEST_SUM" "$diff"
    printf 'clone_total_sum_at_preflight=%s\nclone_test_sum_excludes=PROOF-B-001\n' "$BASELINE_CLONE_TOTAL_SUM"
    printf 'aab_sha256=%s\naab_sha256_status=provided_not_recomputed\nsource_schema_sha256=%s\n' "$EXPECTED_AAB_SHA256" "$sha"
    printf 'dr_full_restore_status=NOT_RUN_SEPARATE_CLONE_REQUIRED\n'
    local i; for i in 0 1 2 3 4; do printf 'check_%s=%s\n' "$i" "${STATUS[$i]:-NOT_RUN}"; done
    printf 'check_5=IN_PROGRESS\nlog_file=%s\n' "$LOG_FILE"
  } >"$ROOT/docs/audit/provenance.txt"
  if [[ "$BASELINE_SOURCE_SUM" != "$EXPECTED_SOURCE_SUM" || "$BASELINE_CLONE_TEST_SUM" != "$EXPECTED_CLONE_TEST_SUM" ]]; then
    fail_check 5 "unexpected pre-load profile: source=$BASELINE_SOURCE_SUM expected=$EXPECTED_SOURCE_SUM clone_test=$BASELINE_CLONE_TEST_SUM expected=$EXPECTED_CLONE_TEST_SUM"
  elif [[ "$sha" =~ ^[0-9a-f]{64}$ ]]; then
    pass_check 5 "schema SHA-256 captured; source_sum=502300 clone_test_sum=30500 diff=471800 expected_for_test_clone; DR restore not claimed"
  else
    fail_check 5 "schema SHA-256 invalid"
  fi
  printf 'check_5=%s\nsource_sum=%s\nclone_test_sum=%s\ndiff=%s\nclassification=expected_for_test_clone\nsource_schema_sha256=%s\n' "${STATUS[5]:-FAIL}" "$BASELINE_SOURCE_SUM" "$BASELINE_CLONE_TEST_SUM" "$diff" "$sha" >>"$ROOT/docs/audit/provenance.txt"
}
mark_prs_ready() {
  command -v gh >/dev/null 2>&1 || return 1
  local token="${GH_TOKEN:-${GITHUB_TOKEN:-}}" pr draft
  [[ -n "$token" ]] || return 1
  for pr in 123 124 125 126; do
    draft="$(GH_TOKEN="$token" gh pr view "$pr" --repo berkah-ajb-dev/Berkahtigaputeri --json isDraft --jq '.isDraft')" || return 1
    [[ "$draft" != true ]] || GH_TOKEN="$token" gh pr ready "$pr" --repo berkah-ajb-dev/Berkahtigaputeri || return 1
  done
}
write_final_verdict() {
  local path="$ROOT/docs/audit/FINAL_VERDICT_5_GAPS_GREEN.md" i
  {
    printf '# Final Verdict — 5 Gaps GREEN\n\nGenerated UTC: %s\n\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    printf 'Source: %s (read-only)\n\nTarget clone: %s\n\nLog: %s\n\n' "$SOURCE_REF" "$CLONE_REF" "$LOG_FILE"
    printf '| Check | Status | Evidence |\n|---|---|---|\n'
    for i in 0 1 2 3 4 5; do printf '| %s | %s | %s |\n' "$i" "${STATUS[$i]}" "${DETAIL[$i]}"; done
    printf '\nAAB SHA-256 supplied by requirement, not independently recomputed: %s\n' "$EXPECTED_AAB_SHA256"
  } >"$path"
}
main() {
  check_endpoint_ids
  check_deps
  [[ -f "$MAP_FILE" ]] || fatal "manifest file missing: $MAP_FILE"
  capture_provenance_baseline
  if [[ "$MODE" == "--full" ]]; then
    require_env CLONE_ANON_KEY CLONE_SERVICE_KEY
    apply_clone_assets || fatal "clone-only migration/helper application failed"
    ensure_proof_fixture || fatal "could not create proof fixture on clone"
  fi
  local attempt
  for ((attempt=1; attempt<=MAX_ATTEMPTS; attempt++)); do
    FAILURES=0; STATUS=(); DETAIL=()
    log "Attempt $attempt/$MAX_ATTEMPTS mode=$MODE"
    check_0; check_1; check_2; check_3; check_4; check_5
    if [[ "$MODE" == "--validate-only" ]]; then
      (( FAILURES == 0 )) && { log "Validation gates green; stress and write tests skipped by mode"; return 0; }
      log "Validate-only found $FAILURES failure(s); no DB writes were performed"
    elif (( FAILURES == 0 && STRESS_EXECUTED == 1 )); then
      if mark_prs_ready; then
        sed -i 's/^status=NOT_ALL_GREEN$/status=ALL_GREEN/' "$ROOT/docs/audit/provenance.txt"
        write_final_verdict
        log "ALL GREEN verified"
        return 0
      fi
      fail_check 5 "checks passed but PR readiness could not be verified"
    else log "Full attempt found $FAILURES failure(s); no GREEN verdict will be created"; fi
    (( attempt < MAX_ATTEMPTS )) && sleep "$((attempt*2))"
  done
  log "Stopped fail-closed after $MAX_ATTEMPTS bounded attempts; inspect $LOG_FILE and docs/audit/provenance.txt"
  return 1
}
main "$@"
