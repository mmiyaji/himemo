import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/profile_name_sync.dart';

void main() {
  const empty = ProfileNameSync();

  ProfileNameSync rename(
    ProfileNameSync state,
    String device,
    String id,
    String name,
  ) => state.rename(name: name, deviceId: device, changeId: id);

  ProfileNameSync transmitted(ProfileNameSync state) =>
      ProfileNameSync.fromJson(state.toJson(includePending: false))!;

  test('older names cannot replace a newer local rename', () {
    final first = rename(empty, 'phone', 'a', 'Work');
    final second = rename(first, 'phone', 'b', 'Personal');

    final replayed = second.merge(transmitted(first));
    expect(replayed.preferredName, 'Personal');
    expect(replayed.sendableId, 'b');
    expect(replayed.heads.single.clock, {'phone': 2});
  });

  test('acknowledgement cannot clear a rename made during upload', () {
    final sent = rename(empty, 'phone', 'sent', 'One');
    final next = rename(sent, 'phone', 'next', 'Two');

    expect(next.acknowledge('sent').sendableId, 'next');
    final acknowledged = next.acknowledge('next');
    expect(acknowledged.sendableId, isNull);
    expect(acknowledged.preferredName, 'Two');
  });

  test('concurrent changes are preserved until a choice supersedes them', () {
    final base = transmitted(rename(empty, 'phone', 'base', 'Original'));
    final phone = rename(base, 'phone', 'phone-edit', 'From iPhone');
    final tablet = rename(base, 'tablet', 'tablet-edit', 'From iPad');

    final conflict = phone.merge(transmitted(tablet));
    expect(conflict.hasConflict, isTrue);
    expect(conflict.pendingId, 'phone-edit');
    expect(conflict.sendableId, isNull);
    expect(conflict.heads.map((head) => head.name), [
      'From iPhone',
      'From iPad',
    ]);

    final resolved = rename(conflict, 'phone', 'choice', 'From iPad');
    expect(resolved.heads.single.clock, {'phone': 3, 'tablet': 1});
    expect(resolved.sendableId, 'choice');
    expect(resolved.hasConflict, isFalse);

    final received = tablet.merge(transmitted(resolved));
    expect(received.preferredName, 'From iPad');
    expect(received.pendingId, isNull);
    expect(received.merge(transmitted(phone)).toJson(), received.toJson());
  });

  test('concurrent identical names converge without a choice', () {
    final phone = rename(empty, 'phone', 'a', 'Same');
    final tablet = rename(empty, 'tablet', 'b', 'Same');

    final merged = phone.merge(tablet);
    expect(merged.hasConflict, isFalse);
    expect(merged.sendableId, 'a');
    expect(merged.heads.map((head) => head.id), ['a', 'b']);
    expect(
      merged.toJson(includePending: false),
      tablet.merge(phone).toJson(includePending: false),
    );
  });

  test('the queue is persisted locally and omitted from remote payloads', () {
    final local = rename(empty, 'phone', 'queued', 'Private');
    final restored = ProfileNameSync.fromJson(
      jsonDecode(jsonEncode(local.toJson())),
    );
    expect(restored?.pendingId, 'queued');
    expect(restored?.preferredName, 'Private');
    expect(transmitted(local).pendingId, isNull);
    expect(empty.merge(local).pendingId, isNull);
  });

  test('invalid clocks and orphan pending IDs are rejected', () {
    expect(
      ProfileNameChange.fromJson({
        'id': 'invalid',
        'name': 'Invalid',
        'clock': {'phone': 0},
      }),
      isNull,
    );
    expect(
      ProfileNameSync.fromJson({'heads': [], 'pendingId': 'unknown'}),
      isNull,
    );
    expect(
      ProfileNameSync.fromJson({
        'heads': [
          {
            'id': 'a',
            'name': 'Old',
            'clock': {'phone': 1},
          },
          {
            'id': 'b',
            'name': 'New',
            'clock': {'phone': 2},
          },
        ],
      }),
      isNull,
    );
  });
}
