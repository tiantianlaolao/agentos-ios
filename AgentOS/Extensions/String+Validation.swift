import Foundation

extension String {
    var isValidChinesePhone: Bool {
        let pattern = "^1[3-9]\\d{9}$"
        return range(of: pattern, options: .regularExpression) != nil
    }

    var isValidURL: Bool {
        guard let url = URL(string: self) else { return false }
        return url.scheme != nil && url.host != nil
    }

    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
