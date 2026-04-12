// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'note_entry.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;

/// @nodoc
mixin _$NoteAttachment {

 AttachmentType get type; String get label; String? get filePath; String? get previewBytesBase64;
/// Create a copy of NoteAttachment
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NoteAttachmentCopyWith<NoteAttachment> get copyWith => _$NoteAttachmentCopyWithImpl<NoteAttachment>(this as NoteAttachment, _$identity);

  /// Serializes this NoteAttachment to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NoteAttachment&&(identical(other.type, type) || other.type == type)&&(identical(other.label, label) || other.label == label)&&(identical(other.filePath, filePath) || other.filePath == filePath)&&(identical(other.previewBytesBase64, previewBytesBase64) || other.previewBytesBase64 == previewBytesBase64));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,label,filePath,previewBytesBase64);

@override
String toString() {
  return 'NoteAttachment(type: $type, label: $label, filePath: $filePath, previewBytesBase64: $previewBytesBase64)';
}


}

/// @nodoc
abstract mixin class $NoteAttachmentCopyWith<$Res>  {
  factory $NoteAttachmentCopyWith(NoteAttachment value, $Res Function(NoteAttachment) _then) = _$NoteAttachmentCopyWithImpl;
@useResult
$Res call({
 AttachmentType type, String label, String? filePath, String? previewBytesBase64
});




}
/// @nodoc
class _$NoteAttachmentCopyWithImpl<$Res>
    implements $NoteAttachmentCopyWith<$Res> {
  _$NoteAttachmentCopyWithImpl(this._self, this._then);

  final NoteAttachment _self;
  final $Res Function(NoteAttachment) _then;

/// Create a copy of NoteAttachment
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? label = null,Object? filePath = freezed,Object? previewBytesBase64 = freezed,}) {
  return _then(_self.copyWith(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as AttachmentType,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,filePath: freezed == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String?,previewBytesBase64: freezed == previewBytesBase64 ? _self.previewBytesBase64 : previewBytesBase64 // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [NoteAttachment].
extension NoteAttachmentPatterns on NoteAttachment {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _NoteAttachment value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _NoteAttachment() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _NoteAttachment value)  $default,){
final _that = this;
switch (_that) {
case _NoteAttachment():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _NoteAttachment value)?  $default,){
final _that = this;
switch (_that) {
case _NoteAttachment() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AttachmentType type,  String label,  String? filePath,  String? previewBytesBase64)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NoteAttachment() when $default != null:
return $default(_that.type,_that.label,_that.filePath,_that.previewBytesBase64);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AttachmentType type,  String label,  String? filePath,  String? previewBytesBase64)  $default,) {final _that = this;
switch (_that) {
case _NoteAttachment():
return $default(_that.type,_that.label,_that.filePath,_that.previewBytesBase64);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AttachmentType type,  String label,  String? filePath,  String? previewBytesBase64)?  $default,) {final _that = this;
switch (_that) {
case _NoteAttachment() when $default != null:
return $default(_that.type,_that.label,_that.filePath,_that.previewBytesBase64);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _NoteAttachment implements NoteAttachment {
  const _NoteAttachment({required this.type, required this.label, this.filePath, this.previewBytesBase64});
  factory _NoteAttachment.fromJson(Map<String, dynamic> json) => _$NoteAttachmentFromJson(json);

@override final  AttachmentType type;
@override final  String label;
@override final  String? filePath;
@override final  String? previewBytesBase64;

/// Create a copy of NoteAttachment
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NoteAttachmentCopyWith<_NoteAttachment> get copyWith => __$NoteAttachmentCopyWithImpl<_NoteAttachment>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$NoteAttachmentToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _NoteAttachment&&(identical(other.type, type) || other.type == type)&&(identical(other.label, label) || other.label == label)&&(identical(other.filePath, filePath) || other.filePath == filePath)&&(identical(other.previewBytesBase64, previewBytesBase64) || other.previewBytesBase64 == previewBytesBase64));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,label,filePath,previewBytesBase64);

@override
String toString() {
  return 'NoteAttachment(type: $type, label: $label, filePath: $filePath, previewBytesBase64: $previewBytesBase64)';
}


}

/// @nodoc
abstract mixin class _$NoteAttachmentCopyWith<$Res> implements $NoteAttachmentCopyWith<$Res> {
  factory _$NoteAttachmentCopyWith(_NoteAttachment value, $Res Function(_NoteAttachment) _then) = __$NoteAttachmentCopyWithImpl;
@override @useResult
$Res call({
 AttachmentType type, String label, String? filePath, String? previewBytesBase64
});




}
/// @nodoc
class __$NoteAttachmentCopyWithImpl<$Res>
    implements _$NoteAttachmentCopyWith<$Res> {
  __$NoteAttachmentCopyWithImpl(this._self, this._then);

  final _NoteAttachment _self;
  final $Res Function(_NoteAttachment) _then;

/// Create a copy of NoteAttachment
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? label = null,Object? filePath = freezed,Object? previewBytesBase64 = freezed,}) {
  return _then(_NoteAttachment(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as AttachmentType,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,filePath: freezed == filePath ? _self.filePath : filePath // ignore: cast_nullable_to_non_nullable
as String?,previewBytesBase64: freezed == previewBytesBase64 ? _self.previewBytesBase64 : previewBytesBase64 // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}


/// @nodoc
mixin _$NoteEntry {

 String get id; String get vaultId; String get title; String get body; DateTime get createdAt; List<NoteAttachment> get attachments; bool get isPinned;
/// Create a copy of NoteEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NoteEntryCopyWith<NoteEntry> get copyWith => _$NoteEntryCopyWithImpl<NoteEntry>(this as NoteEntry, _$identity);

  /// Serializes this NoteEntry to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NoteEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.vaultId, vaultId) || other.vaultId == vaultId)&&(identical(other.title, title) || other.title == title)&&(identical(other.body, body) || other.body == body)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&const DeepCollectionEquality().equals(other.attachments, attachments)&&(identical(other.isPinned, isPinned) || other.isPinned == isPinned));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,vaultId,title,body,createdAt,const DeepCollectionEquality().hash(attachments),isPinned);

@override
String toString() {
  return 'NoteEntry(id: $id, vaultId: $vaultId, title: $title, body: $body, createdAt: $createdAt, attachments: $attachments, isPinned: $isPinned)';
}


}

/// @nodoc
abstract mixin class $NoteEntryCopyWith<$Res>  {
  factory $NoteEntryCopyWith(NoteEntry value, $Res Function(NoteEntry) _then) = _$NoteEntryCopyWithImpl;
@useResult
$Res call({
 String id, String vaultId, String title, String body, DateTime createdAt, List<NoteAttachment> attachments, bool isPinned
});




}
/// @nodoc
class _$NoteEntryCopyWithImpl<$Res>
    implements $NoteEntryCopyWith<$Res> {
  _$NoteEntryCopyWithImpl(this._self, this._then);

  final NoteEntry _self;
  final $Res Function(NoteEntry) _then;

/// Create a copy of NoteEntry
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? vaultId = null,Object? title = null,Object? body = null,Object? createdAt = null,Object? attachments = null,Object? isPinned = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,vaultId: null == vaultId ? _self.vaultId : vaultId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,attachments: null == attachments ? _self.attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<NoteAttachment>,isPinned: null == isPinned ? _self.isPinned : isPinned // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [NoteEntry].
extension NoteEntryPatterns on NoteEntry {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _NoteEntry value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _NoteEntry() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _NoteEntry value)  $default,){
final _that = this;
switch (_that) {
case _NoteEntry():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _NoteEntry value)?  $default,){
final _that = this;
switch (_that) {
case _NoteEntry() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String vaultId,  String title,  String body,  DateTime createdAt,  List<NoteAttachment> attachments,  bool isPinned)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NoteEntry() when $default != null:
return $default(_that.id,_that.vaultId,_that.title,_that.body,_that.createdAt,_that.attachments,_that.isPinned);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String vaultId,  String title,  String body,  DateTime createdAt,  List<NoteAttachment> attachments,  bool isPinned)  $default,) {final _that = this;
switch (_that) {
case _NoteEntry():
return $default(_that.id,_that.vaultId,_that.title,_that.body,_that.createdAt,_that.attachments,_that.isPinned);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String vaultId,  String title,  String body,  DateTime createdAt,  List<NoteAttachment> attachments,  bool isPinned)?  $default,) {final _that = this;
switch (_that) {
case _NoteEntry() when $default != null:
return $default(_that.id,_that.vaultId,_that.title,_that.body,_that.createdAt,_that.attachments,_that.isPinned);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _NoteEntry implements NoteEntry {
  const _NoteEntry({required this.id, required this.vaultId, required this.title, required this.body, required this.createdAt, final  List<NoteAttachment> attachments = const <NoteAttachment>[], this.isPinned = false}): _attachments = attachments;
  factory _NoteEntry.fromJson(Map<String, dynamic> json) => _$NoteEntryFromJson(json);

@override final  String id;
@override final  String vaultId;
@override final  String title;
@override final  String body;
@override final  DateTime createdAt;
 final  List<NoteAttachment> _attachments;
@override@JsonKey() List<NoteAttachment> get attachments {
  if (_attachments is EqualUnmodifiableListView) return _attachments;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_attachments);
}

@override@JsonKey() final  bool isPinned;

/// Create a copy of NoteEntry
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NoteEntryCopyWith<_NoteEntry> get copyWith => __$NoteEntryCopyWithImpl<_NoteEntry>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$NoteEntryToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _NoteEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.vaultId, vaultId) || other.vaultId == vaultId)&&(identical(other.title, title) || other.title == title)&&(identical(other.body, body) || other.body == body)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&const DeepCollectionEquality().equals(other._attachments, _attachments)&&(identical(other.isPinned, isPinned) || other.isPinned == isPinned));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,vaultId,title,body,createdAt,const DeepCollectionEquality().hash(_attachments),isPinned);

