import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

bool get _supportsFirebaseObservability =>
    !kIsWeb &&
    defaultTargetPlatform == TargetPlatform.android &&
    Firebase.apps.isNotEmpty;

Future<void> configureFirebaseObservability({
  required bool enableCollection,
}) async {
  if (!_supportsFirebaseObservability) {
    return;
  }

  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
    enableCollection,
  );
  await FirebasePerformance.instance.setPerformanceCollectionEnabled(
    enableCollection,
  );

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (!enableCollection) {
      return;
    }
    FirebaseCrashlytics.instance.recordFlutterFatalError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    if (enableCollection) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    }
    return true;
  };
}

Future<void> recordNonFatalError(
  Object error,
  StackTrace stackTrace, {
  String? reason,
  Iterable<Object> information = const <Object>[],
}) async {
  if (!_supportsFirebaseObservability) {
    return;
  }
  await FirebaseCrashlytics.instance.recordError(
    error,
    stackTrace,
    reason: reason,
    information: information,
    fatal: false,
  );
}

Future<void> logFirebaseBreadcrumb(String message) async {
  if (!_supportsFirebaseObservability) {
    return;
  }
  FirebaseCrashlytics.instance.log(message);
}

Future<T> runFirebaseTrace<T>(
  String name,
  Future<T> Function() action, {
  Map<String, String> attributes = const <String, String>{},
}) async {
  if (!_supportsFirebaseObservability) {
    return action();
  }
  final trace = FirebasePerformance.instance.newTrace(name);
  for (final entry in attributes.entries) {
    trace.putAttribute(entry.key, entry.value);
  }
  await trace.start();
  final stopwatch = Stopwatch()..start();
  try {
    final result = await action();
    trace.incrementMetric('success', 1);
    return result;
  } catch (error, stackTrace) {
    unawaited(
      recordNonFatalError(
        error,
        stackTrace,
        reason: 'Trace failure: $name',
      ),
    );
    rethrow;
  } finally {
    stopwatch.stop();
    trace.incrementMetric('duration_ms', stopwatch.elapsedMilliseconds);
    await trace.stop();
  }
}
