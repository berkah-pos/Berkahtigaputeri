import 'dart:convert';
import 'dart:math';

import 'package:sqflite/sqflite.dart';

final Random _outboxRandom = Random.secure();

/// Enqueues one versioned server-sync envelope inside the caller's SQLite
/// transaction, so the business write and its outbox record commit together.
Future<void> enqueueOutboxEvent(
  Transaction transaction, {
  required String entityType,
  required String entityId,
  required Map<String, Object?> eventPayload,
  required String createdAtUtc,
  String? eventId,
}) async {
  const allowedTypes = <String>{'product', 'inventory_receipt', 'sale'};
  if (!allowedTypes.contains(entityType)) {
    throw ArgumentError.value(entityType, 'entityType', 'Unsupported event type');
  }
  if (entityId.trim().isEmpty || entityId.length > 150) {
    throw ArgumentError.value(entityId, 'entityId', 'Invalid entity ID');
  }

  final resolvedEventId = eventId ?? newOutboxEventId(entityType);
  if (resolvedEventId.trim().isEmpty || resolvedEventId.length > 100) {
    throw ArgumentError.value(resolvedEventId, 'eventId', 'Invalid event ID');
  }

  final payload = <String, Object?>{
    ...eventPayload,
    'event_id': resolvedEventId,
    'event_type': entityType,
    'payload_version': 1,
    'entity_id': entityId,
  };

  await transaction.insert(
    'outbox_events',
    <String, Object?>{
      'id': resolvedEventId,
      'entity_type': entityType,
      'entity_id': entityId,
      'payload': jsonEncode(payload),
      'status': 'pending',
      'retry_count': 0,
      'created_at_utc': createdAtUtc,
      'last_error': null,
      'next_retry_at_utc': null,
      'acked_at_utc': null,
      'server_receipt_id': null,
    },
    conflictAlgorithm: ConflictAlgorithm.abort,
  );
}

String newOutboxEventId(String entityType) {
  final time = DateTime.now().toUtc().microsecondsSinceEpoch.toRadixString(16);
  final random = List<int>.generate(16, (_) => _outboxRandom.nextInt(256))
      .map((value) => value.toRadixString(16).padLeft(2, '0'))
      .join();
  return 'outbox:$entityType:$time:$random';
}
