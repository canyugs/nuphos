import Foundation
import UniformTypeIdentifiers

struct ComposerDraftKey: Equatable {
    let account: String
    let team: String
    let session: String
}

extension ComposerDrafts {
    static let imported = Notification.Name("NuphosSharedDraftImported")
    static func attachments(for key: ComposerDraftKey) throws -> [ComposerAttachment] {
        guard account == key.account, let storage else { return [] }
        guard let draft = try storage.composer(account: key.account, team: key.team, session: key.session) else { return [] }
        return try draft.files.map { file in
            let source = storage.fileURL(file)
            if UTType(file.type)?.conforms(to: .image) == true {
                let data = try Data(contentsOf: source)
                guard let jpeg = ImageAttachment.jpeg(from: data) else { throw SharedDraftStore.Failure.invalidFile }
                return ComposerAttachment(name: file.name, kind: .image(jpeg))
            }
            let suffix = URL(fileURLWithPath: file.name).pathExtension
            let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(suffix)
            try FileManager.default.copyItem(at: source, to: target)
            return ComposerAttachment(name: file.name, kind: .file(target))
        }
    }
    static func saveAttachments(_ attachments: [ComposerAttachment], text: String, key: ComposerDraftKey) throws {
        guard account == key.account, let storage, let scope = try storage.scope(), scope.account == key.account, scope.team == key.team else { throw SharedDraftStore.Failure.identityChanged }
        var temporary: [URL] = []
        defer { for url in temporary { try? FileManager.default.removeItem(at: url) } }
        let files = try attachments.map { attachment -> (String, String, URL) in
            switch attachment.kind {
            case .image(let data):
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try data.write(to: url, options: [.atomic, .completeFileProtection]); temporary.append(url)
                return (attachment.uploadName, UTType.jpeg.identifier, url)
            case .file(let url): return (attachment.name, UTType(filenameExtension: attachment.name.components(separatedBy: ".").last ?? "")?.identifier ?? UTType.data.identifier, url)
            }
        }
        let id = try storage.composer(account: key.account, team: key.team, session: key.session)?.id ?? UUID()
        try storage.save(id: id, scope: scope, session: key.session, text: text, files: files)
    }
}
