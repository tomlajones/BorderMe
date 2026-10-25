import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../engine/engine_client.dart';
import '../engine/settings.dart';

enum Phase { start, loading, editing, saving, done }

class SkippedPhoto {
  const SkippedPhoto(this.index, this.reason);
  final int index;
  final String reason;
}

class SessionController extends ChangeNotifier {
  SessionController(this.engine, {this.debounce = const Duration(milliseconds: 300)}) {
    _loading = engine.pickLoading.listen((_) {
      if (phase != Phase.start) return;
      phase = Phase.loading;
      _notify();
    });
  }

  static const maxPhotos = 50;

  final EngineClient engine;
  final Duration debounce;
  late final StreamSubscription<int> _loading;
  Timer? _previewTimer;
  bool _disposed = false;

  Phase phase = Phase.start;
  RenderSettings settings = RenderSettings.standard;
  List<String> photos = const [];
  int failedToLoad = 0;
  int currentIndex = 0;
  final Map<int, Uint8List> previews = {};
  String? previewError;

  int saved = 0;
  int total = 0;
  final List<String> thumbnails = [];
  final List<SkippedPhoto> skipped = [];
  bool stoppedLowMemory = false;
  bool permissionDenied = false;
  /// Set when saving failed part way through. The Done screen shows it.
  String? saveError;

  int get processed => saved + skipped.length;

  /// Notifies unless the controller has been disposed. Async work can finish
  /// after the screen has gone.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> init() async {
    settings = await engine.lastSettings();
    _notify();
  }

  Future<void> choosePhotos() async {
    final PickResult result;
    try {
      result = await engine.pickPhotos(limit: maxPhotos);
    } on PlatformException catch (e) {
      // The native picker is already open, so this tap is a duplicate.
      if (e.code == 'busy') return;
      rethrow;
    }
    failedToLoad = result.failed;
    if (result.paths.isEmpty) {
      phase = Phase.start;
      _notify();
      return;
    }
    photos = result.paths;
    currentIndex = 0;
    previews.clear();
    previewError = null;
    phase = Phase.editing;
    _notify();
    unawaited(_loadPreview(0));
  }

  /// Saves immediately so the Share extension starts from the same settings,
  /// but waits for the user to stop tapping before re-rendering the preview.
  void updateSettings(RenderSettings next) {
    if (next == settings) return;
    settings = next;
    previews.clear();
    previewError = null;
    unawaited(engine.saveSettings(next));
    _previewTimer?.cancel();
    _previewTimer = Timer(debounce, () => _loadPreview(currentIndex));
    _notify();
  }

  void showPhoto(int index) {
    currentIndex = index;
    previewError = null;
    _notify();
    if (!previews.containsKey(index)) unawaited(_loadPreview(index));
  }

  Future<void> _loadPreview(int index) async {
    if (index >= photos.length) return;
    final requested = settings;
    final path = photos[index];
    try {
      final bytes = await engine.preview(path, requested);
      // Settings or photos changed while this was rendering: drop it.
      if (requested != settings || index >= photos.length || photos[index] != path) return;
      previews[index] = bytes;
    } catch (_) {
      if (requested != settings || index != currentIndex) return;
      previewError = "This photo couldn't be previewed. It may be skipped when you save.";
    }
    _notify();
  }

  Future<void> save() async {
    _previewTimer?.cancel();
    final previousPhase = phase;
    phase = Phase.saving;
    saved = 0;
    total = photos.length;
    thumbnails.clear();
    skipped.clear();
    stoppedLowMemory = false;
    permissionDenied = false;
    saveError = null;
    _notify();

    try {
      await for (final event in engine.process(photos, settings)) {
        switch (event) {
          case PhotoSaved(:final thumbnailPath):
            saved++;
            if (thumbnailPath.isNotEmpty) thumbnails.add(thumbnailPath);
          case PhotoSkipped(:final index, :final reason):
            skipped.add(SkippedPhoto(index, reason));
          case BatchStopped():
            stoppedLowMemory = true;
          case BatchFinished():
            break;
          case PermissionDenied():
            permissionDenied = true;
        }
        _notify();
      }
    } on PlatformException catch (e) {
      // A batch is already running. Go back to where the user was.
      if (e.code == 'busy') {
        phase = previousPhase;
        _notify();
        return;
      }
      saveError = _failedMessage();
    } catch (_) {
      // Any other failure ends the batch on Done, keeping the counts so far.
      saveError = _failedMessage();
    }
    phase = Phase.done;
    _notify();
  }

  String _failedMessage() =>
      'Something went wrong while saving. $saved of $total photos were saved.';

  void backToEditing() {
    phase = Phase.editing;
    _notify();
  }

  void startAgain() {
    _previewTimer?.cancel();
    photos = const [];
    previews.clear();
    previewError = null;
    saveError = null;
    currentIndex = 0;
    failedToLoad = 0;
    phase = Phase.start;
    _notify();
  }

  Future<void> openPhotos() => engine.openPhotos();
  Future<void> openSettings() => engine.openSettings();

  @override
  void dispose() {
    _disposed = true;
    _previewTimer?.cancel();
    _loading.cancel();
    super.dispose();
  }
}
