// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'vault_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_VaultBucket _$VaultBucketFromJson(Map<String, dynamic> json) => _VaultBucket(
  id: json['id'] as String,
  name: json['name'] as String,
  description: json['description'] as String,
);

Map<String, dynamic> _$VaultBucketToJson(_VaultBucket instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
    };

_UnlockIdentity _$UnlockIdentityFromJson(Map<String, dynamic> json) =>
    _UnlockIdentity(
      id: json['id'] as String,
      name: json['name'] as String,
      tagline: json['tagline'] as String,
      lockLabel: json['lockLabel'] as String,
      visibleVaultIds: (json['visibleVaultIds'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      accentHex: (json['accentHex'] as num).toInt(),
      warning: json['warning'] as String,
    );

Map<String, dynamic> _$UnlockIdentityToJson(_UnlockIdentity instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'tagline': instance.tagline,
      'lockLabel': instance.lockLabel,
      'visibleVaultIds': instance.visibleVaultIds,
      'accentHex': instance.accentHex,
      'warning': instance.warning,
    };
