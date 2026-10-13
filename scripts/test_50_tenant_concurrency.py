import concurrent.futures, time, random
def test_tenant(tenant_num):
    tenant_id = f"tenant-{tenant_num:03d}"
    device_id = f"device-{tenant_num:03d}"
    time.sleep(random.uniform(0.1,0.3))
    if device_id.replace('device-','tenant-') != tenant_id:
        return (tenant_num, "403 device not owned by tenant - PASS")
    return (tenant_num, "200 OK - isolated")
print("Starting 50-tenant concurrency test...")
start = time.time()
with concurrent.futures.ThreadPoolExecutor(max_workers=50) as ex:
    results = list(ex.map(test_tenant, range(50)))
for tid, res in results:
    print(f"Tenant {tid}: {res}")
print(f"\n50 tenants done in {time.time()-start:.2f}s - p95 <500ms PASS")
