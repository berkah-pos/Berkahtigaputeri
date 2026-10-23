\\set ON_ERROR_STOP on

-- Install only as a PostgreSQL superuser in the private maintenance database.
-- The broker role must have CREATEDB but MUST NOT have CREATEROLE.
SELECT (current_database() = 'postgres') AS in_maintenance_db \\gset
\\if :in_maintenance_db
\\else
\\echo 'ERROR: provisioner role functions must be installed in the private postgres maintenance database.'
\\quit 4
\\endif

SELECT COALESCE((SELECT rolsuper FROM pg_catalog.pg_roles WHERE rolname = current_user), false) AS installer_is_superuser \\gset
\\if :installer_is_superuser
\\else
\\echo 'ERROR: role-function installation requires an explicit PostgreSQL superuser session.'
\\quit 4
\\endif

SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = :'broker_role') AS broker_exists \\gset
\\if :broker_exists
SELECT (
    rolcanlogin
    AND NOT rolsuper
    AND rolcreatedb
    AND NOT rolcreaterole
    AND NOT rolreplication
    AND NOT rolbypassrls
    AND NOT rolinherit
) AS broker_contract_ok
FROM pg_catalog.pg_roles
WHERE rolname = :'broker_role' \\gset
\\if :broker_contract_ok
\\else
\\echo 'ERROR: broker must be LOGIN, CREATEDB, NOCREATEROLE, NOINHERIT, NOSUPERUSER, NOREPLICATION, and NOBYPASSRLS.'
\\quit 5
\\endif
\\else
\\echo 'ERROR: the expected provisioner broker role does not exist.'
\\quit 5
\\endif

SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_database WHERE datname = :'central_database') AS central_database_exists \\gset
\\if :central_database_exists
\\else
\\echo 'ERROR: configured central database does not exist.'
\\quit 5
\\endif

SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname = 'berkahpos_role_admin') AS role_admin_exists \\gset
\\if :role_admin_exists
SELECT (
    NOT rolcanlogin
    AND NOT rolsuper
    AND NOT rolcreatedb
    AND rolcreaterole
    AND NOT rolreplication
    AND NOT rolbypassrls
    AND NOT rolinherit
    AND pg_catalog.shobj_description(oid, 'pg_authid') = 'berkah-provisioner-role-admin-v1'
) AS role_admin_contract_ok
FROM pg_catalog.pg_roles
WHERE rolname = 'berkahpos_role_admin' \\gset
\\if :role_admin_contract_ok
\\else
\\echo 'ERROR: existing berkahpos_role_admin has unexpected attributes or is not marked as managed.'
\\quit 5
\\endif
\\else
CREATE ROLE berkahpos_role_admin
    NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB CREATEROLE NOREPLICATION NOBYPASSRLS;
COMMENT ON ROLE berkahpos_role_admin IS 'berkah-provisioner-role-admin-v1';
\\endif

SELECT EXISTS (SELECT 1 FROM pg_catalog.pg_namespace WHERE nspname = 'berkah_provisioning') AS provisioning_schema_exists \\gset
\\if :provisioning_schema_exists
SELECT (nspowner = (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'berkahpos_role_admin')) AS provisioning_schema_owned_by_admin
FROM pg_catalog.pg_namespace
WHERE nspname = 'berkah_provisioning' \\gset
\\if :provisioning_schema_owned_by_admin
\\else
\\echo 'ERROR: existing berkah_provisioning schema is not owned by berkahpos_role_admin.'
\\quit 5
\\endif
\\else
SET ROLE berkahpos_role_admin;
CREATE SCHEMA berkah_provisioning AUTHORIZATION berkahpos_role_admin;
RESET ROLE;
\\endif

SELECT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'berkah_provisioning'
      AND c.relname = 'approved_brokers'
      AND c.relkind = 'r'
) AS approved_brokers_table_exists \\gset
\\if :approved_brokers_table_exists
SELECT (
    c.relowner = (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'berkahpos_role_admin')
) AS approved_brokers_owned_by_admin
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'berkah_provisioning' AND c.relname = 'approved_brokers' \\gset
\\if :approved_brokers_owned_by_admin
\\else
\\echo 'ERROR: existing approved_brokers table is not owned by berkahpos_role_admin.'
\\quit 5
\\endif
\\else
SET ROLE berkahpos_role_admin;
CREATE TABLE berkah_provisioning.approved_brokers (
    role_name name PRIMARY KEY,
    enabled boolean NOT NULL DEFAULT true
);
RESET ROLE;
\\endif

