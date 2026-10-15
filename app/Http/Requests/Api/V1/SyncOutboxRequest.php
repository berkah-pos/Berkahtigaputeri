<?php

namespace App\Http\Requests\Api\V1;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Validator;

class SyncOutboxRequest extends FormRequest
{
    protected function prepareForValidation(): void
    {
        $events = $this->input('events');
        if (! is_array($events)) {
            return;
        }

        foreach ($events as $index => $event) {
            if (! is_array($event)) {
                continue;
            }
            if (! isset($event['idempotency_key']) && isset($event['id'])) {
                $event['idempotency_key'] = $event['id'];
            }

            $payload = $event['payload'] ?? null;
            if (is_string($payload)) {
                $decoded = json_decode($payload, true);
                $payload = is_array($decoded) ? $decoded : $payload;
            }
            if (is_array($payload)) {
                $aliases = [
                    'saleId' => 'sale_id',
                    'transactionId' => 'transaction_id',
                    'grandTotal' => 'grand_total',
                    'ppnAmount' => 'ppn_amount',
                    'occurredAtUtc' => 'occurred_at_utc',
                    'businessDate' => 'business_date',
                    'paymentMethod' => 'payment_method',
                    'transactionDiscountAmount' => 'transaction_discount_amount',
                ];
                foreach ($aliases as $from => $to) {
                    if (! array_key_exists($to, $payload) && array_key_exists($from, $payload)) {
                        $payload[$to] = $payload[$from];
                    }
                }
                if (isset($payload['items']) && is_array($payload['items'])) {
                    foreach ($payload['items'] as $itemIndex => $item) {
                        if (! is_array($item)) {
                            continue;
                        }
                        foreach ([
                            'productId' => 'product_id',
                            'unitPrice' => 'unit_price',
                            'itemDiscountAmount' => 'item_discount_amount',
                        ] as $from => $to) {
                            if (! array_key_exists($to, $item) && array_key_exists($from, $item)) {
                                $item[$to] = $item[$from];
                            }
                        }
                        $payload['items'][$itemIndex] = $item;
                    }
                }
                $event['payload'] = $payload;
            }
            $events[$index] = $event;
        }

        $this->merge(['events' => $events]);
    }

    public function authorize(): bool
    {
        return $this->user() !== null;
    }

    public function rules(): array
    {
        return [
            'tenant_id' => ['required', 'string', 'max:100', 'regex:/^[A-Za-z0-9_-]+$/'],
            'device_id' => ['required', 'string', 'max:150', 'regex:/^[A-Za-z0-9_.:-]+$/'],
            'batch_id' => ['required', 'string', 'max:100', 'regex:/^[A-Za-z0-9_.:-]+$/'],
            'events' => ['required', 'array', 'min:1', 'max:300'],
            'events.*' => ['required', 'array'],
            'events.*.id' => ['required', 'string', 'max:100', 'regex:/^[A-Za-z0-9_.:-]+$/'],
            'events.*.idempotency_key' => ['required', 'string', 'max:100', 'regex:/^[A-Za-z0-9_.:-]+$/'],
            'events.*.entity_type' => ['required', 'in:sale'],
            'events.*.entity_id' => ['required', 'string', 'max:100', 'regex:/^[A-Za-z0-9_.:-]+$/'],
            'events.*.payload' => ['required', 'array'],
            'events.*.payload.sale_id' => ['required', 'string', 'max:100', 'regex:/^[A-Za-z0-9_.:-]+$/'],
            'events.*.payload.transaction_id' => ['sometimes', 'string', 'max:100'],
            'events.*.payload.payment_method' => ['required', 'in:cash,qris,transfer'],
            'events.*.payload.occurred_at_utc' => ['required', 'date'],
            'events.*.payload.business_date' => ['sometimes', 'date_format:Y-m-d'],
            'events.*.payload.grand_total' => ['required', 'integer', 'min:0'],
            'events.*.payload.ppn_amount' => ['required', 'integer', 'min:0'],
            'events.*.payload.transaction_discount_amount' => ['sometimes', 'integer', 'min:0'],
            'events.*.payload.items' => ['required', 'array', 'min:1', 'max:100'],
            'events.*.payload.items.*' => ['required', 'array'],
            'events.*.payload.items.*.product_id' => ['required', 'string', 'max:100'],
            'events.*.payload.items.*.quantity' => ['required', 'integer', 'min:1', 'max:1000000'],
            'events.*.payload.items.*.unit_price' => ['required', 'integer', 'min:0', 'max:9223372036854775807'],
            'events.*.payload.items.*.item_discount_amount' => ['sometimes', 'integer', 'min:0', 'max:9223372036854775807'],
            'events.*.payload.items.*.ppn_exempt' => ['sometimes', 'boolean'],
        ];
    }

    public function withValidator(Validator $validator): void
    {
        $validator->after(function (Validator $validator): void {
            $events = $this->input('events', []);
            if (! is_array($events)) {
                return;
            }
            $eventIds = [];
            $keys = [];
            foreach ($events as $index => $event) {
                if (! is_array($event)) {
                    continue;
                }
                $id = (string) ($event['id'] ?? '');
                $key = (string) ($event['idempotency_key'] ?? '');
                if ($id !== '' && isset($eventIds[$id])) {
                    $validator->errors()->add("events.{$index}.id", 'Each event ID must be unique within a batch.');
                }
                if ($key !== '' && isset($keys[$key])) {
                    $validator->errors()->add("events.{$index}.idempotency_key", 'Each idempotency key must be unique within a batch.');
                }
                $eventIds[$id] = true;
                $keys[$key] = true;
            }
        });
    }
}
