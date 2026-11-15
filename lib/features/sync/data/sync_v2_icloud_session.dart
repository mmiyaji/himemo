import 'sync_v2_enrollment_store.dart';
import 'sync_v2_icloud_transport.dart';
import 'sync_v2_inbox.dart';
import 'sync_v2_publisher.dart';
import 'sync_v2_receiver.dart';

typedef SyncV2ICloudProgress = ({
  bool headersStaged,
  bool hasMoreHeaders,
  int downloadedPayloads,
  int publishedChanges,
  List<String> errors,
});

/// A bounded sync pass for the enrolled account, with no profile-key access.
class SyncV2ICloudSession {
  SyncV2ICloudSession(
    this._enrollments,
    this._inbox, {
    this.stopOnQuarantine = false,
  });

  final SyncV2EnrollmentStore _enrollments;
  final SyncV2Inbox _inbox;
  final bool stopOnQuarantine;
  Future<SyncV2ICloudProgress>? _active;

  Future<SyncV2ICloudProgress> syncOnce({int limit = 50}) async {
    if (limit < 1 || limit > 200) throw ArgumentError.value(limit, 'limit');
    if (_active case final active?) return active;
    final run = _syncOnce(limit);
    _active = run;
    try {
      return await run;
    } finally {
      _active = null;
    }
  }

  Future<SyncV2ICloudProgress> _syncOnce(int limit) async {
    final account = await SyncV2ICloudTransport(accountId: '')
        .readCurrentAccountId();
    final enrollment = await _enrollments.readForAccount(account);
    if (enrollment == null) {
      throw StateError('This device has no iCloud v2 enrollment');
    }
    try {
      final transport = SyncV2ICloudTransport(accountId: account);
      final receiver = SyncV2Receiver(transport, _inbox);
      final errors = <String>[];
      var headersStaged = false;
      var hasMoreHeaders = false;
      var downloaded = 0;
      var published = 0;
      Future<void> receive() async {
        try {
          final page = await receiver.pullPage(
            generationId: enrollment.generationId,
            syncKey: enrollment.syncKey,
            limit: limit,
          );
          headersStaged = page.staged;
          hasMoreHeaders = page.hasMore;
        } on Exception {
          errors.add('header_receive_failed');
        }
        try {
          downloaded = await receiver.pullPendingPayloads(
            generationId: enrollment.generationId,
            syncKey: enrollment.syncKey,
            limit: limit,
          );
        } on Exception {
          errors.add('payload_receive_failed');
        }
      }

      Future<void> publish() async {
        try {
          published = await SyncV2Publisher(transport, _inbox).publishPage(
            generationId: enrollment.generationId,
            limit: limit,
            stopOnQuarantine: stopOnQuarantine,
          );
        } on Exception {
          errors.add('publish_failed');
        }
      }

      await Future.wait([receive(), publish()]);
      return (
        headersStaged: headersStaged,
        hasMoreHeaders: hasMoreHeaders,
        downloadedPayloads: downloaded,
        publishedChanges: published,
        errors: List<String>.unmodifiable(errors),
      );
    } finally {
      enrollment.syncKey.destroy();
    }
  }
}
