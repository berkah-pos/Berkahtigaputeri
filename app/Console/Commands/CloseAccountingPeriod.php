<?php

namespace App\\Console\\Commands;

use App\\Services\\TenantDatabaseRunner;
use Illuminate\\Console\\Command;
use Illuminate\\Database\\Connection;
use Illuminate\\Support\\Facades\\DB;
use Throwable;

class CloseAccountingPeriod extends Command
{
    protected $signature = 'accounting:close-period
        {tenant_id : The centrally registered tenant ID}
        {period : Accounting period in YYYY-MM format}
        {--actor-user-id= : Active platform super-admin user ID for the audit trail}
        {--reason= : Mandatory reason for closing the period}';

    protected $description = 'Close a tenant accounting period and permanently prevent further postings into it.';

    public function handle(TenantDatabaseRunner $runner): int
    {
        $tenantId = trim((string) $this->argument('tenant_id'));
        $period = trim((string) $this->argument('period'));
        $actorId = filter_var($this->option('actor-user-id'), FILTER_VALIDATE_INT);
        $reason = trim((string) $this->option('reason'));

        if ($tenantId === '' || strlen($tenantId) > 150) {
            $this->error('Tenant ID must contain between 1 and 150 characters.');
            return self::FAILURE;
        }

        if (! preg_match('/^([0-9]{4})-(0[1-9]|1[0-2])$/', $period, $matches)
            || ! checkdate((int) $matches[2], 1, (int) $matches[1])) {
            $this->error('Period must be a valid YYYY-MM value.');
            return self::FAILURE;
        }

        if (! is_int($actorId) || $actorId < 1) {
            $this->error('--actor-user-id must identify an active platform super-admin.');
            return self::FAILURE;
        }

        if (strlen($reason) < 10 || strlen($reason) > 500) {
            $this->error('--reason must contain between 10 and 500 characters.');
            return self::FAILURE;
        }

        $actorIsAuthorized = DB::connection('central')->table('users')
            ->where('id', $actorId)
            ->where('is_active', true)
            ->where('is_super_admin', true)
            ->exists();

        if (! $actorIsAuthorized) {
            $this->error('The audit actor must be an active platform super-admin.');
            return self::FAILURE;
        }

        try {
            $created = $runner->run(
                $tenantId,
                function (Connection $connection) use ($period, $actorId, $reason): bool {
                    $existing = $connection->table('accounting_periods')
                        ->where('period_key', $period)
                        ->lockForUpdate()
                        ->first();

                    if ($existing !== null && $existing->status === 'closed') {
                        return false;
                    }

                    $now = now();
                    $values = [
                        'status' => 'closed',
                        'closed_at' => $now,
                        'closed_by_user_id' => $actorId,
                        'close_reason' => $reason,
                        'updated_at' => $now,
                    ];

                    if ($existing === null) {
                        $connection->table('accounting_periods')->insert($values + [
                            'period_key' => $period,
                            'created_at' => $now,
                        ]);
                    } else {
                        $connection->table('accounting_periods')
                            ->where('period_key', $period)
                            ->update($values);
                    }

                    // The PostgreSQL AFTER trigger appends an immutable audit event
                    // in the same transaction as the period closure.
                    return true;
                }
            );
        } catch (Throwable $exception) {
            report($exception);
            $this->error('Could not close the accounting period. Verify tenant provisioning and database availability.');
            return self::FAILURE;
        }

        if (! $created) {
            $this->warn("Accounting period {$period} is already closed; no changes were made.");
            return self::SUCCESS;
        }

        $this->info("Closed accounting period {$period} for tenant {$tenantId}.");
        return self::SUCCESS;
    }
}
