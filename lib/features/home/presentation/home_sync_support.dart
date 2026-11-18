part of 'home_page.dart';

String _appUpdatesUnavailableDescription(AppStrings strings) {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    return strings.appUpdatesDescIos;
  }
  return strings.updateSupportedOnAndroidOnly;
}

String _versionWithBuildDate(AppStrings strings, String version) {
  final buildDate = _formattedBuildDate();
  if (buildDate == null) {
    return version;
  }
  return '$version / ${strings.buildDateLabel(buildDate)}';
}

String? _formattedBuildDate() {
  final value = _buildDateIso.trim();
  if (value.isEmpty) {
    return null;
  }
  final parsed = DateTime.tryParse(value);
  final date = parsed == null ? value : parsed.toLocal().toIso8601String();
  if (date.length >= 10) {
    return date.substring(0, 10).replaceAll('-', '/');
  }
  return value;
}

Future<void> _openStoreListingOrExplain(
  BuildContext context,
  AppStrings strings,
) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    final id = _configuredAppStoreId();
    if (id == null) {
      _showStoreFeedback(context, strings.appStoreIdNotConfigured);
      return;
    }
    final opened = await _launchFirstExternal([
      Uri.parse('itms-apps://apps.apple.com/app/id$id'),
      Uri.parse('https://apps.apple.com/app/id$id'),
    ]);
    if (!context.mounted) {
      return;
    }
    if (!opened) {
      _showStoreFeedback(context, strings.appStoreOpenFailed);
    }
    return;
  }

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    final opened = await _launchFirstExternal([
      Uri.parse('market://details?id=$_androidStorePackageName'),
      Uri.parse(
        'https://play.google.com/store/apps/details?id=$_androidStorePackageName',
      ),
    ]);
    if (!context.mounted) {
      return;
    }
    if (!opened) {
      _showStoreFeedback(context, strings.appStoreOpenFailed);
    }
    return;
  }

  _showStoreFeedback(context, strings.updateStatusUnsupported);
}

Future<void> _openStoreReviewOrExplain(
  BuildContext context,
  AppStrings strings,
) async {
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
    final id = _configuredAppStoreId();
    if (id == null) {
      _showStoreFeedback(context, strings.appStoreIdNotConfigured);
      return;
    }
    final opened = await _launchFirstExternal([
      Uri.parse('itms-apps://itunes.apple.com/app/id$id?action=write-review'),
      Uri.parse('https://apps.apple.com/app/id$id?action=write-review'),
    ]);
    if (!context.mounted) {
      return;
    }
    if (!opened) {
      _showStoreFeedback(context, strings.appStoreOpenFailed);
    }
    return;
  }

  await _openStoreListingOrExplain(context, strings);
}

String? _configuredAppStoreId() {
  final value = _appStoreId.trim();
  return value.isEmpty ? null : value;
}

Future<bool> _launchFirstExternal(List<Uri> uris) async {
  for (final uri in uris) {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    } catch (_) {
      // Try the next URL, usually a web fallback after a store scheme.
    }
  }
  return false;
}

Future<void> _openExternalLink(
  BuildContext context,
  Uri uri,
  AppStrings strings,
) async {
  final shouldOpen = await _confirmExternalLinkOpen(context, uri.toString());
  if (!shouldOpen || !context.mounted) {
    return;
  }
  final opened = await _launchFirstExternal([uri]);
  if (!context.mounted || opened) {
    return;
  }
  _showStoreFeedback(context, strings.linkOpenFailed);
}

void _showStoreFeedback(BuildContext context, String message) {
  if (!context.mounted) {
    return;
  }
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(showCloseIcon: true, content: Text(message)));
}

Future<void> _showNoteConflictResolver(
  BuildContext context,
  WidgetRef ref,
  NoteEntry localNote,
) async {
  final notes = ref.read(notesControllerProvider.notifier);
  final workspace = ref.read(syncV2WorkspaceProvider);
  if (await showSyncV2ConflictDialog(context, ref, localNote)) {
    await notes.reloadFromStorage();
    unawaited(workspace.syncNow().catchError((Object _) {}));
  }
}
