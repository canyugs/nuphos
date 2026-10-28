import SwiftUI

struct SharedDraftsSheet: View {
    let account: String
    let team: String
    var onImport: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var drafts: [SavedDraft] = []
    @State private var editing: SavedDraft?
    @State private var error: String?
    @State private var discard: SavedDraft?
    private let storage = SharedDraftStore.applicationGroup()
    var body: some View {
        NavigationStack {
            List {
                Section { Text("Review saved shares before sending. Drafts expire after 7 days and stay with the account and workspace they were saved to.").font(.footnote) }
                ForEach(drafts) { draft in
                    Button { editing = draft } label: {
                        VStack(alignment: .leading) {
                            Text(draft.text.isEmpty ? "Shared files" : draft.text).lineLimit(3)
                            Text(draft.files.map(\.name).joined(separator: ", ")).font(.caption)
                        }
                    }.swipeActions { Button("Discard", role: .destructive) { discard = draft } }
                }
                if drafts.isEmpty { Text("No shared drafts").foregroundStyle(.secondary) }
            }
            .navigationTitle("Shared drafts")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { reload() }
            .sheet(item: $editing, onDismiss: reload) { draft in SharedDraftEditor(draft: draft, account: account, team: team) { editing = nil; onImport(); dismiss() } }
            .confirmationDialog("Discard this shared draft?", isPresented: Binding(get: { discard != nil }, set: { if !$0 { discard = nil } })) {
                Button("Discard", role: .destructive) {
                    perform { store, scope in if let discard { try store.discard(id: discard.id, scope: scope) } }; discard = nil; reload()
                }
            }
            .alert("Draft unavailable", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }
    }
    private func perform(_ operation: (SharedDraftStore, DraftScope) throws -> Void) {
        do {
            guard let storage, let scope = try storage.scope(), scope.account == account, scope.team == team else { throw SharedDraftStore.Failure.identityChanged }
            try operation(storage, scope)
        } catch { self.error = error.localizedDescription }
    }
    private func reload() { perform { store, scope in drafts = try store.list(scope: scope) } }
}

private struct SharedDraftEditor: View {
    let draft: SavedDraft
    let account: String
    let team: String
    var onImport: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                TextEditor(text: $text).frame(minHeight: 180).accessibilityLabel("Draft text")
                ForEach(draft.files) { file in Label(file.name, systemImage: "doc") }
                Text("Use in composer does not send anything. Choose runtime and review the content before tapping Send.").font(.footnote)
                Button("Use in new agent") { use() }
            }
            .navigationTitle("Review share")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onAppear { text = draft.text }
            .onChange(of: text) { _, _ in
                do {
                    guard let store = SharedDraftStore.applicationGroup(), let scope = try store.scope(), scope.account == account, scope.team == team else { throw SharedDraftStore.Failure.identityChanged }
                    try store.editShare(id: draft.id, scope: scope, text: text)
                } catch { self.error = error.localizedDescription }
            }
            .alert("Couldn't use draft", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
        }
    }
    private func use() {
        do {
            guard let store = SharedDraftStore.applicationGroup(), let scope = try store.scope(), scope.account == account, scope.team == team else { throw SharedDraftStore.Failure.identityChanged }
            // Import is atomic and refuses to overwrite an existing composer draft.
            try store.editShare(id: draft.id, scope: scope, text: text)
            try store.importShare(id: draft.id, scope: scope)
            onImport()
        } catch { self.error = error.localizedDescription }
    }
}