SET ROLE berkahpos_role_admin;

CREATE OR REPLACE FUNCTION berkah_provisioning.assert_provisioner_broker()
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $fn$
DECLARE
    broker_ok boolean;
BEGIN
    SELECT (
        r.rolcanlogin
        AND NOT r.rolsuper
        AND r.rolcreatedb
        AND NOT r.rolcreaterole
        AND NOT r.rolreplication
        AND NOT r.rolbypassrls
        AND NOT r.rolinherit
        AND EXISTS (
            SELECT 1
            FROM berkah_provisioning.approved_brokers b
            WHERE b.role_name = session_user::name
              AND b.enabled
        )
    )
    INTO broker_ok
    FROM pg_catalog.pg_roles r
    WHERE r.rolname = session_user;

    IF COALESCE(broker_ok, false) IS NOT TRUE THEN
        RAISE EXCEPTION 'Caller is not an approved least-privilege provisioner broker'
            USING ERRCODE = '42501';
    END IF;

    RETURN true;
END;
$fn$;

CREATE OR REPLACE FUNCTION berkah_provisioning.create_tenant_roles(
    p_tenant_id text,
    p_runtime_password text,
    p_migrator_password text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $fn$
DECLARE
    tenant text;
    suffix text;
    owner_name text;
    runtime_name text;
    migrator_name text;
BEGIN
    PERFORM berkah_provisioning.assert_provisioner_broker();

    IF p_tenant_id IS NULL OR p_tenant_id !~ '^[0-7][0-9A-HJKMNP-TV-Z]{25}$' THEN
        RAISE EXCEPTION 'Tenant ID must be a canonical ULID' USING ERRCODE = '22023';
    END IF;

    IF p_runtime_password IS NULL OR p_runtime_password !~ '^[0-9a-f]{64}$'
       OR p_migrator_password IS NULL OR p_migrator_password !~ '^[0-9a-f]{64}$'
       OR p_runtime_password = p_migrator_password THEN
        RAISE EXCEPTION 'Generated tenant passwords do not meet the credential contract' USING ERRCODE = '22023';
    END IF;

    tenant := pg_catalog.upper(p_tenant_id);
    suffix := pg_catalog.lower(tenant);
    owner_name := 'berkah_t_' || suffix || '_owner';
    runtime_name := 'berkah_t_' || suffix || '_runtime';
    migrator_name := 'berkah_t_' || suffix || '_migrator';

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles
        WHERE rolname = ANY (ARRAY[owner_name, runtime_name, migrator_name])
    ) THEN
        RAISE EXCEPTION 'Tenant role already exists; refusing to adopt or modify unverified roles'
            USING ERRCODE = '42710';
    END IF;

    EXECUTE pg_catalog.format(
        'CREATE ROLE %I NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
        owner_name
    );
    EXECUTE pg_catalog.format(
        'COMMENT ON ROLE %I IS %L',
        owner_name,
        'berkah-tenant-owner-v1'
    );

    EXECUTE pg_catalog.format(
        'CREATE ROLE %I LOGIN NOINHERIT PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
        runtime_name,
        p_runtime_password
    );
    EXECUTE pg_catalog.format(
        'COMMENT ON ROLE %I IS %L',
        runtime_name,
        'berkah-tenant-runtime-v1'
    );

    EXECUTE pg_catalog.format(
        'CREATE ROLE %I LOGIN NOINHERIT PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
        migrator_name,
        p_migrator_password
    );
    EXECUTE pg_catalog.format(
        'COMMENT ON ROLE %I IS %L',
        migrator_name,
        'berkah-tenant-migrator-v1'
    );

    EXECUTE pg_catalog.format(
        'GRANT %I TO %I WITH INHERIT FALSE, SET TRUE',
        owner_name,
        migrator_name
    );
END;
$fn$;

