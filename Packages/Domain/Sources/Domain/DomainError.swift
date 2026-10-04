public enum DomainError: Error, Equatable, Sendable {
    case currencyMismatch
    case invalidPercentage
    case negativeAmount
    case invalidPaymentAmount
    case invalidProgress
    case invalidLabourDays
    case completionBeforeStart
    case customJobTypeRequired
    case customCategoryRequired
    case costGroupMismatch
    case categoryInUse
    case customerHasProjects
    case categoryHasExpenses
    case emptyName
    case emptyFieldKey
    case customerDeleted
    case crossCompany
    case notFound
    case duplicateName
    case tooManyReceiptPages
    case incompleteExpense
    case incompletePayment
    case incompleteLabour
}
