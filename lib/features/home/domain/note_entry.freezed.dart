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
mixin _$NoteBlock {

 NoteBlockType get type; String? get text; NoteAttachment? get attachment;
/// Create a copy of NoteBlock
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NoteBlockCopyWith<NoteBlock> get copyWith => _$NoteBlockCopyWithImpl<NoteBlock>(this as NoteBlock, _$identity);

  /// Serializes this NoteBlock to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NoteBlock&&(identical(other.type, type) || other.type == type)&&(identical(other.text, text) || other.text == text)&&(identical(other.attachment, attachment) || other.attachment == attachment));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,text,attachment);

@override
String toString() {
  return 'NoteBlock(type: $type, text: $text, attachment: $attachment)';
}


}

/// @nodoc
abstract mixin class $NoteBlockCopyWith<$Res>  {
  factory $NoteBlockCopyWith(NoteBlock value, $Res Function(NoteBlock) _then) = _$NoteBlockCopyWithImpl;
@useResult
$Res call({
 NoteBlockType type, String? text, NoteAttachment? attachment
});


$NoteAttachmentCopyWith<$Res>? get attachment;

}
/// @nodoc
class _$NoteBlockCopyWithImpl<$Res>
    implements $NoteBlockCopyWith<$Res> {
  _$NoteBlockCopyWithImpl(this._self, this._then);

  final NoteBlock _self;
  final $Res Function(NoteBlock) _then;

/// Create a copy of NoteBlock
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? type = null,Object? text = freezed,Object? attachment = freezed,}) {
  return _then(_self.copyWith(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as NoteBlockType,text: freezed == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String?,attachment: freezed == attachment ? _self.attachment : attachment // ignore: cast_nullable_to_non_nullable
as NoteAttachment?,
  ));
}
/// Create a copy of NoteBlock
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$NoteAttachmentCopyWith<$Res>? get attachment {
    if (_self.attachment == null) {
    return null;
  }

  return $NoteAttachmentCopyWith<$Res>(_self.attachment!, (value) {
    return _then(_self.copyWith(attachment: value));
  });
}
}


/// Adds pattern-matching-related methods to [NoteBlock].
extension NoteBlockPatterns on NoteBlock {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _NoteBlock value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _NoteBlock() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _NoteBlock value)  $default,){
final _that = this;
switch (_that) {
case _NoteBlock():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _NoteBlock value)?  $default,){
final _that = this;
switch (_that) {
case _NoteBlock() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( NoteBlockType type,  String? text,  NoteAttachment? attachment)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NoteBlock() when $default != null:
return $default(_that.type,_that.text,_that.attachment);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( NoteBlockType type,  String? text,  NoteAttachment? attachment)  $default,) {final _that = this;
switch (_that) {
case _NoteBlock():
return $default(_that.type,_that.text,_that.attachment);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( NoteBlockType type,  String? text,  NoteAttachment? attachment)?  $default,) {final _that = this;
switch (_that) {
case _NoteBlock() when $default != null:
return $default(_that.type,_that.text,_that.attachment);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _NoteBlock implements NoteBlock {
  const _NoteBlock({required this.type, this.text, this.attachment});
  factory _NoteBlock.fromJson(Map<String, dynamic> json) => _$NoteBlockFromJson(json);

@override final  NoteBlockType type;
@override final  String? text;
@override final  NoteAttachment? attachment;

/// Create a copy of NoteBlock
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NoteBlockCopyWith<_NoteBlock> get copyWith => __$NoteBlockCopyWithImpl<_NoteBlock>(this, _$identity);

@override
Map<String, dynamic> toJson() {
  return _$NoteBlockToJson(this, );
}

@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _NoteBlock&&(identical(other.type, type) || other.type == type)&&(identical(other.text, text) || other.text == text)&&(identical(other.attachment, attachment) || other.attachment == attachment));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,type,text,attachment);

@override
String toString() {
  return 'NoteBlock(type: $type, text: $text, attachment: $attachment)';
}


}

/// @nodoc
abstract mixin class _$NoteBlockCopyWith<$Res> implements $NoteBlockCopyWith<$Res> {
  factory _$NoteBlockCopyWith(_NoteBlock value, $Res Function(_NoteBlock) _then) = __$NoteBlockCopyWithImpl;
@override @useResult
$Res call({
 NoteBlockType type, String? text, NoteAttachment? attachment
});


@override $NoteAttachmentCopyWith<$Res>? get attachment;

}
/// @nodoc
class __$NoteBlockCopyWithImpl<$Res>
    implements _$NoteBlockCopyWith<$Res> {
  __$NoteBlockCopyWithImpl(this._self, this._then);

  final _NoteBlock _self;
  final $Res Function(_NoteBlock) _then;

/// Create a copy of NoteBlock
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? type = null,Object? text = freezed,Object? attachment = freezed,}) {
  return _then(_NoteBlock(
type: null == type ? _self.type : type // ignore: cast_nullable_to_non_nullable
as NoteBlockType,text: freezed == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String?,attachment: freezed == attachment ? _self.attachment : attachment // ignore: cast_nullable_to_non_nullable
as NoteAttachment?,
  ));
}

/// Create a copy of NoteBlock
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$NoteAttachmentCopyWith<$Res>? get attachment {
    if (_self.attachment == null) {
    return null;
  }

  return $NoteAttachmentCopyWith<$Res>(_self.attachment!, (value) {
    return _then(_self.copyWith(attachment: value));
  });
}
}


