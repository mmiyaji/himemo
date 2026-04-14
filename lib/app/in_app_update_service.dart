import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

class InAppUpdateStatus {
  const InAppUpdateStatus({
    required this.isSupported,
    required this.updateAvailable,
    required this.message,
    this.immediateAllowed = false,
    this.flexibleAllowed = false,
    this.availableVersionCode,
    this.installStatus,
    this.updatePriority,
    this.clientVersionStalenessDays,
  });

  const InAppUpdateStatus.unsupported(String message)
    : this(
        isSupported: false,
        updateAvailable: false,
        message: message,
      );

  final bool isSupported;
  final bool updateAvailable;
  final bool immediateAllowed;
  final bool flexibleAllowed;
  final int? availableVersionCode;
  final InstallStatus? installStatus;
  final int? updatePriority;
  final int? clientVersionStalenessDays;
  final String message;
}

class InAppUpdateService {
  const InAppUpdateService();

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<InAppUpdateStatus> checkForUpdate() async {
    if (!_supported) {
      return const InAppUpdateStatus.unsupported(
        'In-app updates are only available on Android.',
      );
    }
    try {
      final info = await InAppUpdate.checkForUpdate();
      final updateAvailable =
          info.updateAvailability == UpdateAvailability.updateAvailable;
      return InAppUpdateStatus(
        isSupported: true,
        updateAvailable: updateAvailable,
        immediateAllowed: info.immediateUpdateAllowed,
        flexibleAllowed: info.flexibleUpdateAllowed,
        availableVersionCode: info.availableVersionCode,
        installStatus: info.installStatus,
        updatePriority: info.updatePriority,
        clientVersionStalenessDays: info.clientVersionStalenessDays,
        message: updateAvailable
            ? 'An update is available from Google Play.'
            : 'The installed build is up to date.',
      );
    } catch (error) {
      return InAppUpdateStatus.unsupported('$error');
    }
  }

  Future<void> performFlexibleUpdate() async {
    if (!_supported) {
      return;
    }
    await InAppUpdate.startFlexibleUpdate();
  }

  Future<void> performImmediateUpdate() async {
    if (!_supported) {
      return;
    }
    await InAppUpdate.performImmediateUpdate();
  }

  Future<void> completeFlexibleUpdate() async {
    if (!_supported) {
      return;
    }
    await InAppUpdate.completeFlexibleUpdate();
  }
}
