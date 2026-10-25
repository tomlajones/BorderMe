import 'dart:async';
import 'dart:convert';

import 'package:borderme/engine/engine_client.dart';
import 'package:borderme/engine/settings.dart';
import 'package:flutter/services.dart';

final Uint8List kOnePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class FakeEngine implements EngineClient {
  FakeEngine({
    this.pickResult = const PickResult(paths: ['/tmp/a.jpg', '/tmp/b.jpg'], failed: 0),
    List<BatchEvent>? events,
    this.failPreview = false,
    this.busyPick = false,
    this.busyProcess = false,
    this.streamError,
    this.stored = RenderSettings.standard,
  }) : events = events ??
            const [
              PhotoSaved(index: 0, thumbnailPath: '/tmp/t0.jpg'),
              PhotoSaved(index: 1, thumbnailPath: '/tmp/t1.jpg'),
              BatchFinished(saved: 2, total: 2),
            ];

  PickResult pickResult;
  List<BatchEvent> events;
  bool failPreview;
  bool busyPick;
  bool busyProcess;
  /// When set, process() emits the events and then this error.
  Object? streamError;
  RenderSettings stored;

  final previewRequests = <(String, RenderSettings)>[];
  final savedSettings = <RenderSettings>[];
  List<String>? processedPaths;
  RenderSettings? processedSettings;
  int openedPhotos = 0;
  int openedSettings = 0;
  final _loading = StreamController<int>.broadcast();

  void announceLoading(int count) => _loading.add(count);

  @override
  Stream<int> get pickLoading => _loading.stream;

  @override
  Future<PickResult> pickPhotos({int limit = 50}) async {
    if (busyPick) throw PlatformException(code: 'busy', message: 'a picker is already open');
    return pickResult;
  }

  @override
  Future<Uint8List> preview(String path, RenderSettings settings, {int maxEdge = 1200}) async {
    previewRequests.add((path, settings));
    if (failPreview) throw PlatformException(code: 'preview_failed', message: 'not a readable image file');
    return kOnePixelPng;
  }

  @override
  Stream<BatchEvent> process(List<String> paths, RenderSettings settings) {
    processedPaths = paths;
    processedSettings = settings;
    if (busyProcess) {
      return Stream<BatchEvent>.error(PlatformException(code: 'busy', message: 'a batch is already running'));
    }
    if (streamError == null) return Stream.fromIterable(events);
    final controller = StreamController<BatchEvent>();
    events.forEach(controller.add);
    controller.addError(streamError!);
    controller.close();
    return controller.stream;
  }

  @override
  Future<RenderSettings> lastSettings() async => stored;

  @override
  Future<void> saveSettings(RenderSettings settings) async => savedSettings.add(settings);

  @override
  Future<void> openPhotos() async => openedPhotos++;

  @override
  Future<void> openSettings() async => openedSettings++;
}
