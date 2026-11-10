import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/presentation/app_pin_input.dart';

void main() {
  testWidgets('profile PIN preserves longer codes and submits explicitly', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final submissions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppPinInput(
            controller: controller,
            variableLength: true,
            onSubmit: () => submissions.add(controller.text),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(EditableText), '0123x456789');
    await tester.pump();
    expect(controller.text, '0123456789');
    expect(submissions, isEmpty);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    expect(submissions, ['0123456789']);
  });

  testWidgets('app PIN filters mixed input before enforcing four digits', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final submissions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppPinInput(
            controller: controller,
            onSubmit: () => submissions.add(controller.text),
          ),
        ),
      ),
    );
    final field = find.byType(EditableText);
    await tester.enterText(field, 'a1-２2');
    expect(controller.text, '12');
    expect(submissions, isEmpty);

    await tester.enterText(field, 'a1-２2b345');
    expect(controller.text, '1234');
    expect(submissions, ['1234']);
  });
}