@override
String toString() {
  return 'NoteEntry(id: $id, vaultId: $vaultId, title: $title, body: $body, createdAt: $createdAt, attachments: $attachments, isPinned: $isPinned)';
}


}

/// @nodoc
abstract mixin class _$NoteEntryCopyWith<$Res> implements $NoteEntryCopyWith<$Res> {
  factory _$NoteEntryCopyWith(_NoteEntry value, $Res Function(_NoteEntry) _then) = __$NoteEntryCopyWithImpl;
@override @useResult
$Res call({
 String id, String vaultId, String title, String body, DateTime createdAt, List<NoteAttachment> attachments, bool isPinned
});




}
/// @nodoc
class __$NoteEntryCopyWithImpl<$Res>
    implements _$NoteEntryCopyWith<$Res> {
  __$NoteEntryCopyWithImpl(this._self, this._then);

  final _NoteEntry _self;
  final $Res Function(_NoteEntry) _then;

/// Create a copy of NoteEntry
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? vaultId = null,Object? title = null,Object? body = null,Object? createdAt = null,Object? attachments = null,Object? isPinned = null,}) {
  return _then(_NoteEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,vaultId: null == vaultId ? _self.vaultId : vaultId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,attachments: null == attachments ? _self._attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<NoteAttachment>,isPinned: null == isPinned ? _self.isPinned : isPinned // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
