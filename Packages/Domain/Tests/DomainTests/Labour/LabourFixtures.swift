import Foundation
@testable import Domain

enum Lab {
    static func employee(_ name: String, rate: String?, hourly: String? = nil, deleted: Bool = false, createdAt: Date = Fx.now) -> Employee {
        Employee(id: UUID(), companyId: Fx.companyId, name: name, phone: nil, role: nil, trade: nil, hourlyRate: hourly.map { Fx.moneyS($0) },
                 dailyRate: rate.map { Fx.moneyS($0) }, certifications: nil, emergencyContact: nil, notes: nil,
                 createdAt: createdAt, updatedAt: createdAt, deletedAt: deleted ? Fx.now : nil)
    }

    static func entry(_ project: Project, _ employee: Employee, days: String, rate: String, on day: String, createdAt: Date = Fx.now, deletedAt: Date? = nil) -> LabourEntry {
        LabourEntry(id: UUID(), companyId: Fx.companyId, projectId: project.id, employeeId: employee.id, workDate: CalendarDate(storage: day)!,
                    days: Decimal(string: days)!, dailyRate: Fx.moneyS(rate), notes: nil, createdAt: createdAt, updatedAt: createdAt, deletedAt: deletedAt)
    }

    /// Spec §4 seed crew and Basement labour (today = 2026-10-03).
    struct Seed {
        let project = Fx.project("Basement Renovation", customer: Fx.customer("Ann Lee"), status: .inProgress, contract: 38_000, progress: 65, start: -18, end: 27)
        let mike = Lab.employee("Mike", rate: "250.00", hourly: "31.25")
        let john = Lab.employee("John", rate: "220.00")
        let david = Lab.employee("David", rate: "200.00")
        var entries: [LabourEntry] {
            [Lab.entry(project, mike, days: "8", rate: "250.00", on: "2026-09-23"),
             Lab.entry(project, john, days: "10", rate: "220.00", on: "2026-09-24"),
             Lab.entry(project, david, days: "7", rate: "200.00", on: "2026-09-25")]
        }
    }
}