/// @nodoc
mixin _$NoteEntry {

 String get id; String get vaultId; String get title; String get body; DateTime get createdAt; DateTime? get updatedAt; DateTime? get deletedAt; String? get deviceId; String? get contentHash; List<NoteAttachment> get attachments; List<NoteBlock> get blocks; bool get isPinned; int get revision; NoteSyncState get syncState; NoteEditorMode get editorMode;
/// Create a copy of NoteEntry
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NoteEntryCopyWith<NoteEntry> get copyWith => _$NoteEntryCopyWithImpl<NoteEntry>(this as NoteEntry, _$identity);

  /// Serializes this NoteEntry to a JSON map.
  Map<String, dynamic> toJson();


@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NoteEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.vaultId, vaultId) || other.vaultId == vaultId)&&(identical(other.title, title) || other.title == title)&&(identical(other.body, body) || other.body == body)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.contentHash, contentHash) || other.contentHash == contentHash)&&const DeepCollectionEquality().equals(other.attachments, attachments)&&const DeepCollectionEquality().equals(other.blocks, blocks)&&(identical(other.isPinned, isPinned) || other.isPinned == isPinned)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.syncState, syncState) || other.syncState == syncState)&&(identical(other.editorMode, editorMode) || other.editorMode == editorMode));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,vaultId,title,body,createdAt,updatedAt,deletedAt,deviceId,contentHash,const DeepCollectionEquality().hash(attachments),const DeepCollectionEquality().hash(blocks),isPinned,revision,syncState,editorMode);

@override
String toString() {
  return 'NoteEntry(id: $id, vaultId: $vaultId, title: $title, body: $body, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt, deviceId: $deviceId, contentHash: $contentHash, attachments: $attachments, blocks: $blocks, isPinned: $isPinned, revision: $revision, syncState: $syncState, editorMode: $editorMode)';
}


}

