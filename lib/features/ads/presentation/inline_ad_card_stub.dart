import 'package:flutter/widgets.dart';

class HiMemoInlineAdCard extends StatelessWidget {
  const HiMemoInlineAdCard({super.key, this.maxHeight = 96});

  final double maxHeight;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
