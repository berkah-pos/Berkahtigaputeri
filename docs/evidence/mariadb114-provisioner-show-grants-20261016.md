# Raw SHOW GRANTS Evidence — MariaDB 11.4 (credentials redacted)

- Run: https://github.com/berkah-pos/Berkahtigaputeri/actions/runs/38887137050
- Candidate under test: security/phase-6-kvm2-backup-budget-audit-20261016
- Purpose: independent disposable-database reproduction of the provisioner compromise boundary.
- Service: MariaDB 11.4.13 in an ephemeral GitHub Actions service container.
- Data: synthetic databases and rows only. No production/shared-staging system was contacted.
- Redaction: any `IDENTIFIED BY PASSWORD` values were replaced by `[REDACTED]`; ephemeral test credentials are not included here.

## Actual SHOW GRANTS for central app account

```sql
GRANT USAGE ON *.* TO `berkahpos_app`@`%` IDENTIFIED BY PASSWORD '[REDACTED]'
GRANT SELECT, INSERT, UPDATE, DELETE ON `berkahpos\\_central`.* TO `berkahpos_app`@`%`
```

## Actual SHOW GRANTS for private provisioner

```sql
GRANT CREATE USER ON *.* TO `berkahpos_provisioner`@`%` IDENTIFIED BY PASSWORD '[REDACTED]'
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE ON `berkahpos\\_t\\_%`.* TO `berkahpos_provisioner`@`%` WITH GRANT OPTION
```

## Actual SHOW GRANTS for private migrator

```sql
GRANT USAGE ON *.* TO `berkahpos_migrator`@`%` IDENTIFIED BY PASSWORD '[REDACTED]'
GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, REFERENCES, INDEX, ALTER ON `berkahpos\\_t\\_%`.* TO `berkahpos_migrator`@`%`
```

## Actual SHOW GRANTS after simulated provisioner compromise

The provisioner created the synthetic principal `audit_compromised_principal` and delegated CRUD on the wildcard tenant schema pattern.

```sql
GRANT USAGE ON *.* TO `audit_compromised_principal`@`%` IDENTIFIED BY PASSWORD '[REDACTED]'
GRANT SELECT, INSERT, UPDATE, DELETE ON `berkahpos\\_t\\_%`.* TO `audit_compromised_principal`@`%`
```

## Observed operations

The red-team script:
- Created `audit_compromised_principal` using the provisioner credential.
- Granted the new principal SELECT/INSERT/UPDATE/DELETE on the same tenant-name wildcard.
- Successfully read the synthetic marker row in tenant A.
- Successfully read the synthetic marker row in tenant B.
- Successfully updated the synthetic marker row in tenant A.
- Successfully updated the synthetic marker row in tenant B.

The workflow output says `SECURITY GATE: FAIL`. The workflow job itself is green because its test objective is to reproduce this expected vulnerability. Do not use that job conclusion as proof of isolation.
