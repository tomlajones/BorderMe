import Foundation
import UniformTypeIdentifiers

struct PickedPhotos {
    let paths: [String]
    let failed: Int
}

/// Copies picked or shared photos into a temporary folder as their original
/// files (HEIC, JPEG, RAW...), metadata intact, so the engine can read them by
/// path. This needs no photo library permission at all.
enum PickedFiles {
    private static let prefix = "Picked-"

    static func freshDirectory() -> URL {
        let temporary = FileManager.default.temporaryDirectory
        let old = (try? FileManager.default.contentsOfDirectory(at: temporary, includingPropertiesForKeys: nil)) ?? []
        for url in old where url.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: url)
        }
        let directory = temporary.appendingPathComponent(prefix + UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Calls `completion` on the main queue, keeping the original order.
    static func copy(providers: [NSItemProvider], completion: @escaping (PickedPhotos) -> Void) {
        let directory = freshDirectory()
        let group = DispatchGroup()
        let lock = NSLock()
        var paths: [Int: String] = [:]

        for (index, provider) in providers.enumerated() {
            guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else { continue }
            group.enter()
            // The provided file is deleted when this handler returns, so it is
            // copied before leaving. iCloud originals download first.
            provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, _ in
                defer { group.leave() }
                guard let url else { return }
                let destination = directory.appendingPathComponent("\(index)-\(url.lastPathComponent)")
                guard (try? FileManager.default.copyItem(at: url, to: destination)) != nil else { return }
                lock.lock()
                paths[index] = destination.path
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            let ordered = paths.keys.sorted().compactMap { paths[$0] }
            completion(PickedPhotos(paths: ordered, failed: providers.count - ordered.count))
        }
    }
}
