<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;
use RuntimeException;

return new class extends Migration
{
    protected $connection = 'central_migrator';

    public function up(): void
    {
        $central = DB::connection('central_migrator');
        $database = $central->getDatabaseName();
        $runtimeRole = trim((string) env('CENTRAL_DB_USERNAME', ''));
        $migratorRole = trim((string) env('CENTRAL_MIGRATOR_DB_USERNAME', ''));

        foreach ([$database, $runtimeRole, $migratorRole] as $identifier) {
            if (! preg_match('/^[a-z][a-z0-9_]{0,62}$/', $identifier)) {
                throw new RuntimeException('Central database and runtime/migrator roles must use approved PostgreSQL identifiers.');
            }
        }

        // This forward-only security migration closes the PostgreSQL default
        // PUBLIC CONNECT path. Explicit central service identities retain access;
        // tenant runtime logins receive no central CONNECT grant.
        $quotedDatabase = '"'.$database.'"';
        $central->unprepared('REVOKE CONNECT ON DATABASE '.$quotedDatabase.' FROM PUBLIC');
        $central->unprepared('GRANT CONNECT ON DATABASE '.$quotedDatabase.' TO "'.$runtimeRole.'"');
        $central->unprepared('GRANT CONNECT ON DATABASE '.$quotedDatabase.' TO "'.$migratorRole.'"');

        $extraRoles = array_filter(array_map(
            'trim',
            explode(',', (string) env('CENTRAL_DB_EXTRA_CONNECT_ROLES', ''))
        ));
        foreach ($extraRoles as $role) {
            if (! preg_match('/^[a-z][a-z0-9_]{0,62}$/', $role)) {
                throw new RuntimeException('CENTRAL_DB_EXTRA_CONNECT_ROLES contains an unsafe role identifier.');
            }
            $central->unprepared('GRANT CONNECT ON DATABASE '.$quotedDatabase.' TO "'.$role.'"');
        }
    }

    public function down(): void
    {
        throw new RuntimeException(
            'Central PUBLIC CONNECT is a security boundary. Do not restore it with migration rollback; use a reviewed forward-only access repair.'
        );
    }
};
