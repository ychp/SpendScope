import Foundation

enum TokenFormatter {
    static func compact(_ value: Int) -> String {
        switch value {
        case 1_000_000_000...:
            String(format: "%.1fB", Double(value) / 1_000_000_000)
        case 1_000_000...:
            String(format: "%.1fM", Double(value) / 1_000_000)
        case 1_000...:
            String(format: "%.1fK", Double(value) / 1_000)
        default:
            String(value)
        }
    }
}
