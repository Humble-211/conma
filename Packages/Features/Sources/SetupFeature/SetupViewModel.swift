import Foundation
import Observation
import SwiftUI
import Domain

@Observable
@MainActor
public final class SetupViewModel {
    public var companyName = ""
    public var ownerName = ""
    public var currency: CurrencyCode = .cad
    public private(set) var isSaving = false
    public private(set) var errorKey: LocalizedStringKey?

    private let companyRepository: any CompanyRepository
    private let onCompleted: (CompanySetup) -> Void

    public init(companyRepository: any CompanyRepository, onCompleted: @escaping (CompanySetup) -> Void) {
        self.companyRepository = companyRepository
        self.onCompleted = onCompleted
    }

    public var canSubmit: Bool {
        !companyName.trimmingCharacters(in: .whitespaces).isEmpty && !ownerName.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    public func submit() async {
        guard canSubmit else { return }
        isSaving = true
        errorKey = nil
        defer { isSaving = false }
        let now = Date()
        let company = Company(id: UUID(), name: companyName.trimmingCharacters(in: .whitespaces), currencyCode: currency, createdAt: now, updatedAt: now, deletedAt: nil)
        let owner = User(id: UUID(), companyId: company.id, displayName: ownerName.trimmingCharacters(in: .whitespaces), email: nil, role: .owner, authUserId: nil, createdAt: now, updatedAt: now, deletedAt: nil)
        do {
            try await companyRepository.create(company: company, owner: owner)
            onCompleted(CompanySetup(company: company, owner: owner))
        } catch {
            errorKey = "setup.error"
        }
    }
}
