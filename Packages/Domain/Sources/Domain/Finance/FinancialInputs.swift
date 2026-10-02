public struct FinancialInputs: Sendable {
    public var project: Project
    public var estimateLines: [ProjectEstimateLine]
    public var expenses: [Expense]
    public var labourEntries: [LabourEntry]
    public var payments: [Payment]
    /// Always zero until change orders ship; kept in the formula so it never changes shape.
    public var approvedChangeOrders: Money

    public init(project: Project, estimateLines: [ProjectEstimateLine], expenses: [Expense], labourEntries: [LabourEntry], payments: [Payment], approvedChangeOrders: Money) {
        self.project = project; self.estimateLines = estimateLines; self.expenses = expenses
        self.labourEntries = labourEntries; self.payments = payments; self.approvedChangeOrders = approvedChangeOrders
    }
}
