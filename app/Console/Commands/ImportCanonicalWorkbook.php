<?php

namespace App\Console\Commands;

use App\Services\Configuration\CanonicalWorkbookImporter;
use Illuminate\Console\Command;
use JsonException;
use stdClass;
use Throwable;

class ImportCanonicalWorkbook extends Command
{
    protected $signature = 'config:import-workbook
        {file : JSON manifest produced by scripts/export_workbook_for_laravel.py}
        {--apply : Commit the validated manifest to the central PostgreSQL database}
        {--post-check : Read-only comparison of stored normalized scopes against the manifest}';

    protected $description = 'Validate the canonical 352-key manifest; default execution is a database-free dry run.';

    public function handle(CanonicalWorkbookImporter $importer): int
    {
        $path = (string) $this->argument('file');
        if (! is_file($path) || ! is_readable($path)) {
            $this->error("Cannot read manifest: {$path}");
            return self::FAILURE;
        }

        if ($this->option('apply') && $this->option('post-check')) {
            $this->error('Choose --apply or --post-check, not both. Apply already performs its post-check transactionally.');
            return self::FAILURE;
        }

        try {
            $contents = file_get_contents($path);
            if ($contents === false) {
                throw new \RuntimeException("Unable to read manifest: {$path}");
            }
            $manifest = json_decode($contents, false, 512, JSON_THROW_ON_ERROR);
            if (! $manifest instanceof stdClass) {
                throw new \InvalidArgumentException('Manifest root must be a JSON object.');
            }

            $validated = $importer->validateManifest($manifest);
            $this->line('Validated exact 352-entry inventory: global=1, template=3, tenant=100, service=140, device=108.');
            $this->line('Canonical keyset MD5: '.CanonicalWorkbookImporter::EXPECTED_KEYSET_MD5);

            if ($this->option('post-check')) {
                $check = $importer->postCheck($manifest);
                $this->info("POST-CHECK {$check['status']}: {$check['total']} stored scopes; keyset {$check['keyset_md5']}.");
                return self::SUCCESS;
            }

            if (! $this->option('apply')) {
                // Intentionally no DB call is reachable from the default path.
                $this->info('DRY-RUN PASS: 352 normalized scopes validated; no database connection was opened and no writes were attempted.');
                return self::SUCCESS;
            }

            $result = $importer->apply($manifest);
            $this->info("APPLY PASS: inserted={$result['inserted']}, updated={$result['updated']}, unchanged={$result['unchanged']}, total={$result['total']}.");
            $this->info("POST-CHECK PASS: keyset {$result['keyset_md5']}; all changes committed in one central-DB transaction.");

            return self::SUCCESS;
        } catch (JsonException|\InvalidArgumentException|\RuntimeException $exception) {
            $this->error($exception->getMessage());
            return self::FAILURE;
        } catch (Throwable $exception) {
            report($exception);
            $this->error('Configuration import failed; its PostgreSQL transaction was rolled back if apply had begun.');
            return self::FAILURE;
        }
    }
}
