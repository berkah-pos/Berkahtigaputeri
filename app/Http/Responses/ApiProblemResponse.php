<?php

namespace App\Http\Responses;

use App\Http\Middleware\ApiRequestContext;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpFoundation\Response as SymfonyResponse;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;
use Symfony\Component\HttpKernel\Exception\MethodNotAllowedHttpException;
use Symfony\Component\HttpKernel\Exception\NotFoundHttpException;
use Throwable;

final class ApiProblemResponse
{
    /**
     * Render API exceptions using a stable RFC 9457-style envelope.
     *
     * Exception messages, SQL details, file paths and stack traces are deliberately
     * excluded. They remain available to the application's configured server logs.
     */
    public static function fromException(Request $request, Throwable $exception): JsonResponse
    {
        [$status, $code, $title, $detail, $errors, $exceptionHeaders] = self::describe($exception);

        $requestId = ApiRequestContext::ensureRequestId($request);
        $problem = [
            'type' => 'about:blank',
            'title' => $title,
            'status' => $status,
            'detail' => $detail,
            'instance' => $request->getPathInfo(),
            'code' => $code,
            'request_id' => $requestId,
        ];

        if ($errors !== null) {
            $problem['errors'] = $errors;
        }

        $headers = [
            'Content-Type' => 'application/problem+json',
            'X-Request-ID' => $requestId,
            'Cache-Control' => 'no-store, private',
            'X-Content-Type-Options' => 'nosniff',
        ];

        // Preserve only protocol headers required for clients to recover correctly.
        foreach (['Allow', 'Retry-After', 'WWW-Authenticate'] as $header) {
            if (isset($exceptionHeaders[$header])) {
                $headers[$header] = $exceptionHeaders[$header];
            }
        }

        $response = response()->json(
            $problem,
            $status,
            $headers,
            JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE
        );
        $response->headers->set('Content-Type', 'application/problem+json');

        return $response;
    }

    /**
     * @return array{int, string, string, string, array<string, array<int, string>>|null, array<string, string>}
     */
    private static function describe(Throwable $exception): array
    {
        if ($exception instanceof ValidationException) {
            return [
                422,
                'validation_failed',
                'Unprocessable Content',
                'One or more fields are invalid.',
                $exception->errors(),
                [],
            ];
        }

        if ($exception instanceof AuthenticationException) {
            return [401, 'authentication_required', 'Unauthorized', 'Authentication is required.', null, []];
        }

        if ($exception instanceof AuthorizationException) {
            return [403, 'forbidden', 'Forbidden', 'The request is not authorized.', null, []];
        }

        if ($exception instanceof ModelNotFoundException) {
            return [404, 'resource_not_found', 'Not Found', 'The requested resource was not found.', null, []];
        }

        if ($exception instanceof MethodNotAllowedHttpException) {
            $headers = $exception->getHeaders();

            return [
                405,
                'method_not_allowed',
                'Method Not Allowed',
                'The requested HTTP method is not supported for this resource.',
                null,
                $headers,
            ];
        }

        if ($exception instanceof NotFoundHttpException) {
            return [404, 'route_or_resource_not_found', 'Not Found', 'The requested route or resource was not found.', null, []];
        }

        if ($exception instanceof HttpExceptionInterface) {
            $status = $exception->getStatusCode();
            $headers = $exception->getHeaders();

            return self::describeHttpStatus($status, $headers);
        }

        return [500, 'internal_error', 'Internal Server Error', 'An unexpected error occurred.', null, []];
    }

    /**
     * @param array<string, string> $headers
     * @return array{int, string, string, string, null, array<string, string>}
     */
    private static function describeHttpStatus(int $status, array $headers): array
    {
        $known = [
            400 => ['bad_request', 'Bad Request', 'The request could not be processed.'],
            401 => ['authentication_required', 'Unauthorized', 'Authentication is required.'],
            403 => ['forbidden', 'Forbidden', 'The request is not authorized.'],
            404 => ['not_found', 'Not Found', 'The requested route or resource was not found.'],
            405 => ['method_not_allowed', 'Method Not Allowed', 'The requested HTTP method is not supported for this resource.'],
            408 => ['request_timeout', 'Request Timeout', 'The request timed out. Please retry safely.'],
            409 => ['conflict', 'Conflict', 'The request conflicts with the current resource state.'],
            410 => ['gone', 'Gone', 'The requested resource is no longer available.'],
            413 => ['content_too_large', 'Content Too Large', 'The request body is too large.'],
            415 => ['unsupported_media_type', 'Unsupported Media Type', 'The request media type is not supported.'],
            419 => ['session_expired', 'Authentication Session Expired', 'The request session is no longer valid.'],
            422 => ['unprocessable_content', 'Unprocessable Content', 'The request could not be validated.'],
            425 => ['too_early', 'Too Early', 'The request cannot be processed yet.'],
            429 => ['rate_limited', 'Too Many Requests', 'Too many requests. Try again later.'],
            500 => ['internal_error', 'Internal Server Error', 'An unexpected error occurred.'],
            501 => ['not_implemented', 'Not Implemented', 'This operation is not implemented.'],
            502 => ['bad_gateway', 'Bad Gateway', 'A required upstream service returned an invalid response.'],
            503 => ['service_unavailable', 'Service Unavailable', 'The service is temporarily unavailable.'],
            504 => ['gateway_timeout', 'Gateway Timeout', 'A required upstream service did not respond in time.'],
        ];

        if (isset($known[$status])) {
            [$code, $title, $detail] = $known[$status];

            return [$status, $code, $title, $detail, null, $headers];
        }

        $title = SymfonyResponse::$statusTexts[$status] ?? 'HTTP Error';

        return [$status, 'http_error', $title, 'The request could not be completed.', null, $headers];
    }
}
