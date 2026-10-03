import Foundation
import GRDB
import Domain

enum RecordSupport {
    static func uuid(_ text: String, table: String, id: String, column: String) throws -> UUID {
        guard let value = UUID(uuidString: text) else { throw DataError.corruptRow(table: table, id: id, column: column) }
        return value
    }

    static func uuid(_ text: String?, table: String, id: String, column: String) throws -> UUID? {
        guard let text else { return nil }
        guard let value = UUID(uuidString: text) else { throw DataError.corruptRow(table: table, id: id, column: column) }
        return value
    }

    static func money(_ text: String, currency: CurrencyCode, table: String, id: String, column: String) throws -> Money {
        guard let value = Money(storage: text, currency: currency) else { throw DataError.corruptRow(table: table, id: id, column: column) }
        return value
    }

    static func date(_ text: String, table: String, id: String, column: String) throws -> Date {
        guard let value = Timestamps.date(text) else { throw DataError.corruptRow(table: table, id: id, column: column) }
        return value
    }

    static func date(_ text: String?, table: String, id: String, column: String) throws -> Date? {
        guard let text else { return nil }
        guard let value = Timestamps.date(text) else { throw DataError.corruptRow(table: table, id: id, column: column) }
        return value
    }

    static func calendarDate(_ text: String?, table: String, id: String, column: String) throws -> CalendarDate? {
        guard let text else { return nil }
        guard let value = CalendarDate(storage: text) else { throw DataError.corruptRow(table: table, id: id, column: column) }
        return value
    }

    static func decimal(_ text: String?, table: String, id: String, column: String) throws -> Decimal? {
        guard let text else { return nil }
        guard let value = Decimal(string: text, locale: nil) else { throw DataError.corruptRow(table: table, id: id, column: column) }
        return value
    }

    static func key(_ uuid: UUID) -> String { uuid.uuidString.lowercased() }
}

extension UUID {
    var dbKey: String { uuidString.lowercased() }
}
