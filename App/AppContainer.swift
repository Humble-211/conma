import Foundation
import Observation
import Domain
import Data
import FeatureSupport

@Observable
@MainActor
final class AppContainer {
    struct Ready {
        let database: AppDatabase
        let companyRepository: any CompanyRepository
        let customerRepository: any CustomerRepository
        let projectRepository: any ProjectRepository
        let estimateRepository: any ProjectEstimateRepository
        let scheduleRepository: any PaymentScheduleRepository
        let insightsRepository: any InsightsRepository
        let activityLogRepository: any ActivityLogRepository
        let draftStore: any DraftStore
        let expenseRepository: any ExpenseRepository
        let categoryRepository: any CustomCategoryRepository
        let paymentRepository: any PaymentRepository
        let employeeRepository: any EmployeeRepository
        let labourRepository: any LabourRepository
        let captureMode: ReceiptCaptureMode
        let settings: AppSettings
        var setup: CompanySetup?
    }

    enum State {
        case loading
        case ready(Ready)
        case failed(Error)
    }

    private(set) var state: State = .loading
    let settings: AppSettings
    let options: LaunchOptions

    init(options: LaunchOptions = .parse()) {
        self.options = options
        let defaults: UserDefaults = options.isUITesting ? UserDefaults(suiteName: "ui-testing") ?? .standard : .standard
        if options.isUITesting { defaults.removePersistentDomain(forName: "ui-testing") }
        self.settings = AppSettings(defaults: defaults)
        if let locale = options.localeOverride { settings.language = locale == "vi" ? .vietnamese : .english }
        if let appearance = options.appearanceOverride { settings.appearance = appearance == "dark" ? .dark : .light }
        if options.isUITesting, let raw = options.todayOverride, let day = CalendarDate(storage: raw) { TodayProvider.override = day }
    }

    static var databaseURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appendingPathComponent("ConMa", isDirectory: true).appendingPathComponent("conma.sqlite")
    }

    func load() async {
        state = .loading
        do {
            let database = options.isUITesting ? try AppDatabase.inMemory() : try AppDatabase.onDisk(at: AppContainer.databaseURL)
            let clock = Clock.system
            let companies = GRDBCompanyRepository(database: database, clock: clock)
            let draftDirectory = options.isUITesting
                ? FileManager.default.temporaryDirectory.appendingPathComponent("conma-ui-drafts", isDirectory: true)
                : FileDraftStore.defaultDirectory()
            if options.isUITesting && !options.keepDrafts { try? FileManager.default.removeItem(at: draftDirectory) }
            let receiptStore: FileReceiptStore
            if options.isUITesting {
                // In-memory DB per launch → receipts in a throwaway folder, cleared on every launch. Never the real Application Support.
                receiptStore = FileReceiptStore(root: FileManager.default.temporaryDirectory.appendingPathComponent("conma-ui-receipts", isDirectory: true))
                try? FileManager.default.removeItem(at: receiptStore.root)
            } else {
                receiptStore = FileReceiptStore.applicationSupport()
            }
            var ready = Ready(database: database,
                              companyRepository: companies,
                              customerRepository: GRDBCustomerRepository(database: database, clock: clock),
                              projectRepository: GRDBProjectRepository(database: database, clock: clock),
                              estimateRepository: GRDBProjectEstimateRepository(database: database, clock: clock),
                              scheduleRepository: GRDBPaymentScheduleRepository(database: database, clock: clock),
                              insightsRepository: GRDBInsightsRepository(database: database),
                              activityLogRepository: GRDBActivityLogRepository(database: database),
                              draftStore: FileDraftStore(directory: draftDirectory),
                              expenseRepository: GRDBExpenseRepository(database: database, clock: clock, receiptStore: receiptStore),
                              categoryRepository: GRDBCustomCategoryRepository(database: database, clock: clock),
                              paymentRepository: GRDBPaymentRepository(database: database, clock: clock),
                              employeeRepository: GRDBEmployeeRepository(database: database, clock: clock),
                              labourRepository: GRDBLabourRepository(database: database, clock: clock),
                              captureMode: options.isUITesting && options.fakeScanner ? .fake : .live,
                              settings: settings,
                              setup: nil)
            #if DEBUG
            if options.seedSampleData {
                ready.setup = try await SampleData.seedIfEmpty(database, clock: clock, today: TodayProvider.today(timeZone: .current), receiptStore: receiptStore,
                                                                sampleReceipt: SampleReceipt.jpeg(vendor: "HOME DEPOT #7011", lines: [("2X4 SPF 8FT x 96", "2,016.00"), ("OSB 7/16 x 12", "384.00")], total: "2,712.00"))
            }
            #endif
            if ready.setup == nil { ready.setup = try await companies.current() }
            state = .ready(ready)
        } catch {
            state = .failed(error)
        }
    }

    func completeSetup(_ setup: CompanySetup) {
        guard case .ready(var ready) = state else { return }
        ready.setup = setup
        state = .ready(ready)
    }

    func retry() async { await load() }
}