/// @nodoc
abstract mixin class $NoteEntryCopyWith<$Res>  {
  factory $NoteEntryCopyWith(NoteEntry value, $Res Function(NoteEntry) _then) = _$NoteEntryCopyWithImpl;
@useResult
$Res call({
 String id, String vaultId, String title, String body, DateTime createdAt, DateTime? updatedAt, DateTime? deletedAt, String? deviceId, String? contentHash, List<NoteAttachment> attachments, List<NoteBlock> blocks, bool isPinned, int revision, NoteSyncState syncState, NoteEditorMode editorMode
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
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? vaultId = null,Object? title = null,Object? body = null,Object? createdAt = null,Object? updatedAt = freezed,Object? deletedAt = freezed,Object? deviceId = freezed,Object? contentHash = freezed,Object? attachments = null,Object? blocks = null,Object? isPinned = null,Object? revision = null,Object? syncState = null,Object? editorMode = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,vaultId: null == vaultId ? _self.vaultId : vaultId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,contentHash: freezed == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String?,attachments: null == attachments ? _self.attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<NoteAttachment>,blocks: null == blocks ? _self.blocks : blocks // ignore: cast_nullable_to_non_nullable
as List<NoteBlock>,isPinned: null == isPinned ? _self.isPinned : isPinned // ignore: cast_nullable_to_non_nullable
as bool,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,syncState: null == syncState ? _self.syncState : syncState // ignore: cast_nullable_to_non_nullable
as NoteSyncState,editorMode: null == editorMode ? _self.editorMode : editorMode // ignore: cast_nullable_to_non_nullable
as NoteEditorMode,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String vaultId,  String title,  String body,  DateTime createdAt,  DateTime? updatedAt,  DateTime? deletedAt,  String? deviceId,  String? contentHash,  List<NoteAttachment> attachments,  List<NoteBlock> blocks,  bool isPinned,  int revision,  NoteSyncState syncState,  NoteEditorMode editorMode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NoteEntry() when $default != null:
return $default(_that.id,_that.vaultId,_that.title,_that.body,_that.createdAt,_that.updatedAt,_that.deletedAt,_that.deviceId,_that.contentHash,_that.attachments,_that.blocks,_that.isPinned,_that.revision,_that.syncState,_that.editorMode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String vaultId,  String title,  String body,  DateTime createdAt,  DateTime? updatedAt,  DateTime? deletedAt,  String? deviceId,  String? contentHash,  List<NoteAttachment> attachments,  List<NoteBlock> blocks,  bool isPinned,  int revision,  NoteSyncState syncState,  NoteEditorMode editorMode)  $default,) {final _that = this;
switch (_that) {
case _NoteEntry():
return $default(_that.id,_that.vaultId,_that.title,_that.body,_that.createdAt,_that.updatedAt,_that.deletedAt,_that.deviceId,_that.contentHash,_that.attachments,_that.blocks,_that.isPinned,_that.revision,_that.syncState,_that.editorMode);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String vaultId,  String title,  String body,  DateTime createdAt,  DateTime? updatedAt,  DateTime? deletedAt,  String? deviceId,  String? contentHash,  List<NoteAttachment> attachments,  List<NoteBlock> blocks,  bool isPinned,  int revision,  NoteSyncState syncState,  NoteEditorMode editorMode)?  $default,) {final _that = this;
switch (_that) {
case _NoteEntry() when $default != null:
return $default(_that.id,_that.vaultId,_that.title,_that.body,_that.createdAt,_that.updatedAt,_that.deletedAt,_that.deviceId,_that.contentHash,_that.attachments,_that.blocks,_that.isPinned,_that.revision,_that.syncState,_that.editorMode);case _:
  return null;

}
}

}

/// @nodoc
@JsonSerializable()

class _NoteEntry implements NoteEntry {
  const _NoteEntry({required this.id, required this.vaultId, required this.title, required this.body, required this.createdAt, this.updatedAt, this.deletedAt, this.deviceId, this.contentHash, final  List<NoteAttachment> attachments = const <NoteAttachment>[], final  List<NoteBlock> blocks = const <NoteBlock>[], this.isPinned = false, this.revision = 1, this.syncState = NoteSyncState.localOnly, this.editorMode = NoteEditorMode.rich}): _attachments = attachments,_blocks = blocks;
  factory _NoteEntry.fromJson(Map<String, dynamic> json) => _$NoteEntryFromJson(json);

@override final  String id;
@override final  String vaultId;
@override final  String title;
@override final  String body;
@override final  DateTime createdAt;
@override final  DateTime? updatedAt;
@override final  DateTime? deletedAt;
@override final  String? deviceId;
@override final  String? contentHash;
 final  List<NoteAttachment> _attachments;
@override@JsonKey() List<NoteAttachment> get attachments {
  if (_attachments is EqualUnmodifiableListView) return _attachments;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_attachments);
}

 final  List<NoteBlock> _blocks;
@override@JsonKey() List<NoteBlock> get blocks {
  if (_blocks is EqualUnmodifiableListView) return _blocks;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_blocks);
}

