<?php

namespace App\Services\Tenant;

use Carbon\CarbonImmutable;
use Illuminate\Database\Connection;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use InvalidArgumentException;
use RuntimeException;
use Throwable;

/**
 * Creates full accounting reversals for non-sale journals only.
 *
 * It intentionally refuses sale journals: a sale refund/return must reverse
 * sale, inventory, cost, payment and outbox projections atomically and is not
 * implemented by this journal-only service.
 */
class JournalReversalService
{
    public function reverse(
        string $originalJournalId,
        string $idempotencyKey,
        string $effectiveDate,
        string $reasonCode,
        string $actorReference,
        string $deviceId,
        string $appVersion,
    ): array {
        $originalJournalId = $this->requiredText($originalJournalId, 'originalJournalId', 100);
        $idempotencyKey = $this->requiredText($idempotencyKey, 'idempotencyKey', 90);
        if (!preg_match('/^[A-Za-z0-9._:-]+$/', $idempotencyKey)) {
            throw new InvalidArgumentException('idempotencyKey contains unsupported characters.');
        }
        if (!in_array($reasonCode, ['correction', 'void', 'other'], true)) {
            throw new InvalidArgumentException('reasonCode must be correction, void or other.');
        }
        try {
            $date = CarbonImmutable::createFromFormat('!Y-m-d', $effectiveDate);
            if ($date === false || $date->format('Y-m-d') !== $effectiveDate) {
                throw new InvalidArgumentException('effectiveDate must use YYYY-MM-DD.');
            }
        } catch (Throwable $exception) {
            throw new InvalidArgumentException('effectiveDate must use YYYY-MM-DD.', previous: $exception);
        }

        $actor = $this->requiredText($actorReference, 'actorReference', 150);
        $device = $this->requiredText($deviceId, 'deviceId', 150);
        $version = $this->requiredText($appVersion, 'appVersion', 80);
        $fingerprint = hash('sha256', json_encode([
            'original_journal_id' => $originalJournalId,
            'effective_date' => $effectiveDate,
            'reason_code' => $reasonCode,
        ], JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES));

        try {
            return DB::connection('tenant')->transaction(function (Connection $db) use (
                $originalJournalId, $idempotencyKey, $effectiveDate, $reasonCode,
                $actor, $device, $version, $fingerprint
            ): array {
                $existingEvent = $db->table('accounting_events')
                    ->where('idempotency_key', $idempotencyKey)
                    ->lockForUpdate()
                    ->first();
                if ($existingEvent !== null) {
                    return $this->returnExisting($existingEvent, $fingerprint);
                }

                $original = $db->table('journal_entries')
                    ->where('id', $originalJournalId)
                    ->lockForUpdate()
                    ->first();
                if ($original === null || $original->status !== 'posted') {
                    throw new SalePostingException('Only an existing posted journal can be reversed.');
                }
                if ($original->entry_type === 'sale') {
                    throw new SalePostingException('Sale reversal is unsupported until sale, stock, COGS and sync receipt reversal are implemented atomically.');
                }
                if ($db->table('journal_entries')->where('reversal_of_entry_id', $originalJournalId)->exists()) {
                    throw new SalePostingException('This journal already has a full reversal.');
                }

                $originalLines = $db->table('journal_lines')
                    ->where('journal_entry_id', $originalJournalId)
                    ->orderBy('line_no')
                    ->orderBy('id')
                    ->get();
                if ($originalLines->count() < 2) {
                    throw new SalePostingException('Original journal does not have a complete line set.');
                }

                $now = CarbonImmutable::now('UTC');
                $timestamp = $now->format('Y-m-d H:i:s');
                $reversalId = 'reverse:'.$idempotencyKey;
                $db->table('journal_entries')->insert([
                    'id' => $reversalId,
                    'source_event_id' => null,
                    'description' => 'Reversal of '.$originalJournalId.' ('.$reasonCode.')',
                    'journal_date' => $effectiveDate,
                    'status' => 'draft',
                    'entry_type' => 'reversal',
                    'currency_code' => 'IDR',
                    'actor_reference' => $actor,
                    'device_id' => $device,
                    'app_version' => $version,
                    'transaction_reference' => $idempotencyKey,
                    'idempotency_key' => $idempotencyKey,
                    'payload_sha256' => $fingerprint,
                    'reversal_of_entry_id' => $originalJournalId,
                    'created_at' => $timestamp,
                    'updated_at' => $timestamp,
                ]);

                foreach ($originalLines as $index => $line) {
                    $db->table('journal_lines')->insert([
                        'journal_entry_id' => $reversalId,
                        'line_no' => $index,
                        'account_code' => $line->account_code,
                        'debit' => (int) $line->credit,
                        'credit' => (int) $line->debit,
                        'created_at' => $timestamp,
                        'updated_at' => $timestamp,
                    ]);
                }

                $db->table('journal_entries')->where('id', $reversalId)->update([
                    'status' => 'posted',
                    'posted_at' => $now->format('Y-m-d H:i:sP'),
                    'updated_at' => $timestamp,
                ]);

                $db->table('accounting_events')->insert([
                    'id' => 'accounting-reversal:'.$idempotencyKey,
                    'journal_entry_id' => $reversalId,
                    'event_type' => 'journal.posted',
                    'actor_reference' => $actor,
                    'occurred_at' => $now->format('Y-m-d H:i:sP'),
                    'device_id' => $device,
                    'app_version' => $version,
                    'transaction_reference' => $idempotencyKey,
                    'idempotency_key' => $idempotencyKey,
                    'context' => json_encode([
                        'source' => 'accounting_reversal_service',
                        'original_journal_id' => $originalJournalId,
                        'reason_code' => $reasonCode,
                        'request_sha256' => $fingerprint,
                    ], JSON_THROW_ON_ERROR),
                ]);

                return [
                    'status' => 'posted',
                    'journal_entry_id' => $reversalId,
                    'reversal_of_entry_id' => $originalJournalId,
                    'currency_code' => 'IDR',
                    'total_debit' => (int) $originalLines->sum('credit'),
                    'total_credit' => (int) $originalLines->sum('debit'),
                ];
            }, 3);
        } catch (QueryException $exception) {
            if (!$this->isUniqueViolation($exception)) {
                throw $exception;
            }

            $existingEvent = DB::connection('tenant')->table('accounting_events')
                ->where('idempotency_key', $idempotencyKey)
                ->first();
            if ($existingEvent !== null) {
                return $this->returnExisting($existingEvent, $fingerprint);
            }
            throw new SalePostingException('A reversal uniqueness conflict occurred; inspect existing reversal state before retry.', previous: $exception);
        }
    }

