import 'dart:io';

import 'package:berkahtigaputeri_pos/core/database/outbox_repository.dart';
import 'package:berkahtigaputeri_pos/core/database/pos_database.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_database.dart';

void main() {
  group('SQLite durable outbox state machine', () {
    test('does not acknowledge an event omitted from server acceptance', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      await _insertEvent(database, id: 'event-omitted');

      final repository = SqliteOutboxRepository(database);
      final claimed = await repository.claimPending();
      expect(claimed.map((event) => event.id), <String>['event-omitted']);
      expect(claimed.single.status, OutboxEventStatus.syncing);

      await repository.applyServerResult(
        submittedEventIds: <String>['event-omitted'],
        result: ServerOutboxBatchResult.fromJson(<String, dynamic>{
          'accepted_event_ids': <String>[],
        }),
      );

      final row = await _readEvent(database, 'event-omitted');
      expect(row.status, OutboxEventStatus.pending);
      expect(row.retryCount, 1);
      expect(row.lastError, contains('did not explicitly acknowledge'));
      expect((await repository.listUnresolved()).map((event) => event.id),
          contains('event-omitted'));
    });

    test('only explicit server acceptance marks an event synced', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      await _insertEvent(database, id: 'event-accepted');
      final repository = SqliteOutboxRepository(database);
      await repository.claimPending();

      await repository.applyServerResult(
        submittedEventIds: <String>['event-accepted'],
        result: ServerOutboxBatchResult.fromJson(<String, dynamic>{
          'accepted_event_ids': <String>['event-accepted'],
        }),
      );

      expect((await _readEvent(database, 'event-accepted')).status,
          OutboxEventStatus.synced);
      expect(await repository.listUnresolved(), isEmpty);
    });

    test('server conflicts remain visible and are never dropped', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      await _insertEvent(database, id: 'event-conflict');
      final repository = SqliteOutboxRepository(database);
      await repository.claimPending();

      await repository.applyServerResult(
        submittedEventIds: <String>['event-conflict'],
        result: ServerOutboxBatchResult.fromJson(<String, dynamic>{
          'accepted_event_ids': <String>[],
          'conflicts': <Map<String, String>>[
            <String, String>{
              'event_id': 'event-conflict',
              'reason': 'payload hash conflicts with an existing transaction',
            },
          ],
        }),
      );

      final unresolved = await repository.listUnresolved();
      expect(unresolved, hasLength(1));
      expect(unresolved.single.id, 'event-conflict');
      expect(unresolved.single.status, OutboxEventStatus.conflict);
      expect(unresolved.single.lastError, contains('payload hash conflicts'));
    });

    test('transport failure restores pending retry state', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      await _insertEvent(database, id: 'event-network');
      final repository = SqliteOutboxRepository(database);
      await repository.claimPending();

      await repository.markTransportFailure(
        submittedEventIds: <String>['event-network'],
      );

      final row = await _readEvent(database, 'event-network');
      expect(row.status, OutboxEventStatus.pending);
      expect(row.retryCount, 1);
      expect(row.lastError, contains('acceptance was not confirmed'));
    });

    test('rejects an acknowledgement ID outside the submitted batch', () async {
      final database = await openTestDatabase();
      addTearDown(database.close);
      await _insertEvent(database, id: 'event-owned');
      final repository = SqliteOutboxRepository(database);
      await repository.claimPending();

      await expectLater(
        repository.applyServerResult(
          submittedEventIds: <String>['event-owned'],
          result: ServerOutboxBatchResult.fromJson(<String, dynamic>{
            'accepted_event_ids': <String>['different-event'],
          }),
        ),
        throwsFormatException,
      );
      expect((await _readEvent(database, 'event-owned')).status,
          OutboxEventStatus.syncing);
    });

    test('preserves durable event and recovers interrupted syncing on restart',
        () async {
      final directory =
          await Directory.systemTemp.createTemp('berkah-pos-outbox-');
      addTearDown(() => directory.delete(recursive: true));
      final path = directory.path + '/pos-test.sqlite';

      var database = await openTestDatabase(path: path);
      await _insertEvent(database, id: 'event-durable', status: 'syncing');
      await database.close();

      database = await openTestDatabase(path: path);
      addTearDown(database.close);
      final row = await _readEvent(database, 'event-durable');
      expect(row.id, 'event-durable');
      expect(row.status, OutboxEventStatus.pending);
      expect(row.retryCount, 1);
      expect(row.lastError, contains('Recovered interrupted sync'));
      expect(await SqliteOutboxRepository(database).listUnresolved(),
          hasLength(1));
    });
  });
}

Future<void> _insertEvent(
  PosDatabase database, {
  required String id,
  String status = 'pending',
}) async {
  await database.database.insert('outbox_events', <String, Object?>{
    'id': id,
    'entity_type': 'sale',
    'entity_id': 'sale:' + id,
    'payload': '{"eventId":"$id"}',
    'status': status,
    'retry_count': 0,
    'created_at_utc': '2026-10-15T00:00:00.000Z',
    'last_error': null,
    'last_attempt_at_utc': null,
  });
}

Future<OutboxEvent> _readEvent(PosDatabase database, String id) async {
  final rows = await database.database.query(
    'outbox_events',
    where: 'id = ?',
    whereArgs: <Object?>[id],
    limit: 1,
  );
  expect(rows, hasLength(1));
  return OutboxEvent.fromRow(rows.single);
}
