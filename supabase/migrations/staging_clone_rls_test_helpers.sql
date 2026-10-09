-- Test helpers for an isolated staging clone only.
CREATE OR REPLACE FUNCTION private.create_test_tenant(p_name text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE v_tenant_id uuid;
BEGIN
  IF p_name IS NULL OR pg_catalog.length(pg_catalog.btrim(p_name)) < 1
     OR pg_catalog.length(pg_catalog.btrim(p_name)) > 120 THEN
    RAISE EXCEPTION 'test tenant name must contain 1..120 characters';
  END IF;
  SELECT t.tenant_id INTO v_tenant_id
  FROM public.accounting_tenants AS t WHERE t.name = p_name
  ORDER BY t.created_at LIMIT 1;
  IF v_tenant_id IS NOT NULL THEN RETURN v_tenant_id; END IF;
  INSERT INTO public.accounting_tenants(name,owner_subject,status)
  VALUES(p_name,'staging-clone-test:'||p_name,'active')
  RETURNING tenant_id INTO v_tenant_id;
  RETURN v_tenant_id;
END;
$function$;
REVOKE ALL ON FUNCTION private.create_test_tenant(text) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.test_tenant_isolation()
RETURNS boolean LANGUAGE plpgsql SECURITY INVOKER SET search_path TO ''
AS $function$
DECLARE v_tenant_id uuid; v_count bigint;
BEGIN
  SELECT t.tenant_id INTO v_tenant_id
  FROM public.accounting_tenants AS t WHERE t.name='TENANT_B_TEST'
  ORDER BY t.created_at LIMIT 1;
  IF v_tenant_id IS NULL THEN RETURN false; END IF;
  SELECT count(*) INTO v_count FROM public.accounting_journals AS j
  WHERE j.tenant_id=v_tenant_id AND j.transaction_ref='PROOF-B-001';
  RETURN v_count=1;
END;
$function$;
REVOKE ALL ON FUNCTION public.test_tenant_isolation() FROM PUBLIC, anon, authenticated;
