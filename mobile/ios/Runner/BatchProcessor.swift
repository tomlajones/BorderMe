import Flutter
import UIKit

/// Borders a batch one photo at a time, so memory stays bounded, and streams
/// progress to Dart.
final class BatchProcessor: NSObject, FlutterStreamHandler {
    private var sink: FlutterEventSink?
    private let lock = NSLock()
    private var memoryWarned = false
    private var running = false
    private let batchID = UUID().uuidString
    private var observer: NSObjectProtocol?

    override init() {
        super.init()
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.setMemoryWarned(true)
        }
    }

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        sink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        sink = nil
        return nil
    }

    /// Returns false, doing nothing, if a batch is already running.
    func start(paths: [String], settings: RenderSettings) -> Bool {
        lock.lock()
        if running {
            lock.unlock()
            return false
        }
        running = true
        lock.unlock()
        setMemoryWarned(false)
        Task.detached(priority: .userInitiated) { [weak self] in
            await self?.run(paths: paths, settings: settings)
            self?.setRunning(false)
        }
        return true
    }

    private func run(paths: [String], settings: RenderSettings) async {
        guard await LibraryWriter.requestAccess() else {
            emit(["type": "denied"])
            return
        }
        var saved = 0
        for (index, path) in paths.enumerated() {
            // Finish the current photo, then stop, rather than risk iOS ending
            // the app partway through a save.
            if isMemoryWarned() {
                emit(["type": "stopped", "saved": saved, "total": paths.count])
                return
            }
            let url = URL(fileURLWithPath: path)
            do {
                let rendered = try autoreleasepool {
                    try Renderer.render(sourceURL: url, settings: settings, maximumEdge: EngineLimits.appMaximumEdge)
                }
                try await LibraryWriter.save(jpegData: rendered.jpegData)
                saved += 1
                emit(["type": "saved", "index": index, "thumbnail": thumbnail(for: url, settings: settings, index: index) ?? ""])
            } catch {
                emit(["type": "skipped", "index": index, "reason": FailureReason.describe(error)])
            }
        }
        emit(["type": "finished", "saved": saved, "total": paths.count])
    }

    private func thumbnail(for url: URL, settings: RenderSettings, index: Int) -> String? {
        guard let preview = try? Renderer.preview(sourceURL: url, settings: settings, maximumEdge: 300) else { return nil }
        // A fresh name per batch stops Flutter's image cache showing stale thumbnails.
        let destination = url.deletingLastPathComponent().appendingPathComponent("thumb-\(batchID)-\(index).jpg")
        guard (try? preview.jpegData.write(to: destination)) != nil else { return nil }
        return destination.path
    }

    private func emit(_ event: [String: Any]) {
        DispatchQueue.main.async { [weak self] in self?.sink?(event) }
    }

    private func setRunning(_ value: Bool) {
        lock.lock()
        running = value
        lock.unlock()
    }

    private func setMemoryWarned(_ value: Bool) {
        lock.lock()
        memoryWarned = value
        lock.unlock()
    }

    private func isMemoryWarned() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return memoryWarned
    }
}
