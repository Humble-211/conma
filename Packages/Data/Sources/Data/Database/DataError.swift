public enum DataError: Error, Equatable {
    case corruptRow(table: String, id: String, column: String)
    case notFound
}
