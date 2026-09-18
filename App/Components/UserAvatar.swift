import SwiftUI

struct UserAvatar: View {
    let username: String
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            Circle().fill(AppTheme.artworkGradient(seed: username))
            Text(username.prefix(1).uppercased())
                .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
