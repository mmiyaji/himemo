part of 'home_page.dart';

String _profilePasswordLabel(AppStrings strings) => strings.localized(
  en: 'Password',
  ja: 'パスワード',
  zh: '密码',
  ko: '비밀번호',
  es: 'Contraseña',
  de: 'Passwort',
);

Widget _profilePasswordVisibility(
  AppStrings strings, {
  required bool visible,
  required VoidCallback onPressed,
}) => IconButton(
  tooltip: visible
      ? strings.localized(
          en: 'Hide password',
          ja: 'パスワードを隠す',
          zh: '隐藏密码',
          ko: '비밀번호 숨기기',
          es: 'Ocultar contraseña',
          de: 'Passwort ausblenden',
        )
      : strings.localized(
          en: 'Show password',
          ja: 'パスワードを表示',
          zh: '显示密码',
          ko: '비밀번호 표시',
          es: 'Mostrar contraseña',
          de: 'Passwort anzeigen',
        ),
  onPressed: onPressed,
  icon: Icon(
    visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
  ),
);

class _PrivateProfileDraft {
  const _PrivateProfileDraft({
    required this.name,
    required this.password,
    required this.usePin,
    this.recoveryPassword,
  });

  final String name;
  final String password;
  final bool usePin;
  final String? recoveryPassword;
}

String _privateProfilePasswordMinimumLengthError(AppStrings strings) {
  const minimumLength = PrivateMemoProfileStore.minimumPasswordLength;
  return strings.localized(
    en: 'Use at least $minimumLength characters.',
    ja: '$minimumLength文字以上で入力してください。',
    zh: '请至少输入 $minimumLength 个字符。',
    ko: '$minimumLength자 이상 입력하세요.',
    es: 'Usa al menos $minimumLength caracteres.',
    de: 'Verwende mindestens $minimumLength Zeichen.',
  );
}

Future<String?> _showPrivateProfilePasswordSetupDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  required String helperText,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _PrivateProfilePasswordSetupDialog(
      title: title,
      label: label,
      confirmLabel: confirmLabel,
      helperText: helperText,
    ),
  );
}

class _PrivateProfilePasswordSetupDialog extends StatefulWidget {
  const _PrivateProfilePasswordSetupDialog({
    required this.title,
    required this.label,
    required this.confirmLabel,
    required this.helperText,
  });

  final String title;
  final String label;
  final String confirmLabel;
  final String helperText;

  @override
  State<_PrivateProfilePasswordSetupDialog> createState() =>
      _PrivateProfilePasswordSetupDialogState();
}

class _PrivateProfilePasswordSetupDialogState
    extends State<_PrivateProfilePasswordSetupDialog> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.helperText,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              key: SettingsScreen.privateProfilePasswordInputKey,
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: widget.label,
                border: const OutlineInputBorder(),
                errorText: _errorText,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: SettingsScreen.privateProfileConfirmInputKey,
              controller: _confirmController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: widget.confirmLabel,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          onPressed: () {
            final password = _passwordController.text.trim();
            final confirmation = _confirmController.text.trim();
            if (password.runes.length <
                PrivateMemoProfileStore.minimumPasswordLength) {
              setState(() {
                _errorText = _privateProfilePasswordMinimumLengthError(strings);
              });
              return;
            }
            if (password != confirmation) {
              setState(() {
                _errorText = strings.keysDoNotMatch;
              });
              return;
            }
            Navigator.of(context).pop(password);
          },
          child: Text(strings.save),
        ),
      ],
    );
  }
}

class _AddPrivateProfileDialog extends StatefulWidget {
  const _AddPrivateProfileDialog({this.enrollDevicePin = false});

  final bool enrollDevicePin;

  @override
  State<_AddPrivateProfileDialog> createState() =>
      _AddPrivateProfileDialogState();
}

