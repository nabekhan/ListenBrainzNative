import SwiftUI

struct SectionHeader: View {
    private let title: Text
    private let subtitle: Text?

    init(title: LocalizedStringResource, subtitle: LocalizedStringResource? = nil) {
        self.title = Text(title)
        self.subtitle = subtitle.map(Text.init)
    }

    init(title: LocalizedStringResource, verbatimSubtitle: String?) {
        self.title = Text(title)
        self.subtitle = verbatimSubtitle.map { Text(verbatim: $0) }
    }

    init(verbatimTitle: String, verbatimSubtitle: String? = nil) {
        self.title = Text(verbatim: verbatimTitle)
        self.subtitle = verbatimSubtitle.map { Text(verbatim: $0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            title
                .font(.title2.bold())
            if let subtitle {
                subtitle
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityAddTraits(.isHeader)
    }
}
