import 'pos_database.dart';

enum OutboxEventStatus { pending, syncing, synced, conflict }

class OutboxEvent {
  const OutboxEvent({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.payload,
    required this.status,
    required this.retryCount,
    required this.createdAtUtc,
    this.lastError,
    this.lastAttemptAtUtc,
  });

  final String id;
  final String entityType;
  final String entityId;
  final String payload;
  final OutboxEventStatus status;
  final int retryCount;
  final String createdAtUtc;
  final String? lastError;
  final String? lastAttemptAtUtc;

  factory OutboxEvent.fromRow(Map<String, Object?> row) {
    final rawStatus = row['status'];
    final status = OutboxEventStatus.values.where(
      (value) => value.name == rawStatus,
    );
    if (status.isEmpty) {
      throw FormatException('Unknown outbox status: ' + rawStatus.toString());
    }
    return OutboxEvent(
      id: row['id']! as String,
      entityType: row['entity_type']! as String,
      entityId: row['entity_id']! as String,
      payload: row['payload']! as String,
      status: status.first,
      retryCount: (row['retry_count'] as num?)?.toInt() ?? 0,
      createdAtUtc: row['created_at_utc']! as String,
      lastError: row['last_error'] as String?,
      lastAttemptAtUtc: row['last_attempt_at_utc'] as String?,
    );
  }
}

/// This response parser does not imply that a live Laravel sync endpoint exists.
class ServerOutboxBatchResult {
  const ServerOutboxBatchResult({
    required this.acceptedEventIds,
    required this.conflicts,
  });

  final Set<String> acceptedEventIds;
  final Map<String, String> conflicts;

  factory ServerOutboxBatchResult.fromJson(Map<String, dynamic> json) {
    final rawAccepted = json['accepted_event_ids'];
    if (rawAccepted is! List) {
      throw const FormatException(
        'Server response must contain accepted_event_ids.',
      );
    }
    final accepted = <String>{};
    for (final rawId in rawAccepted) {
      if (rawId is! String || rawId.trim().isEmpty || !accepted.add(rawId)) {
        throw const FormatException(
          'accepted_event_ids contains an invalid or duplicate ID.',
        );
      }
    }

    final conflicts = <String, String>{};
    final rawConflicts = json['conflicts'] ?? const <dynamic>[];
    if (rawConflicts is! List) {
      throw const FormatException('conflicts must be a list.');
    }
    for (final rawConflict in rawConflicts) {
      if (rawConflict is! Map) {
        throw const FormatException('Each conflict must be an object.');
      }
      final eventId = rawConflict['event_id'];
      final reason = rawConflict['reason'];
      if (eventId is! String ||
          eventId.trim().isEmpty ||
          reason is! String ||
          reason.trim().isEmpty ||
          conflicts.containsKey(eventId)) {
        throw const FormatException('Invalid or duplicate conflict entry.');
      }
      conflicts[eventId] = reason;
    }
    if (accepted.any(conflicts.containsKey)) {
      throw const FormatException(
        'An event cannot be both accepted and conflicted.',
      );
    }
    return ServerOutboxBatchResult(
      acceptedEventIds: accepted,
      conflicts: conflicts,
    );
  }
}

/// Durable local ledger only. No method deletes unsynced transactions.
class SqliteOutboxRepository {
  const SqliteOutboxRepository(this._database);

  final PosDatabase _database;

  Future<List<OutboxEvent>> listUnresolved() async {
    final rows = await _database.database.query(
      'outbox_events',
      where: 'status != ?',
      whereArgs: <Object?>[OutboxEventStatus.synced.name],
      orderBy: 'created_at_utc ASC, id ASC',
    );
    return rows.map(OutboxEvent.fromRow).toList(growable: false);
  }

  Future<List<OutboxEvent>> claimPending({
    int limit = 100,
    DateTime? attemptedAtUtc,
  }) async {
    if (limit < 1 || limit > 300) {
      throw ArgumentError.value(limit, 'limit', 'Must be between 1 and 300.');
    }
    final attemptedAt =
        (attemptedAtUtc ?? DateTime.now().toUtc()).toUtc().toIso8601String();
    return _database.transaction<List<OutboxEvent>>((transaction) async {
      final candidates = await transaction.query(
        'outbox_events',
        where: 'status = ?',
        whereArgs: <Object?>[OutboxEventStatus.pending.name],
        orderBy: 'created_at_utc ASC, id ASC',
        limit: limit,
      );
      final claimed = <OutboxEvent>[];
      for (final row in candidates) {
        final id = row['id']! as String;
        final changed = await transaction.update(
          'outbox_events',
          <String, Object?>{
            'status': OutboxEventStatus.syncing.name,
            'last_error': null,
            'last_attempt_at_utc': attemptedAt,
          },
          where: 'id = ? AND status = ?',
          whereArgs: <Object?>[id, OutboxEventStatus.pending.name],
        );
        if (changed == 1) {
          claimed.add(
            OutboxEvent.fromRow(<String, Object?>{
              ...row,
              'status': OutboxEventStatus.syncing.name,
              'last_error': null,
              'last_attempt_at_utc': attemptedAt,
            }),
          );
        }
      }
      return claimed;
    });
  }