class _AddPrivateProfileDialogState extends State<_AddPrivateProfileDialog> {
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _recoveryController = TextEditingController();
  final _confirmRecoveryController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  late bool _usePin = widget.enrollDevicePin;
  bool _showPassword = false;

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _recoveryController.dispose();
    _confirmRecoveryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final passwordLabel = strings.text('home.profile.password.2');
    const minimum = PrivateMemoProfileStore.minimumPinLength;
    final pinLengthHelp = strings.localized(
      en: 'Use at least $minimum digits (0–9).',
      ja: '半角数字（0〜9）を$minimum桁以上入力してください。',
      zh: '请输入至少 $minimum 位半角数字（0–9）。',
      ko: '숫자(0–9)를 $minimum자리 이상 입력하세요.',
      es: 'Usa al menos $minimum dígitos (0–9).',
      de: 'Verwende mindestens $minimum Ziffern (0–9).',
    );
    return AlertDialog(
      title: Text(
        widget.enrollDevicePin
            ? strings.localized(en: 'Set device PIN', ja: 'この端末のPINを設定')
            : strings.text('home.add.private.profile'),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.enrollDevicePin)
                TextFormField(
                  key: SettingsScreen.privateProfileNameInputKey,
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: strings.text('home.profile.name'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              const SizedBox(height: 16),
              if (supportsDeviceProfilePin && !widget.enrollDevicePin)
                SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(
                      value: false,
                      label: Text(_profilePasswordLabel(strings)),
                    ),
                    ButtonSegment(value: true, label: Text(strings.pin)),
                  ],
                  selected: {_usePin},
                  onSelectionChanged: (selection) {
                    _passwordController.clear();
                    _confirmController.clear();
                    setState(() {
                      _usePin = selection.single;
                      _showPassword = false;
                    });
                  },
                ),
              const SizedBox(height: 8),
              if (_usePin) ...[
                Text(
                  strings.localized(
                    en: 'The PIN works on this device. Use the recovery password on other devices.',
                    ja: 'PINはこの端末で使えます。ほかの端末では復旧パスワードを使ってください。',
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _recoveryController,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: strings.localized(
                      en: 'Recovery password',
                      ja: '復旧パスワード',
                    ),
                  ),
                  validator: (value) {
                    final password = (value ?? '').trim();
                    if (password.runes.length <
                        PrivateMemoProfileStore.minimumPasswordLength) {
                      return _privateProfilePasswordMinimumLengthError(strings);
                    }
                    if (RegExp(r'^\d+$').hasMatch(password)) {
                      return strings.localized(
                        en: 'Use more than digits.',
                        ja: '数字以外の文字も使ってください。',
                      );
                    }
                    return null;
                  },
                ),
                if (!widget.enrollDevicePin)
                  TextFormField(
                    controller: _confirmRecoveryController,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: strings.text('home.confirm.password'),
                    ),
                    validator: (value) => value == _recoveryController.text
                        ? null
                        : strings.text('home.passwords.do.not.match'),
                  ),
                const SizedBox(height: 16),
                Text(pinLengthHelp),
                const SizedBox(height: 8),
                AppPinInput(
                  key: SettingsScreen.privateProfilePasswordInputKey,
                  controller: _passwordController,
                  variableLength: true,
                  validator: (value) =>
                      PrivateMemoProfileStore.isValidPin(value ?? '')
                      ? null
                      : pinLengthHelp,
                ),
              ] else
                TextFormField(
                  key: SettingsScreen.privateProfilePasswordInputKey,
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: passwordLabel,
                    border: const OutlineInputBorder(),
                    suffixIcon: _profilePasswordVisibility(
                      strings,
                      visible: _showPassword,
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                  validator: (value) =>
                      (value ?? '').trim().runes.length <
                          PrivateMemoProfileStore.minimumPasswordLength
                      ? _privateProfilePasswordMinimumLengthError(strings)
                      : null,
                ),
              if (_usePin)
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _passwordController,
                  builder: (context, value, _) {
                    final pin = value.text;
                    if (!PrivateMemoProfileStore.isValidPin(pin) ||
                        pin.length >= 8) {
                      return const SizedBox.shrink();
                    }
                    final theme = Theme.of(context);
                    return Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          strings.localized(
                            en: 'Low strength: A short PIN is easier to guess if someone obtains a copy of the protected profile key.',
                            ja: '強度が低いPINです。保護されたプロファイル鍵のコピーが漏れると、短いPINは推測されやすくなります。',
                            zh: '强度较低：如果受保护的配置文件密钥副本泄露，短 PIN 更容易被猜出。',
                            ko: '낮은 강도: 보호된 프로필 키의 사본이 유출되면 짧은 PIN은 추측하기 쉽습니다.',
                            es: 'Seguridad baja: un PIN corto es más fácil de adivinar si se obtiene una copia de la clave protegida del perfil.',
                            de: 'Geringe Stärke: Eine kurze PIN ist leichter zu erraten, wenn eine Kopie des geschützten Profilschlüssels in fremde Hände gerät.',
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              const SizedBox(height: 12),
              if (_usePin) ...[
                Text(strings.text('home.confirm.pin')),
                const SizedBox(height: 8),
                AppPinInput(
                  key: SettingsScreen.privateProfileConfirmInputKey,
                  controller: _confirmController,
                  label: strings.text('home.confirm.pin'),
                  variableLength: true,
                  validator: (value) => value == _passwordController.text
                      ? null
                      : strings.text('home.pin.confirmation.did.not.match'),
                ),
              ] else
                TextFormField(
                  key: SettingsScreen.privateProfileConfirmInputKey,
                  controller: _confirmController,
                  obscureText: !_showPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: strings.text('home.confirm.password'),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (value) => value == _passwordController.text
                      ? null
                      : strings.text('home.passwords.do.not.match'),
                ),
              const SizedBox(height: 12),
              Text(
                strings.localized(
                  en: 'If you forget the PIN or password, HiMemo cannot unlock or recover the private profile data. Support cannot respond to password reset, unlock, or data recovery requests.',
                  ja: 'PINやパスワードを忘れると、HiMemo ではプライベートプロファイルのロック解除やデータ復旧はできません。パスワード忘れ、ロック解除、データ復旧に関するお問い合わせにも対応できません。',
                  zh: '如果忘记 PIN 或密码，HiMemo 无法解锁或恢复私密配置文件数据。支持也无法处理密码重置、解锁或数据恢复请求。',
                  ko: 'PIN이나 비밀번호를 잊으면 HiMemo에서 개인 프로필 잠금 해제나 데이터 복구를 할 수 없습니다. 비밀번호 재설정, 잠금 해제, 데이터 복구 요청에도 대응할 수 없습니다.',
                  es: 'Si olvidas el PIN o la contraseña, HiMemo no puede desbloquear ni recuperar los datos del perfil privado. Soporte no puede responder solicitudes de restablecimiento, desbloqueo o recuperacion.',
                  de: 'Wenn du die PIN oder das Passwort vergisst, kann HiMemo die Daten des privaten Profils nicht entsperren oder wiederherstellen. Support kann keine Anfragen zum Zurucksetzen, Entsperren oder Wiederherstellen bearbeiten.',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          key: SettingsScreen.privateProfileSubmitKey,
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) {
              return;
            }
            Navigator.of(context).pop(
              _PrivateProfileDraft(
                name: _nameController.text,
                password: _passwordController.text,
                usePin: _usePin,
                recoveryPassword: _usePin ? _recoveryController.text : null,
              ),
            );
          },
          child: Text(
            widget.enrollDevicePin
                ? strings.localized(en: 'Save PIN', ja: 'PINを保存')
                : strings.text('home.add'),
          ),
        ),
      ],
    );
  }
}