@override@JsonKey() final  bool isPinned;
@override@JsonKey() final  int revision;
@override@JsonKey() final  NoteSyncState syncState;
@override@JsonKey() final  NoteEditorMode editorMode;

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
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _NoteEntry&&(identical(other.id, id) || other.id == id)&&(identical(other.vaultId, vaultId) || other.vaultId == vaultId)&&(identical(other.title, title) || other.title == title)&&(identical(other.body, body) || other.body == body)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.deletedAt, deletedAt) || other.deletedAt == deletedAt)&&(identical(other.deviceId, deviceId) || other.deviceId == deviceId)&&(identical(other.contentHash, contentHash) || other.contentHash == contentHash)&&const DeepCollectionEquality().equals(other._attachments, _attachments)&&const DeepCollectionEquality().equals(other._blocks, _blocks)&&(identical(other.isPinned, isPinned) || other.isPinned == isPinned)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.syncState, syncState) || other.syncState == syncState)&&(identical(other.editorMode, editorMode) || other.editorMode == editorMode));
}

@JsonKey(includeFromJson: false, includeToJson: false)
@override
int get hashCode => Object.hash(runtimeType,id,vaultId,title,body,createdAt,updatedAt,deletedAt,deviceId,contentHash,const DeepCollectionEquality().hash(_attachments),const DeepCollectionEquality().hash(_blocks),isPinned,revision,syncState,editorMode);

@override
String toString() {
  return 'NoteEntry(id: $id, vaultId: $vaultId, title: $title, body: $body, createdAt: $createdAt, updatedAt: $updatedAt, deletedAt: $deletedAt, deviceId: $deviceId, contentHash: $contentHash, attachments: $attachments, blocks: $blocks, isPinned: $isPinned, revision: $revision, syncState: $syncState, editorMode: $editorMode)';
}


}

/// @nodoc
abstract mixin class _$NoteEntryCopyWith<$Res> implements $NoteEntryCopyWith<$Res> {
  factory _$NoteEntryCopyWith(_NoteEntry value, $Res Function(_NoteEntry) _then) = __$NoteEntryCopyWithImpl;
@override @useResult
$Res call({
 String id, String vaultId, String title, String body, DateTime createdAt, DateTime? updatedAt, DateTime? deletedAt, String? deviceId, String? contentHash, List<NoteAttachment> attachments, List<NoteBlock> blocks, bool isPinned, int revision, NoteSyncState syncState, NoteEditorMode editorMode
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
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? vaultId = null,Object? title = null,Object? body = null,Object? createdAt = null,Object? updatedAt = freezed,Object? deletedAt = freezed,Object? deviceId = freezed,Object? contentHash = freezed,Object? attachments = null,Object? blocks = null,Object? isPinned = null,Object? revision = null,Object? syncState = null,Object? editorMode = null,}) {
  return _then(_NoteEntry(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,vaultId: null == vaultId ? _self.vaultId : vaultId // ignore: cast_nullable_to_non_nullable
as String,title: null == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String,body: null == body ? _self.body : body // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,deletedAt: freezed == deletedAt ? _self.deletedAt : deletedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,deviceId: freezed == deviceId ? _self.deviceId : deviceId // ignore: cast_nullable_to_non_nullable
as String?,contentHash: freezed == contentHash ? _self.contentHash : contentHash // ignore: cast_nullable_to_non_nullable
as String?,attachments: null == attachments ? _self._attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<NoteAttachment>,blocks: null == blocks ? _self._blocks : blocks // ignore: cast_nullable_to_non_nullable
as List<NoteBlock>,isPinned: null == isPinned ? _self.isPinned : isPinned // ignore: cast_nullable_to_non_nullable
as bool,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,syncState: null == syncState ? _self.syncState : syncState // ignore: cast_nullable_to_non_nullable
as NoteSyncState,editorMode: null == editorMode ? _self.editorMode : editorMode // ignore: cast_nullable_to_non_nullable
as NoteEditorMode,
  ));
}


}

// dart format on
