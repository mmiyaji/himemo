// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'vault_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$VaultBucket {

 String get id; String get name; String get description;
/// Create a copy of VaultBucket
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VaultBucketCopyWith<VaultBucket> get copyWith => _$VaultBucketCopyWithImpl<VaultBucket>(this as VaultBucket, _$identity);

  /// Serializes this VaultBucket to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is VaultBucket&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,description);

@override
String toString() {
  return 'VaultBucket(id: $id, name: $name, description: $description)';
}


}

/// @nodoc
abstract mixin class $VaultBucketCopyWith<$Res>  {
  factory $VaultBucketCopyWith(VaultBucket value, $Res Function(VaultBucket) _then) = _$VaultBucketCopyWithImpl;
@useResult
$Res call({
 String id, String name, String description
});




}
/// @nodoc
class _$VaultBucketCopyWithImpl<$Res>
    implements $VaultBucketCopyWith<$Res> {
  _$VaultBucketCopyWithImpl(this._self, this._then);

  final VaultBucket _self;
  final $Res Function(VaultBucket) _then;

/// Create a copy of VaultBucket
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? description = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [VaultBucket].
extension VaultBucketPatterns on VaultBucket {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _VaultBucket value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _VaultBucket() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _VaultBucket value)  $default,){
final _that = this;
switch (_that) {
case _VaultBucket():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _VaultBucket value)?  $default,){
final _that = this;
switch (_that) {
case _VaultBucket() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String description)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _VaultBucket() when $default != null:
return $default(_that.id,_that.name,_that.description);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String description)  $default,) {final _that = this;
switch (_that) {
case _VaultBucket():
return $default(_that.id,_that.name,_that.description);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String description)?  $default,) {final _that = this;
switch (_that) {
case _VaultBucket() when $default != null:
return $default(_that.id,_that.name,_that.description);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _VaultBucket implements VaultBucket {
  const _VaultBucket({required this.id, required this.name, required this.description});
  factory _VaultBucket.fromJson(Map<String, dynamic> json) => _$VaultBucketFromJson(json);

@override final  String id;
@override final  String name;
@override final  String description;

/// Create a copy of VaultBucket
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$VaultBucketCopyWith<_VaultBucket> get copyWith => __$VaultBucketCopyWithImpl<_VaultBucket>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$VaultBucketToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _VaultBucket&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,description);

@override
String toString() {
  return 'VaultBucket(id: $id, name: $name, description: $description)';
}


}

/// @nodoc
abstract mixin class _$VaultBucketCopyWith<$Res> implements $VaultBucketCopyWith<$Res> {
  factory _$VaultBucketCopyWith(_VaultBucket value, $Res Function(_VaultBucket) _then) = __$VaultBucketCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String description
});




}
/// @nodoc
class __$VaultBucketCopyWithImpl<$Res>
    implements _$VaultBucketCopyWith<$Res> {
  __$VaultBucketCopyWithImpl(this._self, this._then);

  final _VaultBucket _self;
  final $Res Function(_VaultBucket) _then;

/// Create a copy of VaultBucket
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? description = null,}) {
  return _then(_VaultBucket(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}


/// @nodoc
mixin _$UnlockIdentity {

 String get id; String get name; String get tagline; String get lockLabel; List<String> get visibleVaultIds; int get accentHex; String get warning;
/// Create a copy of UnlockIdentity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnlockIdentityCopyWith<UnlockIdentity> get copyWith => _$UnlockIdentityCopyWithImpl<UnlockIdentity>(this as UnlockIdentity, _$identity);

  /// Serializes this UnlockIdentity to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UnlockIdentity&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.tagline, tagline) || other.tagline == tagline)&&(identical(other.lockLabel, lockLabel) || other.lockLabel == lockLabel)&&const DeepCollectionEquality().equals(other.visibleVaultIds, visibleVaultIds)&&(identical(other.accentHex, accentHex) || other.accentHex == accentHex)&&(identical(other.warning, warning) || other.warning == warning));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,tagline,lockLabel,const DeepCollectionEquality().hash(visibleVaultIds),accentHex,warning);

@override
String toString() {
  return 'UnlockIdentity(id: $id, name: $name, tagline: $tagline, lockLabel: $lockLabel, visibleVaultIds: $visibleVaultIds, accentHex: $accentHex, warning: $warning)';
}


}

/// @nodoc
abstract mixin class $UnlockIdentityCopyWith<$Res>  {
  factory $UnlockIdentityCopyWith(UnlockIdentity value, $Res Function(UnlockIdentity) _then) = _$UnlockIdentityCopyWithImpl;
@useResult
$Res call({
 String id, String name, String tagline, String lockLabel, List<String> visibleVaultIds, int accentHex, String warning
});




}
/// @nodoc
class _$UnlockIdentityCopyWithImpl<$Res>
    implements $UnlockIdentityCopyWith<$Res> {
  _$UnlockIdentityCopyWithImpl(this._self, this._then);

  final UnlockIdentity _self;
  final $Res Function(UnlockIdentity) _then;

/// Create a copy of UnlockIdentity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? tagline = null,Object? lockLabel = null,Object? visibleVaultIds = null,Object? accentHex = null,Object? warning = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,tagline: null == tagline ? _self.tagline : tagline // ignore: cast_nullable_to_non_nullable
as String,lockLabel: null == lockLabel ? _self.lockLabel : lockLabel // ignore: cast_nullable_to_non_nullable
as String,visibleVaultIds: null == visibleVaultIds ? _self.visibleVaultIds : visibleVaultIds // ignore: cast_nullable_to_non_nullable
as List<String>,accentHex: null == accentHex ? _self.accentHex : accentHex // ignore: cast_nullable_to_non_nullable
as int,warning: null == warning ? _self.warning : warning // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [UnlockIdentity].
extension UnlockIdentityPatterns on UnlockIdentity {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UnlockIdentity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UnlockIdentity() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UnlockIdentity value)  $default,){
final _that = this;
switch (_that) {
case _UnlockIdentity():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UnlockIdentity value)?  $default,){
final _that = this;
switch (_that) {
case _UnlockIdentity() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String tagline,  String lockLabel,  List<String> visibleVaultIds,  int accentHex,  String warning)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UnlockIdentity() when $default != null:
return $default(_that.id,_that.name,_that.tagline,_that.lockLabel,_that.visibleVaultIds,_that.accentHex,_that.warning);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String tagline,  String lockLabel,  List<String> visibleVaultIds,  int accentHex,  String warning)  $default,) {final _that = this;
switch (_that) {
case _UnlockIdentity():
return $default(_that.id,_that.name,_that.tagline,_that.lockLabel,_that.visibleVaultIds,_that.accentHex,_that.warning);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String tagline,  String lockLabel,  List<String> visibleVaultIds,  int accentHex,  String warning)?  $default,) {final _that = this;
switch (_that) {
case _UnlockIdentity() when $default != null:
return $default(_that.id,_that.name,_that.tagline,_that.lockLabel,_that.visibleVaultIds,_that.accentHex,_that.warning);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _UnlockIdentity implements UnlockIdentity {
  const _UnlockIdentity({required this.id, required this.name, required this.tagline, required this.lockLabel, required final  List<String> visibleVaultIds, required this.accentHex, required this.warning}): _visibleVaultIds = visibleVaultIds;
  factory _UnlockIdentity.fromJson(Map<String, dynamic> json) => _$UnlockIdentityFromJson(json);

@override final  String id;
@override final  String name;
@override final  String tagline;
@override final  String lockLabel;
 final  List<String> _visibleVaultIds;
@override List<String> get visibleVaultIds {
  if (_visibleVaultIds is EqualUnmodifiableListView) return _visibleVaultIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_visibleVaultIds);
}

@override final  int accentHex;
@override final  String warning;

/// Create a copy of UnlockIdentity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UnlockIdentityCopyWith<_UnlockIdentity> get copyWith => __$UnlockIdentityCopyWithImpl<_UnlockIdentity>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$UnlockIdentityToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _UnlockIdentity&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.tagline, tagline) || other.tagline == tagline)&&(identical(other.lockLabel, lockLabel) || other.lockLabel == lockLabel)&&const DeepCollectionEquality().equals(other._visibleVaultIds, _visibleVaultIds)&&(identical(other.accentHex, accentHex) || other.accentHex == accentHex)&&(identical(other.warning, warning) || other.warning == warning));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,name,tagline,lockLabel,const DeepCollectionEquality().hash(_visibleVaultIds),accentHex,warning);

@override
String toString() {
  return 'UnlockIdentity(id: $id, name: $name, tagline: $tagline, lockLabel: $lockLabel, visibleVaultIds: $visibleVaultIds, accentHex: $accentHex, warning: $warning)';
}


}

/// @nodoc
abstract mixin class _$UnlockIdentityCopyWith<$Res> implements $UnlockIdentityCopyWith<$Res> {
  factory _$UnlockIdentityCopyWith(_UnlockIdentity value, $Res Function(_UnlockIdentity) _then) = __$UnlockIdentityCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String tagline, String lockLabel, List<String> visibleVaultIds, int accentHex, String warning
});




}
/// @nodoc
class __$UnlockIdentityCopyWithImpl<$Res>
    implements _$UnlockIdentityCopyWith<$Res> {
  __$UnlockIdentityCopyWithImpl(this._self, this._then);

  final _UnlockIdentity _self;
  final $Res Function(_UnlockIdentity) _then;

/// Create a copy of UnlockIdentity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? tagline = null,Object? lockLabel = null,Object? visibleVaultIds = null,Object? accentHex = null,Object? warning = null,}) {
  return _then(_UnlockIdentity(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,tagline: null == tagline ? _self.tagline : tagline // ignore: cast_nullable_to_non_nullable
as String,lockLabel: null == lockLabel ? _self.lockLabel : lockLabel // ignore: cast_nullable_to_non_nullable
as String,visibleVaultIds: null == visibleVaultIds ? _self._visibleVaultIds : visibleVaultIds // ignore: cast_nullable_to_non_nullable
as List<String>,accentHex: null == accentHex ? _self.accentHex : accentHex // ignore: cast_nullable_to_non_nullable
as int,warning: null == warning ? _self.warning : warning // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
