// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:typed_data';

String? createWebVideoObjectUrl(Uint8List bytes, String mimeType) {
  if (bytes.isEmpty) {
    return null;
  }
  final blob = html.Blob(<Object>[bytes], mimeType);
  return html.Url.createObjectUrlFromBlob(blob);
}

void revokeWebVideoObjectUrl(String url) {
  html.Url.revokeObjectUrl(url);
}
