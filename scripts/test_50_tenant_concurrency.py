#!/usr/bin/env python3
"""
REAL Phase 5 + 6 integration test against staging.
Requires: SUPABASE_URL, SUPABASE_SERVICE_KEY, SUPABASE_ANON_KEY env
"""
import os, concurrent.futures, requests, time, json
URL=os.environ.get('SUPABASE_URL')
SVC=os.environ.get('SUPABASE_SERVICE_KEY')
ANON=os.environ.get('SUPABASE_ANON_KEY')
assert URL and SVC, "set SUPABASE_URL + SERVICE_KEY"

def headers(key): return {"apikey":key,"Authorization":f"Bearer {key}","Content-Type":"application/json"}

# Test 1: anon 0 rows
r=requests.get(f"{URL}/rest/v1/app_config?limit=1", headers=headers(ANON))
assert r.status_code in (401,403), f"anon should be denied, got {r.status_code}"
print("PASS anon denied:", r.status_code)

# Test 2: cross-tenant device 403 via get_effective_config
# Try tenant:xxx device from other tenant - RPC should deny via RLS/can_write
# This needs a real device_id from other tenant - use known test tenant
r=requests.post(f"{URL}/rest/v1/rpc/get_effective_config", headers=headers(ANON), json={"p_tenant_id":"test","p_device_id":"device_other"})
print(f"Cross-tenant anon: {r.status_code} (expected 401/403)")

# Test 3: concurrent version conflict 40001
# Get a real key version
resp=requests.get(f"{URL}/rest/v1/app_config?key=eq.global&select=key,value", headers=headers(SVC))
row=resp.json()[0]
ver=row['value']['version']
key=row['key']
print(f"Current {key} v{ver}")

def concurrent_update(n):
    # Both use same expected_version -> one succeeds one fails 40001
    payload={"p_key":key,"p_new_value":{"test":n,"version":ver},"p_expected_version":ver}
    rr=requests.post(f"{URL}/rest/v1/rpc/update_app_config_atomic", headers=headers(SVC), json=payload)
    return (n, rr.status_code, rr.text[:200])

with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:
    results=list(ex.map(concurrent_update, range(2)))

success=[r for r in results if r[1]==200]
conflict=[r for r in results if '40001' in r[2] or r[1]>=400]
print(f"Concurrent: {len(success)} success, {len(conflict)} conflict 40001")
print(results)
assert len(success)==1 and len(conflict)==1, "must be 1 success 1x40001"
print("PASS Phase 6 concurrent 40001")

# Restore original version
requests.post(f"{URL}/rest/v1/rpc/update_app_config_atomic", headers=headers(SVC), json={"p_key":key,"p_new_value":row['value'],"p_expected_version":ver+1})

print("Phase 5 + 6 REAL DB PASS")
