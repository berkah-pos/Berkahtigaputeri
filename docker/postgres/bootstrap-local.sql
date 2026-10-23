\\set ON_ERROR_STOP on

-- This helper is for a private, disposable local Compose database only.
-- It must never be used to provision production or real tenant databases.
SELECT (current_user = :'bootstrap_role' AND rolsuper) AS bootstrap_is_superuser
FROM pg_roles
WHERE rolname = current_user
\\gset
\\if :bootstrap_is_superuser
\\else
\\echo 'ERROR: local database bootstrap must run as its dedicated bootstrap superuser.'
\\quit 4
\\endif

SELECT (current_database() = :'central_database') AS correct_target_database
\\gset
\\if :correct_target_database
\\else
\\echo 'ERROR: local bootstrap target does not match the connected database.'
\\quit 4
\\endif

SELECT (:'runtime_role' <> :'bootstrap_role') AS distinct_runtime_role
\\gset
\\if :distinct_runtime_role
\\else
\\echo 'ERROR: runtime role must be different from the PostgreSQL bootstrap role.'
\\quit 4
\\endif

SELECT format(
    'CREATE ROLE %I WITH LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD %L',
    :'runtime_role',
    :'runtime_password'
)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'runtime_role')
\\gexec

-- Existing roles are not silently trusted: refuse to continue if the runtime
-- identity has inherited/SET ROLE memberships or owns database/application
-- objects already present in this local PostgreSQL cluster.
SELECT EXISTS (
    SELECT 1
    FROM pg_auth_members
    WHERE member = (SELECT oid FROM pg_roles WHERE rolname = :'runtime_role')
) AS runtime_has_memberships
\\gset
\\if :runtime_has_memberships
\\echo 'ERROR: local runtime role has role memberships; inspect and reconcile it manually.'
\\quit 5
\\endif

SELECT (
    EXISTS (SELECT 1 FROM pg_database WHERE datdba = (SELECT oid FROM pg_roles WHERE rolname = :'runtime_role'))
    OR EXISTS (SELECT 1 FROM pg_class WHERE relowner = (SELECT oid FROM pg_roles WHERE rolname = :'runtime_role'))
    OR EXISTS (SELECT 1 FROM pg_namespace WHERE nspowner = (SELECT oid FROM pg_roles WHERE rolname = :'runtime_role'))
    OR EXISTS (SELECT 1 FROM pg_proc WHERE proowner = (SELECT oid FROM pg_roles WHERE rolname = :'runtime_role'))
    OR EXISTS (SELECT 1 FROM pg_type WHERE typowner = (SELECT oid FROM pg_roles WHERE rolname = :'runtime_role'))
) AS runtime_owns_objects
\\gset
\\if :runtime_owns_objects
\\echo 'ERROR: local runtime role owns database or schema objects; inspect and reconcile ownership manually.'
\\quit 5
\\endif

ALTER ROLE :"runtime_role"
    WITH LOGIN NOINHERIT NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS
    PASSWORD :'runtime_password';

REVOKE ALL ON DATABASE :"central_database" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"central_database" TO :"runtime_role";

REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO :"runtime_role";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO :"runtime_role";
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO :"runtime_role";

-- Local developer migrations are run only through the explicit one-shot
-- dev-migrate profile, not through the web/queue app service.
ALTER DEFAULT PRIVILEGES FOR ROLE :"bootstrap_role" IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"runtime_role";
ALTER DEFAULT PRIVILEGES FOR ROLE :"bootstrap_role" IN SCHEMA public
    GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO :"runtime_role";
