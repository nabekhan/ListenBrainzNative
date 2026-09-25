import SwiftUI

/// Presents only destinations already included in ListenBrainz metadata. The
/// actions open a selected service; they do not claim to play or resolve audio.
struct ExternalMediaDestinationButton: View {
    let links: [ExternalMediaLink]

    var body: some View {
        if let link = links.only {
            Link(destination: link.url) {
                Label(link.actionTitle, systemImage: "arrow.up.right.square")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 13))
            .tint(AppTheme.accent)
            .accessibilityHint(link.accessibilityHint)
        } else if !links.isEmpty {
            Menu {
                ExternalMediaDestinationActions.linkItems(links)
            } label: {
                Label("Listen elsewhere", systemImage: "arrow.up.right.square")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 13))
            .tint(AppTheme.accent)
            .accessibilityHint("Choose a service to open in another app or browser")
        }
    }
}

@MainActor
enum ExternalMediaDestinationActions {
    /// A single action stays direct. Multiple actions form one submenu when
    /// embedded in a context menu so they do not crowd recording actions.
    @ViewBuilder
    static func menuItems(_ links: [ExternalMediaLink]) -> some View {
        if let link = links.only {
            linkItem(link)
        } else if !links.isEmpty {
            Menu {
                linkItems(links)
            } label: {
                Label("Listen elsewhere", systemImage: "arrow.up.right.square")
            }
        }
    }

    @ViewBuilder
    static func linkItems(_ links: [ExternalMediaLink]) -> some View {
        ForEach(links, id: \.url) { link in
            linkItem(link)
        }
    }

    private static func linkItem(_ link: ExternalMediaLink) -> some View {
        Link(destination: link.url) {
            Label(link.actionTitle, systemImage: "arrow.up.right.square")
        }
        .accessibilityHint(link.accessibilityHint)
    }
}

private extension Array {
    var only: Element? { count == 1 ? first : nil }
}
