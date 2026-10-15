-- Application runtime account: scoped CRUD/index/reference privileges only.
-- MariaDB reports a metadata-only "GRANT USAGE ON *.*" for accounts with no
-- global grants; this account must not have any global privilege or GRANT OPTION.
REVOKE ALL PRIVILEGES, GRANT OPTION FROM 'berkahpos_app'@'%';

GRANT SELECT, INSERT, UPDATE, DELETE, INDEX, REFERENCES
ON \`berkahpos_central\`.* TO 'berkahpos_app'@'%';

GRANT SELECT, INSERT, UPDATE, DELETE, INDEX, REFERENCES
ON \`berkahpos_tenant_%\`.* TO 'berkahpos_app'@'%';

-- Provisioner credentials are created separately by 00-create-provisioner.sh.
-- Global DDL/GRANT OPTION is reserved for explicit Artisan CLI provisioning only.
GRANT CREATE, DROP, ALTER, INDEX, REFERENCES
ON *.* TO 'berkahpos_provisioner'@'%' WITH GRANT OPTION;

GRANT SELECT, INSERT, UPDATE, DELETE, INDEX, REFERENCES
ON \`berkahpos_central\`.* TO 'berkahpos_provisioner'@'%';

GRANT SELECT, INSERT, UPDATE, DELETE, INDEX, REFERENCES
ON \`berkahpos_tenant_%\`.* TO 'berkahpos_provisioner'@'%';

FLUSH PRIVILEGES;
