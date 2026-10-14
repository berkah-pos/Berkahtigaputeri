-- This login is confined to the private Compose network. It requires global DDL
-- so stancl/tenancy can provision each tenant database on this one MariaDB host.
-- No database or Redis port is published to the host.
GRANT CREATE, DROP, ALTER, INDEX, SELECT, INSERT, UPDATE, DELETE, REFERENCES
ON *.* TO 'berkahpos_app'@'%';
FLUSH PRIVILEGES;
