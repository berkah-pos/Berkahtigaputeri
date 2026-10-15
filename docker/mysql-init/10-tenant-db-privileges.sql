-- Applied only by the MariaDB image's first-boot init process as root.
-- Normal web and queue runtimes never receive root or provisioner credentials.

REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'berkahpos_app'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE
ON `berkahpos\\_central`.* TO 'berkahpos_app'@'%';

-- The private provisioner has CREATE only on tenant-prefixed databases (not
-- globally), plus global CREATE USER because MariaDB account creation is a
-- global privilege. It has no global DROP/ALTER or global DML privileges.
GRANT CREATE ON `berkahpos\\_tenant\\_%`.* TO 'berkahpos_provisioner'@'%';
GRANT CREATE USER ON *.* TO 'berkahpos_provisioner'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE
ON `berkahpos\\_tenant\\_%`.* TO 'berkahpos_provisioner'@'%' WITH GRANT OPTION;

-- The migrator is only present in the private tenant-provisioner service.
-- DDL is schema-pattern scoped and has no GRANT OPTION or DROP privilege.
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES
ON `berkahpos\\_tenant\\_%`.* TO 'berkahpos_migrator'@'%';

FLUSH PRIVILEGES;
