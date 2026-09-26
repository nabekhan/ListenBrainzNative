import SwiftUI

struct AuthenticationView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var session: SessionModel
    @State private var token = ""
    @State private var username = ""
    @State private var showsPublicProfile = false
    @State private var showsWebSignIn = false

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
            .sheet(isPresented: $showsWebSignIn) {
                ListenBrainzWebSignInView(session: session)
            }
            .task {
                #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("-brainz-open-web-sign-in") {
                        showsWebSignIn = true
                    }
                #endif
            }
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
                        .font(
                            .system(
                                dynamicTypeSize.isAccessibilitySize ? .title : .largeTitle,
                                design: .rounded,
                                weight: .bold
                            )
                        )
                    Text("History, taste, discovery, and the people who listen like you.")
                        .font(dynamicTypeSize.isAccessibilitySize ? .body.weight(.semibold) : .headline)
                        .foregroundStyle(.white.opacity(0.82))
                }
                .foregroundStyle(.white)
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .frame(minHeight: 300)
        }
    }

    private var signInSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(
                title: "Connect ListenBrainz",
                subtitle: "Sign in to add feedback, pin tracks, manage playlists, and edit your listens."
            )

            Button {
                showsWebSignIn = true
            } label: {
                Label("Continue with MusicBrainz", systemImage: "person.crop.circle.badge.checkmark")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 13))
            .disabled(session.isWorking)
            .accessibilityIdentifier("continue-musicbrainz-sign-in")

            Text("Prefer a token? Paste it below.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SecureField("User token", text: $token)
                .textContentType(.password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(14)
                .background(
                    Color(.secondarySystemGroupedBackground),
                    in: .rect(cornerRadius: 13, style: .continuous)
                )

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
                    Text(session.isWorking ? "Checking token…" : "Continue with token")
                        .frame(maxWidth: .infinity)
                }
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 13))
            .disabled(session.isWorking || token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Link(destination: URL(string: "https://listenbrainz.org/settings/")!) {
                Label("Find your token in ListenBrainz settings", systemImage: "arrow.up.right")
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
                    .background(
                        Color(.secondarySystemGroupedBackground),
                        in: .rect(cornerRadius: 13, style: .continuous)
                    )
                    .onSubmit { Task { await session.browsePublicProfile(username: username) } }
                Button("Browse profile") {
                    Task { await session.browsePublicProfile(username: username) }
                }
                    .buttonStyle(.bordered)
            }
        }
    }

    private var privacyNote: some View {
        Label {
            Text("Your token stays in this device’s Keychain and is sent only to ListenBrainz.")
        } icon: {
            Image(systemName: "lock.shield.fill")
                .foregroundStyle(AppTheme.secondary)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}
