// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;
import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';

final _registeredVideoViews = <String>{};
final _videoElementsByViewType = <String, html.VideoElement>{};

Widget buildWebVideoElementView({
  required String viewType,
  required String objectUrl,
  required bool autoplay,
  required bool muted,
  required bool fillAvailableHeight,
}) {
  if (_registeredVideoViews.add(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final video = html.VideoElement()
        ..src = objectUrl
        ..controls = true
        ..autoplay = autoplay
        ..preload = 'metadata'
        ..muted = muted
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = fillAvailableHeight ? 'contain' : 'cover'
        ..style.backgroundColor = 'black';
      video.setAttribute('playsinline', 'true');
      _videoElementsByViewType[viewType] = video;
      return video;
    });
  }
  return HtmlElementView(viewType: viewType);
}

void updateWebVideoElementMuted(String viewType, bool muted) {
  _videoElementsByViewType[viewType]?.muted = muted;
}
