import SwiftUI
import Combine
import UIKit

final class ShareViewController: UIViewController {
    private let model = ShareModel()
    private var finished = false
    private var stageWatcher: AnyCancellable?

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(
            model: model,
            onDone: { [weak self] in self?.finish(cancelled: false) },
            onCancel: { [weak self] in self?.finish(cancelled: true) }
        ))
        // Swiping the sheet down mid-save would drop the remaining photos.
        stageWatcher = model.$stage.sink { [weak self] stage in
            if case .saving = stage { self?.isModalInPresentation = true } else { self?.isModalInPresentation = false }
        }
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)

        let items = extensionContext?.inputItems as? [NSExtensionItem] ?? []
        model.load(providers: items.flatMap { $0.attachments ?? [] })
    }

    private func finish(cancelled: Bool) {
        guard !finished else { return }
        finished = true
        PickedFiles.removeAll()
        if cancelled {
            extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
        } else {
            extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
