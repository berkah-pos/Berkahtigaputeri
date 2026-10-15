-- Applied only by the MariaDB image's first-boot init process as root.
-- Normal web and queue runtimes never receive root or provisioner credentials.

REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'berkahpos_app'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE
ON `berkahpos\_central`.* TO 'berkahpos_app'@'%';

-- The private provisioner can create schemas and users, but has no global
-- DML grants and no DROP/ALTER privilege. Its data grants are restricted to
-- tenant database names; GRANT OPTION is limited to those CRUD privileges.
GRANT CREATE, CREATE USER ON *.* TO 'berkahpos_provisioner'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE
ON `berkahpos\_tenant\_%`.* TO 'berkahpos_provisioner'@'%' WITH GRANT OPTION;

-- The migrator is only present in the private tenant-provisioner service.
-- DDL is schema-pattern scoped and has no GRANT OPTION or DROP privilege.
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES
ON `berkahpos\_tenant\_%`.* TO 'berkahpos_migrator'@'%';

FLUSH PRIVILEGES;
