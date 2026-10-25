import Flutter
import UIKit

final class EnginePlugin: NSObject, FlutterPlugin {
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
            let limit = arguments["limit"] as? Int ?? 50
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
            let paths = arguments["paths"] as? [String] ?? []
            batch.start(paths: paths, settings: RenderSettings(channelValue: arguments["settings"]))
            result(nil)
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
