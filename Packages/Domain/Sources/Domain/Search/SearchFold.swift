import Foundation

public enum SearchFold {
    /// Case- and diacritic-insensitive normalization for user search; `đ/Đ` → `d` (not covered by diacriticInsensitive).
    public static func normalize(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "đ", with: "d")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
