-- Berkah POS - read-only live schema fingerprint for staging reconciliation.
-- Reveals object names and hashes only; it does not return business row values or change schema/data.
-- This is an inventory fingerprint, NOT a full DDL dump or replacement for recovered migration source.

select jsonb_build_object(
 'postgres_version', current_setting('server_version'),
 'relations', (
   select jsonb_agg(jsonb_build_object(
     'id', n.nspname || '.' || c.relname,
     'kind', c.relkind, 'rls_enabled', c.relrowsecurity, 'force_rls', c.relforcerowsecurity,
     'columns_md5', (
       select md5(coalesce(string_agg(a.attname || ':' || format_type(a.atttypid,a.atttypmod) || ':' || a.attnotnull::text || ':' || coalesce(pg_get_expr(ad.adbin,ad.adrelid),''), E'\n' order by a.attnum),''))
       from pg_attribute a left join pg_attrdef ad on ad.adrelid=a.attrelid and ad.adnum=a.attnum
       where a.attrelid=c.oid and a.attnum>0 and not a.attisdropped
     ),
     'constraints_md5', (select md5(coalesce(string_agg(con.conname || ':' || pg_get_constraintdef(con.oid),E'\n' order by con.conname),'')) from pg_constraint con where con.conrelid=c.oid),
     'indexes_md5', (select md5(coalesce(string_agg(i.relname || ':' || pg_get_indexdef(i.oid),E'\n' order by i.relname),'')) from pg_index ix join pg_class i on i.oid=ix.indexrelid where ix.indrelid=c.oid)
   ) order by n.nspname,c.relname)
   from pg_class c join pg_namespace n on n.oid=c.relnamespace
   where n.nspname in ('public','private','accounting_private','inventory_private') and c.relkind in ('r','p','v','m','f')
 ),
 'functions', (
   select jsonb_agg(jsonb_build_object(
     'id', n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')',
     'returns', pg_get_function_result(p.oid), 'language', l.lanname, 'security_definer', p.prosecdef,
     'definition_md5', md5(pg_get_functiondef(p.oid)),
     'anon_execute', has_function_privilege('anon',p.oid,'EXECUTE'),
     'authenticated_execute', has_function_privilege('authenticated',p.oid,'EXECUTE'),
     'acl', coalesce(array_to_string(p.proacl,','),'DEFAULT')
   ) order by n.nspname,p.proname,pg_get_function_identity_arguments(p.oid))
   from pg_proc p join pg_namespace n on n.oid=p.pronamespace join pg_language l on l.oid=p.prolang
   where n.nspname in ('public','private','accounting_private','inventory_private')
 ),
 'policies', (
   select jsonb_agg(jsonb_build_object('id',schemaname || '.' || tablename || '.' || policyname,
     'fingerprint_md5',md5(coalesce(cmd,'') || '|' || coalesce(array_to_string(roles,','),'') || '|' || coalesce(qual,'') || '|' || coalesce(with_check,'')),
     'command',cmd,'roles',roles) order by schemaname,tablename,policyname)
   from pg_policies where schemaname in ('public','private','accounting_private','inventory_private')
 ),
 'triggers', (
   select jsonb_agg(jsonb_build_object('id',n.nspname || '.' || c.relname || '.' || t.tgname,
     'enabled',t.tgenabled,'definition_md5',md5(pg_get_triggerdef(t.oid))) order by n.nspname,c.relname,t.tgname)
   from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
   where not t.tgisinternal and n.nspname in ('public','private','accounting_private','inventory_private')
 ),
 'extensions', (select jsonb_agg(jsonb_build_object('name',e.extname,'version',e.extversion,'schema',n.nspname) order by e.extname) from pg_extension e join pg_namespace n on n.oid=e.extnamespace),
 'app_config_fingerprint', (select jsonb_build_object('count',count(*),'key_md5',md5(string_agg(key,E'\n' order by key)),'key_value_md5',md5(string_agg(key || '=' || value::text,E'\n' order by key))) from public.app_config),
 'tenant_row_count',(select count(*) from public.tenants), 'device_row_count',(select count(*) from public.devices)
) as manifest;
