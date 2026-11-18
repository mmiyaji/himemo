// Development-only CloudKit sandbox session. Never imported by production.
import 'package:drift/drift.dart' show QueryExecutor;
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/sync/data/sync_v2_cloudkit_web.dart';
import 'package:himemo/features/sync/data/sync_v2_enrollment_store.dart';
import 'package:himemo/features/sync/data/sync_v2_generation_registration.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_icloud_session.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';
import 'package:himemo/features/sync/presentation/sync_v2_cloudkit_readonly.dart'
    show SyncV2EphemeralKeyStore;
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';

/// Always configures the test-only development zones, never production zones.
Future<bool> configureCloudKitSandbox({
  required SyncV2CloudKitWebBridge bridge,
  required String apiToken,
  required String namespace,
}) {
  if (apiToken.isEmpty ||
      !RegExp(r'^[A-Za-z0-9_-]{16,32}$').hasMatch(namespace)) {
    throw ArgumentError('Invalid sandbox configuration');
  }
  return bridge.configure(
    containerIdentifier: 'iCloud.org.ruhenheim.himemo',
    apiToken: apiToken,
    environment: 'development',
    enableWrites: true,
    sandboxNamespace: namespace,
  );
}

/// Prevents work initiated after disconnect and invalidates late responses.
/// CloudKit writes already dispatched cannot be cancelled by the client.
class SandboxTransportGate {
  SandboxTransportGate(this._invoke, this._disconnect);
  final SyncV2CloudKitWebInvoker _invoke;
  final Future<void> Function() _disconnect;
  bool _closed = false;
  int _revision = 0;

  Future<Object?> invoke(String method, Map<String, Object?> arguments) async {
    if (_closed) throw StateError('Sandbox session is closed');
    final revision = _revision;
    try {
      final result = await _invoke(method, arguments);
      if (_closed || revision != _revision) {
        throw StateError('Sandbox session is closed');
      }
      return result;
    } catch (_) {
      if (_closed || revision != _revision) {
        throw StateError('Sandbox session is closed');
      }
      rethrow;
    }
  }

  Future<void> close() {
    if (_closed) return Future<void>.value();
    _closed = true;
    _revision++;
    return _disconnect();
  }
}

/// Owns V2 credentials and the isolated in-memory database for one connection.
class SyncV2CloudKitSandboxSession {
  SyncV2CloudKitSandboxSession._(this.workspace, this._store, this._gate);
  final SyncV2WorkspaceController workspace;
  final SyncV2EphemeralKeyStore _store;
  final SandboxTransportGate _gate;
  bool _closed = false;
  Future<void>? _closing;

  static SyncV2CloudKitSandboxSession create({
    required QueryExecutor executor,
    required SyncV2CloudKitWebInvoker invoke,
    required Future<void> Function() disconnect,
  }) {
    final encryption = EncryptionService();
    final headers = SyncV2HeaderCodec(encryption);
    final inbox = SyncV2Inbox(executor, headers);
    final store = SyncV2EphemeralKeyStore();
    final enrollments = SyncV2EnrollmentStore(store);
    final gate = SandboxTransportGate(invoke, disconnect);
    SyncV2CloudKitWebTransport transport(String account) =>
        SyncV2CloudKitWebTransport(accountId: account, invoke: gate.invoke);
    Future<String> accountReader() => transport('').readCurrentAccountId();
    final workspace = SyncV2WorkspaceController(
      inbox: inbox,
      repository: SyncV2NoteRepository(
        inbox,
        headers,
        SyncV2PayloadCodec(encryption),
      ),
      store: store,
      enrollments: enrollments,
      registrationTransport: transport(''),
      registrationFactory: (account) =>
          SyncV2GenerationRegistration(transport(account), enrollments),
      syncOperation: () => SyncV2ICloudSession(
        enrollments,
        inbox,
        stopOnQuarantine: true,
        accountReader: accountReader,
        transportFactory: (account) =>
            (reader: transport(account), writer: transport(account)),
      ).syncOnce(),
      supported: true,
      automaticSync: true,
    );
    return SyncV2CloudKitSandboxSession._(workspace, store, gate);
  }

  /// Synchronously revokes keys and stops future work before awaiting bridge
  /// cleanup. The widget owner must first remove the workspace from the screen.
  Future<void> close() {
    if (_closed) return _closing ?? Future<void>.value();
    _closed = true;
    workspace.revokeSession();
    _store.clearSession();
    try {
      _closing = _gate.close();
    } catch (error, stack) {
      _closing = Future<void>.error(error, stack);
    } finally {
      workspace.dispose();
    }
    return _closing!;
  }
}
