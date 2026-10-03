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
        let draftStore: any DraftStore
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
            var ready = Ready(database: database,
                              companyRepository: companies,
                              customerRepository: GRDBCustomerRepository(database: database, clock: clock),
                              projectRepository: GRDBProjectRepository(database: database, clock: clock),
                              estimateRepository: GRDBProjectEstimateRepository(database: database, clock: clock),
                              scheduleRepository: GRDBPaymentScheduleRepository(database: database, clock: clock),
                              draftStore: FileDraftStore(directory: draftDirectory),
                              setup: nil)
            #if DEBUG
            if options.seedSampleData {
                ready.setup = try await SampleData.seedIfEmpty(database, clock: clock, today: CalendarDate(Date(), timeZone: .current))
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
