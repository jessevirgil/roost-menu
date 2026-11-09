import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    var body: some View { SettingsForm(auth: state.auth) }
}

private struct SettingsForm: View {
    @ObservedObject var auth: AuthManager
    @State private var pasted = ""
    @State private var busy = false
    @State private var message: String?
    @State private var messageIsError = false
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch Roost Menu at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            launchError = nil
                        } catch {
                            launchError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let launchError { Text(launchError).font(.caption).foregroundStyle(.red) }
                Text("Works best when the app is in your Applications folder.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("1 · Your Google project") {
                TextField("Device Access Project ID", text: $auth.projectID, prompt: Text("e.g. 32c4c2bc-fe0d-461b-b51c-f3885afff2f0"))
                TextField("OAuth Client ID", text: $auth.clientID, prompt: Text("ends in .apps.googleusercontent.com"))
                HStack {
                    SecureField("OAuth Client Secret", text: $auth.clientSecret)
                    Button("Paste") { if let s = NSPasteboard.general.string(forType: .string) { auth.clientSecret = s.trimmed } }
                }
                Text("New here? SETUP.md walks through creating these three values (about 15 minutes, one-time $5 Google fee). The secret is stored in your Mac’s Keychain. The Project ID is the UUID from the Device Access console, not the Google Cloud project name.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("2 · Sign in") {
                if auth.isSignedIn {
                    Label("Signed in", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                    Button("Sign out") { auth.signOut(); message = nil }
                } else {
                    Button("Open Google sign-in in my browser") { auth.openSignIn() }
                        .disabled(!auth.isConfigured)
                    Text("Approve access to your devices. Google then sends you to google.com. Copy the **entire address** from the browser’s address bar and paste it below. (If you get “Google hasn’t verified this app”, click Advanced → Go to … (unsafe). That’s expected for your own project.)")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        TextField("Pasted address", text: $pasted, prompt: Text("https://www.google.com/?code=…"))
                        Button("Paste") { if let s = NSPasteboard.general.string(forType: .string) { pasted = s } }
                    }
                    Button("Finish sign-in") {
                        busy = true
                        Task {
                            do {
                                try await auth.finishSignIn(pasted: pasted)
                                pasted = ""
                                message = "Signed in."; messageIsError = false
                            } catch {
                                message = error.localizedDescription; messageIsError = true
                            }
                            busy = false
                        }
                    }
                    .disabled(pasted.trimmed.isEmpty || busy)
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(messageIsError ? .red : .green)
                }
            }

            Section("About") {
                Text("Polls every 45 seconds. Streams are extended automatically every few minutes. If Google signs you out about once a week, your Google OAuth app is still in *Testing* mode. Publishing it to production stops that (see “The 7-day sign-out” in SETUP.md). Roost Menu is an independent project, not affiliated with Google.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 640)
        .onChange(of: auth.projectID) { _, _ in auth.saveCredentials() }
        .onChange(of: auth.clientID) { _, _ in auth.saveCredentials() }
    }
}
