import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';

void main() {
  group('notes list preferences', () {
    test('user changes made while restoring are persisted and kept', () async {
      SharedPreferences.setMockInitialValues({
        'notes.list_density': NotesListDensity.compact.name,
        'notes.list_sort_field': NotesListSortField.updatedAt.name,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Reading starts each provider's async restore from the V1 preference
      // keys. The explicit V2 selection must win even if it matches the
      // provider's initial default value.
      expect(
        container.read(notesListDensityControllerProvider),
        NotesListDensity.standard,
      );
      expect(
        container.read(notesListSortControllerProvider),
        NotesListSortField.createdAt,
      );

      final densitySave = container
          .read(notesListDensityControllerProvider.notifier)
          .setDensity(NotesListDensity.standard);
      final sortSave = container
          .read(notesListSortControllerProvider.notifier)
          .setSortField(NotesListSortField.createdAt);
      await Future.wait([densitySave, sortSave]);
      await pumpEventQueue();

      expect(
        container.read(notesListDensityControllerProvider),
        NotesListDensity.standard,
      );
      expect(
        container.read(notesListSortControllerProvider),
        NotesListSortField.createdAt,
      );
      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString('notes.list_density'),
        NotesListDensity.standard.name,
      );
      expect(
        preferences.getString('notes.list_sort_field'),
        NotesListSortField.createdAt.name,
      );
    });
  });
}
