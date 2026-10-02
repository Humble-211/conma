import SwiftUI
import Domain

public extension JobType {
    var titleKey: LocalizedStringKey { LocalizedStringKey("jobType.\(rawValue)") }
}

public extension CurrencyCode {
    var titleKey: LocalizedStringKey { LocalizedStringKey("currency.\(rawValue)") }
}