  Future<void> applyServerResult({
    required Iterable<String> submittedEventIds,
    required ServerOutboxBatchResult result,
  }) async {
    final submittedList = submittedEventIds.toList(growable: false);
    final submitted = submittedList.toSet();
    if (submittedList.any((id) => id.trim().isEmpty) ||
        submitted.length != submittedList.length) {
      throw ArgumentError('Submitted event IDs must be unique and non-empty.');
    }
    if (!submitted.containsAll(result.acceptedEventIds) ||
        !submitted.containsAll(result.conflicts.keys)) {
      throw const FormatException(
        'Server response contains an event ID not in this submitted batch.',
      );
    }
    if (submitted.isEmpty) return;

    final now = DateTime.now().toUtc().toIso8601String();
    await _database.transaction<void>((transaction) async {
      for (final id in submittedList) {
        final rows = await transaction.query(
          'outbox_events',
          where: 'id = ?',
          whereArgs: <Object?>[id],
          limit: 1,
        );
        if (rows.isEmpty || rows.single['status'] != 'syncing') {
          throw StateError(
            'Event is missing or was not claimed for sync: ' + id,
          );
        }
      }

      for (final id in submittedList) {
        if (result.acceptedEventIds.contains(id)) {
          // An explicit server acceptance is the only path to "synced".
          await transaction.update(
            'outbox_events',
            <String, Object?>{
              'status': OutboxEventStatus.synced.name,
              'last_error': null,
              'last_attempt_at_utc': now,
            },
            where: 'id = ? AND status = ?',
            whereArgs: <Object?>[id, OutboxEventStatus.syncing.name],
          );
        } else if (result.conflicts.containsKey(id)) {
          await transaction.update(
            'outbox_events',
            <String, Object?>{
              'status': OutboxEventStatus.conflict.name,
              'last_error': result.conflicts[id],
              'last_attempt_at_utc': now,
            },
            where: 'id = ? AND status = ?',
            whereArgs: <Object?>[id, OutboxEventStatus.syncing.name],
          );
        } else {
          // Missing acknowledgement is not success; keep the event retryable.
          final rows = await transaction.query(
            'outbox_events',
            columns: <String>['retry_count'],
            where: 'id = ?',
            whereArgs: <Object?>[id],
            limit: 1,
          );
          final retryCount = (rows.single['retry_count'] as num).toInt();
          await transaction.update(
            'outbox_events',
            <String, Object?>{
              'status': OutboxEventStatus.pending.name,
              'retry_count': retryCount + 1,
              'last_error':
                  'Server did not explicitly acknowledge this event; retry retained.',
              'last_attempt_at_utc': now,
            },
            where: 'id = ? AND status = ?',
            whereArgs: <Object?>[id, OutboxEventStatus.syncing.name],
          );
        }
      }
    });
  }

  Future<void> markTransportFailure({
    required Iterable<String> submittedEventIds,
  }) async {
    final ids = submittedEventIds.toList(growable: false);
    final uniqueIds = ids.toSet();
    if (ids.any((id) => id.trim().isEmpty) || ids.length != uniqueIds.length) {
      throw ArgumentError('Submitted event IDs must be unique and non-empty.');
    }
    if (ids.isEmpty) return;

    final now = DateTime.now().toUtc().toIso8601String();
    await _database.transaction<void>((transaction) async {
      for (final id in ids) {
        final rows = await transaction.query(
          'outbox_events',
          columns: <String>['retry_count'],
          where: 'id = ? AND status = ?',
          whereArgs: <Object?>[id, OutboxEventStatus.syncing.name],
          limit: 1,
        );
        if (rows.isEmpty) continue;
        final retryCount = (rows.single['retry_count'] as num).toInt();
        await transaction.update(
          'outbox_events',
          <String, Object?>{
            'status': OutboxEventStatus.pending.name,
            'retry_count': retryCount + 1,
            'last_error':
                'Transport failed; server acceptance was not confirmed.',
            'last_attempt_at_utc': now,
          },
          where: 'id = ? AND status = ?',
          whereArgs: <Object?>[id, OutboxEventStatus.syncing.name],
        );
      }
    });
  }
}
