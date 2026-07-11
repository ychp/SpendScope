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

    static func percentage(_ value: Double) -> String {
        let normalized = value.isFinite ? min(max(value, 0), 1) : 0
        return String(format: "%.1f%%", normalized * 100)
    }
}
