import SwiftUI

/// Parameters and result of one tool call — the "View details" FlowDown
/// opens from a tool row. Command tools get a terminal-style result.
struct ToolDetailSheet: View {
    let part: ChatPart.ToolPart
    @Environment(\.dismiss) private var dismiss

    private var isCommand: Bool { part.isCommandTool }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header

                    if isCommand, let command = part.input?["command"]?.stringValue {
                        section("Command") { code(command) }
                        if let out = part.output {
                            let stdout = out["stdout"]?.stringValue ?? ""
                            let stderr = out["stderr"]?.stringValue ?? ""
                            let exit = out["exitCode"]?.numberValue.map { Int($0) }
                            if !stdout.isEmpty { section("Output") { code(stdout) } }
                            if !stderr.isEmpty { section("Errors") { code(stderr, tint: .red) } }
                            if let exit { section("Exit code") { Text("\(exit)").font(Theme.Text.mono(.footnote)) } }
                            if stdout.isEmpty, stderr.isEmpty, exit == nil { section("Result") { code(out.prettyPrinted) } }
                        }
                    } else {
                        if let input = part.input { section("Parameters") { code(input.prettyPrinted) } }
                        if let output = part.output { section("Result") { code(output.prettyPrinted) } }
                    }
                    if let error = part.errorText { section("Error") { code(error, tint: .red) } }
                }
                .padding(16)
            }
            .background(Theme.chatCanvas)
            .navigationTitle(part.kindLabel)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .tint(Theme.heading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(part.displayLabel).font(Theme.Text.body.weight(.semibold)).foregroundStyle(Theme.heading)
            Text("\(part.kindLabel) · \(part.state.rawValue.replacingOccurrences(of: "-", with: " "))").font(Theme.Text.caption).foregroundStyle(Theme.muted)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(Theme.Text.micro.weight(.semibold)).kerning(0.4).foregroundStyle(Theme.muted)
            content()
        }
    }

    private func code(_ text: String, tint: Color? = nil) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(text)
                .font(Theme.Text.mono(.caption))
                .foregroundStyle(tint ?? Theme.heading)
                .textSelection(.enabled)
                .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.chatSurface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