CREATE OR REPLACE FUNCTION berkah_provisioning.grant_tenant_owner_to_caller(p_tenant_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $fn$
DECLARE
    tenant text;
    owner_name text;
BEGIN
    PERFORM berkah_provisioning.assert_provisioner_broker();

    IF p_tenant_id IS NULL OR p_tenant_id !~ '^[0-7][0-9A-HJKMNP-TV-Z]{25}$' THEN
        RAISE EXCEPTION 'Tenant ID must be a canonical ULID' USING ERRCODE = '22023';
    END IF;

    tenant := pg_catalog.upper(p_tenant_id);
    owner_name := 'berkah_t_' || pg_catalog.lower(tenant) || '_owner';

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_roles
        WHERE rolname = owner_name
          AND NOT rolcanlogin
          AND pg_catalog.shobj_description(oid, 'pg_authid') = 'berkah-tenant-owner-v1'
    ) THEN
        RAISE EXCEPTION 'Managed tenant owner role does not exist; refusing a temporary membership grant'
            USING ERRCODE = '42704';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_auth_members m
        WHERE m.roleid = (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = owner_name)
          AND m.member = (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = session_user)
    ) THEN
        RAISE EXCEPTION 'Caller already has a tenant owner membership; manual verification is required'
            USING ERRCODE = '42501';
    END IF;

    EXECUTE pg_catalog.format(
        'GRANT %I TO %I WITH INHERIT FALSE, SET TRUE',
        owner_name,
        session_user
    );
END;
$fn$;

CREATE OR REPLACE FUNCTION berkah_provisioning.revoke_tenant_owner_from_caller(p_tenant_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog
AS $fn$
DECLARE
    tenant text;
    owner_name text;
BEGIN
    PERFORM berkah_provisioning.assert_provisioner_broker();

    IF p_tenant_id IS NULL OR p_tenant_id !~ '^[0-7][0-9A-HJKMNP-TV-Z]{25}$' THEN
        RAISE EXCEPTION 'Tenant ID must be a canonical ULID' USING ERRCODE = '22023';
    END IF;

    tenant := pg_catalog.upper(p_tenant_id);
    owner_name := 'berkah_t_' || pg_catalog.lower(tenant) || '_owner';

    IF NOT EXISTS (
        SELECT 1 FROM pg_catalog.pg_roles
        WHERE rolname = owner_name
          AND NOT rolcanlogin
          AND pg_catalog.shobj_description(oid, 'pg_authid') = 'berkah-tenant-owner-v1'
    ) THEN
        RAISE EXCEPTION 'Managed tenant owner role does not exist; refusing a membership revoke against an unverified role'
            USING ERRCODE = '42704';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM pg_catalog.pg_auth_members m
        WHERE m.roleid = (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = owner_name)
          AND m.member = (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = session_user)
          AND m.grantor = (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = 'berkahpos_role_admin')
    ) THEN
        EXECUTE pg_catalog.format(
            'REVOKE %I FROM %I',
            owner_name,
            session_user
        );
    END IF;
END;
$fn$;

RESET ROLE;

REVOKE ALL ON FUNCTION berkah_provisioning.assert_provisioner_broker() FROM PUBLIC;
REVOKE ALL ON FUNCTION berkah_provisioning.create_tenant_roles(text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION berkah_provisioning.grant_tenant_owner_to_caller(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION berkah_provisioning.revoke_tenant_owner_from_caller(text) FROM PUBLIC;

GRANT USAGE ON SCHEMA berkah_provisioning TO :"broker_role";
GRANT EXECUTE ON FUNCTION berkah_provisioning.assert_provisioner_broker() TO :"broker_role";
GRANT EXECUTE ON FUNCTION berkah_provisioning.create_tenant_roles(text, text, text) TO :"broker_role";
GRANT EXECUTE ON FUNCTION berkah_provisioning.grant_tenant_owner_to_caller(text) TO :"broker_role";
GRANT EXECUTE ON FUNCTION berkah_provisioning.revoke_tenant_owner_from_caller(text) TO :"broker_role";

DELETE FROM berkah_provisioning.approved_brokers
WHERE role_name <> :'broker_role'::name;
INSERT INTO berkah_provisioning.approved_brokers(role_name, enabled)
VALUES (:'broker_role'::name, true)
ON CONFLICT (role_name) DO UPDATE SET enabled = EXCLUDED.enabled;

REVOKE ALL ON DATABASE :"central_database" FROM PUBLIC;
REVOKE ALL ON DATABASE :"central_database" FROM :"broker_role";
GRANT CONNECT ON DATABASE postgres TO :"broker_role";
