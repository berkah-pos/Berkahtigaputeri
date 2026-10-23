import 'dart:convert';
import 'package:sqflite/sqflite.dart';

import '../auth/laravel_auth_service.dart';
import '../database/pos_database.dart';

/// Bounded, manually-triggered synchronization of the durable local outbox.
/// Local records are never deleted after a server response.
class OutboxSyncService {
  OutboxSyncService({
    required PosDatabase database,
    required LaravelAuthService authService,
    this.appVersion = 'unknown',
    this.maxEventsPerRun = 20,
  })  : _database = database,
        _authService = authService;

  final PosDatabase _database;
  final LaravelAuthService _authService;
  final String appVersion;
  final int maxEventsPerRun;

  bool _running = false;

  Future<OutboxSyncReport> syncPending() async {
    if (_running) {
      throw StateError('A local outbox synchronization is already running.');
    }
    _running = true;
    try {
      final db = _database.database;
      final now = DateTime.now().toUtc().toIso8601String();

      // Recover records left in-flight by an interrupted process. Re-delivery
      // is safe because the server binds a payload hash to the event ID.
      await db.rawUpdate(
        "UPDATE outbox_events SET status = 'retry', retry_count = retry_count + 1, "
        "last_error = ?, next_retry_at_utc = ? WHERE status = 'in_flight'",
        <Object?>['Recovered after interrupted synchronization.', now],
      );

      final limit = maxEventsPerRun < 1
          ? 1
          : (maxEventsPerRun > 20 ? 20 : maxEventsPerRun);
      final candidates = await db.rawQuery(
        '''
        SELECT *
        FROM outbox_events
        WHERE status IN ('pending', 'retry')
          AND (next_retry_at_utc IS NULL OR next_retry_at_utc <= ?)
        ORDER BY
          CASE entity_type
            WHEN 'product' THEN 0
            WHEN 'inventory_receipt' THEN 1
            WHEN 'sale' THEN 2
            ELSE 3
          END,
          created_at_utc,
          id
        LIMIT ?
        ''',
        <Object?>[now, limit],
      );

      var attempted = 0;
      var acknowledged = 0;
      var attentionRequired = 0;
      var retryScheduled = 0;
      var deferred = 0;

      for (final row in candidates) {
        final eventId = row['id']! as String;
        final entityType = row['entity_type']! as String;
        final entityId = row['entity_id']! as String;

        Map<String, dynamic> payload;
        try {
          final decoded = jsonDecode(row['payload']! as String);
          if (decoded is! Map) {
            throw const FormatException('Outbox payload is not an object.');
          }
          payload = Map<String, dynamic>.from(decoded);
          if (payload['event_id'] != eventId ||
              payload['event_type'] != entityType ||
              payload['entity_id'] != entityId ||
              payload['payload_version'] != 1) {
            throw const FormatException('Outbox envelope does not match its row.');
          }
        } catch (error) {
          await _markAttention(db, eventId, 'Invalid local event payload: $error');
          attentionRequired++;
          continue;
        }

        if (await _hasBlockingDependency(
          db,
          eventId: eventId,
          entityType: entityType,
          entityId: entityId,
          payload: payload,
        )) {
          deferred++;
          continue;
        }

        final changed = await db.update(
          'outbox_events',
          <String, Object?>{'status': 'in_flight', 'last_error': null},
          where: "id = ? AND status IN ('pending', 'retry')",
          whereArgs: <Object?>[eventId],
        );
        if (changed != 1) continue;

        attempted++;
        try {
          final response = await _authService.syncOutboxEvent(
            appVersion: appVersion,
            event: <String, dynamic>{
              'event_id': eventId,
              'entity_type': entityType,
              'entity_id': entityId,
              'payload': payload,
            },
          );
          final rawResults = response['results'];
          final result = rawResults is List &&
                  rawResults.isNotEmpty &&
                  rawResults.first is Map
              ? Map<String, dynamic>.from(rawResults.first as Map)
              : <String, dynamic>{};
          if (result['event_id'] != eventId) {
            await _markRetry(
              db,
              eventId,
              row['retry_count'] as int? ?? 0,
              'Server response did not identify the submitted event.',
            );
            retryScheduled++;
            continue;
          }

          final status = result['status'];
          final receiptId = result['receipt_id'];
          if ((status == 'accepted' || status == 'replayed') &&
              receiptId is String &&
              receiptId.trim().isNotEmpty) {
            await db.update(
              'outbox_events',
              <String, Object?>{
                'status': 'acknowledged',
                'acked_at_utc': DateTime.now().toUtc().toIso8601String(),
                'server_receipt_id': receiptId,
                'last_error': null,
                'next_retry_at_utc': null,
              },
              where: 'id = ?',
              whereArgs: <Object?>[eventId],
            );
            acknowledged++;
          } else if (status == 'conflict' || status == 'needs_attention') {
            await _markAttention(
              db,
              eventId,
              (result['message'] as String?) ?? 'Server reported an event conflict.',
            );
            attentionRequired++;
          } else {
            await _markRetry(
              db,
              eventId,
              row['retry_count'] as int? ?? 0,
              (result['message'] as String?) ?? 'Server requested an event retry.',
            );
            retryScheduled++;
          }
        } on AuthFailure catch (failure) {
          // Authentication/device/subscription state can be repaired without
          // changing the event. Keep the durable event retryable after re-login
          // or re-authorization; only event-level HTTP conflicts are terminal.
          final terminal = failure.statusCode == 409 ||
              failure.statusCode == 413 ||
              failure.statusCode == 422;
          if (terminal) {
            await _markAttention(
              db,
              eventId,
              failure.code + ': ' + failure.message,
            );
            attentionRequired++;
          } else {
            await _markRetry(
              db,
              eventId,
              row['retry_count'] as int? ?? 0,
              failure.code + ': ' + failure.message,
            );
            retryScheduled++;
          }
        } catch (error) {
          await _markRetry(
            db,
            eventId,
            row['retry_count'] as int? ?? 0,
            'Transient synchronization failure: $error',
          );
          retryScheduled++;
        }
      }

      final remainingRow = (await db.rawQuery(
        "SELECT COUNT(*) AS value FROM outbox_events WHERE status <> 'acknowledged'",
      )).single;
      return OutboxSyncReport(
        attempted: attempted,
        acknowledged: acknowledged,
        attentionRequired: attentionRequired,
        retryScheduled: retryScheduled,
        deferred: deferred,
        remaining: (remainingRow['value'] as num).toInt(),
      );
    } finally {
      _running = false;
    }
  }

