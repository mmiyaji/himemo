import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_strings.dart';
import '../domain/note_entry.dart';
import '../domain/vault_models.dart';
import 'home_providers.dart';

class WidgetQuickCaptureScreen extends ConsumerStatefulWidget {
  const WidgetQuickCaptureScreen({super.key});

  @override
  ConsumerState<WidgetQuickCaptureScreen> createState() =>
      _WidgetQuickCaptureScreenState();
}

class _WidgetQuickCaptureScreenState
    extends ConsumerState<WidgetQuickCaptureScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _saving = false;
  String? _loadedNonce;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(widgetQuickCaptureSettingsControllerProvider);
    final request = ref.watch(widgetQuickCaptureRequestControllerProvider);
    final onboardingReady =
        ref.watch(appLaunchControllerProvider) == AppLaunchSurface.ready;
    final everydayVault = ref.watch(vaultByIdProvider('everyday'));
    final colorScheme = Theme.of(context).colorScheme;
    final requestText = request?.initialText.trim() ?? '';
    final requestFiles = request?.files ?? const <QuickCaptureFile>[];
    final rejectedFiles =
        request?.rejectedFiles ?? const <QuickCaptureRejectedFile>[];

    if (_loadedNonce != request?.nonce) {
      _loadedNonce = request?.nonce;
      _controller.value = TextEditingValue(
        text: requestText,
        selection: TextSelection.collapsed(offset: requestText.length),
      );
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(context.strings.quickMemo),
        actions: [
          IconButton(
            tooltip: context.strings.close,
            onPressed: _close,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 640,
                    minHeight: (constraints.maxHeight - 40).clamp(
                      0,
                      double.infinity,
                    ),
                  ),
                  child:
                      (enabled || request?.shareId != null) && onboardingReady
                      ? _CapturePanel(
                          controller: _controller,
                          vault: everydayVault,
                          saving: _saving,
                          source: request?.source ?? QuickCaptureSource.widget,
                          files: requestFiles,
                          rejectedFiles: rejectedFiles,
                          onSubmit: _submit,
                          onCancel: _close,
                          discardUnavailable:
                              request?.shareId != null &&
                              requestText.isEmpty &&
                              requestFiles.isEmpty,
                        )
                      : Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                            borderRadius: BorderRadius.circular(12),
                            color: colorScheme.surface,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                onboardingReady
                                    ? context.strings.quickWidgetCaptureOff
                                    : context.strings.finishSetupFirst,
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                onboardingReady
                                    ? context
                                          .strings
                                          .enableQuickWidgetInSettings
                                    : context
                                          .strings
                                          .completeOnboardingBeforeWidget,
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: 20),
                              FilledButton.tonal(
                                onPressed: _close,
                                child: Text(context.strings.close),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _submit({bool discardUnavailable = false}) async {
    final text = _controller.text.trim();
    final request = ref.read(widgetQuickCaptureRequestControllerProvider);
    final files = request?.files ?? const <QuickCaptureFile>[];
    if ((text.isEmpty && files.isEmpty && !discardUnavailable) || _saving) {
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      final bridge = ref.read(widgetQuickCaptureBridgeProvider);
      final requests = ref.read(
        widgetQuickCaptureRequestControllerProvider.notifier,
      );
      final shareId = request?.shareId;
      if (text.isNotEmpty || files.isNotEmpty) {
        await ref
            .read(notesControllerProvider.notifier)
            .createSharedFileCapture(
              rawText: text,
              files: files,
              shareId: shareId,
            );
      }
      if (shareId == null) {
        await bridge.deleteImportedFiles(files);
      } else {
        await bridge.acknowledgeSharedCapture(shareId);
      }
      requests.clear();
      if (shareId != null) await bridge.openNextPending();
      if (!mounted) {
        return;
      }
      if (text.isNotEmpty || files.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            showCloseIcon: true,
            content: Text(context.strings.quickMemoSaved),
          ),
        );
      }
      if (ref.read(widgetQuickCaptureRequestControllerProvider) == null) {
        _navigateAway();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          showCloseIcon: true,
          content: Text(context.strings.sharedMemoSaveFailed),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  void _close() {
    if (_saving) return;
    final request = ref.read(widgetQuickCaptureRequestControllerProvider);
    if (request?.shareId == null) {
      unawaited(
        ref
            .read(widgetQuickCaptureBridgeProvider)
            .deleteImportedFiles(request?.files ?? const <QuickCaptureFile>[]),
      );
    }
    ref.read(widgetQuickCaptureRequestControllerProvider.notifier).clear();
    _navigateAway();
  }

  void _navigateAway() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.go('/notes');
      return;
    }
    SystemNavigator.pop();
  }
}

