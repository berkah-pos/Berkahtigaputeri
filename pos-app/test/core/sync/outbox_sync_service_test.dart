import 'dart:convert';

import 'package:berkahtigaputeri_pos/core/auth/laravel_auth_service.dart';
import 'package:berkahtigaputeri_pos/core/sync/outbox_event_writer.dart';
import 'package:berkahtigaputeri_pos/core/sync/outbox_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show Response;
import 'package:http/testing.dart';

import '../../helpers/test_database.dart';

class _MemoryVault implements SecureVault {
  final Map<String, String> values = <String, String>{};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  test('event is acknowledged only after a server receipt is returned', () async {
    final database = await openTestDatabase();
    addTearDown(database.close);
    final vault = _MemoryVault()..values['berkah.auth.laravel.access_token'] = 'test-bearer';
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      expect(request.url.path, '/api/v1/sync');
      expect(request.headers['authorization'], 'Bearer test-bearer');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body.containsKey('tenant_id'), isFalse);
      expect(body.containsKey('device_id'), isFalse);
      final event = (body['events'] as List).single as Map<String, dynamic>;
      return Response(
        jsonEncode(<String, Object?>{
          'results': <Map<String, Object?>>[
            <String, Object?>{
              'event_id': event['event_id'],
              'status': 'accepted',
              'receipt_id': event['event_id'],
            },
          ],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);
    final auth = LaravelAuthService(
      baseUrl: 'https://api.example.test',
      vault: vault,
      client: client,
    );

    await database.transaction<void>((transaction) async {
      await enqueueOutboxEvent(
        transaction,
        entityType: 'product',
        entityId: 'P-OUTBOX',
        createdAtUtc: DateTime.now().toUtc().toIso8601String(),
        eventPayload: <String, Object?>{
          'product': <String, Object?>{
            'id': 'P-OUTBOX',
            'sku': 'SKU-OUTBOX',
            'name_id': 'Outbox test',
            'price': 5000,
            'ppn_exempt': false,
          },
        },
      );
    });

    final report = await OutboxSyncService(
      database: database,
      authService: auth,
      appVersion: 'test-build',
    ).syncPending();

    final row = (await database.database.query('outbox_events')).single;
    expect(requestCount, 1);
    expect(report.acknowledged, 1);
    expect(row['status'], 'acknowledged');
    expect(row['acked_at_utc'], isNotNull);
    expect(row['server_receipt_id'], isNotEmpty);
    expect(row['last_error'], isNull);
    expect(row['next_retry_at_utc'], isNull);
  });

  test('authentication or entitlement failure keeps the event retryable', () async {
    final database = await openTestDatabase();
    addTearDown(database.close);
    final vault = _MemoryVault()..values['berkah.auth.laravel.access_token'] = 'test-bearer';
    final client = MockClient((request) async => Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 'tenant_not_entitled',
              'message': 'Subscription is not entitled.',
            },
          }),
          403,
          headers: <String, String>{'content-type': 'application/json'},
        ));
    addTearDown(client.close);
    final auth = LaravelAuthService(
      baseUrl: 'https://api.example.test',
      vault: vault,
      client: client,
    );

    await database.transaction<void>((transaction) async {
      await enqueueOutboxEvent(
        transaction,
        entityType: 'product',
        entityId: 'P-AUTH-RETRY',
        createdAtUtc: DateTime.now().toUtc().toIso8601String(),
        eventPayload: <String, Object?>{
          'product': <String, Object?>{
            'id': 'P-AUTH-RETRY',
            'sku': 'SKU-AUTH-RETRY',
            'name_id': 'Entitlement retry test',
            'price': 5000,
            'ppn_exempt': false,
          },
        },
      );
    });

    final report = await OutboxSyncService(
      database: database,
      authService: auth,
    ).syncPending();

    final row = (await database.database.query('outbox_events')).single;
    expect(report.retryScheduled, 1);
    expect(report.attentionRequired, 0);
    expect(row['status'], 'retry');
    expect(row['retry_count'], 1);
    expect(row['next_retry_at_utc'], isNotNull);
    expect(row['acked_at_utc'], isNull);
  });

  test('transient server failure retains the event and schedules retry', () async {
    final database = await openTestDatabase();
    addTearDown(database.close);
    final vault = _MemoryVault()..values['berkah.auth.laravel.access_token'] = 'test-bearer';
    final client = MockClient((request) async => Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 'tenant_database_not_provisioned',
              'message': 'Tenant database is not registered.',
            },
          }),
          503,
          headers: <String, String>{'content-type': 'application/json'},
        ));
    addTearDown(client.close);
    final auth = LaravelAuthService(
      baseUrl: 'https://api.example.test',
      vault: vault,
      client: client,
    );

    await database.transaction<void>((transaction) async {
      await enqueueOutboxEvent(
        transaction,
        entityType: 'product',
        entityId: 'P-RETRY',
        createdAtUtc: DateTime.now().toUtc().toIso8601String(),
        eventPayload: <String, Object?>{
          'product': <String, Object?>{
            'id': 'P-RETRY',
            'sku': 'SKU-RETRY',
            'name_id': 'Retry test',
            'price': 5000,
            'ppn_exempt': false,
          },
        },
      );
    });

    final report = await OutboxSyncService(
      database: database,
      authService: auth,
    ).syncPending();

    final row = (await database.database.query('outbox_events')).single;
    expect(report.retryScheduled, 1);
    expect(row['status'], 'retry');
    expect(row['retry_count'], 1);
    expect(row['next_retry_at_utc'], isNotNull);
    expect(row['acked_at_utc'], isNull);
    expect(row['server_receipt_id'], isNull);
  });


  test('return outbox waits for its sale acknowledgement and retries offline failures safely', () async {
    final database = await openTestDatabase();
    addTearDown(database.close);
    final vault = _MemoryVault()..values['berkah.auth.laravel.access_token'] = 'test-bearer';
    var returnFailedOnce = true;
    var requestCount = 0;
    final client = MockClient((request) async {
      requestCount++;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      final event = (body['events'] as List).single as Map<String, dynamic>;
      if (event['entity_type'] == 'sale_return' && returnFailedOnce) {
        return Response(
          jsonEncode(<String, Object?>{
            'error': <String, Object?>{
              'code': 'tenant_database_not_provisioned',
              'message': 'Tenant database is not registered.',
            },
          }),
          503,
          headers: <String, String>{'content-type': 'application/json'},
        );
      }
      return Response(
        jsonEncode(<String, Object?>{
          'results': <Map<String, Object?>>[
            <String, Object?>{
              'event_id': event['event_id'],
              'status': 'accepted',
              'receipt_id': event['event_id'],
            },
          ],
        }),
        200,
        headers: <String, String>{'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);
    final auth = LaravelAuthService(
      baseUrl: 'https://api.example.test',
      vault: vault,
      client: client,
    );

    final now = DateTime.now().toUtc().toIso8601String();
    const saleId = 'sale:RETURN-OUTBOX';
    const transactionId = 'RETURN-OUTBOX';
    const saleEventId = 'outbox:sale:RETURN-OUTBOX';
    const returnId = 'return:RETURN-OUTBOX';
    const returnEventId = 'outbox:sale_return:return:RETURN-OUTBOX';
    await database.database.insert('sales', <String, Object?>{
      'id': saleId,
      'transaction_id': transactionId,
      'request_fingerprint': 'local-fingerprint',
      'occurred_at_utc': now,
      'business_date': '2026-10-24',
      'timezone': 'Asia/Jakarta',
      'gross_amount': 10000,
      'item_discount_amount': 0,
      'transaction_discount_amount': 0,
      'discount_amount': 0,
      'taxable_dpp': 10000,
      'exempt_dpp': 0,
      'dpp': 10000,
      'ppn_amount': 1100,
      'grand_total': 11100,
      'cogs_amount': 5000,
      'payment_method': 'cash',
      'created_at_utc': now,
    });

    await database.transaction<void>((transaction) async {
      await enqueueOutboxEvent(
        transaction,
        eventId: saleEventId,
        entityType: 'sale',
        entityId: saleId,
        createdAtUtc: now,
        eventPayload: <String, Object?>{
          'transaction_id': transactionId,
          'sale': <String, Object?>{
            'id': saleId,
            'transaction_id': transactionId,
          },
          'items': <Map<String, Object?>>[],
        },
      );
      await enqueueOutboxEvent(
        transaction,
        eventId: returnEventId,
        entityType: 'sale_return',
        entityId: returnId,
        createdAtUtc: now,
        eventPayload: <String, Object?>{
          'return': <String, Object?>{
            'id': returnId,
            'original_sale_id': saleId,
          },
          'items': <Map<String, Object?>>[],
        },
      );
    });

    final service = OutboxSyncService(database: database, authService: auth);
    final first = await service.syncPending();
    final saleOutbox = (await database.database.query(
      'outbox_events',
      where: 'id = ?',
      whereArgs: <Object?>[saleEventId],
    )).single;
    final returnOutbox = (await database.database.query(
      'outbox_events',
      where: 'id = ?',
      whereArgs: <Object?>[returnEventId],
    )).single;

    expect(first.acknowledged, 1);
    expect(first.retryScheduled, 1);
    expect(saleOutbox['status'], 'acknowledged');
    expect(returnOutbox['status'], 'retry');
    expect(returnOutbox['acked_at_utc'], isNull);
    expect(returnOutbox['server_receipt_id'], isNull);

    returnFailedOnce = false;
    await database.database.update(
      'outbox_events',
      <String, Object?>{'next_retry_at_utc': '2000-01-01T00:00:00.000Z'},
      where: 'id = ?',
      whereArgs: <Object?>[returnEventId],
    );
    final second = await service.syncPending();
    final recoveredReturn = (await database.database.query(
      'outbox_events',
      where: 'id = ?',
      whereArgs: <Object?>[returnEventId],
    )).single;

    expect(second.acknowledged, 1);
    expect(recoveredReturn['status'], 'acknowledged');
    expect(recoveredReturn['server_receipt_id'], returnEventId);
    expect(requestCount, 3);
  });

}