    private function returnExisting(object $event, string $fingerprint): array
    {
        $context = is_array($event->context)
            ? $event->context
            : json_decode((string) $event->context, true, 512, JSON_THROW_ON_ERROR);
        if (($context['request_sha256'] ?? null) !== $fingerprint) {
            throw new IdempotencyConflictException('Reversal idempotency key is already bound to another request.');
        }

        $db = DB::connection('tenant');
        $header = $db->table('journal_entries')->where('id', $event->journal_entry_id)->first();
        if ($header === null || $header->status !== 'posted' || $header->entry_type !== 'reversal') {
            throw new SalePostingException('Stored reversal receipt does not reference a posted reversal.');
        }
        $lines = $db->table('journal_lines')->where('journal_entry_id', $header->id)->get();

        return [
            'status' => 'posted',
            'journal_entry_id' => (string) $header->id,
            'reversal_of_entry_id' => (string) $header->reversal_of_entry_id,
            'currency_code' => 'IDR',
            'total_debit' => (int) $lines->sum('debit'),
            'total_credit' => (int) $lines->sum('credit'),
        ];
    }

    private function requiredText(string $value, string $field, int $maxLength): string
    {
        $value = trim($value);
        if ($value === '' || mb_strlen($value) > $maxLength) {
            throw new InvalidArgumentException("{$field} must contain 1 to {$maxLength} characters.");
        }

        return $value;
    }

    private function isUniqueViolation(QueryException $exception): bool
    {
        $state = (string) $exception->getCode();
        $previous = $exception->getPrevious();
        if ($previous instanceof \PDOException && isset($previous->errorInfo[0])) {
            $state = (string) $previous->errorInfo[0];
        }

        return $state === '23505';
    }
}
