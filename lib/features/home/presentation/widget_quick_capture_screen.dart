import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
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

    if (requestText.isNotEmpty && _controller.text != requestText) {
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
                    minHeight: (constraints.maxHeight - 40).clamp(0, double.infinity),
                  ),
                  child: enabled && onboardingReady
                      ? _CapturePanel(
                          controller: _controller,
                          vault: everydayVault,
                          saving: _saving,
                          source: request?.source ?? QuickCaptureSource.widget,
                          onSubmit: _submit,
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
                                style: Theme.of(context).textTheme.headlineSmall,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                onboardingReady
                                    ? context.strings.enableQuickWidgetInSettings
                                    : context.strings.completeOnboardingBeforeWidget,
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(color: colorScheme.onSurfaceVariant),
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

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _saving) {
      return;
    }
    setState(() {
      _saving = true;
    });
    await ref
        .read(notesControllerProvider.notifier)
        .createWidgetQuickCapture(text);
    ref.read(widgetQuickCaptureRequestControllerProvider.notifier).clear();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.strings.quickMemoSaved)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 250));
    _close();
  }

  void _close() {
    ref.read(widgetQuickCaptureRequestControllerProvider.notifier).clear();
    SystemNavigator.pop();
  }
}

class _CapturePanel extends StatelessWidget {
  const _CapturePanel({
    required this.controller,
    required this.vault,
    required this.saving,
    required this.source,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final VaultBucket vault;
  final bool saving;
  final QuickCaptureSource source;
  final Future<void> Function() onSubmit;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
            context.strings.isJapanese
                ? source == QuickCaptureSource.share
                      ? '共有メニューから受け取ったテキストを、そのまま Daily Notes に送れます。既存ノートや private vault の内容は開きません。'
                      : 'テキストだけをすばやく記録します。この画面では既存ノートや private vault の内容は表示しません。'
                : source == QuickCaptureSource.share
                ? 'Shared text can be sent straight to Daily Notes. This route never reveals existing notes or private vault content.'
                : 'Text only. This route never reveals existing notes or private vault content.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('widget-quick-capture-input'),
            controller: controller,
            autofocus: true,
            minLines: 6,
            maxLines: 12,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: context.strings.isJapanese
                  ? source == QuickCaptureSource.share
                        ? '共有されたテキストを整えて、そのまま Daily Notes に保存できます。'
                        : 'メモを書いて、そのまま Daily Notes に送ります。'
                  : source == QuickCaptureSource.share
                  ? 'Tidy the shared text and save it to Daily Notes.'
                  : 'Write a memo and send it to Daily Notes.',
              border: const OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              OutlinedButton(
                onPressed: saving ? null : SystemNavigator.pop,
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
