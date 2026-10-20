import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../api/laravel_api_client.dart';
import '../config/app_identity_store.dart';
import '../database/pos_database.dart';

class OutboxSyncSummary {
  const OutboxSyncSummary({
    required this.accepted,
    required this.retried,
    required this.needsAttention,
  });

  final int accepted;
  final int retried;
  final int needsAttention;

  bool get didWork => accepted + retried + needsAttention > 0;
}

/// Explicit, bounded foreground sync. A row is acknowledged only after Laravel
/// returns a durable receipt from its tenant-database transaction.
class OutboxSyncService {
  OutboxSyncService({
    required PosDatabase database,
    required LaravelApiClient apiClient,
    required AppIdentityStore identityStore,
    DateTime Function()? clock,
  })  : _database = database,
        _apiClient = apiClient,
        _identityStore = identityStore,
        _clock = clock ?? DateTime.now;

  static const int _maxEventsPerRun = 20;
  static const int _maxAttempts = 12;
  final PosDatabase _database;
  final LaravelApiClient _apiClient;
  final AppIdentityStore _identityStore;
  final DateTime Function() _clock;
  bool _running = false;

  Future<OutboxSyncSummary> syncPending() async {
    if (_running) {
      return const OutboxSyncSummary(accepted: 0, retried: 0, needsAttention: 0);
    }
    if (!_apiClient.hasAuthenticatedSession) {
      throw const ApiException(401, 'unauthenticated', 'Silakan login kembali sebelum sinkronisasi.');
    }
    final deviceId = _identityStore.deviceId.trim();
    final tenantId = _identityStore.tenantId.trim();
    if (deviceId.isEmpty || tenantId.isEmpty) {
      throw const ApiException(403, 'device_not_authorized', 'Tenant/perangkat belum diatur dan diverifikasi.');
    }

    _running = true;
    var accepted = 0;
    var retried = 0;
    var needsAttention = 0;
    try {
      // A terminated process may leave rows in-flight. They are safe to retry
      // because the server keys acceptance by event ID plus canonical payload SHA.
      await _database.database.update(
        'outbox_events',
        <String, Object?>{
          'status': 'retry',
          'last_error': 'Pemulihan otomatis setelah proses sebelumnya berhenti.',
          'next_retry_at_utc': _clock().toUtc().toIso8601String(),
        },
        where: "status = 'in_flight'",
      );

      final now = _clock().toUtc().toIso8601String();
      final rows = await _database.database.query(
        'outbox_events',
        where: "(status = 'pending' OR status = 'retry') AND (next_retry_at_utc IS NULL OR next_retry_at_utc <= ?)",
        whereArgs: <Object?>[now],
        orderBy: 'created_at_utc ASC, id ASC',
        limit: _maxEventsPerRun,
      );

      for (final row in rows) {
        final eventId = row['id']?.toString() ?? '';
        final payloadRaw = row['payload']?.toString() ?? '';
        Map<String, dynamic> payload;
        try {
          final decoded = jsonDecode(payloadRaw);
          if (decoded is! Map) throw const FormatException('Payload outbox bukan objek JSON.');
          payload = Map<String, dynamic>.from(decoded);
          if (eventId.isEmpty ||
              payload['event_id']?.toString() != eventId ||
              payload['event_type']?.toString() != row['entity_type']?.toString() ||
              payload['payload_version'] != 1) {
            throw const FormatException('Kontrak event outbox tidak cocok.');
          }
        } catch (error) {
          await _markAttention(eventId, 'Payload lokal tidak valid: ' + error.toString());
          needsAttention++;
          continue;
        }

        final nextAttempt = ((row['retry_count'] as int?) ?? 0) + 1;
        await _database.database.update(
          'outbox_events',
          <String, Object?>{
            'status': 'in_flight',
            'retry_count': nextAttempt,
            'last_error': null,
            'next_retry_at_utc': null,
          },
          where: 'id = ? AND status IN (?, ?)',
          whereArgs: <Object?>[eventId, 'pending', 'retry'],
        );

        try {
          final response = await _apiClient.syncOutboxEvent(
            deviceId: deviceId,
            appVersion: const String.fromEnvironment('APP_VERSION', defaultValue: 'unknown'),
            event: <String, dynamic>{
              'event_id': eventId,
              'entity_type': row['entity_type']?.toString() ?? '',
              'entity_id': row['entity_id']?.toString() ?? '',
              'payload': payload,
            },
          );
          final results = response['results'];
          if (results is! List || results.length != 1 || results.first is! Map) {
            throw const FormatException('Respons sync tidak memiliki satu hasil event.');
          }
          final result = Map<String, dynamic>.from(results.first as Map);
          final state = result['status']?.toString();
          if (state == 'accepted' || state == 'replayed') {
            final receipt = result['receipt_id']?.toString() ?? '';
            if (receipt.isEmpty) throw const FormatException('Receipt server kosong.');
            await _database.database.update(
              'outbox_events',
              <String, Object?>{
                'status': 'acknowledged',
                'acked_at_utc': _clock().toUtc().toIso8601String(),
                'server_receipt_id': receipt,
                'last_error': null,
                'next_retry_at_utc': null,
              },
              where: 'id = ? AND status = ?',
              whereArgs: <Object?>[eventId, 'in_flight'],
            );
            accepted++;
          } else if (state == 'conflict' || state == 'needs_attention') {
            await _markAttention(eventId, (result['message'] ?? 'Server menandai event untuk penanganan manual.').toString());
            needsAttention++;
          } else {
            throw const FormatException('Status receipt sync tidak dikenal.');
          }
        } on ApiException catch (error) {
          if (error.statusCode == 409 || error.statusCode == 422 || error.statusCode == 401 || error.statusCode == 403) {
            await _markAttention(eventId, error.message);
            needsAttention++;
          } else {
            await _scheduleRetry(eventId, nextAttempt, error.message);
            retried++;
          }
        } on ApiTransportException catch (error) {
          await _scheduleRetry(eventId, nextAttempt, error.message);
          retried++;
        } on FormatException catch (error) {
          await _scheduleRetry(eventId, nextAttempt, error.message);
          retried++;
        } catch (error) {
          await _scheduleRetry(eventId, nextAttempt, 'Kesalahan sync: ' + error.toString());
          retried++;
        }
      }

      return OutboxSyncSummary(
        accepted: accepted,
        retried: retried,
        needsAttention: needsAttention,
      );
    } finally {
      _running = false;
    }
  }

  Future<void> _scheduleRetry(String eventId, int attempt, String message) async {
    if (attempt >= _maxAttempts) {
      await _markAttention(eventId, 'Batas retry tercapai. ' + message);
      return;
    }
    final exponent = attempt.clamp(1, 10);
    final delaySeconds = (5 * (1 << (exponent - 1))).clamp(5, 3600);
    final retryAt = _clock().toUtc().add(Duration(seconds: delaySeconds));
    await _database.database.update(
      'outbox_events',
      <String, Object?>{
        'status': 'retry',
        'last_error': message,
        'next_retry_at_utc': retryAt.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: <Object?>[eventId],
    );
  }

  Future<void> _markAttention(String eventId, String message) async {
    if (eventId.isEmpty) return;
    await _database.database.update(
      'outbox_events',
      <String, Object?>{
        'status': 'needs_attention',
        'last_error': message,
        'next_retry_at_utc': null,
      },
      where: 'id = ?',
      whereArgs: <Object?>[eventId],
    );
  }
}
