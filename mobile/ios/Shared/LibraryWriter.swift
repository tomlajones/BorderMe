import Photos

enum LibraryWriterError: Error {
    case saveFailed
}

/// Saves new photos with add-only access, the narrowest permission iOS has.
/// Mat Board never reads the photo library.
enum LibraryWriter {
    static func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        return status == .authorized || status == .limited
    }

    static func save(jpegData: Data) async throws {
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.forAsset().addResource(with: .photo, data: jpegData, options: nil)
            }
        } catch {
            throw LibraryWriterError.saveFailed
        }
    }
}
