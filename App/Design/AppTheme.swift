import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.93, green: 0.31, blue: 0.17)
    static let secondary = Color(red: 0.20, green: 0.47, blue: 0.51)

    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.18, green: 0.09, blue: 0.14),
            Color(red: 0.53, green: 0.16, blue: 0.15),
            Color(red: 0.93, green: 0.31, blue: 0.17),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static func artworkGradient(seed: String) -> LinearGradient {
        let value = seed.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        let hue = Double(abs(value % 255)) / 255
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.56, brightness: 0.72),
                Color(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.72, brightness: 0.34),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}
