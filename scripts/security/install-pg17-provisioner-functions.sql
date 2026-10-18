-- PostgreSQL 17 tenant-role control plane.
-- Install as the PostgreSQL bootstrap administrator while connected to database "postgres".
-- The SECURITY DEFINER owner is NOLOGIN; the broker itself never receives CREATEROLE.
-- This file must not be applied to production until reviewed and backed up.

DO $bootstrap$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'berkah_role_admin') THEN
        CREATE ROLE berkah_role_admin
            NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB CREATEROLE
            NOREPLICATION NOBYPASSRLS;
    END IF;

    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'berkah_provisioner') THEN
        RAISE EXCEPTION 'Create berkah_provisioner with a secret password before installing this file';
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_namespace
         WHERE nspname = 'provisioning'
           AND nspowner <> (SELECT oid FROM pg_roles WHERE rolname = 'berkah_role_admin')
    ) THEN
        RAISE EXCEPTION 'Existing provisioning schema has an unexpected owner; manual review required';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_namespace WHERE nspname = 'provisioning'
    ) THEN
        CREATE SCHEMA provisioning AUTHORIZATION berkah_role_admin;
    END IF;
END
$bootstrap$;

DO $validate$
DECLARE
    v_login boolean;
    v_super boolean;
    v_createdb boolean;
    v_createrole boolean;
    v_replication boolean;
    v_bypassrls boolean;
    v_inherit boolean;
BEGIN
    SELECT rolcanlogin, rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls, rolinherit
      INTO v_login, v_super, v_createdb, v_createrole, v_replication, v_bypassrls, v_inherit
      FROM pg_roles WHERE rolname = 'berkah_role_admin';
    IF NOT FOUND OR v_login OR v_super OR v_createdb OR NOT v_createrole
       OR v_replication OR v_bypassrls OR v_inherit THEN
        RAISE EXCEPTION 'berkah_role_admin attributes violate the reviewed no-login function-owner contract';
    END IF;

    SELECT rolcanlogin, rolsuper, rolcreatedb, rolcreaterole, rolreplication, rolbypassrls, rolinherit
      INTO v_login, v_super, v_createdb, v_createrole, v_replication, v_bypassrls, v_inherit
      FROM pg_roles WHERE rolname = 'berkah_provisioner';
    IF NOT FOUND OR NOT v_login OR v_super OR NOT v_createdb OR v_createrole
       OR v_replication OR v_bypassrls OR v_inherit THEN
        RAISE EXCEPTION 'berkah_provisioner attributes violate the reviewed CREATEDB-only broker contract';
    END IF;
END
$validate$;

DO $central_acl$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = 'berkahpos_central') THEN
        RAISE EXCEPTION 'Canonical central database berkahpos_central must exist before provisioning is enabled';
    END IF;
    EXECUTE 'REVOKE CONNECT, TEMPORARY ON DATABASE berkahpos_central FROM PUBLIC';
    EXECUTE 'REVOKE CONNECT, TEMPORARY ON DATABASE berkahpos_central FROM berkah_provisioner';
END
$central_acl$;

ALTER SCHEMA provisioning OWNER TO berkah_role_admin;
REVOKE ALL ON SCHEMA provisioning FROM PUBLIC;
GRANT USAGE ON SCHEMA provisioning TO berkah_provisioner;

SET ROLE berkah_role_admin;

