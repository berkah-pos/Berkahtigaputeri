<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use RuntimeException;

return new class extends Migration
{
    protected $connection = 'tenant_migrator';

    private function targetConnection(): string
    {
        return 'tenant_migrator';
    }

    public function up(): void
    {
        $connection = DB::connection($this->targetConnection());
        $schema = Schema::connection($this->targetConnection());

        foreach (['journal_entries', 'journal_lines'] as $requiredTable) {
            if (! $schema->hasTable($requiredTable)) {
                throw new RuntimeException("Required tenant accounting table {$requiredTable} is missing.");
            }
        }

        if (! $schema->hasTable('accounting_periods')) {
            $schema->create('accounting_periods', function (Blueprint $table): void {
                $table->string('period_key', 7)->primary();
                $table->string('status', 10)->default('open');
                $table->timestamp('closed_at')->nullable();
                $table->unsignedBigInteger('closed_by_user_id')->nullable();
                $table->string('close_reason', 500)->nullable();
                $table->timestamps();
            });
        }

        if (! $schema->hasTable('accounting_period_events')) {
            $schema->create('accounting_period_events', function (Blueprint $table): void {
                $table->bigIncrements('id');
                $table->string('period_key', 7);
                $table->string('action', 16);
                $table->unsignedBigInteger('actor_user_id');
                $table->string('reason', 500);
                $table->timestamp('occurred_at');
                $table->timestamps();
                $table->unique(['period_key', 'action'], 'accounting_period_events_period_action_unique');
                $table->foreign('period_key', 'accounting_period_events_period_fk')
                    ->references('period_key')
                    ->on('accounting_periods')
                    ->onDelete('restrict');
            });
        }

        // Fail closed if an existing tenant database already contains malformed
        // journal lines or unbalanced entries. Do not silently rewrite accounting history.
        $connection->unprepared(<<<'SQL'
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM public.journal_lines
        WHERE debit < 0 OR credit < 0
           OR (debit > 0 AND credit > 0)
           OR (debit = 0 AND credit = 0)
    ) THEN
        RAISE EXCEPTION 'Existing journal lines contain invalid debit/credit values';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.journal_lines l
        LEFT JOIN public.journal_entries j ON j.id = l.journal_entry_id
        WHERE j.id IS NULL
    ) THEN
        RAISE EXCEPTION 'Existing journal lines reference a missing journal entry';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.journal_entries j
        LEFT JOIN public.journal_lines l ON l.journal_entry_id = j.id
        WHERE j.status = 'posted'
        GROUP BY j.id
        HAVING COUNT(l.id) < 2
            OR COALESCE(SUM(l.debit), 0) <= 0
            OR COALESCE(SUM(l.credit), 0) <= 0
            OR COALESCE(SUM(l.debit), 0) <> COALESCE(SUM(l.credit), 0)
            OR COUNT(*) FILTER (WHERE l.line_no IS NULL) > 0
            OR COUNT(l.line_no) <> COUNT(DISTINCT l.line_no)
    ) THEN
        RAISE EXCEPTION 'Existing posted journal entries are unbalanced or have invalid line ordering';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'accounting_periods_period_key_format_check'
          AND conrelid = 'public.accounting_periods'::regclass
    ) THEN
        ALTER TABLE public.accounting_periods
            ADD CONSTRAINT accounting_periods_period_key_format_check
            CHECK (period_key ~ '^[0-9]{4}-(0[1-9]|1[0-2])$');
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'accounting_periods_status_check'
          AND conrelid = 'public.accounting_periods'::regclass
    ) THEN
        ALTER TABLE public.accounting_periods
            ADD CONSTRAINT accounting_periods_status_check
            CHECK (status IN ('open', 'closed'));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'accounting_periods_close_metadata_check'
          AND conrelid = 'public.accounting_periods'::regclass
    ) THEN
        ALTER TABLE public.accounting_periods
            ADD CONSTRAINT accounting_periods_close_metadata_check
            CHECK (
                (status = 'open' AND closed_at IS NULL
                    AND closed_by_user_id IS NULL AND close_reason IS NULL)
                OR
                (status = 'closed' AND closed_at IS NOT NULL
                    AND closed_by_user_id IS NOT NULL AND closed_by_user_id > 0
                    AND length(trim(close_reason)) >= 10)
            );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'journal_lines_debit_credit_sane_check'
          AND conrelid = 'public.journal_lines'::regclass
    ) THEN
        ALTER TABLE public.journal_lines
            ADD CONSTRAINT journal_lines_debit_credit_sane_check
            CHECK (
                debit >= 0 AND credit >= 0
                AND ((debit > 0 AND credit = 0) OR (credit > 0 AND debit = 0))
            );
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'journal_lines_journal_entry_fk'
          AND conrelid = 'public.journal_lines'::regclass
    ) THEN
        ALTER TABLE public.journal_lines
            ADD CONSTRAINT journal_lines_journal_entry_fk
            FOREIGN KEY (journal_entry_id)
            REFERENCES public.journal_entries(id)
            ON DELETE RESTRICT;
    END IF;
