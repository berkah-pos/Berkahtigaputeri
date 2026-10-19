<?php

namespace Tests\\Feature;

use Illuminate\\Support\\Facades\\Route;
use Tests\\TestCase;

class BillingOutOfScopeTest extends TestCase
{
    public function test_billing_and_entitlement_mutation_routes_are_absent_for_rc1(): void
    {
        $blockedTerms = '/(?:^|[\\/._-])(payment|payments|billing|subscription|subscriptions|webhook|midtrans|xendit|entitlement|entitlements)(?:$|[\\/._-])/i';
        $matches = [];

        foreach (Route::getRoutes() as $route) {
            $name = $route->getName() ?? '';
            $identity = strtolower($route->uri().' '.$name.' '.$route->getActionName());

            if (preg_match($blockedTerms, $identity) === 1) {
                $matches[] = implode('|', $route->methods()).' '.$route->uri().' ['.$name.']';
            }
        }

        $this->assertSame(
            [],
            $matches,
            'RC1 billing is out of scope: no payment, webhook, subscription or entitlement mutation route may be registered.'
        );
    }
}
