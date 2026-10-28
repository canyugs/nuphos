import UIKit
import UniformTypeIdentifiers

/// Stages content locally. This extension has no token, network client or runtime API.
final class ShareViewController: UIViewController {
    private let textView = UITextView()
    private let status = UILabel()
    private let save = UIButton(type: .system)
    private var files: [(String, String, URL)] = []
    private var temporary: [URL] = []
    private var scope: DraftScope?
    private let store = SharedDraftStore.applicationGroup()
    private let shareID = UUID()
    private var task: Task<Void, Never>?
    private var finished = false
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        textView.font = .preferredFont(forTextStyle: .body)
        textView.accessibilityLabel = "Shared text"
        textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
        status.numberOfLines = 0
        status.font = .preferredFont(forTextStyle: .footnote)
        save.setTitle("Save draft", for: .normal); save.isEnabled = false
        save.addTarget(self, action: #selector(saveDraft), for: .touchUpInside)
        let cancel = UIButton(type: .system); cancel.setTitle("Cancel", for: .normal)
        cancel.addTarget(self, action: #selector(cancelShare), for: .touchUpInside)
        let title = UILabel(); title.text = "Save to Nuphos"; title.font = .preferredFont(forTextStyle: .headline)
        let stack = UIStackView(arrangedSubviews: [title, textView, status, save, cancel]); stack.axis = .vertical; stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20), stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20), stack.bottomAnchor.constraint(lessThanOrEqualTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)])
        preferredContentSize = CGSize(width: 400, height: 500)
        status.text = "Preparing shared content…"
        task = Task { await loadItems() }
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if !finished { finished = true; task?.cancel(); cleanup() }
    }
    private func loadItems() async {
        do {
            guard let store, let scope = try store.scope() else { throw SharedDraftStore.Failure.unavailable }
            self.scope = scope
            let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
            var text: [String] = []; var count = 0
            for item in items {
                if let value = item.attributedContentText?.string, !value.isEmpty { text.append(value) }
                for provider in item.attachments ?? [] {
                    try Task.checkCancellation(); count += 1
                    guard count <= SharedDraftStore.maxFiles else { throw SharedDraftStore.Failure.capacity }
                    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                        let value = try await value(provider, type: UTType.fileURL.identifier)
                        guard let url = value as? URL, url.isFileURL else { throw SharedDraftStore.Failure.invalidFile }
                        try retain(url, name: provider.suggestedName ?? url.lastPathComponent, type: UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.data.identifier)
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                        guard let url = try await value(provider, type: UTType.url.identifier) as? URL, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw SharedDraftStore.Failure.invalidFile }
                        text.append(url.absoluteString)
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                        let item = try await value(provider, type: UTType.plainText.identifier)
                        guard let string = item as? String else { throw SharedDraftStore.Failure.invalidFile }; text.append(string)
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                        // A public.image file representation may be an archived UIImage,
                        // not encoded image bytes. Ask the provider for its image object.
                        let url = try await imageRepresentation(provider)
                        files.append((provider.suggestedName ?? "Shared image.png", UTType.png.identifier, url))
                    } else if let type = provider.registeredTypeIdentifiers.first(where: { UTType($0)?.conforms(to: .data) == true }) {
                        let url = try await representation(provider, type: type)
                        files.append((provider.suggestedName ?? "Shared file", type, url))
                    } else { throw SharedDraftStore.Failure.invalidFile }
                }
            }
            try Task.checkCancellation()
            guard !finished, !text.isEmpty || !files.isEmpty else { throw SharedDraftStore.Failure.invalidFile }
            textView.text = text.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: "\n\n")
            guard textView.text.utf8.count <= SharedDraftStore.maxTextBytes else { throw SharedDraftStore.Failure.capacity }
            status.text = files.map { $0.0 }.joined(separator: "\n") + "\nSaved drafts stay on this device for 7 days. Open Nuphos → Shared drafts to review and send. Nothing is sent now."
            save.isEnabled = true
        } catch { status.text = error.localizedDescription; save.isEnabled = false; cleanup() }
    }
    private func value(_ provider: NSItemProvider, type: String) async throws -> NSSecureCoding {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { value, error in
                if let error { continuation.resume(throwing: error) }
                else if let value { continuation.resume(returning: value) }
                else { continuation.resume(throwing: SharedDraftStore.Failure.invalidFile) }
            }
        }
    }
    private func imageRepresentation(_ provider: NSItemProvider) async throws -> URL {
        let object = try await value(provider, type: UTType.image.identifier)
        let image: UIImage?
        if let value = object as? UIImage { image = value }
        else if let data = object as? Data { image = UIImage(data: data) }
        else if let url = object as? URL { image = UIImage(contentsOfFile: url.path) }
        else { image = nil }
        guard let image, let cgImage = image.cgImage,
              cgImage.width <= 16_000_000 / max(1, cgImage.height),
              let data = image.pngData() else { throw SharedDraftStore.Failure.invalidFile }
        guard data.count <= SharedDraftStore.maxFileBytes else { throw SharedDraftStore.Failure.capacity }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try data.write(to: target, options: [.atomic, .completeFileProtection])
        return target
    }
    private func representation(_ provider: NSItemProvider, type: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
                do {
                    if let error { throw error }; guard let url else { throw SharedDraftStore.Failure.invalidFile }
                    let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
                    guard bytes <= SharedDraftStore.maxFileBytes else { throw SharedDraftStore.Failure.capacity }
                    let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    try FileManager.default.copyItem(at: url, to: target)
                    continuation.resume(returning: target)
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    private func retain(_ source: URL, name: String, type: String) throws {
        let scoped = source.startAccessingSecurityScopedResource(); defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let bytes = try source.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard bytes <= SharedDraftStore.maxFileBytes else { throw SharedDraftStore.Failure.capacity }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: source, to: target); temporary.append(target); files.append((name, type, target))
    }
    @objc private func saveDraft() {
        guard !finished, let store, let scope else { return }
        do {
            try store.save(id: shareID, scope: scope, session: nil, text: textView.text, files: files)
            finished = true; cleanup(); extensionContext?.completeRequest(returningItems: nil)
        } catch { status.text = error.localizedDescription }
    }
    @objc private func cancelShare() {
        finished = true; task?.cancel(); cleanup()
        extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError))
    }
    private func cleanup() { for url in temporary + files.map({ $0.2 }) { try? FileManager.default.removeItem(at: url) }; temporary = []; files = [] }
    deinit { task?.cancel() }
}