END
$$;
SQL);

        $connection->unprepared(<<<'SQL'
CREATE OR REPLACE FUNCTION public.btp_guard_journal_entry_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.status = 'posted' THEN
            RAISE EXCEPTION 'Posted journal entries are immutable'
                USING ERRCODE = '55000';
        END IF;
        RETURN OLD;
    END IF;

    IF OLD.status = 'posted' AND NEW IS DISTINCT FROM OLD THEN
        RAISE EXCEPTION 'Posted journal entries are immutable'
            USING ERRCODE = '55000';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS btp_journal_entry_immutable ON public.journal_entries;
CREATE TRIGGER btp_journal_entry_immutable
BEFORE UPDATE OR DELETE ON public.journal_entries
FOR EACH ROW EXECUTE FUNCTION public.btp_guard_journal_entry_mutation();
SQL);

        $connection->unprepared(<<<'SQL'
CREATE OR REPLACE FUNCTION public.btp_guard_journal_line_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    parent_status text;
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        SELECT status INTO parent_status
        FROM public.journal_entries
        WHERE id = OLD.journal_entry_id
        FOR KEY SHARE;

        IF parent_status = 'posted' THEN
            RAISE EXCEPTION 'Lines of a posted journal entry are immutable'
                USING ERRCODE = '55000';
        END IF;

        IF TG_OP = 'DELETE' THEN
            RETURN OLD;
        END IF;
    END IF;

    SELECT status INTO parent_status
    FROM public.journal_entries
    WHERE id = NEW.journal_entry_id
    FOR KEY SHARE;

    IF parent_status IS NULL THEN
        RAISE EXCEPTION 'Journal line must reference an existing journal entry'
            USING ERRCODE = '23503';
    END IF;

    IF parent_status = 'posted' THEN
        RAISE EXCEPTION 'Cannot insert or move a line into a posted journal entry'
            USING ERRCODE = '55000';
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS btp_journal_line_immutable ON public.journal_lines;
CREATE TRIGGER btp_journal_line_immutable
BEFORE INSERT OR UPDATE OR DELETE ON public.journal_lines
FOR EACH ROW EXECUTE FUNCTION public.btp_guard_journal_line_mutation();
SQL);

        $connection->unprepared(<<<'SQL'
CREATE OR REPLACE FUNCTION public.btp_validate_journal_posting()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    total_debit numeric;
    total_credit numeric;
    line_count bigint;
    period_key text;
BEGIN
    IF NEW.status = 'posted' AND OLD.status IS DISTINCT FROM 'posted' THEN
        period_key := to_char(NEW.journal_date, 'YYYY-MM');

        -- Serialize close-vs-post operations for the same accounting month.
        PERFORM pg_advisory_xact_lock(hashtext('btp_accounting_period:' || period_key)::bigint);

        IF EXISTS (
            SELECT 1 FROM public.accounting_periods
            WHERE accounting_periods.period_key = period_key AND status = 'closed'
        ) THEN
            RAISE EXCEPTION 'Accounting period % is closed; posted journals cannot be added', period_key
                USING ERRCODE = '23514';
        END IF;

        SELECT COUNT(*), COALESCE(SUM(debit), 0), COALESCE(SUM(credit), 0)
        INTO line_count, total_debit, total_credit
        FROM public.journal_lines
        WHERE journal_entry_id = NEW.id;

        IF line_count < 2 OR total_debit <= 0 OR total_credit <= 0 OR total_debit <> total_credit THEN
            RAISE EXCEPTION 'Journal % must contain at least two balanced debit/credit lines', NEW.id
                USING ERRCODE = '23514';
        END IF;

        IF EXISTS (
            SELECT 1 FROM public.journal_lines
            WHERE journal_entry_id = NEW.id AND line_no IS NULL
        ) OR EXISTS (
            SELECT 1
            FROM public.journal_lines
            WHERE journal_entry_id = NEW.id
            GROUP BY line_no
            HAVING COUNT(*) > 1
        ) THEN
            RAISE EXCEPTION 'Journal % has missing or duplicate line numbers', NEW.id
                USING ERRCODE = '23514';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS btp_journal_posting_guard ON public.journal_entries;
CREATE TRIGGER btp_journal_posting_guard
BEFORE UPDATE OF status ON public.journal_entries
FOR EACH ROW EXECUTE FUNCTION public.btp_validate_journal_posting();
SQL);

        $connection->unprepared(<<<'SQL'
CREATE OR REPLACE FUNCTION public.btp_guard_accounting_period_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    period_to_lock text;
BEGIN
    IF TG_OP = 'DELETE' THEN
        IF OLD.status = 'closed' THEN
            RAISE EXCEPTION 'Closed accounting periods cannot be deleted'
                USING ERRCODE = '55000';
        END IF;
        RETURN OLD;
    END IF;

    period_to_lock := NEW.period_key;
    IF TG_OP = 'UPDATE' THEN
        IF OLD.period_key IS DISTINCT FROM NEW.period_key THEN
            RAISE EXCEPTION 'Accounting period identity is immutable'
                USING ERRCODE = '55000';
        END IF;
        IF OLD.status = 'closed' AND NEW IS DISTINCT FROM OLD THEN
            RAISE EXCEPTION 'Closed accounting periods cannot be reopened or changed'
                USING ERRCODE = '55000';
        END IF;
    END IF;

    PERFORM pg_advisory_xact_lock(hashtext('btp_accounting_period:' || period_to_lock)::bigint);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS btp_accounting_period_guard ON public.accounting_periods;
CREATE TRIGGER btp_accounting_period_guard
BEFORE INSERT OR UPDATE OR DELETE ON public.accounting_periods
FOR EACH ROW EXECUTE FUNCTION public.btp_guard_accounting_period_mutation();
SQL);

        $connection->unprepared(<<<'SQL'
CREATE OR REPLACE FUNCTION public.btp_audit_accounting_period_close()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF NEW.status = 'closed' THEN
        IF TG_OP = 'INSERT' THEN
            INSERT INTO public.accounting_period_events
                (period_key, action, actor_user_id, reason, occurred_at, created_at, updated_at)
            VALUES
                (NEW.period_key, 'closed', NEW.closed_by_user_id, NEW.close_reason,
                 NEW.closed_at, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
        ELSIF OLD.status IS DISTINCT FROM 'closed' THEN
            INSERT INTO public.accounting_period_events
                (period_key, action, actor_user_id, reason, occurred_at, created_at, updated_at)
            VALUES
                (NEW.period_key, 'closed', NEW.closed_by_user_id, NEW.close_reason,
                 NEW.closed_at, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP);
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS btp_accounting_period_close_audit ON public.accounting_periods;
CREATE TRIGGER btp_accounting_period_close_audit
AFTER INSERT OR UPDATE ON public.accounting_periods
FOR EACH ROW EXECUTE FUNCTION public.btp_audit_accounting_period_close();
SQL);

        $connection->unprepared(<<<'SQL'
CREATE OR REPLACE FUNCTION public.btp_guard_accounting_period_event_mutation()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    RAISE EXCEPTION 'Accounting period audit events are append-only'
        USING ERRCODE = '55000';
END;
$$;

DROP TRIGGER IF EXISTS btp_accounting_period_event_immutable ON public.accounting_period_events;
CREATE TRIGGER btp_accounting_period_event_immutable
BEFORE UPDATE OR DELETE ON public.accounting_period_events
FOR EACH ROW EXECUTE FUNCTION public.btp_guard_accounting_period_event_mutation();
SQL);
    }

    public function down(): void
    {
        throw new RuntimeException(
            'This tenant accounting integrity migration is forward-only to protect posted journals and closed periods.'
        );
    }
};
