import 'package:freezed_annotation/freezed_annotation.dart';

part 'vault_models.freezed.dart';
part 'vault_models.g.dart';

@freezed
abstract class VaultBucket with _$VaultBucket {
  const factory VaultBucket({
    required String id,
    required String name,
    required String description,
  }) = _VaultBucket;

  factory VaultBucket.fromJson(Map<String, dynamic> json) =>
      _$VaultBucketFromJson(json);
}

@freezed
abstract class UnlockIdentity with _$UnlockIdentity {
  const factory UnlockIdentity({
    required String id,
    required String name,
    required String tagline,
    required String lockLabel,
    required List<String> visibleVaultIds,
    required int accentHex,
    required String warning,
  }) = _UnlockIdentity;

  factory UnlockIdentity.fromJson(Map<String, dynamic> json) =>
      _$UnlockIdentityFromJson(json);
}
