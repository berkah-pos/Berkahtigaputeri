\set ON_ERROR_STOP on

-- This helper is for a private, disposable local Compose database only.
-- It must never be used to provision production or real tenant databases.
SELECT (current_user = :'bootstrap_role' AND rolsuper) AS bootstrap_is_superuser
FROM pg_roles
WHERE rolname = current_user
\gset
\if :bootstrap_is_superuser
\else
\echo 'ERROR: local database bootstrap must run as its dedicated bootstrap superuser.'
\quit 4
\endif

SELECT (current_database() = :'central_database') AS correct_target_database
\gset
\if :correct_target_database
\else
\echo 'ERROR: local bootstrap target does not match the connected database.'
\quit 4
\endif

SELECT (:'runtime_role' <> :'bootstrap_role') AS distinct_runtime_role
\gset
\if :distinct_runtime_role
\else
\echo 'ERROR: runtime role must be different from the PostgreSQL bootstrap role.'
\quit 4
\endif

-- An existing role must carry our marker before this helper will change
-- it. This prevents a name collision from silently adopting another identity.
SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'runtime_role') AS runtime_role_exists
\gset
\if :runtime_role_exists
SELECT (shobj_description(oid, 'pg_authid') = 'berkahpos-local-compose-runtime-v1') AS runtime_role_is_managed
FROM pg_roles
WHERE rolname = :'runtime_role'
\gset
\if :runtime_role_is_managed
\else
\echo 'ERROR: runtime role already exists but is not owned by the local Compose bootstrap contract.'
\quit 5
\endif
\else
SELECT format(
    'CREATE ROLE %I WITH LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD %L',
    :'runtime_role',
    :'runtime_password'
)
\gexec
COMMENT ON ROLE :"runtime_role" IS 'berkahpos-local-compose-runtime-v1';
\endif

-- Refuse to adopt roles with inherited/SET ROLE memberships, unexpected
-- database grants, or ownership of existing database/application objects.
-- Existing roles are not silently trusted: refuse to continue if the runtime
-- identity has inherited/SET ROLE memberships or owns database/application
-- objects already present in this local PostgreSQL cluster.
SELECT EXISTS (
    SELECT 1
    FROM pg_auth_members
    WHERE member = (SELECT oid FROM pg_roles WHERE rolname = :'runtime_role')
) AS runtime_has_memberships
\gset
\if :runtime_has_memberships
\echo 'ERROR: local runtime role has role memberships; inspect and reconcile it manually.'
\quit 5
\endif

SELECT EXISTS (
    SELECT 1
    FROM pg_database d
    CROSS JOIN LATERAL aclexplode(COALESCE(d.datacl, acldefault('d', d.datdba))) acl
    WHERE d.datname <> :'central_database'
      AND acl.grantee = (SELECT oid FROM pg_roles WHERE rolname = :'runtime_role')
      AND acl.privilege_type IN ('CONNECT', 'CREATE', 'TEMPORARY')
) AS runtime_has_other_database_grants
\gset
\if :runtime_has_other_database_grants
\echo 'ERROR: local runtime role has direct privileges on another database; inspect and reconcile manually.'
\quit 5
\endif

SELECT (
    EXISTS (SELECT 1 FROM pg_database WHERE datdba = (SELECT oid FROM pg_roles WHERE rolname = :'runtime_role'))
    OR EXISTS (SELECT 1 FROM pg_class WHERE relowner = (SELECT oid FROM pg_roles WHERE rolname = :'runtime_role'))
    OR EXISTS (SELECT 1 FROM pg_namespace WHERE nspowner = (SELECT oid FROM pg_roles WHERE rolname = :'runtime_role'))
    OR EXISTS (SELECT 1 FROM pg_proc WHERE proowner = (SELECT oid FROM pg_roles WHERE rolname = :'runtime_role'))
    OR EXISTS (SELECT 1 FROM pg_type WHERE typowner = (SELECT oid FROM pg_roles WHERE rolname = :'runtime_role'))
) AS runtime_owns_objects
\gset
\if :runtime_owns_objects
\echo 'ERROR: local runtime role owns database or schema objects; inspect and reconcile ownership manually.'
\quit 5
\endif

ALTER ROLE :"runtime_role"
    WITH LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS
    PASSWORD :'runtime_password';

REVOKE ALL ON DATABASE :"central_database" FROM PUBLIC;
REVOKE ALL ON DATABASE :"central_database" FROM :"runtime_role";
GRANT CONNECT ON DATABASE :"central_database" TO :"runtime_role";

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON SCHEMA public FROM :"runtime_role";
GRANT USAGE ON SCHEMA public TO :"runtime_role";
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM PUBLIC, :"runtime_role";
REVOKE ALL ON ALL SEQUENCES IN SCHEMA public FROM PUBLIC, :"runtime_role";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO :"runtime_role";
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO :"runtime_role";

-- Local developer migrations are run only through the explicit one-shot
-- dev-migrate profile, not through the web/queue app service.
ALTER DEFAULT PRIVILEGES FOR ROLE :"bootstrap_role" IN SCHEMA public
    REVOKE ALL ON TABLES FROM PUBLIC, :"runtime_role";
ALTER DEFAULT PRIVILEGES FOR ROLE :"bootstrap_role" IN SCHEMA public
    REVOKE ALL ON SEQUENCES FROM PUBLIC, :"runtime_role";
ALTER DEFAULT PRIVILEGES FOR ROLE :"bootstrap_role" IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"runtime_role";
ALTER DEFAULT PRIVILEGES FOR ROLE :"bootstrap_role" IN SCHEMA public
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO :"runtime_role";
