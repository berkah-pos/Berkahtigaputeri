<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Route;
use Illuminate\Validation\ValidationException;
use Tests\TestCase;

class ApiContractTest extends TestCase
{
    public function test_api_success_responses_include_safe_request_correlation_headers(): void
    {
        $requestId = '550e8400-e29b-41d4-a716-446655440000';

        $this->withHeader('X-Request-ID', $requestId)
            ->getJson('/api/v1/platform-health')
            ->assertOk()
            ->assertHeader('X-Request-ID', $requestId)
            ->assertHeader('Cache-Control', 'no-store, private')
            ->assertHeader('X-Content-Type-Options', 'nosniff');
    }

    public function test_invalid_client_request_id_is_replaced_with_a_safe_uuid(): void
    {
        $response = $this->withHeader('X-Request-ID', 'attacker value with spaces')
            ->getJson('/api/v1/platform-health')
            ->assertOk();

        $requestId = (string) $response->headers->get('X-Request-ID');

        $this->assertMatchesRegularExpression(
            '/\A[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}\z/i',
            $requestId
        );
        $this->assertNotSame('attacker value with spaces', $requestId);
    }

    public function test_missing_api_route_returns_problem_details_without_framework_internals(): void
    {
        $response = $this->getJson('/api/v1/route-that-does-not-exist')
            ->assertNotFound()
            ->assertHeader('Content-Type', 'application/problem+json')
            ->assertHeader('Cache-Control', 'no-store, private')
            ->assertJsonStructure([
                'type',
                'title',
                'status',
                'detail',
                'instance',
                'code',
                'request_id',
            ])
            ->assertJsonPath('code', 'route_or_resource_not_found')
            ->assertJsonPath('instance', '/api/v1/route-that-does-not-exist')
            ->assertDontSee('NotFoundHttpException')
            ->assertDontSee('stack trace');

        $this->assertSame(
            $response->headers->get('X-Request-ID'),
            $response->json('request_id')
        );
    }

    public function test_api_method_not_allowed_uses_a_stable_problem_response(): void
    {
        $this->postJson('/api/v1/platform-health')
            ->assertStatus(405)
            ->assertHeader('Content-Type', 'application/problem+json')
            ->assertJsonPath('code', 'method_not_allowed')
            ->assertJsonPath('status', 405);
    }

    public function test_authorization_can_hide_resource_existence_with_a_not_found_status(): void
    {
        Route::get('/api/v1/__contract-test/hidden-resource', static function () {
            throw (new AuthorizationException('Do not reveal resource existence.'))->asNotFound();
        });

        $this->getJson('/api/v1/__contract-test/hidden-resource')
            ->assertNotFound()
            ->assertJsonPath('code', 'not_found')
            ->assertDontSee('Do not reveal resource existence.');
    }

    public function test_api_validation_errors_preserve_field_errors_in_the_common_envelope(): void
    {
        Route::post('/api/v1/__contract-test/validation', static function () {
            throw ValidationException::withMessages([
                'email' => ['The email field is required.'],
            ]);
        });

        $this->postJson('/api/v1/__contract-test/validation', [])
            ->assertStatus(422)
            ->assertHeader('Content-Type', 'application/problem+json')
            ->assertJsonPath('code', 'validation_failed')
            ->assertJsonPath('status', 422)
            ->assertJsonPath('errors.email.0', 'The email field is required.');
    }

    public function test_unhandled_api_errors_do_not_leak_exception_messages(): void
    {
        config(['app.debug' => true]);
        Route::get('/api/v1/__contract-test/internal-error', static function () {
            throw new \RuntimeException('private database URL and credentials');
        });

        $this->getJson('/api/v1/__contract-test/internal-error')
            ->assertStatus(500)
            ->assertHeader('Content-Type', 'application/problem+json')
            ->assertJsonPath('code', 'internal_error')
            ->assertJsonPath('detail', 'An unexpected error occurred.')
            ->assertDontSee('private database URL and credentials')
            ->assertDontSee('RuntimeException');
    }

    public function test_liveness_remains_available_after_more_than_the_api_rate_limit(): void
    {
        for ($attempt = 0; $attempt < 121; $attempt++) {
            $response = $this->getJson('/api/v1/platform-health');

            $this->assertSame(200, $response->getStatusCode(), 'Liveness must not be blocked by the API rate limiter.');
        }
    }

    public function test_api_rate_limiter_returns_a_retryable_problem_response(): void
    {
        Route::get('/api/v1/__contract-test/throttled', static fn () => response()->json(['ok' => true]))
            ->middleware('throttle:api');

        $blocked = null;

        for ($attempt = 0; $attempt < 121; $attempt++) {
            $response = $this->getJson('/api/v1/__contract-test/throttled');

            if ($response->getStatusCode() === 429) {
                $blocked = $response;
                break;
            }
        }

        $this->assertNotNull($blocked, 'The named API rate limiter should reject requests beyond the configured budget.');
        $blocked
            ->assertStatus(429)
            ->assertHeader('Content-Type', 'application/problem+json')
            ->assertHeader('Retry-After')
            ->assertJsonPath('code', 'rate_limited')
            ->assertJsonPath('status', 429);
    }
}
