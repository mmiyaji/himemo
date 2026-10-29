import 'secret_verifier_store.dart';
import 'secure_key_value_store.dart';

class AppPinLockStore extends SecretVerifierStore {
  AppPinLockStore({required super.encryptionService, super.attemptStore})
    : super(
        secureStore: PreferencesKeyValueStore(),
        storageKey: 'settings.web_app_pin.v1',
      );

  Future<bool> hasPin() => hasSecret();
}