class _CapturePanel extends StatelessWidget {
  const _CapturePanel({
    required this.controller,
    required this.vault,
    required this.saving,
    required this.source,
    required this.files,
    required this.rejectedFiles,
    required this.onSubmit,
    required this.onCancel,
    required this.discardUnavailable,
  });

  final TextEditingController controller;
  final VaultBucket vault;
  final bool saving;
  final QuickCaptureSource source;
  final List<QuickCaptureFile> files;
  final List<QuickCaptureRejectedFile> rejectedFiles;
  final Future<void> Function({bool discardUnavailable}) onSubmit;
  final VoidCallback onCancel;
  final bool discardUnavailable;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isShare = source == QuickCaptureSource.share;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
        color: colorScheme.surface,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.strings.sendQuickMemo,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              Chip(
                label: Text(vault.name),
                avatar: const Icon(Icons.edit_note_rounded, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            context.strings.quickCaptureDescription(isShare: isShare),
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          if (files.isNotEmpty) ...[
            Text(
              context.strings.sharedFiles,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final file in files)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_iconForQuickCaptureFile(file)),
                title: Text(
                  file.name.isEmpty ? file.path.split('/').last : file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(file.mimeType),
                dense: true,
              ),
            const SizedBox(height: 8),
          ],
          if (rejectedFiles.isNotEmpty) ...[
            Text(
              context.strings.filesNotImported,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            for (final file in rejectedFiles)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.error_outline_rounded),
                title: Text(
                  file.name.isEmpty
                      ? context.strings.sharedFileFallback
                      : file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    if (file.mimeType.isNotEmpty) file.mimeType,
                    if (file.reason.isNotEmpty)
                      context.strings.sharedFileImportFailureReason(
                        file.reason,
                      ),
                  ].join(' - '),
                ),
                dense: true,
              ),
            const SizedBox(height: 8),
          ],
          TextField(
            key: const Key('widget-quick-capture-input'),
            controller: controller,
            autofocus: files.isEmpty,
            minLines: 6,
            maxLines: 12,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: context.strings.quickCaptureHint(isShare: isShare),
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          if (discardUnavailable)
            TextButton(
              onPressed: saving
                  ? null
                  : () => onSubmit(discardUnavailable: true),
              child: Text(
                context.strings.localized(
                  en: 'Discard unavailable share',
                  ja: '取り込めない共有を破棄',
                ),
              ),
            ),
          Row(
            children: [
              OutlinedButton(
                onPressed: saving ? null : onCancel,
                child: Text(context.strings.cancel),
              ),
              const Spacer(),
              FilledButton.icon(
                key: const Key('widget-quick-capture-submit'),
                onPressed: saving ? null : onSubmit,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  saving ? context.strings.sending : context.strings.sendMemo,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

IconData _iconForQuickCaptureFile(QuickCaptureFile file) {
  return switch (file.attachmentType) {
    AttachmentType.photo => Icons.photo_outlined,
    AttachmentType.video => Icons.videocam_outlined,
    AttachmentType.audio => Icons.graphic_eq_rounded,
    AttachmentType.file => Icons.insert_drive_file_outlined,
    null => Icons.insert_drive_file_outlined,
  };
}
