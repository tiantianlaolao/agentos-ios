import Foundation

extension Date {
    func chatDateLabel() -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return String(localized: "Today")
        } else if calendar.isDateInYesterday(self) {
            return String(localized: "Yesterday")
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: self)
        }
    }

    func chatTimeLabel() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    static func fromTimestamp(_ ms: Int) -> Date {
        Date(timeIntervalSince1970: Double(ms) / 1000.0)
    }
}
