// Explicitly-built diagnostic tool. Not routed or imported by production.
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:himemo/features/security/data/sync_v2_web_recovery.dart';

void main() => runApp(const MaterialApp(home: V2RecoveryScreen()));

class V2RecoveryScreen extends StatefulWidget {
  const V2RecoveryScreen({super.key});
  @override
  State<V2RecoveryScreen> createState() => _V2RecoveryScreenState();
}

class _V2RecoveryScreenState extends State<V2RecoveryScreen> {
  final recovery = SyncV2WebRecovery();
  List<V2RecoveryInfo>? copies;
  bool busy = false;
  String? message;

  static const names = <V2RecoveryCopy, String>{
    V2RecoveryCopy.legacyLocal: '旧ブラウザー保存領域',
    V2RecoveryCopy.legacyIndexed: '旧IndexedDB',
    V2RecoveryCopy.wasmIndexed: '新IndexedDB',
    V2RecoveryCopy.wasmOpfs: '新ブラウザーファイル領域',
  };
  static const filenames = <V2RecoveryCopy, String>{
    V2RecoveryCopy.legacyLocal: 'himemo-v2-legacy-local.sqlite',
    V2RecoveryCopy.legacyIndexed: 'himemo-v2-legacy-indexeddb.sqlite',
    V2RecoveryCopy.wasmIndexed: 'himemo-v2-wasm-indexeddb.sqlite',
    V2RecoveryCopy.wasmOpfs: 'himemo-v2-wasm-opfs.sqlite',
  };

  @override
  void initState() {
    super.initState();
    Future.microtask(_inspect);
  }

  String errorText(Object error) {
    if (error.toString().contains('another tab')) {
      return 'V2を開いている他のタブを閉じ、この画面で再確認してください。';
    }
    return '確認できませんでした。このブラウザーでは安全に読み出せない可能性があります。';
  }

  Future<void> _inspect() async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final found = await recovery.inspect();
      if (mounted) setState(() => copies = found);
    } catch (error) {
      if (mounted) {
        setState(() {
          copies = null;
          message = errorText(error);
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _export(V2RecoveryCopy copy) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    Uint8List? bytes;
    try {
      bytes = await recovery.export(copy);
      await FilePicker.saveFile(fileName: filenames[copy]!, bytes: bytes);
      if (mounted) setState(() => message = '選んだコピーのダウンロードを開始しました。');
    } catch (error) {
      if (mounted) setState(() => message = errorText(error));
    } finally {
      if (bytes != null) bytes.fillRange(0, bytes.length, 0);
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('V2 データの確認と書き出し')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'この画面は、このブラウザーに残るV2データの控えを確認します。元のデータは変更しません。復旧コードやパスワードの入力は不要です。',
            ),
            const SizedBox(height: 12),
            if (message != null)
              Text(message!, key: const ValueKey('recovery-message')),
            if (busy) const LinearProgressIndicator(),
            for (final info in copies ?? <V2RecoveryInfo>[])
              ListTile(
                key: ValueKey('recovery-${info.copy.name}'),
                title: Text(names[info.copy]!),
                subtitle: Text(
                  info.unavailable
                      ? '確認できません'
                      : info.size == null
                      ? '見つかりません'
                      : '${info.size} バイト',
                ),
                trailing: info.size == null || info.unavailable
                    ? null
                    : TextButton(
                        key: ValueKey('export-${info.copy.name}'),
                        onPressed: busy ? null : () => _export(info.copy),
                        child: const Text('書き出す'),
                      ),
              ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: busy ? null : _inspect,
              child: const Text('再確認'),
            ),
          ],
        ),
      ),
    ),
  );
}
