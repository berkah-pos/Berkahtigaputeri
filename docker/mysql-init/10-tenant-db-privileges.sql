-- Application runtime account: scoped CRUD/index/reference privileges only.
-- MariaDB may show metadata-only "GRANT USAGE ON *.*" for a database user.
-- No global privileges or GRANT OPTION are permitted for the app account.
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'berkahpos_app'@'%';

GRANT SELECT, INSERT, UPDATE, DELETE, INDEX, REFERENCES
ON `berkahpos\_central`.* TO 'berkahpos_app'@'%';

GRANT SELECT, INSERT, UPDATE, DELETE, INDEX, REFERENCES
ON `berkahpos\_tenant\_%`.* TO 'berkahpos_app'@'%';

-- Provisioner credentials are created separately by 00-create-provisioner.sh.
-- Global DDL/GRANT OPTION is reserved for explicit Artisan CLI provisioning only.
GRANT CREATE, DROP, ALTER, INDEX, REFERENCES
ON *.* TO 'berkahpos_provisioner'@'%' WITH GRANT OPTION;

GRANT SELECT, INSERT, UPDATE, DELETE, INDEX, REFERENCES
ON `berkahpos\_central`.* TO 'berkahpos_provisioner'@'%';

GRANT SELECT, INSERT, UPDATE, DELETE, INDEX, REFERENCES
ON `berkahpos\_tenant\_%`.* TO 'berkahpos_provisioner'@'%';

FLUSH PRIVILEGES;