class _RenamePrivateProfileDialog extends StatefulWidget {
  const _RenamePrivateProfileDialog({required this.initialName});

  final String initialName;

  @override
  State<_RenamePrivateProfileDialog> createState() =>
      _RenamePrivateProfileDialogState();
}

class _RenamePrivateProfileDialogState
    extends State<_RenamePrivateProfileDialog> {
  late final TextEditingController _nameController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.localized(en: 'Rename profile', ja: 'プロファイル名を変更')),
      content: Form(
        key: _formKey,
        child: TextFormField(
          key: SettingsScreen.privateProfileRenameInputKey,
          controller: _nameController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: strings.text('home.profile.name'),
            border: const OutlineInputBorder(),
          ),
          validator: (value) => value == null || value.trim().isEmpty
              ? strings.localized(
                  en: 'Enter a profile name.',
                  ja: 'プロファイル名を入力してください。',
                )
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(strings.cancel),
        ),
        FilledButton(
          key: SettingsScreen.privateProfileRenameSubmitKey,
          onPressed: () {
            if (!(_formKey.currentState?.validate() ?? false)) {
              return;
            }
            Navigator.of(context).pop(_nameController.text.trim());
          },
          child: Text(strings.save),
        ),
      ],
    );
  }
}

/// Dialog used after admin mode has been entered to unlock one named profile.
///
/// Keeping the profile identity in this dialog is important: admin mode can
/// expose more than one profile, and the password belongs to the selected
/// profile rather than to the admin session.
class AdminProfileUnlockDialog extends StatefulWidget {
  const AdminProfileUnlockDialog({
    super.key,
    required this.profileName,
    required this.onUnlock,
    this.createdAt,
    this.isLegacy = false,
  });

