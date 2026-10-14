#!/usr/bin/env python3
"""Validate the recorded Supabase migration reconciliation evidence without database writes."""
from __future__ import annotations
import hashlib, json, re, sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "supabase/reconciliation/remote-migration-ledger-2026-10-14.json"
MIGRATIONS = ROOT / "supabase/migrations"
VERSION_RE = re.compile(r"^(\d{14})_[a-z0-9_]+\.sql$")
REQUIRED = ("historical_sql_recovered","source_versions_and_remote_application_matched","schema_only_dump_reviewed","clean_database_replay_passed","isolated_tenant_tests_passed","security_definer_grants_reviewed","backup_restore_test_passed","human_approval_recorded")
def git_blob_sha(data: bytes) -> str:
    return hashlib.sha1(f"blob {len(data)}\0".encode("ascii") + data).hexdigest()
def main() -> int:
    try: data=json.loads(MANIFEST.read_text(encoding='utf-8'))
    except (OSError,json.JSONDecodeError) as exc:
        print(f'::error::Cannot read reconciliation manifest: {exc}',file=sys.stderr); return 1
    errors=[]
    if data.get('schema_version') != 1: errors.append('unsupported manifest schema_version')
    status=data.get('status')
    if status not in {'BLOCKED_SOURCE_SQL_NOT_RECOVERED','BLOCKED_HISTORICAL_REPLAY_PENDING','BLOCKED_PREHISTORY_BASELINE_REPLAY_PENDING','BLOCKED_CANONICAL_CONFIG_FIXTURE_REPLAY_PENDING','BLOCKED_CLONE_DRIFT_AND_RUNTIME_GATES','RECONCILED'}: errors.append('invalid reconciliation status')
    expected=data.get('repository',{}).get('tracked_migration_files',[])
    expected_names=sorted(x.get('file','') for x in expected)
    paths=sorted(MIGRATIONS.glob('*.sql'))
    if expected_names != sorted(p.name for p in paths): errors.append('tracked migration file set changed; refresh ledger and re-audit')
    for entry in expected:
        path=MIGRATIONS / entry.get('file','')
        match=VERSION_RE.fullmatch(path.name)
        if not match: errors.append(f'invalid migration filename: {path.name}'); continue
        if match.group(1) != entry.get('version'): errors.append(f'manifest/file version mismatch: {path.name}')
        if not path.is_file(): errors.append(f'missing migration file: {path.name}'); continue
        if git_blob_sha(path.read_bytes()) != entry.get('git_blob_sha'): errors.append(f'Git blob SHA changed: {path.name}; refresh ledger after review')
    for env in data.get('environments',[]):
        rows=env.get('migrations',[]); versions=[x.get('version') for x in rows]
        if len(versions) != len(set(versions)): errors.append(f'duplicate migration version: {env.get("label")}')
        if any(not re.fullmatch(r'\d{14}',str(v)) for v in versions): errors.append(f'malformed migration version: {env.get("label")}')
        if len(rows) != env.get('migration_count'): errors.append(f'migration_count mismatch: {env.get("label")}')
        if versions != sorted(versions): errors.append(f'migration ledger not ordered: {env.get("label")}')
    if data.get('production_project_identified') is not False: errors.append('production project identity must be separately verified')
    if status == 'RECONCILED':
        missing=[k for k in REQUIRED if data.get('required_gates',{}).get(k) is not True]
        if missing: errors.append('cannot mark reconciled; missing gates: '+', '.join(missing))
        if not data.get('source_recovery_review',{}).get('remote_body_archive_verified', False): errors.append('remote SQL body archive verification is not recorded')
    if errors:
        [print('::error::'+e,file=sys.stderr) for e in errors]; return 1
    staging=next((x for x in data['environments'] if x['label']=='staging'),{})
    clone=next((x for x in data['environments'] if x['label']=='staging-clone'),{})
    print('PASS: migration snapshots are ordered and unique; tracked file names and Git blob SHAs match the manifest.')
    print(f'PASS: remote history counts captured: staging={staging.get("migration_count")}, staging-clone={clone.get("migration_count")}.')
    print('RECONCILIATION STATUS: '+status)
    if status == 'BLOCKED_SOURCE_SQL_NOT_RECOVERED': print('NOTICE: historical SQL-body archive is missing; remote push/reset/migration repair remain prohibited.')
    elif status == 'BLOCKED_HISTORICAL_REPLAY_PENDING': print('NOTICE: SQL bodies are recovered; historical replay is pending; remote push/reset/migration repair remain prohibited.')
    elif status == 'BLOCKED_PREHISTORY_BASELINE_REPLAY_PENDING': print('NOTICE: remote SQL bodies are recovered; historical replay needs a documented pre-history licences scaffold.')
    elif status == 'BLOCKED_CANONICAL_CONFIG_FIXTURE_REPLAY_PENDING': print('NOTICE: historical replay needs the canonical 352-key workbook fixture; seed only the disposable runner.')
    elif status == 'BLOCKED_CLONE_DRIFT_AND_RUNTIME_GATES': print('NOTICE: historical staging replay passed, but clone/runtime/restore/release gates remain blocked.')
    return 0
if __name__ == '__main__': raise SystemExit(main())
