<?php

namespace Tests\\Feature;

use Illuminate\\Database\\Connection;
use Illuminate\\Database\\QueryException;
use Illuminate\\Support\\Facades\\DB;
use Tests\\TestCase;

class TenantAccountingInvariantTest extends TestCase
{
    private Connection $tenantDb;

    protected function setUp(): void
    {
        parent::setUp();

        $this->tenantDb = DB::connection('tenant_migrator');
        $this->tenantDb->beginTransaction();
    }

    protected function tearDown(): void
    {
        if (isset($this->tenantDb)) {
            while ($this->tenantDb->transactionLevel() > 0) {
                $this->tenantDb->rollBack();
            }
        }

        parent::tearDown();
    }

    public function test_balanced_journal_can_be_posted(): void
    {
        $this->insertDraftJournal('invariant-balanced', '2026-10-21', [
            ['debit' => 12500, 'credit' => 0],
            ['debit' => 0, 'credit' => 12500],
        ]);

        $changed = $this->tenantDb->table('journal_entries')
            ->where('id', 'invariant-balanced')
            ->update(['status' => 'posted', 'updated_at' => now()]);

        $this->assertSame(1, $changed);
        $this->assertSame('posted', $this->tenantDb->table('journal_entries')
            ->where('id', 'invariant-balanced')->value('status'));
    }

    public function test_unbalanced_journal_cannot_be_posted(): void
    {
        $this->insertDraftJournal('invariant-unbalanced', '2026-10-21', [
            ['debit' => 12500, 'credit' => 0],
            ['debit' => 0, 'credit' => 12499],
        ]);

        $this->assertDatabaseRejected(
            fn () => $this->tenantDb->table('journal_entries')
                ->where('id', 'invariant-unbalanced')
                ->update(['status' => 'posted', 'updated_at' => now()]),
            'must contain at least two balanced debit/credit lines'
        );
    }

    public function test_posted_journal_header_and_lines_are_immutable(): void
    {
        $this->insertDraftJournal('invariant-immutable', '2026-10-21', [
            ['debit' => 200, 'credit' => 0],
            ['debit' => 0, 'credit' => 200],
        ]);
        $this->postDraftJournal('invariant-immutable');

        $lineId = $this->tenantDb->table('journal_lines')
            ->where('journal_entry_id', 'invariant-immutable')
            ->value('id');

        $this->assertDatabaseRejected(
            fn () => $this->tenantDb->table('journal_entries')
                ->where('id', 'invariant-immutable')
                ->update(['description' => 'tampered', 'updated_at' => now()]),
            'Posted journal entries are immutable'
        );
        $this->assertDatabaseRejected(
            fn () => $this->tenantDb->table('journal_lines')->where('id', $lineId)
                ->update(['debit' => 201, 'updated_at' => now()]),
            'Lines of a posted journal entry are immutable'
        );
        $this->assertDatabaseRejected(
            fn () => $this->tenantDb->table('journal_lines')->insert([
                'journal_entry_id' => 'invariant-immutable',
                'line_no' => 2,
                'account_code' => '1-1010',
                'debit' => 1,
                'credit' => 0,
                'created_at' => now(),
                'updated_at' => now(),
            ]),
            'Cannot insert or move a line into a posted journal entry'
        );
        $this->assertDatabaseRejected(
            fn () => $this->tenantDb->table('journal_lines')->where('id', $lineId)->delete(),
            'Lines of a posted journal entry are immutable'
        );
        $this->assertDatabaseRejected(
            fn () => $this->tenantDb->table('journal_entries')
                ->where('id', 'invariant-immutable')->delete(),
            'Posted journal entries are immutable'
        );
    }

    public function test_closed_period_rejects_journals_and_cannot_be_reopened_or_deleted(): void
    {
        $now = now();
        $this->tenantDb->table('accounting_periods')->insert([
            'period_key' => '2026-10',
            'status' => 'closed',
            'closed_at' => $now,
            'closed_by_user_id' => 987654,
            'close_reason' => 'Month-end review completed',
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        $this->assertSame(1, $this->tenantDb->table('accounting_period_events')
            ->where('period_key', '2026-10')->where('action', 'closed')->count());

        $this->insertDraftJournal('invariant-closed-period', '2026-10-21', [
            ['debit' => 500, 'credit' => 0],
            ['debit' => 0, 'credit' => 500],
        ]);
        $this->assertDatabaseRejected(
            fn () => $this->postDraftJournal('invariant-closed-period'),
            'is closed; posted journals cannot be added'
        );
        $this->assertDatabaseRejected(
            fn () => $this->tenantDb->table('accounting_periods')
                ->where('period_key', '2026-10')
                ->update([
                    'status' => 'open',
                    'closed_at' => null,
                    'closed_by_user_id' => null,
                    'close_reason' => null,
                    'updated_at' => now(),
                ]),
            'Closed accounting periods cannot be reopened or changed'
        );
        $this->assertDatabaseRejected(
            fn () => $this->tenantDb->table('accounting_periods')
                ->where('period_key', '2026-10')->delete(),
            'Closed accounting periods cannot be deleted'
        );

        $eventId = $this->tenantDb->table('accounting_period_events')
            ->where('period_key', '2026-10')->value('id');
        $this->assertDatabaseRejected(
            fn () => $this->tenantDb->table('accounting_period_events')
                ->where('id', $eventId)->update(['reason' => 'tampered']),
            'audit events are append-only'
        );
    }

    private function insertDraftJournal(string $id, string $journalDate, array $lines): void
    {
        $now = now();
        $this->tenantDb->table('journal_entries')->insert([
            'id' => $id,
            'source_event_id' => 'test:'.$id,
            'description' => 'Accounting invariant test',
            'journal_date' => $journalDate,
            'transaction_id' => 'test:'.$id,
            'occurred_at' => $now,
            'timezone' => 'Asia/Jakarta',
            'status' => 'draft',
            'created_at' => $now,
            'updated_at' => $now,
        ]);

        foreach ($lines as $lineNo => $line) {
            $this->tenantDb->table('journal_lines')->insert([
                'journal_entry_id' => $id,
                'line_no' => $lineNo,
                'account_code' => $line['debit'] > 0 ? '1-1010' : '4-4010',
                'debit' => $line['debit'],
                'credit' => $line['credit'],
                'created_at' => $now,
                'updated_at' => $now,
            ]);
        }
    }

    private function postDraftJournal(string $id): void
    {
        $this->tenantDb->table('journal_entries')
            ->where('id', $id)
            ->update(['status' => 'posted', 'updated_at' => now()]);
    }

    private function assertDatabaseRejected(callable $operation, string $message): void
    {
        try {
            $this->tenantDb->transaction($operation);
            $this->fail('Expected the PostgreSQL accounting guard to reject this operation.');
        } catch (QueryException $exception) {
            $this->assertStringContainsString($message, $exception->getMessage());
        }
    }
}