CREATE TABLE IF NOT EXISTS provisioning.audit_events (
    event_id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tenant_id text NOT NULL CHECK (tenant_id ~ '^[0-7][0-9A-HJKMNP-TV-Z]{25}$'),
    action text NOT NULL CHECK (action IN (
        'role_created', 'role_membership_granted', 'role_membership_revoked',
        'database_created', 'database_acl_hardened', 'schema_acl_hardened',
        'provision_resumed', 'tenant_ready', 'collision_rejected'
    )),
    target text NOT NULL CHECK (octet_length(target) <= 256),
    actor text NOT NULL DEFAULT SESSION_USER,
    happened_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE provisioning.audit_events OWNER TO berkah_role_admin;
REVOKE ALL ON TABLE provisioning.audit_events FROM PUBLIC, berkah_provisioner;

CREATE TABLE IF NOT EXISTS provisioning.tenant_provisioning_intents (
    tenant_id text PRIMARY KEY CHECK (tenant_id ~ '^[0-7][0-9A-HJKMNP-TV-Z]{25}$'),
    database_name text NOT NULL UNIQUE,
    owner_role text NOT NULL UNIQUE,
    state text NOT NULL CHECK (state IN ('database_intent', 'provisioning', 'ready')),
    created_at timestamptz NOT NULL DEFAULT clock_timestamp(),
    updated_at timestamptz NOT NULL DEFAULT clock_timestamp()
);
ALTER TABLE provisioning.tenant_provisioning_intents OWNER TO berkah_role_admin;
REVOKE ALL ON TABLE provisioning.tenant_provisioning_intents FROM PUBLIC, berkah_provisioner;
-- The broker may inspect durable state for fail-closed recovery, but cannot mutate it directly.
GRANT SELECT ON TABLE provisioning.tenant_provisioning_intents TO berkah_provisioner;

CREATE OR REPLACE FUNCTION provisioning.record_event(
    p_tenant_id text,
    p_action text,
    p_target text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, provisioning
AS $function$
DECLARE v_suffix text;
BEGIN
    IF SESSION_USER <> 'berkah_provisioner' THEN
        RAISE EXCEPTION 'Caller is not the dedicated provisioning broker' USING ERRCODE = '42501';
    END IF;
    IF p_tenant_id !~ '^[0-7][0-9A-HJKMNP-TV-Z]{25}$' THEN
        RAISE EXCEPTION 'Tenant identifier is not a canonical ULID' USING ERRCODE = '22023';
    END IF;
    v_suffix := lower(p_tenant_id);
    IF p_target NOT IN (
        'berkah_owner_' || v_suffix, 'berkah_runtime_' || v_suffix,
        'berkah_migrator_' || v_suffix, 'berkahpos_t_' || v_suffix,
        'schema:public', 'state:provisioning', 'state:ready'
    ) THEN
        RAISE EXCEPTION 'Audit target is not in the deterministic tenant namespace' USING ERRCODE = '22023';
    END IF;
    IF p_action NOT IN (
        'role_created', 'role_membership_granted', 'role_membership_revoked',
        'database_created', 'database_acl_hardened', 'schema_acl_hardened',
        'provision_resumed', 'tenant_ready', 'collision_rejected'
    ) THEN
        RAISE EXCEPTION 'Audit action is not allowlisted' USING ERRCODE = '22023';
    END IF;
    INSERT INTO provisioning.audit_events(tenant_id, action, target, actor)
    VALUES (p_tenant_id, p_action, p_target, SESSION_USER);
END
$function$;

CREATE OR REPLACE FUNCTION provisioning.mark_provisioning_intent(p_tenant_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, provisioning
AS $function$
DECLARE
    v_suffix text;
    v_database text;
    v_owner text;
    v_db_owner text;
    v_db_comment text;
    v_state text;
BEGIN
    IF SESSION_USER <> 'berkah_provisioner' THEN
        RAISE EXCEPTION 'Caller is not the dedicated provisioning broker' USING ERRCODE = '42501';
    END IF;
    IF p_tenant_id !~ '^[0-7][0-9A-HJKMNP-TV-Z]{25}$' THEN
        RAISE EXCEPTION 'Tenant identifier is not a canonical ULID' USING ERRCODE = '22023';
    END IF;
    v_suffix := lower(p_tenant_id);
    v_database := 'berkahpos_t_' || v_suffix;
    v_owner := 'berkah_owner_' || v_suffix;

    SELECT state INTO v_state
      FROM provisioning.tenant_provisioning_intents
     WHERE tenant_id = p_tenant_id AND database_name = v_database AND owner_role = v_owner
     FOR UPDATE;
    IF NOT FOUND OR v_state NOT IN ('database_intent', 'provisioning') THEN
        RAISE EXCEPTION 'No eligible durable intent exists for this database transition' USING ERRCODE = '55000';
    END IF;

    SELECT pg_get_userbyid(d.datdba), shobj_description(d.oid, 'pg_database')
      INTO v_db_owner, v_db_comment
      FROM pg_database d WHERE d.datname = v_database;
    IF NOT FOUND OR v_db_owner <> v_owner
       OR v_db_comment <> 'berkah-pos:tenant-db:v1;tenant=' || p_tenant_id || ';state=provisioning' THEN
        RAISE EXCEPTION 'Database catalog does not match the pending tenant intent' USING ERRCODE = '55000';
    END IF;

    UPDATE provisioning.tenant_provisioning_intents
       SET state = 'provisioning', updated_at = clock_timestamp()
     WHERE tenant_id = p_tenant_id;
END
$function$;

CREATE OR REPLACE FUNCTION provisioning.ensure_tenant_roles(
    p_tenant_id text,
    p_runtime_verifier text,
    p_migrator_verifier text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, provisioning
AS $function$
DECLARE
    v_suffix text;
    v_owner text;
    v_runtime text;
    v_migrator text;
    v_database text;
    v_db_owner text;
    v_db_comment text;
    v_db_allowconn boolean;
    v_intent_database text;
    v_intent_owner text;
    v_intent_state text;
    v_intent_exists boolean;
    v_comment text;
    v_login boolean;
    v_super boolean;
    v_createdb boolean;
    v_createrole boolean;
    v_replication boolean;
    v_bypassrls boolean;
    v_inherit boolean;
    v_database_exists boolean;
BEGIN
    IF SESSION_USER <> 'berkah_provisioner' THEN
        RAISE EXCEPTION 'Caller is not the dedicated provisioning broker' USING ERRCODE = '42501';
    END IF;

    IF p_tenant_id !~ '^[0-7][0-9A-HJKMNP-TV-Z]{25}$' THEN
        RAISE EXCEPTION 'Tenant identifier is not a canonical ULID' USING ERRCODE = '22023';
    END IF;
    -- Accept only server-stored SCRAM-SHA-256 verifiers, never cleartext passwords.
    -- Salt=16 bytes (24 Base64 chars), each key=32 bytes (44 Base64 chars).
    IF p_runtime_verifier !~ '^SCRAM-SHA-256\$4096:[A-Za-z0-9+/]{22}==\$[A-Za-z0-9+/]{43}=:[A-Za-z0-9+/]{43}=$'
       OR p_migrator_verifier !~ '^SCRAM-SHA-256\$4096:[A-Za-z0-9+/]{22}==\$[A-Za-z0-9+/]{43}=:[A-Za-z0-9+/]{43}=$' THEN
        RAISE EXCEPTION 'Password verifier input has an invalid SCRAM format' USING ERRCODE = '22023';
    END IF;

    v_suffix := lower(p_tenant_id);
    v_owner := 'berkah_owner_' || v_suffix;
    v_runtime := 'berkah_runtime_' || v_suffix;
    v_migrator := 'berkah_migrator_' || v_suffix;
    v_database := 'berkahpos_t_' || v_suffix;

    SELECT pg_get_userbyid(d.datdba), shobj_description(d.oid, 'pg_database'), d.datallowconn
      INTO v_db_owner, v_db_comment, v_db_allowconn
      FROM pg_database d
     WHERE d.datname = v_database;
    v_database_exists := FOUND;

    SELECT database_name, owner_role, state
      INTO v_intent_database, v_intent_owner, v_intent_state
      FROM provisioning.tenant_provisioning_intents
     WHERE tenant_id = p_tenant_id;
    v_intent_exists := FOUND;
    IF v_intent_exists AND (v_intent_database <> v_database OR v_intent_owner <> v_owner) THEN
        RAISE EXCEPTION 'Durable tenant intent conflicts with deterministic identifiers' USING ERRCODE = '55000';
    END IF;

    IF v_database_exists THEN
        IF v_db_owner IS DISTINCT FROM v_owner THEN
            RAISE EXCEPTION 'Database owner collision; refusing to adopt existing database' USING ERRCODE = '55000';
        END IF;

        IF v_db_comment = 'berkah-pos:tenant-db:v1;tenant=' || p_tenant_id || ';state=ready' THEN
            IF NOT v_intent_exists OR v_intent_state <> 'ready' THEN
                RAISE EXCEPTION 'Ready marker has no matching durable ready intent' USING ERRCODE = '55000';
            END IF;
            PERFORM provisioning.release_tenant_roles(p_tenant_id);
            RETURN 'ready';
        ELSIF v_db_comment = 'berkah-pos:tenant-db:v1;tenant=' || p_tenant_id || ';state=provisioning' THEN
            IF NOT v_intent_exists OR v_intent_state NOT IN ('database_intent', 'provisioning') THEN
                RAISE EXCEPTION 'Provisioning marker has no matching durable intent' USING ERRCODE = '55000';
            END IF;
        ELSIF v_db_comment IS NULL AND v_db_allowconn = FALSE
           AND v_intent_exists AND v_intent_state = 'database_intent' THEN
            -- Recover only the exact closed database that was preceded by our
            -- durable intent. Arbitrary unmarked databases are never adopted.
            NULL;
        ELSE
            RAISE EXCEPTION 'Database marker/state is unverified; refusing to adopt it' USING ERRCODE = '55000';
        END IF;
    END IF;

    -- A marked database must never be paired with newly created replacement roles.
    IF v_database_exists AND (
        NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_owner)
        OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_runtime)
        OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = v_migrator)
    ) THEN
        RAISE EXCEPTION 'Marked database is missing a tenant role; manual review required' USING ERRCODE = '55000';
    END IF;

    SELECT shobj_description(r.oid, 'pg_authid'), r.rolcanlogin, r.rolsuper,
           r.rolcreatedb, r.rolcreaterole, r.rolreplication, r.rolbypassrls, r.rolinherit
      INTO v_comment, v_login, v_super, v_createdb, v_createrole, v_replication, v_bypassrls, v_inherit
      FROM pg_roles r WHERE r.rolname = v_owner;
    IF NOT FOUND THEN
        EXECUTE format('CREATE ROLE %I NOLOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS', v_owner);
        EXECUTE format('COMMENT ON ROLE %I IS %L', v_owner,
            'berkah-pos:tenant-role:v1;tenant=' || p_tenant_id || ';kind=owner');
        INSERT INTO provisioning.audit_events(tenant_id, action, target, actor)
        VALUES (p_tenant_id, 'role_created', v_owner, SESSION_USER);
    ELSIF v_comment <> 'berkah-pos:tenant-role:v1;tenant=' || p_tenant_id || ';kind=owner'
       OR v_login OR v_super OR v_createdb OR v_createrole OR v_replication OR v_bypassrls OR v_inherit THEN
        RAISE EXCEPTION 'Tenant owner role provenance or attributes mismatch' USING ERRCODE = '55000';
    END IF;

    SELECT shobj_description(r.oid, 'pg_authid'), r.rolcanlogin, r.rolsuper,
           r.rolcreatedb, r.rolcreaterole, r.rolreplication, r.rolbypassrls, r.rolinherit
      INTO v_comment, v_login, v_super, v_createdb, v_createrole, v_replication, v_bypassrls, v_inherit
      FROM pg_roles r WHERE r.rolname = v_runtime;
    IF NOT FOUND THEN
        IF v_database_exists THEN
            RAISE EXCEPTION 'Marked database is missing its runtime role' USING ERRCODE = '55000';
        END IF;
        EXECUTE format(
            'CREATE ROLE %I LOGIN NOINHERIT CONNECTION LIMIT 30 NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD %L',
            v_runtime, p_runtime_verifier
        );
        EXECUTE format('COMMENT ON ROLE %I IS %L', v_runtime,
            'berkah-pos:tenant-role:v1;tenant=' || p_tenant_id || ';kind=runtime');
        INSERT INTO provisioning.audit_events(tenant_id, action, target, actor)
        VALUES (p_tenant_id, 'role_created', v_runtime, SESSION_USER);
    ELSIF v_comment <> 'berkah-pos:tenant-role:v1;tenant=' || p_tenant_id || ';kind=runtime'
       OR NOT v_login OR v_super OR v_createdb OR v_createrole OR v_replication OR v_bypassrls OR v_inherit THEN
        RAISE EXCEPTION 'Tenant runtime role provenance or attributes mismatch' USING ERRCODE = '55000';
    END IF;

    SELECT shobj_description(r.oid, 'pg_authid'), r.rolcanlogin, r.rolsuper,
           r.rolcreatedb, r.rolcreaterole, r.rolreplication, r.rolbypassrls, r.rolinherit
      INTO v_comment, v_login, v_super, v_createdb, v_createrole, v_replication, v_bypassrls, v_inherit
      FROM pg_roles r WHERE r.rolname = v_migrator;
    IF NOT FOUND THEN
        IF v_database_exists THEN
            RAISE EXCEPTION 'Marked database is missing its migrator role' USING ERRCODE = '55000';
        END IF;
        EXECUTE format(
            'CREATE ROLE %I LOGIN NOINHERIT CONNECTION LIMIT 3 NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD %L',
            v_migrator, p_migrator_verifier
        );
        EXECUTE format('COMMENT ON ROLE %I IS %L', v_migrator,
            'berkah-pos:tenant-role:v1;tenant=' || p_tenant_id || ';kind=migrator');
        INSERT INTO provisioning.audit_events(tenant_id, action, target, actor)
        VALUES (p_tenant_id, 'role_created', v_migrator, SESSION_USER);
    ELSIF v_comment <> 'berkah-pos:tenant-role:v1;tenant=' || p_tenant_id || ';kind=migrator'
       OR NOT v_login OR v_super OR v_createdb OR v_createrole OR v_replication OR v_bypassrls OR v_inherit THEN
        RAISE EXCEPTION 'Tenant migrator role provenance or attributes mismatch' USING ERRCODE = '55000';
    END IF;

    SELECT database_name, owner_role, state
      INTO v_intent_database, v_intent_owner, v_intent_state
      FROM provisioning.tenant_provisioning_intents
     WHERE tenant_id = p_tenant_id;
    IF FOUND THEN
        IF v_intent_database <> v_database OR v_intent_owner <> v_owner
           OR v_intent_state NOT IN ('database_intent', 'provisioning') THEN
            RAISE EXCEPTION 'Existing durable tenant intent is inconsistent' USING ERRCODE = '55000';
        END IF;
    ELSE
        INSERT INTO provisioning.tenant_provisioning_intents
            (tenant_id, database_name, owner_role, state)
        VALUES (p_tenant_id, v_database, v_owner, 'database_intent');
    END IF;

    -- Role admin's NOLOGIN identity owns these memberships. Broker has SET, not ADMIN,
    -- on precisely the target tenant's owner and migrator while it is provisioning.
    IF EXISTS (
        SELECT 1 FROM pg_auth_members m
          JOIN pg_roles member ON member.oid = m.member
          JOIN pg_roles granted ON granted.oid = m.roleid
          JOIN pg_roles grantor ON grantor.oid = m.grantor
         WHERE member.rolname = 'berkah_provisioner'
           AND granted.rolname = v_owner
           AND grantor.rolname = 'berkah_role_admin'
           AND (m.admin_option OR m.inherit_option OR NOT m.set_option)
    ) OR EXISTS (
        SELECT 1 FROM pg_auth_members m
          JOIN pg_roles member ON member.oid = m.member
          JOIN pg_roles granted ON granted.oid = m.roleid
         WHERE member.rolname = 'berkah_provisioner' AND granted.rolname = v_owner
           AND NOT EXISTS (
               SELECT 1 FROM pg_roles grantor WHERE grantor.oid = m.grantor AND grantor.rolname = 'berkah_role_admin'
           )
    ) THEN
        RAISE EXCEPTION 'Owner role membership is unexpected; manual review required' USING ERRCODE = '55000';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_auth_members m
          JOIN pg_roles member ON member.oid = m.member
          JOIN pg_roles granted ON granted.oid = m.roleid
          JOIN pg_roles grantor ON grantor.oid = m.grantor
         WHERE member.rolname = 'berkah_provisioner'
           AND granted.rolname = v_owner
           AND grantor.rolname = 'berkah_role_admin'
           AND NOT m.admin_option AND NOT m.inherit_option AND m.set_option
    ) THEN
        EXECUTE format('GRANT %I TO %I WITH SET TRUE, INHERIT FALSE, ADMIN FALSE GRANTED BY %I',
            v_owner, 'berkah_provisioner', 'berkah_role_admin');
        INSERT INTO provisioning.audit_events(tenant_id, action, target, actor)
        VALUES (p_tenant_id, 'role_membership_granted', v_owner, SESSION_USER);
    END IF;

    IF EXISTS (
        SELECT 1 FROM pg_auth_members m
          JOIN pg_roles member ON member.oid = m.member
          JOIN pg_roles granted ON granted.oid = m.roleid
          JOIN pg_roles grantor ON grantor.oid = m.grantor
         WHERE member.rolname = 'berkah_provisioner'
           AND granted.rolname = v_migrator
           AND grantor.rolname = 'berkah_role_admin'
           AND (m.admin_option OR m.inherit_option OR NOT m.set_option)
    ) OR EXISTS (
        SELECT 1 FROM pg_auth_members m
          JOIN pg_roles member ON member.oid = m.member
          JOIN pg_roles granted ON granted.oid = m.roleid
         WHERE member.rolname = 'berkah_provisioner' AND granted.rolname = v_migrator
           AND NOT EXISTS (
               SELECT 1 FROM pg_roles grantor WHERE grantor.oid = m.grantor AND grantor.rolname = 'berkah_role_admin'
           )
    ) THEN
        RAISE EXCEPTION 'Migrator role membership is unexpected; manual review required' USING ERRCODE = '55000';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM pg_auth_members m
          JOIN pg_roles member ON member.oid = m.member
          JOIN pg_roles granted ON granted.oid = m.roleid
          JOIN pg_roles grantor ON grantor.oid = m.grantor
         WHERE member.rolname = 'berkah_provisioner'
           AND granted.rolname = v_migrator
           AND grantor.rolname = 'berkah_role_admin'
           AND NOT m.admin_option AND NOT m.inherit_option AND m.set_option
    ) THEN
        EXECUTE format('GRANT %I TO %I WITH SET TRUE, INHERIT FALSE, ADMIN FALSE GRANTED BY %I',
            v_migrator, 'berkah_provisioner', 'berkah_role_admin');
        INSERT INTO provisioning.audit_events(tenant_id, action, target, actor)
        VALUES (p_tenant_id, 'role_membership_granted', v_migrator, SESSION_USER);
    END IF;

    -- The broker temporarily SET ROLEs to this NOLOGIN owner when finalizing the
    -- database. Grant only the schema plus this exact function; finalization
    -- revokes both in the same transaction as the ready-state transition.
    EXECUTE format('GRANT USAGE ON SCHEMA provisioning TO %I', v_owner);
    EXECUTE format(
        'GRANT EXECUTE ON FUNCTION provisioning.finalize_tenant_roles(text) TO %I',
        v_owner
    );

    RETURN 'provisioning';