  final String profileName;
  final Future<bool> Function(String password) onUnlock;
  final DateTime? createdAt;
  final bool isLegacy;

  @override
  State<AdminProfileUnlockDialog> createState() =>
      _AdminProfileUnlockDialogState();
}

class _AdminProfileUnlockDialogState extends State<AdminProfileUnlockDialog> {
  final _passwordController = TextEditingController();
  bool _busy = false;
  bool _usePin = false;
  bool _showPassword = false;
  String? _errorText;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() {
        _errorText = context.strings.localized(
          en: 'Enter the PIN or password for ${widget.profileName}.',
          ja: '${widget.profileName} のPINまたはパスワードを入力してください。',
        );
      });
      return;
    }

    setState(() {
      _busy = true;
      _errorText = null;
    });
    bool unlocked = false;
    var failedWithException = false;
    try {
      unlocked = await widget.onUnlock(password);
    } catch (_) {
      // Authentication failures must not expose implementation details.
      unlocked = false;
      failedWithException = true;
    }
    if (!mounted) return;
    if (unlocked) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _busy = false;
      _errorText = failedWithException
          ? context.strings.localized(
              en: 'Unable to unlock. Please try again.',
              ja: '解除できませんでした。もう一度お試しください。',
            )
          : context.strings.localized(
              en: 'The password for ${widget.profileName} is incorrect.',
              ja: '${widget.profileName} のパスワードが正しくありません。',
            );
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final targetLabel = strings.localized(en: 'Target profile', ja: '対象プロファイル');
    final adminGuidance = strings.localized(
      en: 'You are already signed in to admin mode. Enter the PIN or password for “${widget.profileName}” once. In admin mode, you can use device authentication from then on.',
      ja: '管理者モードにはログイン済みです。初回のみ「${widget.profileName}」のPINまたはパスワードを入力してください。次回からは管理者モードなら端末認証で開けます。',
    );
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(strings.localized(en: 'Unlock profile', ja: 'プロファイルを解除')),
        scrollable: true,
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(targetLabel, style: Theme.of(context).textTheme.labelLarge),
              const SizedBox(height: 4),
              SelectableText(
                widget.profileName,
                key: const Key('admin-profile-unlock-target'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (widget.createdAt != null) ...[
                const SizedBox(height: 4),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: strings.localized(en: 'Created: ', ja: '作成日時：'),
                      ),
                      TextSpan(
                        text: _formatDateTime(widget.createdAt!, strings),
                      ),
                    ],
                  ),
                  key: const Key('admin-profile-unlock-created-at'),
                ),
              ],
              if (widget.isLegacy) ...[
                const SizedBox(height: 4),
                Text(
                  strings.localized(en: 'Legacy profile', ja: '旧形式のプロファイル'),
                  key: const Key('admin-profile-unlock-legacy'),
                ),
              ],
              const SizedBox(height: 12),
              Text(adminGuidance),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text(_profilePasswordLabel(strings)),
                  ),
                  ButtonSegment(value: true, label: Text(strings.pin)),
                ],
                selected: {_usePin},
                onSelectionChanged: _busy
                    ? null
                    : (selection) {
                        _passwordController.clear();
                        setState(() {
                          _usePin = selection.single;
                          _showPassword = false;
                          _errorText = null;
                        });
                      },
              ),
              const SizedBox(height: 12),
              if (_usePin) ...[
                AppPinInput(
                  controller: _passwordController,
                  variableLength: true,
                  autofocus: true,
                  enabled: !_busy,
                  onSubmit: _submit,
                ),
                if (_errorText case final error?) ...[
                  const SizedBox(height: 8),
                  Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ] else
                TextField(
                  key: const Key('admin-profile-unlock-password-input'),
                  controller: _passwordController,
                  obscureText: !_showPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  enabled: !_busy,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: strings.localized(
                      en: '\${widget.profileName} password',
                      ja: '\${widget.profileName} のパスワード',
                    ),
                    border: const OutlineInputBorder(),
                    errorText: _errorText,
                    suffixIcon: _profilePasswordVisibility(
                      strings,
                      visible: _showPassword,
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            key: const Key('admin-profile-unlock-cancel'),
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: Text(strings.cancel),
          ),
          FilledButton(
            key: const Key('admin-profile-unlock-submit'),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(strings.localized(en: 'Unlock', ja: '解除')),
          ),
        ],
      ),
    );
  }
}
