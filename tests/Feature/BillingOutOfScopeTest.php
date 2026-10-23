<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Route;
use Tests\TestCase;

class BillingOutOfScopeTest extends TestCase
{
    public function test_no_payment_webhook_subscription_or_entitlement_routes_are_registered(): void
    {
        $blockedTerms = [
            'payment',
            'payments',
            'billing',
            'subscription',
            'subscriptions',
            'webhook',
            'midtrans',
            'xendit',
            'entitlement',
            'entitlements',
        ];
        $matches = [];

        foreach (Route::getRoutes() as $route) {
            $name = $route->getName() ?? '';
            $identity = strtolower($route->uri().' '.$name.' '.$route->getActionName());

            foreach ($blockedTerms as $term) {
                if (str_contains($identity, $term)) {
                    $matches[] = implode('|', $route->methods()).' '.$route->uri().' ['.$name.']';
                    break;
                }
            }
        }

        $this->assertSame(
            [],
            $matches,
            'RC1 billing is out of scope: payment, webhook, subscription and entitlement routes must remain absent.'
        );
    }

    public function test_rc1_subscription_schema_defaults_are_inactive_and_unconfigured(): void
    {
        $migration = file_get_contents(base_path(
            'database/migrations/central/2026_10_19_000001_fail_closed_subscription_defaults.php'
        ));

        $this->assertIsString($migration);
        $this->assertStringContainsString("default('unconfigured')", $migration);
        $this->assertStringContainsString("default('inactive')", $migration);
        $this->assertStringNotContainsString("default('trial')", $migration);
        $this->assertStringContainsString('rollback must not restore the legacy trial-by-default behavior', $migration);
    }

    public function test_workbook_import_does_not_create_a_trial_or_subscription_entitlement(): void
    {
        $importer = file_get_contents(base_path('app/Console/Commands/ImportCanonicalWorkbook.php'));

        $this->assertIsString($importer);
        $this->assertStringNotContainsString('use App\\Models\\Central\\Subscription;', $importer);
        $this->assertStringNotContainsString('Subscription::query()->firstOrCreate', $importer);
        $this->assertStringNotContainsString("'status' => 'trial'", $importer);
        $this->assertStringContainsString('Workbook imports must not grant a trial or subscription entitlement.', $importer);
    }
}
