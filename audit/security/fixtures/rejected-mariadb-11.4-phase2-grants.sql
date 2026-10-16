-- HISTORICAL SECURITY FIXTURE ONLY; do not apply to the selected PostgreSQL 17 target.
-- Exact grant policy copied from rejected candidate branch
-- security/independent-kvm2-isolation-review-20261016:
-- docker/mysql-init/10-tenant-db-privileges.sql
-- source blob: b3bc64b71ce453be5a9b88556b72654dce562423
--
-- This intentionally preserves the suspect grants so a disposable MariaDB 11.4
-- test can characterize the compromised-provisioner blast radius. It is not
-- an approved runtime migration and must not be used outside that throwaway test.

REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'berkahpos_app'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE
ON `berkahpos\_central`.* TO 'berkahpos_app'@'%';

GRANT CREATE ON `berkahpos\_t\_%`.* TO 'berkahpos_provisioner'@'%';
GRANT CREATE USER ON *.* TO 'berkahpos_provisioner'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE
ON `berkahpos\_t\_%`.* TO 'berkahpos_provisioner'@'%' WITH GRANT OPTION;

GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES
ON `berkahpos\_t\_%`.* TO 'berkahpos_migrator'@'%';

FLUSH PRIVILEGES;
