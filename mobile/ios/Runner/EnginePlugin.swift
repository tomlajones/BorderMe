import Flutter
import UIKit

final class EnginePlugin: NSObject, FlutterPlugin {
    private static let maximumBatch = 50
    private let channel: FlutterMethodChannel
    private let picker = PhotoPicker()
    private let batch = BatchProcessor()
    private let previewQueue = DispatchQueue(label: "borderme.preview", qos: .userInitiated)

    init(channel: FlutterMethodChannel) {
        self.channel = channel
    }

    static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "borderme/engine", binaryMessenger: registrar.messenger())
        let instance = EnginePlugin(channel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
        let events = FlutterEventChannel(name: "borderme/engine/progress", binaryMessenger: registrar.messenger())
        events.setStreamHandler(instance.batch)
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "pickPhotos":
            guard !picker.isPending else {
                result(FlutterError(code: "busy", message: "A photo picker is already open.", details: nil))
                return
            }
            // PHPicker treats 0 as unlimited, so clamp to the batch cap.
            let limit = min(max(arguments["limit"] as? Int ?? 50, 1), Self.maximumBatch)
            picker.present(
                limit: limit,
                onLoading: { [channel] count in channel.invokeMethod("pickLoading", arguments: count) },
                completion: { picked in result(["paths": picked.paths, "failed": picked.failed]) }
            )
        case "preview":
            guard let path = arguments["path"] as? String else {
                result(FlutterError(code: "bad_arguments", message: "path is missing", details: nil))
                return
            }
            let settings = RenderSettings(channelValue: arguments["settings"])
            let maxEdge = arguments["maxEdge"] as? Int ?? 1200
            previewQueue.async {
                do {
                    let preview = try Renderer.preview(sourceURL: URL(fileURLWithPath: path), settings: settings, maximumEdge: maxEdge)
                    DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: preview.jpegData)) }
                } catch {
                    let reason = FailureReason.describe(error)
                    DispatchQueue.main.async { result(FlutterError(code: "preview_failed", message: reason, details: nil)) }
                }
            }
        case "process":
            let paths = Array((arguments["paths"] as? [String] ?? []).prefix(Self.maximumBatch))
            if batch.start(paths: paths, settings: RenderSettings(channelValue: arguments["settings"])) {
                result(nil)
            } else {
                result(FlutterError(code: "busy", message: "Photos are already being saved.", details: nil))
            }
        case "lastSettings":
            result(SettingsStore.load().channelValue)
        case "saveSettings":
            SettingsStore.save(RenderSettings(channelValue: arguments["settings"]))
            result(nil)
        case "openSettings":
            open(UIApplication.openSettingsURLString)
            result(nil)
        case "openPhotos":
            open("photos-redirect://")
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        UIApplication.shared.open(url)
    }
}
