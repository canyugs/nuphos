import SwiftUI

struct LoginView: View {
    @Environment(AuthSession.self) private var session
    @State private var email = ""
    @State private var credential = ""
    @State private var newPassword = ""
    @State private var usePassword = false
    @State private var setPassword = false
    @State private var codeSent = false
    @State private var busy = false
    @State private var error: String?
    @State private var resendAt = Date.distantPast

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image("NuphosMark").resizable().scaledToFit().frame(width: 64, height: 64)
                Text("Welcome to Nuphos").font(.largeTitle.bold())
                Text("Sign in with your email. New accounts are created after email verification.").foregroundStyle(Theme.muted)
                TextField("Email address", text: $email)
                    .textContentType(.emailAddress).autocorrectionDisabled()
                    #if os(iOS)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    #endif
                    .textFieldStyle(.roundedBorder).disabled(busy || codeSent)
                if usePassword {
                    SecureField("Password", text: $credential).textContentType(.password).textFieldStyle(.roundedBorder)
                } else if codeSent {
                    TextField("6-digit email code", text: $credential).textContentType(.oneTimeCode)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .textFieldStyle(.roundedBorder)
                    Text("Check your inbox. The code expires in 10 minutes.").font(.footnote)
                    Toggle("Set or reset my password", isOn: $setPassword)
                    if setPassword {
                        SecureField("New password (12–128 characters)", text: $newPassword).textContentType(.newPassword).textFieldStyle(.roundedBorder)
                    }
                }
                if let error { Text(error).foregroundStyle(.red) }
                else if case .signedOut(let message) = session.state, let message { Text(message).foregroundStyle(.red) }
                Button(busy ? "Please wait…" : usePassword || codeSent ? "Sign in" : "Send verification code") {
                    Task { await submit() }
                }.buttonStyle(.borderedProminent).disabled(busy || email.trimmingCharacters(in: .whitespaces).isEmpty)
                Button(usePassword ? "Use an email code / reset password" : "Use a password") {
                    usePassword.toggle(); codeSent = false; credential = ""; error = nil; setPassword = false
                }.disabled(busy)
                if codeSent {
                    Button("Use a different email") { codeSent = false; credential = ""; error = nil }.disabled(busy)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Button("Resend code") { Task { await sendCode() } }
                            .disabled(busy || context.date < resendAt)
                    }
                }
                HStack {
                    Link("Terms", destination: URL(string: "https://nuphos.ai/terms")!)
                    Link("Privacy policy", destination: URL(string: "https://nuphos.ai/privacy")!)
                }.font(.footnote)
                Text("By continuing, you agree to the Terms of Service.").font(.footnote).foregroundStyle(Theme.muted)
            }.padding(28).frame(maxWidth: 440).frame(maxWidth: .infinity)
        }.background(Theme.canvas)
    }

    private func submit() async {
        if !usePassword && !codeSent { await sendCode(); return }
        busy = true; error = nil
        defer { busy = false }
        do {
            try await session.emailSignIn(email: email, credential: credential, password: usePassword, newPassword: setPassword ? newPassword : nil)
        } catch { self.error = error.localizedDescription }
    }

    private func sendCode() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            let _: AccountAPI.OK = try await AccountAPI.request("email/request-code", method: "POST", body: ["email": email])
            codeSent = true; resendAt = .now.addingTimeInterval(60)
        } catch { self.error = error.localizedDescription }
    }
}
