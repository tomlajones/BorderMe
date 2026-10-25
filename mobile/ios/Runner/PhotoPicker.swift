import PhotosUI
import UIKit

final class PhotoPicker: NSObject, PHPickerViewControllerDelegate {
    private var onLoading: ((Int) -> Void)?
    private var completion: ((PickedPhotos) -> Void)?

    var isPending: Bool { completion != nil }

    func present(limit: Int, onLoading: @escaping (Int) -> Void, completion: @escaping (PickedPhotos) -> Void) {
        // No photo library is passed in, so the picker needs no permission and
        // hands back files rather than library identifiers.
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = limit
        configuration.preferredAssetRepresentationMode = .current

        guard let presenter = UIApplication.shared.topViewController else {
            completion(PickedPhotos(paths: [], failed: 0))
            return
        }
        self.onLoading = onLoading
        self.completion = completion
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let completion else { return }
        self.completion = nil
        // A cancelled pick must not touch the previous pick's files.
        if results.isEmpty {
            completion(PickedPhotos(paths: [], failed: 0))
            return
        }
        onLoading?(results.count)
        PickedFiles.copy(providers: results.map(\.itemProvider), completion: completion)
    }
}

extension UIApplication {
    var topViewController: UIViewController? {
        let window = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
