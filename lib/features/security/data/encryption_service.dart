import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class EncryptionService {
  EncryptionService({
    AesGcm? algorithm,
    Random? random,
    Pbkdf2? kdf,
  }) : _algorithm = algorithm ?? AesGcm.with256bits(),
       _random = random ?? Random.secure(),
       _kdf =
           kdf ??
           Pbkdf2(
             macAlgorithm: Hmac.sha256(),
             iterations: 210000,
             bits: 256,
           );

  final AesGcm _algorithm;
  final Random _random;
  final Pbkdf2 _kdf;

  Future<String> encryptJson({
    required Map<String, dynamic> payload,
    required SecretKey secretKey,
  }) async {
    final encoded = utf8.encode(jsonEncode(payload));
    return encryptBytes(
      clearBytes: encoded,
      secretKey: secretKey,
      additionalData: utf8.encode('json'),
    );
  }

  Future<String> encryptBytes({
    required List<int> clearBytes,
    required SecretKey secretKey,
    List<int>? additionalData,
  }) async {
    final nonce = _randomBytes(_algorithm.nonceLength);
    final box = await _algorithm.encrypt(
      clearBytes,
      secretKey: secretKey,
      nonce: nonce,
      aad: additionalData ?? const <int>[],
    );

    return jsonEncode({
      'version': 1,
      'nonce': base64Encode(box.nonce),
      'cipherText': base64Encode(box.cipherText),
      'mac': base64Encode(box.mac.bytes),
    });
  }

  Future<Map<String, dynamic>> decryptJson({
    required String encodedPayload,
    required SecretKey secretKey,
  }) async {
    final clearBytes = await decryptBytes(
      encodedPayload: encodedPayload,
      secretKey: secretKey,
      additionalData: utf8.encode('json'),
    );
    return Map<String, dynamic>.from(
      jsonDecode(utf8.decode(clearBytes)) as Map<String, dynamic>,
    );
  }

  Future<List<int>> decryptBytes({
    required String encodedPayload,
    required SecretKey secretKey,
    List<int>? additionalData,
  }) async {
    final decoded = Map<String, dynamic>.from(
      jsonDecode(encodedPayload) as Map<String, dynamic>,
    );
    final secretBox = SecretBox(
      base64Decode(decoded['cipherText'] as String),
      nonce: base64Decode(decoded['nonce'] as String),
      mac: Mac(base64Decode(decoded['mac'] as String)),
    );
    return _algorithm.decrypt(
      secretBox,
      secretKey: secretKey,
      aad: additionalData ?? const <int>[],
    );
  }

  Future<String> deriveSecretVerifier({
    required String secret,
    required List<int> salt,
  }) async {
    final derived = await _kdf.deriveKeyFromPassword(
      password: secret,
      nonce: salt,
    );
    final bytes = await derived.extractBytes();
    return base64Encode(bytes);
  }

  List<int> generateSalt({int length = 16}) => _randomBytes(length);

  List<int> generateKeyBytes({int length = 32}) => _randomBytes(length);

  List<int> _randomBytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));
}
