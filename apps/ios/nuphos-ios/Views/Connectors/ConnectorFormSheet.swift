import SwiftUI

/// The credential form for a connector that binds by POSTing fields (a token,
/// a URL, a role ARN). The fields come from the catalog row, so this screen
/// never needs to know which provider it is showing.
struct ConnectorFormSheet: View {
    let connector: Connector
    let teamId: String
    /// Called once the bind lands, so the catalog sheet can close behind us.
    var onBound: () -> Void

    @Environment(ConnectorsStore.self) private var connectors
    @Environment(\.dismiss) private var dismiss
    @State private var values: [String: String] = [:]

    private var fields: [Connector.Field] {
        if case .form(_, let fields) = connector.bind { return fields }
        return []
    }

    private var isSubmitting: Bool { connectors.connecting == connector.key }

    /// Required fields filled. The backend does the real validation — this
    /// only stops an obviously empty submit.
    private var canSubmit: Bool {
        fields.allSatisfy { !$0.required || !trimmed($0).isEmpty }
    }

    var body: some View {
        Form {
            Section {
                ForEach(fields) { field in
                    FieldRow(field: field, text: binding(for: field))
                }
            } footer: {
                if let note = connector.note {
                    Text(note).font(.system(size: 12)).foregroundStyle(Theme.muted)
                }
            }
            .listRowBackground(Theme.surface)

            Section {
                Button {
                    submit()
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting {
                            ProgressView().controlSize(.small).tint(Theme.muted)
                        } else {
                            Text("Connect").font(.system(size: 15, weight: .medium))
                        }
                        Spacer()
                    }
                }
                .disabled(!canSubmit || isSubmitting)
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.canvas)
        .navigationTitle(connector.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func trimmed(_ field: Connector.Field) -> String {
        (values[field.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func binding(for field: Connector.Field) -> Binding<String> {
        Binding(get: { values[field.key] ?? "" }, set: { values[field.key] = $0 })
    }

    private func submit() {
        // `.strict()` on the backend schemas rejects unknown keys and blank
        // optionals alike, so only non-empty fields go in the body.
        var body: [String: String] = [:]
        for field in fields {
            let value = trimmed(field)
            if !value.isEmpty { body[field.key] = value }
        }
        Task {
            if await connectors.connect(connector, teamId: teamId, fields: body) {
                dismiss()
                onBound()
            }
        }
    }
}

private struct FieldRow: View {
    let field: Connector.Field
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(field.title).font(.system(size: 12)).foregroundStyle(Theme.muted)
                if !field.required {
                    Text("optional").font(.system(size: 11)).foregroundStyle(Theme.muted.opacity(0.7))
                }
            }
            input
                .font(.system(size: 15))
                .foregroundStyle(Theme.heading)
                .autocorrectionDisabled()
                #if os(iOS)
                .textInputAutocapitalization(.never)
                #endif
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var input: some View {
        switch field.kind {
        case .secret:
            SecureField(field.placeholder.isEmpty ? field.title : field.placeholder, text: $text)
        case .url:
            TextField(field.placeholder.isEmpty ? field.title : field.placeholder, text: $text)
                #if os(iOS)
                .keyboardType(.URL)
                #endif
        case .email:
            TextField(field.placeholder.isEmpty ? field.title : field.placeholder, text: $text)
                #if os(iOS)
                .keyboardType(.emailAddress)
                #endif
        case .text:
            TextField(field.placeholder.isEmpty ? field.title : field.placeholder, text: $text)
        }
    }
}
