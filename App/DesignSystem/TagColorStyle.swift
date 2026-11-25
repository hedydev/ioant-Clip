import SwiftUI

extension TagColor {
    var swiftUIColor: Color {
        switch self {
        case .gray: .gray
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .teal: .teal
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        }
    }
    var label: LocalizedStringKey {
        switch self {
        case .gray: "color.gray"
        case .red: "color.red"
        case .orange: "color.orange"
        case .yellow: "color.yellow"
        case .green: "color.green"
        case .teal: "color.teal"
        case .blue: "color.blue"
        case .purple: "color.purple"
        case .pink: "color.pink"
        }
    }
}
