import SwiftUI

struct AuthenticationView: View {
    @Bindable var session: SessionModel
    @State private var token = ""
    @State private var username = ""
    @State private var showsPublicProfile = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    hero
                    signInSection
                    Divider()
                    publicProfileSection
                    privacyNote
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Welcome")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(AppTheme.heroGradient)
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 48, weight: .semibold))
                    Spacer()
                    Text("Your music life,\nbeautifully native.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text("History, taste, discovery, and the people who listen like you.")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.82))
                }
                .foregroundStyle(.white)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 300)
        }
    }

    private var signInSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "Connect ListenBrainz", subtitle: "Use your personal token for private actions such as feedback and deleting listens.")

            SecureField("User token", text: $token)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(.background, in: .rect(cornerRadius: 13, style: .continuous))

            if let message = session.errorMessage {
                Label(message, systemImage: "exclamationmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await session.signIn(token: token) }
            } label: {
                HStack {
                    if session.isWorking { ProgressView().tint(.white) }
                    Text(session.isWorking ? "Checking token…" : "Continue")
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 13))
            .disabled(session.isWorking)

            Link(destination: URL(string: "https://listenbrainz.org/settings/")!) {
                Label("Find your token in ListenBrainz Settings", systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private var publicProfileSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation { showsPublicProfile.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Browse a public profile").font(.headline)
                        Text("No token required").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: showsPublicProfile ? "chevron.up" : "chevron.down")
                }
            }
            .buttonStyle(.plain)

            if showsPublicProfile {
                TextField("ListenBrainz username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(.background, in: .rect(cornerRadius: 13, style: .continuous))
                    .onSubmit { Task { await session.browsePublicProfile(username: username) } }
                Button("Browse Profile") {
                    Task { await session.browsePublicProfile(username: username) }
                }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var privacyNote: some View {
        Label {
            Text("Your token is stored only in this device’s Keychain. It is never written to logs, preferences, or source files.")
        } icon: {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(AppTheme.secondary)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
