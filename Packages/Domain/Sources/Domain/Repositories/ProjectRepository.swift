import Foundation

public struct ProjectSummary: Sendable, Hashable, Identifiable {
    public let project: Project
    public let customerName: String

    public var id: UUID { project.id }

    public init(project: Project, customerName: String) {
        self.project = project
        self.customerName = customerName
    }
}

public struct ProjectDetailSnapshot: Sendable, Hashable {
    public let project: Project
    public let customer: Customer
    public let estimateLines: [ProjectEstimateLine]
    public let scheduleItems: [PaymentScheduleItem]

    public init(project: Project, customer: Customer, estimateLines: [ProjectEstimateLine], scheduleItems: [PaymentScheduleItem]) {
        self.project = project
        self.customer = customer
        self.estimateLines = estimateLines
        self.scheduleItems = scheduleItems
    }
}

public protocol ProjectRepository: Sendable {
    func get(id: UUID) async throws -> Project?
    func list(companyId: UUID) async throws -> [Project]
    /// Live, non-deleted projects with customer name, ordered by updatedAt desc. Emits on every change.
    func observeSummaries(companyId: UUID) -> AsyncThrowingStream<[ProjectSummary], Error>
    /// Inserts project, scope fields, estimate lines, schedule items and the optional new customer in ONE transaction,
    /// with a single `projectCreated` activity row (+ `customerCreated` when a customer is created).
    func create(_ bundle: NewProjectBundle, actor: ActivityActor) async throws
    /// Live project + customer + lines + items; emits nil when the project is missing or soft-deleted.
    func observeDetail(id: UUID) -> AsyncThrowingStream<ProjectDetailSnapshot?, Error>
    /// Insert or update, including scope fields; writes activity log rows for creation,
    /// contract value, status and manual progress changes, in the same transaction.
    func save(_ project: Project, actor: ActivityActor) async throws
    /// Cascading soft delete per spec A.2.
    func softDelete(id: UUID, actor: ActivityActor) async throws
    /// Writes `statusChanged {from,to}` in the same transaction; same status → no write. Throws DomainError.notFound.
    func changeStatus(id: UUID, to status: ProjectStatus, actor: ActivityActor) async throws
    /// Writes `progressChanged {from,to}` ("" for nil); equal → no write. Validates 0…100.
    func setManualProgress(id: UUID, to value: Int?, actor: ActivityActor) async throws
    /// Customer must be live and in the same company; writes `customerChanged {from,to,fromId,toId}` (names).
    func changeCustomer(id: UUID, to customerId: UUID, actor: ActivityActor) async throws
}
