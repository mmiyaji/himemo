import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/app/audit_log.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('drops v1 entries and redacts sensitive field values', () async {
    const legacySecret = 'legacy-private-profile-name';
    const retainedEntry =
        '2026-07-10T00:00:00.000Z [audit] retained_event count=1';
    SharedPreferences.setMockInitialValues({
      'audit_logging.entries.v1': <String>[
        '2026-07-09T00:00:00.000Z [audit] old_event name=$legacySecret',
      ],
      'audit_logging.entries.v2': <String>[retainedEntry],
    });

    final service = AuditLogService.instance;
    expect(await service.entries(), const <String>[retainedEntry]);

    var preferences = await SharedPreferences.getInstance();
    expect(preferences.getStringList('audit_logging.entries.v1'), isNull);

    await service.record(
      'private_note_access',
      data: const <String, Object?>{
        'tagIds': 'family,medical',
        'vaultId': 'private_profile:personal',
        'PROFILE_ID': 'profile-42',
        'noteId': 'note-sensitive-42',
        'displayName': 'Sensitive Person',
        'name': 'private-photo.jpg',
        'count': 3,
        'result': 'access granted',
        'omitted': null,
      },
    );

    final line = (await service.entries()).last;
    expect(line, contains('tagIds=[redacted]'));
    expect(line, contains('vaultId=[redacted]'));
    expect(line, contains('PROFILE_ID=[redacted]'));
    expect(line, contains('noteId=[redacted]'));
    expect(line, contains('displayName=[redacted]'));
    expect(line, contains('name=[redacted]'));
    expect(line, contains('count=3'));
    expect(line, contains('result=access_granted'));
    expect(line, isNot(contains('family,medical')));
    expect(line, isNot(contains('private_profile:personal')));
    expect(line, isNot(contains('profile-42')));
    expect(line, isNot(contains('note-sensitive-42')));
    expect(line, isNot(contains('Sensitive Person')));
    expect(line, isNot(contains('private-photo.jpg')));
    expect(line, isNot(contains('omitted=')));

    preferences = await SharedPreferences.getInstance();
    expect(preferences.getStringList('audit_logging.entries.v2'), <String>[
      retainedEntry,
      line,
    ]);
    final exported = await service.exportText();
    expect(exported, isNot(contains(legacySecret)));
    expect(exported, isNot(contains('Sensitive Person')));
  });
}
