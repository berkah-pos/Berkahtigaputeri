\set ON_ERROR_STOP on
\getenv central_db CENTRAL_DB_DATABASE
\getenv central_runtime_username CENTRAL_DB_USERNAME
\getenv central_runtime_password CENTRAL_DB_PASSWORD
\getenv central_migrator_username CENTRAL_DB_MIGRATOR_USERNAME
\getenv central_migrator_password CENTRAL_DB_MIGRATOR_PASSWORD
\getenv tenant_db TENANT_DB_DATABASE
\getenv tenant_runtime_username TENANT_DB_USERNAME
\getenv tenant_runtime_password TENANT_DB_PASSWORD
\getenv tenant_migrator_username TENANT_DB_MIGRATOR_USERNAME
\getenv tenant_migrator_password TENANT_DB_MIGRATOR_PASSWORD

-- This script is mounted only by local development Compose.
-- The bootstrap account never enters the app container.
REVOKE CONNECT ON DATABASE postgres FROM PUBLIC;

SELECT format(
  'CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
  :'central_migrator_username', :'central_migrator_password'
)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'central_migrator_username') \gexec;
SELECT format(
  'ALTER ROLE %I WITH LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
  :'central_migrator_username', :'central_migrator_password'
) \gexec;
SELECT format(
  'CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
  :'central_runtime_username', :'central_runtime_password'
)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'central_runtime_username') \gexec;
SELECT format(
  'ALTER ROLE %I WITH LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
  :'central_runtime_username', :'central_runtime_password'
) \gexec;

SELECT format(
  'CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
  :'tenant_migrator_username', :'tenant_migrator_password'
)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'tenant_migrator_username') \gexec;
SELECT format(
  'ALTER ROLE %I WITH LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
  :'tenant_migrator_username', :'tenant_migrator_password'
) \gexec;
SELECT format(
  'CREATE ROLE %I LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
  :'tenant_runtime_username', :'tenant_runtime_password'
)
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'tenant_runtime_username') \gexec;
SELECT format(
  'ALTER ROLE %I WITH LOGIN PASSWORD %L NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS',
  :'tenant_runtime_username', :'tenant_runtime_password'
) \gexec;

SELECT format('CREATE DATABASE %I OWNER %I', :'central_db', :'central_migrator_username')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'central_db') \gexec;
SELECT format('CREATE DATABASE %I OWNER %I', :'tenant_db', :'tenant_migrator_username')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'tenant_db') \gexec;

SELECT format('REVOKE ALL PRIVILEGES ON DATABASE %I FROM PUBLIC', :'central_db') \gexec;
SELECT format('GRANT CONNECT ON DATABASE %I TO %I, %I',
  :'central_db', :'central_migrator_username', :'central_runtime_username') \gexec;
SELECT format('REVOKE ALL PRIVILEGES ON DATABASE %I FROM PUBLIC', :'tenant_db') \gexec;
SELECT format('GRANT CONNECT ON DATABASE %I TO %I, %I',
  :'tenant_db', :'tenant_migrator_username', :'tenant_runtime_username') \gexec;

\connect :central_db
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO :"central_migrator_username";
GRANT USAGE ON SCHEMA public TO :"central_runtime_username";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO :"central_runtime_username";
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO :"central_runtime_username";
ALTER DEFAULT PRIVILEGES FOR ROLE :"central_migrator_username" IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"central_runtime_username";
ALTER DEFAULT PRIVILEGES FOR ROLE :"central_migrator_username" IN SCHEMA public
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO :"central_runtime_username";

\connect :tenant_db
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO :"tenant_migrator_username";
GRANT USAGE ON SCHEMA public TO :"tenant_runtime_username";
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO :"tenant_runtime_username";
GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO :"tenant_runtime_username";
ALTER DEFAULT PRIVILEGES FOR ROLE :"tenant_migrator_username" IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO :"tenant_runtime_username";
ALTER DEFAULT PRIVILEGES FOR ROLE :"tenant_migrator_username" IN SCHEMA public
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO :"tenant_runtime_username";