END
$function$;

CREATE OR REPLACE FUNCTION provisioning.release_tenant_roles(p_tenant_id text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, provisioning
AS $function$
DECLARE
    v_suffix text;
    v_owner text;
    v_runtime text;
    v_migrator text;
    v_comment text;
BEGIN
    IF SESSION_USER <> 'berkah_provisioner' THEN
        RAISE EXCEPTION 'Caller is not the dedicated provisioning broker' USING ERRCODE = '42501';
    END IF;
    IF p_tenant_id !~ '^[0-7][0-9A-HJKMNP-TV-Z]{25}$' THEN
        RAISE EXCEPTION 'Tenant identifier is not a canonical ULID' USING ERRCODE = '22023';
    END IF;

    v_suffix := lower(p_tenant_id);
    v_owner := 'berkah_owner_' || v_suffix;
    v_runtime := 'berkah_runtime_' || v_suffix;
    v_migrator := 'berkah_migrator_' || v_suffix;

    SELECT shobj_description(r.oid, 'pg_authid') INTO v_comment
      FROM pg_roles r WHERE r.rolname = v_owner;
    IF FOUND AND v_comment = 'berkah-pos:tenant-role:v1;tenant=' || p_tenant_id || ';kind=owner'
       AND EXISTS (
           SELECT 1 FROM pg_auth_members m
             JOIN pg_roles member ON member.oid = m.member
             JOIN pg_roles granted ON granted.oid = m.roleid
             JOIN pg_roles grantor ON grantor.oid = m.grantor
            WHERE member.rolname = 'berkah_provisioner'
              AND granted.rolname = v_owner AND grantor.rolname = 'berkah_role_admin'
       ) THEN
        EXECUTE format('REVOKE %I FROM %I GRANTED BY %I', v_owner, 'berkah_provisioner', 'berkah_role_admin');
        INSERT INTO provisioning.audit_events(tenant_id, action, target, actor)
        VALUES (p_tenant_id, 'role_membership_revoked', v_owner, SESSION_USER);
    END IF;

    SELECT shobj_description(r.oid, 'pg_authid') INTO v_comment
      FROM pg_roles r WHERE r.rolname = v_migrator;
    IF FOUND AND v_comment = 'berkah-pos:tenant-role:v1;tenant=' || p_tenant_id || ';kind=migrator'
       AND EXISTS (
           SELECT 1 FROM pg_auth_members m
             JOIN pg_roles member ON member.oid = m.member
             JOIN pg_roles granted ON granted.oid = m.roleid
             JOIN pg_roles grantor ON grantor.oid = m.grantor
            WHERE member.rolname = 'berkah_provisioner'
              AND granted.rolname = v_migrator AND grantor.rolname = 'berkah_role_admin'
       ) THEN
        EXECUTE format('REVOKE %I FROM %I GRANTED BY %I', v_migrator, 'berkah_provisioner', 'berkah_role_admin');
        INSERT INTO provisioning.audit_events(tenant_id, action, target, actor)
        VALUES (p_tenant_id, 'role_membership_revoked', v_migrator, SESSION_USER);
    END IF;

    -- The runtime role must never be a member of the broker. Do not delete/alter any role here.
    SELECT shobj_description(r.oid, 'pg_authid') INTO v_comment
      FROM pg_roles r WHERE r.rolname = v_runtime;
    IF FOUND AND v_comment = 'berkah-pos:tenant-role:v1;tenant=' || p_tenant_id || ';kind=runtime'
       AND pg_has_role('berkah_provisioner', v_runtime, 'MEMBER') THEN
        RAISE EXCEPTION 'Unexpected broker membership in runtime role; administrator review required' USING ERRCODE = '55000';
    END IF;
END
$function$;

CREATE OR REPLACE FUNCTION provisioning.finalize_tenant_roles(p_tenant_id text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, provisioning
AS $function$
DECLARE
    v_suffix text;
    v_owner text;
    v_runtime text;
    v_migrator text;
    v_database text;
    v_db_owner text;
    v_db_comment text;
BEGIN
    IF SESSION_USER <> 'berkah_provisioner' THEN
        RAISE EXCEPTION 'Caller is not the dedicated provisioning broker' USING ERRCODE = '42501';
    END IF;
    IF p_tenant_id !~ '^[0-7][0-9A-HJKMNP-TV-Z]{25}$' THEN
        RAISE EXCEPTION 'Tenant identifier is not a canonical ULID' USING ERRCODE = '22023';
    END IF;

    v_suffix := lower(p_tenant_id);
    v_owner := 'berkah_owner_' || v_suffix;
    v_runtime := 'berkah_runtime_' || v_suffix;
    v_migrator := 'berkah_migrator_' || v_suffix;
    v_database := 'berkahpos_t_' || v_suffix;

    SELECT pg_get_userbyid(d.datdba), shobj_description(d.oid, 'pg_database')
      INTO v_db_owner, v_db_comment
      FROM pg_database d WHERE d.datname = v_database;
    IF NOT FOUND OR v_db_owner <> v_owner
       OR v_db_comment <> 'berkah-pos:tenant-db:v1;tenant=' || p_tenant_id || ';state=ready' THEN
        RAISE EXCEPTION 'Refusing final role closure before the database-ready marker' USING ERRCODE = '55000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_roles
         WHERE rolname = v_owner
           AND shobj_description(oid, 'pg_authid') = 'berkah-pos:tenant-role:v1;tenant=' || p_tenant_id || ';kind=owner'
           AND NOT rolcanlogin AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole
           AND NOT rolreplication AND NOT rolbypassrls AND NOT rolinherit
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_roles
         WHERE rolname = v_runtime
           AND shobj_description(oid, 'pg_authid') = 'berkah-pos:tenant-role:v1;tenant=' || p_tenant_id || ';kind=runtime'
           AND rolcanlogin AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole
           AND NOT rolreplication AND NOT rolbypassrls AND NOT rolinherit
    ) OR NOT EXISTS (
        SELECT 1 FROM pg_roles
         WHERE rolname = v_migrator
           AND shobj_description(oid, 'pg_authid') = 'berkah-pos:tenant-role:v1;tenant=' || p_tenant_id || ';kind=migrator'
           AND rolcanlogin
           AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole
           AND NOT rolreplication AND NOT rolbypassrls AND NOT rolinherit
    ) THEN
        RAISE EXCEPTION 'Final role provenance or attributes are invalid' USING ERRCODE = '55000';
    END IF;

    -- This function runs in the same transaction as the caller's ready-marker/ACL
    -- update. A crash cannot leave the database ready while the migrator remains login.
    EXECUTE format('ALTER ROLE %I NOLOGIN', v_migrator);
    EXECUTE format('REVOKE %I FROM %I GRANTED BY %I', v_owner, 'berkah_provisioner', 'berkah_role_admin');
    INSERT INTO provisioning.audit_events(tenant_id, action, target, actor)
    VALUES (p_tenant_id, 'role_membership_revoked', v_owner, SESSION_USER);
    EXECUTE format('REVOKE %I FROM %I GRANTED BY %I', v_migrator, 'berkah_provisioner', 'berkah_role_admin');
    INSERT INTO provisioning.audit_events(tenant_id, action, target, actor)
    VALUES (p_tenant_id, 'role_membership_revoked', v_migrator, SESSION_USER);
    INSERT INTO provisioning.audit_events(tenant_id, action, target, actor)
    VALUES (p_tenant_id, 'tenant_ready', 'state:ready', SESSION_USER);
    UPDATE provisioning.tenant_provisioning_intents
       SET state = 'ready', updated_at = clock_timestamp()
     WHERE tenant_id = p_tenant_id
       AND database_name = v_database
       AND owner_role = v_owner
       AND state = 'provisioning';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Durable provisioning intent cannot transition to ready' USING ERRCODE = '55000';
    END IF;

    -- Revoke the temporary maintenance-schema capability before the same
    -- transaction commits the ready marker and runtime/migrator ACL transition.
    EXECUTE format(
        'REVOKE EXECUTE ON FUNCTION provisioning.finalize_tenant_roles(text) FROM %I',
        v_owner
    );
    EXECUTE format('REVOKE USAGE ON SCHEMA provisioning FROM %I', v_owner);
    RETURN 'ready';
END
$function$;

RESET ROLE;

REVOKE ALL ON ALL FUNCTIONS IN SCHEMA provisioning FROM PUBLIC;
GRANT EXECUTE ON FUNCTION provisioning.record_event(text, text, text) TO berkah_provisioner;
GRANT EXECUTE ON FUNCTION provisioning.mark_provisioning_intent(text) TO berkah_provisioner;
GRANT EXECUTE ON FUNCTION provisioning.ensure_tenant_roles(text, text, text) TO berkah_provisioner;
GRANT EXECUTE ON FUNCTION provisioning.finalize_tenant_roles(text) TO berkah_provisioner;
