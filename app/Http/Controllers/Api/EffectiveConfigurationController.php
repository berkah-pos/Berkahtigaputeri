<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\Central\User;
use App\Services\Configuration\CanonicalConfig;
use App\Services\Configuration\ConfigurationUnavailableException;
use App\Services\Configuration\ConfigurationVersionConflict;
use App\Services\Configuration\ConfigurationWriter;
use App\Services\Configuration\EffectiveConfigResolver;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use InvalidArgumentException;
use JsonException;
use stdClass;

final class EffectiveConfigurationController extends Controller
{
    public function show(Request $request, string $service, EffectiveConfigResolver $resolver): JsonResponse
    {
        if (! is_string($request->query('device_id'))) {
            return response()->json([
                'error' => 'invalid_request',
                'message' => 'device_id is required.',
            ], 422);
        }

        try {
            return response()->json(
                $resolver->resolve($this->authenticatedUser($request), $request->query('device_id'), $service)
            );
        } catch (AuthorizationException $exception) {
            return response()->json(['error' => 'forbidden', 'message' => $exception->getMessage()], 403);
        } catch (ConfigurationUnavailableException $exception) {
            return response()->json(['error' => 'configuration_unavailable', 'message' => $exception->getMessage()], 503);
        } catch (InvalidArgumentException $exception) {
            return response()->json(['error' => 'invalid_request', 'message' => $exception->getMessage()], 422);
        }
    }

    public function updateDeviceOverride(
        Request $request,
        string $service,
        EffectiveConfigResolver $resolver,
        ConfigurationWriter $writer
    ): JsonResponse {
        try {
            $payload = json_decode($request->getContent(), false, 512, JSON_THROW_ON_ERROR);
        } catch (JsonException) {
            return response()->json(['error' => 'invalid_request', 'message' => 'Request body must be valid JSON.'], 422);
        }

        if (! $payload instanceof stdClass ||
            ! is_string($payload->device_id ?? null) ||
            ! is_int($payload->expected_version ?? null) ||
            ! (($payload->config ?? null) instanceof stdClass)) {
            return response()->json([
                'error' => 'invalid_request',
                'message' => 'Expected device_id, positive integer expected_version, and config object.',
            ], 422);
        }

        try {
            $result = $writer->compareAndSetDeviceOverride(
                $this->authenticatedUser($request),
                $payload->device_id,
                $service,
                $payload->expected_version,
                CanonicalConfig::decodeObject($payload->config, 'config')
            );
            $effective = $resolver->resolve($this->authenticatedUser($request), $payload->device_id, $service);
            $effective['write'] = [
                'scope' => 'device',
                'version' => $result['version'],
                'config_hash' => $result['config_hash'],
            ];

            return response()->json($effective);
        } catch (ConfigurationVersionConflict $exception) {
            return response()->json([
                'error' => 'configuration_version_conflict',
                'message' => $exception->getMessage(),
                'expected_version' => $exception->expectedVersion,
                'current_version' => $exception->currentVersion,
            ], 409);
        } catch (AuthorizationException $exception) {
            return response()->json(['error' => 'forbidden', 'message' => $exception->getMessage()], 403);
        } catch (ConfigurationUnavailableException $exception) {
            return response()->json(['error' => 'configuration_unavailable', 'message' => $exception->getMessage()], 503);
        } catch (InvalidArgumentException $exception) {
            return response()->json(['error' => 'invalid_request', 'message' => $exception->getMessage()], 422);
        }
    }

    private function authenticatedUser(Request $request): User
    {
        $user = $request->user();
        if (! $user instanceof User) {
            throw new AuthorizationException('Authenticated user context is required.');
        }

        return $user;
    }
}