  Future<bool> _hasBlockingDependency(
    DatabaseExecutor db, {
    required String eventId,
    required String entityType,
    required String entityId,
    required Map<String, dynamic> payload,
  }) async {
    if (entityType == 'product' || entityType == 'inventory_receipt') {
      final predecessors = await db.rawQuery(
        '''
        SELECT id
        FROM outbox_events
        WHERE entity_id = ?
          AND entity_type IN ('product', 'inventory_receipt')
          AND status <> 'acknowledged'
        ORDER BY
          CASE entity_type
            WHEN 'product' THEN 0
            WHEN 'inventory_receipt' THEN 1
            ELSE 2
          END,
          created_at_utc,
          id
        ''',
        <Object?>[entityId],
      );
      return predecessors.isNotEmpty && predecessors.first['id'] != eventId;
    }

    if (entityType != 'sale') return false;
    final rawItems = payload['items'];
    if (rawItems is! List) return false;
    final productIds = <String>{};
    for (final item in rawItems) {
      if (item is Map && item['product_id'] is String) {
        productIds.add(item['product_id'] as String);
      }
    }
    if (productIds.isEmpty) return false;

    final placeholders = List<String>.filled(productIds.length, '?').join(',');
    final unresolved = await db.rawQuery(
      '''
      SELECT id
      FROM outbox_events
      WHERE entity_type IN ('product', 'inventory_receipt')
        AND entity_id IN ($placeholders)
        AND status <> 'acknowledged'
      LIMIT 1
      ''',
      productIds.toList(growable: false),
    );
    return unresolved.isNotEmpty;
  }

  Future<void> _markAttention(DatabaseExecutor db, String id, String error) async {
    await db.update(
      'outbox_events',
      <String, Object?>{
        'status': 'needs_attention',
        'last_error': _shortError(error),
        'next_retry_at_utc': null,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> _markRetry(
    DatabaseExecutor db,
    String id,
    int retryCount,
    String error,
  ) async {
    final exponent = retryCount >= 8 ? 8 : (retryCount < 0 ? 0 : retryCount);
    final computedDelay = 5 * (1 << exponent);
    final delaySeconds = computedDelay > 900 ? 900 : computedDelay;
    final nextRetry = DateTime.now()
        .toUtc()
        .add(Duration(seconds: delaySeconds))
        .toIso8601String();
    await db.update(
      'outbox_events',
      <String, Object?>{
        'status': 'retry',
        'retry_count': retryCount + 1,
        'last_error': _shortError(error),
        'next_retry_at_utc': nextRetry,
      },
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  String _shortError(String value) {
    final normalized = value.trim();
    return normalized.length <= 500 ? normalized : normalized.substring(0, 500);
  }
}

class OutboxSyncReport {
  const OutboxSyncReport({
    required this.attempted,
    required this.acknowledged,
    required this.attentionRequired,
    required this.retryScheduled,
    required this.deferred,
    required this.remaining,
  });

  final int attempted;
  final int acknowledged;
  final int attentionRequired;
  final int retryScheduled;
  final int deferred;
  final int remaining;

  String get summary {
    if (attempted == 0 && remaining == 0) return 'Tidak ada antrean sinkronisasi.';
    return 'Server menerima $acknowledged event; $attentionRequired perlu ditinjau, '
        '$retryScheduled dijadwalkan ulang, $deferred menunggu dependensi. '
        'Sisa antrean lokal: $remaining.';
  }
}
