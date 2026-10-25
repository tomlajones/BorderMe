import SwiftUI
import UIKit

/// All updates to published state happen on the main queue.
final class ShareModel: ObservableObject {
    enum Stage: Equatable {
        case loading
        case ready
        case saving(done: Int, total: Int)
        case finished(saved: Int, skipped: [String])
        case failed(String)
    }

    @Published var settings: RenderSettings {
        didSet {
            SettingsStore.save(settings)
            refreshPreview()
        }
    }
    @Published private(set) var stage: Stage = .loading
    @Published private(set) var preview: UIImage?
    /// The preview could not be rendered. Saving may still work.
    @Published private(set) var previewFailed = false
    private(set) var paths: [String] = []
    private var unopened = 0
    private let renderQueue = DispatchQueue(label: "borderme.share.render", qos: .userInitiated)

    init() {
        settings = SettingsStore.load()
    }

    func load(providers: [NSItemProvider]) {
        PickedFiles.copy(providers: providers) { [weak self] picked in
            guard let self else { return }
            self.paths = picked.paths
            self.unopened = picked.failed
            if picked.paths.isEmpty {
                self.stage = .failed("BorderMe couldn't open these photos.")
            } else {
                self.stage = .ready
                self.refreshPreview()
            }
        }
    }

    func refreshPreview() {
        guard let first = paths.first else { return }
        let requested = settings
        renderQueue.async { [weak self] in
            let rendered = try? Renderer.preview(sourceURL: URL(fileURLWithPath: first), settings: requested, maximumEdge: 900)
            let image = rendered.flatMap { UIImage(data: $0.jpegData) }
            DispatchQueue.main.async {
                guard let self, self.settings == requested else { return }
                self.preview = image
                self.previewFailed = image == nil
            }
        }
    }

    func save() {
        let paths = self.paths
        let settings = self.settings
        stage = .saving(done: 0, total: paths.count)
        Task.detached(priority: .userInitiated) { [weak self] in
            guard await LibraryWriter.requestAccess() else {
                self?.setStage(.failed("BorderMe needs permission to add photos. You can allow it in Settings > Privacy & Security > Photos."))
                return
            }
            var saved = 0
            var skipped: [String] = []
            for (index, path) in paths.enumerated() {
                do {
                    // Extensions get far less memory than apps, hence the smaller cap.
                    let rendered = try autoreleasepool {
                        try Renderer.render(
                            sourceURL: URL(fileURLWithPath: path),
                            settings: settings,
                            maximumEdge: EngineLimits.extensionMaximumEdge
                        )
                    }
                    try await LibraryWriter.save(jpegData: rendered.jpegData)
                    saved += 1
                } catch {
                    skipped.append("Photo \(index + 1): \(FailureReason.describe(error))")
                }
                self?.setStage(.saving(done: index + 1, total: paths.count))
            }
            if let unopened = self?.unopened, unopened > 0 {
                skipped.append(unopened == 1 ? "1 photo couldn't be opened." : "\(unopened) photos couldn't be opened.")
            }
            self?.setStage(.finished(saved: saved, skipped: skipped))
        }
    }

    private func setStage(_ next: Stage) {
        DispatchQueue.main.async { [weak self] in self?.stage = next }
    }
}
