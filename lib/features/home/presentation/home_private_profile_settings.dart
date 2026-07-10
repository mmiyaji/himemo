part of 'home_page.dart';

class _PrivateProfileDraft {
  const _PrivateProfileDraft({required this.name, required this.password});

  final String name;
  final String password;
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
  const _AddPrivateProfileDialog();

  @override
  State<_AddPrivateProfileDialog> createState() =>
      _AddPrivateProfileDialogState();
}

class _AddPrivateProfileDialogState extends State<_AddPrivateProfileDialog> {
  final _nameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return AlertDialog(
      title: Text(strings.text('home.add.private.profile')),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                key: SettingsScreen.privateProfileNameInputKey,
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: strings.text('home.profile.name'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                strings.localized(
                  en: 'If you forget this password, HiMemo cannot unlock or recover the private profile data. Support cannot respond to password reset, unlock, or data recovery requests.',
                  ja: 'このパスワードを忘れると、HiMemo ではプライベートプロファイルのロック解除やデータ復旧はできません。パスワード忘れ、ロック解除、データ復旧に関するお問い合わせにも対応できません。',
                  zh: '如果忘记此密码，HiMemo 无法解锁或恢复私密配置文件数据。支持也无法处理密码重置、解锁或数据恢复请求。',
                  ko: '이 비밀번호를 잊으면 HiMemo에서 개인 프로필 잠금 해제나 데이터 복구를 할 수 없습니다. 비밀번호 재설정, 잠금 해제, 데이터 복구 요청에도 대응할 수 없습니다.',
                  es: 'Si olvidas esta contrasena, HiMemo no puede desbloquear ni recuperar los datos del perfil privado. Soporte no puede responder solicitudes de restablecimiento, desbloqueo o recuperacion.',
                  de: 'Wenn du dieses Passwort vergisst, kann HiMemo die Daten des privaten Profils nicht entsperren oder wiederherstellen. Support kann keine Anfragen zum Zurucksetzen, Entsperren oder Wiederherstellen bearbeiten.',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: SettingsScreen.privateProfilePasswordInputKey,
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: strings.text('home.profile.password.2'),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return strings.text('home.enter.a.password.2');
                  }
                  if (value.trim().runes.length <
                      PrivateMemoProfileStore.minimumPasswordLength) {
                    return _privateProfilePasswordMinimumLengthError(strings);
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: SettingsScreen.privateProfileConfirmInputKey,
                controller: _confirmController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: strings.text('home.confirm.password'),
                  border: const OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value != _passwordController.text) {
                    return strings.text('home.passwords.do.not.match');
                  }
                  return null;
                },
              ),
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
              ),
            );
          },
          child: Text(strings.text('home.add')),
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
