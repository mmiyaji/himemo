import 'package:flutter/material.dart';

class SyncV2CloudKitReadOnlyScreen extends StatelessWidget {
  const SyncV2CloudKitReadOnlyScreen({super.key, this.onExit});
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('この画面はWeb版でのみ利用できます。')));
}
