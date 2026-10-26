import 'dart:async';

import 'package:flutter/services.dart';

import 'settings.dart';

class PickResult {
  const PickResult({required this.paths, required this.failed});
  final List<String> paths;
  final int failed;
}

sealed class BatchEvent {
  const BatchEvent();
}

class PhotoSaved extends BatchEvent {
  const PhotoSaved({required this.index, required this.thumbnailPath});
  final int index;
  final String thumbnailPath;

  @override
  bool operator ==(Object other) => other is PhotoSaved && other.index == index && other.thumbnailPath == thumbnailPath;
  @override
  int get hashCode => Object.hash(index, thumbnailPath);
}

class PhotoSkipped extends BatchEvent {
  const PhotoSkipped({required this.index, required this.reason});
  final int index;
  final String reason;

  @override
  bool operator ==(Object other) => other is PhotoSkipped && other.index == index && other.reason == reason;
  @override
  int get hashCode => Object.hash(index, reason);
}

enum StopReason {
  /// iOS warned that memory was running low.
  lowMemory,

  /// BorderMe was in the background and iOS ran out of time to give it.
  outOfTime,
}

/// The batch stopped early, after the photo it was on.
class BatchStopped extends BatchEvent {
  const BatchStopped({required this.saved, required this.total, required this.reason});
  final int saved;
  final int total;
  final StopReason reason;

  @override
  bool operator ==(Object other) =>
      other is BatchStopped && other.saved == saved && other.total == total && other.reason == reason;
  @override
  int get hashCode => Object.hash(saved, total, reason);
}

class BatchFinished extends BatchEvent {
  const BatchFinished({required this.saved, required this.total});
  final int saved;
  final int total;

  @override
  bool operator ==(Object other) => other is BatchFinished && other.saved == saved && other.total == total;
  @override
  int get hashCode => Object.hash(saved, total);
}

class PermissionDenied extends BatchEvent {
  const PermissionDenied();

  @override
  bool operator ==(Object other) => other is PermissionDenied;
  @override
  int get hashCode => 0;
}

BatchEvent? parseBatchEvent(Object? raw) {
  if (raw is! Map) return null;
  // A typed local, because type promotion of `raw` doesn't reach into the
  // nested function below.
  final Map<Object?, Object?> map = raw;
  int number(String key) => (map[key] as num?)?.toInt() ?? 0;
  return switch (map['type']) {
    'saved' => PhotoSaved(index: number('index'), thumbnailPath: map['thumbnail'] as String? ?? ''),
    'skipped' => PhotoSkipped(index: number('index'), reason: map['reason'] as String? ?? 'could not be processed'),
    'stopped' => BatchStopped(
      saved: number('saved'),
      total: number('total'),
      reason: map['reason'] == 'time' ? StopReason.outOfTime : StopReason.lowMemory,
    ),
    'finished' => BatchFinished(saved: number('saved'), total: number('total')),
    'denied' => const PermissionDenied(),
    _ => null,
  };
}

/// Everything the UI needs from native code. Tests use a fake.
abstract class EngineClient {
  Future<PickResult> pickPhotos({int limit = 50});

  /// Fires once the picker closes and picked photos start copying.
  Stream<int> get pickLoading;

  Future<Uint8List> preview(String path, RenderSettings settings, {int maxEdge = 1200});

  /// Completes after a finished, stopped or denied event.
  Stream<BatchEvent> process(List<String> paths, RenderSettings settings);

  Future<RenderSettings> lastSettings();
  Future<void> saveSettings(RenderSettings settings);
  Future<void> openSettings();
  Future<void> openPhotos();
}

class MethodChannelEngine implements EngineClient {
  MethodChannelEngine() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pickLoading') _pickLoading.add((call.arguments as num?)?.toInt() ?? 0);
      return null;
    });
  }

  static const _channel = MethodChannel('borderme/engine');
  static const _events = EventChannel('borderme/engine/progress');
  final _pickLoading = StreamController<int>.broadcast();

  @override
  Stream<int> get pickLoading => _pickLoading.stream;

  @override
  Future<PickResult> pickPhotos({int limit = 50}) async {
    final raw = await _channel.invokeMapMethod<String, Object?>('pickPhotos', {'limit': limit}) ?? const {};
    return PickResult(
      paths: (raw['paths'] as List<Object?>?)?.cast<String>() ?? const [],
      failed: (raw['failed'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<Uint8List> preview(String path, RenderSettings settings, {int maxEdge = 1200}) async {
    final bytes = await _channel.invokeMethod<Uint8List>(
      'preview',
      {'path': path, 'settings': settings.toMap(), 'maxEdge': maxEdge},
    );
    if (bytes == null) throw StateError('The engine returned an empty preview.');
    return bytes;
  }

  @override
  Stream<BatchEvent> process(List<String> paths, RenderSettings settings) {
    late final StreamController<BatchEvent> controller;
    StreamSubscription<Object?>? subscription;
    controller = StreamController<BatchEvent>(
      onListen: () {
        // Listen first so no early event is missed, then start the batch.
        subscription = _events.receiveBroadcastStream().listen(
          (raw) {
            final event = parseBatchEvent(raw);
            if (event == null) return;
            controller.add(event);
            if (event is BatchFinished || event is BatchStopped || event is PermissionDenied) {
              subscription?.cancel();
              controller.close();
            }
          },
          onError: controller.addError,
          // If native ends the stream without a terminal event, close it so
          // save() can't hang.
          onDone: () {
            if (!controller.isClosed) controller.close();
          },
        );
        // A refused start (e.g. 'busy') arrives here, so it reaches the caller
        // instead of being lost as an unhandled future error.
        _channel.invokeMethod<void>('process', {'paths': paths, 'settings': settings.toMap()}).catchError((
          Object error,
        ) {
          if (controller.isClosed) return;
          controller.addError(error);
          subscription?.cancel();
          controller.close();
        });
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<RenderSettings> lastSettings() async =>
      RenderSettings.fromMap(await _channel.invokeMapMethod<String, Object?>('lastSettings'));

  @override
  Future<void> saveSettings(RenderSettings settings) =>
      _channel.invokeMethod<void>('saveSettings', {'settings': settings.toMap()});

  @override
  Future<void> openSettings() => _channel.invokeMethod<void>('openSettings');

  @override
  Future<void> openPhotos() => _channel.invokeMethod<void>('openPhotos');
}
