import Foundation
import SwiftData

struct AgentExpensePatch: Codable, Equatable {
    var id: UUID
    var updatedAt: Date?
    var categoryName: String?
    var status: ExpenseStatus?
    var paymentAccount: String?
    var paymentMethod: String?
    var vendorName: String?
    var clientName: String?
    var projectName: String?
    var isBillable: Bool?
    var isReimbursable: Bool?
    var note: String?
}

struct AgentReceiptMatchPatch: Codable, Equatable {
    var expenseID: UUID
    var receiptAttachmentID: UUID
    var updatedAt: Date?
}

struct AgentDuplicateResolutionPatch: Codable, Equatable {
    var duplicateExpenseID: UUID
    var action: String
    var updatedAt: Date?
}

struct AgentVendorRulePatch: Codable, Equatable {
    var merchantPattern: String
    var categoryName: String
    var taxBucket: String
}

struct AgentDraftExpensePatch: Codable, Equatable {
    var receiptAttachmentID: UUID
}

enum AgentProposalService {
    @MainActor
    @discardableResult
    static func syncProposalFiles(context: ModelContext) throws -> Int {
        try AgentWorkspaceService.ensureWorkspace()
        var changedCount = 0
        for payload in try filePayloads() {
            if try upsert(payload: payload, context: context) {
                changedCount += 1
            }
        }
        if changedCount > 0 {
            try context.save()
        }
        return changedCount
    }

    static func write(payload: AgentProposalPayload) throws {
        try AgentWorkspaceService.ensureWorkspace()
        let url = try proposalURL(for: payload.id)
        try JSONEncoder.agentEncoder.encode(payload).write(to: url, options: .atomic)
    }

    static func filePayloads() throws -> [AgentProposalPayload] {
        let directory = try AgentWorkspaceService.proposalsDirectory()
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }
        return try urls
            .map { try Data(contentsOf: $0) }
            .map { try JSONDecoder.agentDecoder.decode(AgentProposalPayload.self, from: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func payload(id: UUID) throws -> AgentProposalPayload {
        let url = try proposalURL(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw AgentWorkspaceError.proposalNotFound(id)
        }
        return try JSONDecoder.agentDecoder.decode(AgentProposalPayload.self, from: Data(contentsOf: url))
    }

    @MainActor
    @discardableResult
    static func upsert(payload: AgentProposalPayload, context: ModelContext) throws -> Bool {
        var descriptor = FetchDescriptor<AgentProposal>(
            predicate: #Predicate { proposal in
                proposal.id == payload.id
            }
        )
        descriptor.fetchLimit = 1

        if let existing = try context.fetch(descriptor).first {
            let didChange = existing.kind != payload.kind
                || existing.title != payload.title
                || existing.targetIDs != payload.targetIDs
                || existing.beforeJSON != payload.beforeJSON
                || existing.afterJSON != payload.afterJSON
                || existing.reason != payload.reason
                || existing.confidence != payload.confidence
                || existing.risk != payload.risk
                || existing.status != payload.status
                || existing.runID != payload.runID
                || existing.sourceClient != payload.sourceClient
                || existing.createdAt != payload.createdAt
                || existing.reviewedAt != payload.reviewedAt
                || existing.validationSummary != payload.validationSummary
            guard didChange else { return false }

            existing.kind = payload.kind
            existing.title = payload.title
            existing.setTargetIDs(payload.targetIDs)
            existing.beforeJSON = payload.beforeJSON
            existing.afterJSON = payload.afterJSON
            existing.reason = payload.reason
            existing.confidence = payload.confidence
            existing.risk = payload.risk
            existing.status = payload.status
            existing.runID = payload.runID
            existing.sourceClient = payload.sourceClient
            existing.createdAt = payload.createdAt
            existing.reviewedAt = payload.reviewedAt
            existing.validationSummary = payload.validationSummary
            return true
        }

        context.insert(
            AgentProposal(
                id: payload.id,
                kind: payload.kind,
                title: payload.title,
                targetIDs: payload.targetIDs,
                beforeJSON: payload.beforeJSON,
                afterJSON: payload.afterJSON,
                reason: payload.reason,
                confidence: payload.confidence,
                risk: payload.risk,
                status: payload.status,
                runID: payload.runID,
                sourceClient: payload.sourceClient,
                createdAt: payload.createdAt,
                reviewedAt: payload.reviewedAt,
                validationSummary: payload.validationSummary
            )
        )
        return true
    }

    @MainActor
    @discardableResult
    static func apply(_ proposal: AgentProposal, context: ModelContext, reviewer: String = NSUserName()) throws -> String {
        guard proposal.status == .pending else {
            throw AgentWorkspaceError.validationFailed("Only pending proposals can be applied.")
        }

        let summary: String
        switch proposal.kind {
        case .classification, .expenseUpdate:
            summary = try applyExpenseUpdate(proposal, context: context)
        case .receiptMatch:
            summary = try applyReceiptMatch(proposal, context: context)
        case .duplicateResolution:
            summary = try applyDuplicateResolution(proposal, context: context)
        case .vendorRule:
            summary = try applyVendorRule(proposal, context: context)
        case .draftExpense:
            summary = try applyDraftExpense(proposal, context: context)
        case .backup:
            throw AgentWorkspaceError.unsupportedProposal("Backup proposals must be executed from Settings so the user chooses the destination.")
        case .auditPackage:
            throw AgentWorkspaceError.unsupportedProposal("Audit package proposals must be executed from Reports so the user chooses the destination and date range.")
        case .unknown:
            throw AgentWorkspaceError.unsupportedProposal("Unknown proposal kind cannot be applied.")
        }

        proposal.status = .accepted
        proposal.reviewedAt = Date()
        proposal.validationSummary = summary
        context.insert(
            AgentActionLog(
                proposalID: proposal.id,
                reviewer: reviewer,
                action: "accepted",
                validationResult: summary
            )
        )
        try context.save()
        try write(payload: AgentProposalPayload(proposal))
        _ = try? AgentSnapshotService.writeSnapshot(context: context)
        return summary
    }

    @MainActor
    static func reject(_ proposal: AgentProposal, context: ModelContext, reviewer: String = NSUserName()) throws {
        proposal.status = .rejected
        proposal.reviewedAt = Date()
        proposal.validationSummary = "Rejected by reviewer."
        context.insert(
            AgentActionLog(
                proposalID: proposal.id,
                reviewer: reviewer,
                action: "rejected",
                validationResult: proposal.validationSummary
            )
        )
        try context.save()
        try write(payload: AgentProposalPayload(proposal))
        _ = try? AgentSnapshotService.writeSnapshot(context: context)
    }

    private static func proposalURL(for id: UUID) throws -> URL {
        try AgentWorkspaceService.proposalsDirectory()
            .appendingPathComponent("\(id.uuidString).json")
    }

    @MainActor
    private static func applyExpenseUpdate(_ proposal: AgentProposal, context: ModelContext) throws -> String {
        let before = try decodeOptionalPatch(AgentExpensePatch.self, from: proposal.beforeJSON)
        let after = try decodePatch(AgentExpensePatch.self, from: proposal.afterJSON)
        let expense = try fetchExpense(id: after.id, context: context)

        if let before {
            try validateExpense(before: before, current: expense)
        } else {
            throw AgentWorkspaceError.validationFailed("Expense update proposals must include beforeJSON for stale-change validation.")
        }

        if let categoryName = after.categoryName {
            expense.categoryName = clean(categoryName)
        }
        if let status = after.status {
            expense.status = status
        }
        if let paymentAccount = after.paymentAccount {
            expense.paymentAccount = clean(paymentAccount)
        }
        if let paymentMethod = after.paymentMethod {
            expense.paymentMethod = clean(paymentMethod)
        }
        if let vendorName = after.vendorName {
            expense.vendorName = clean(vendorName)
        }
        if let clientName = after.clientName {
            expense.clientName = clean(clientName)
        }
        if let projectName = after.projectName {
            expense.projectName = ExpenseLedger.isCompanyProjectName(projectName) ? "" : clean(projectName)
        }
        if let isBillable = after.isBillable {
            expense.isBillable = isBillable
        }
        if let isReimbursable = after.isReimbursable {
            expense.isReimbursable = isReimbursable
        }
        if let note = after.note {
            expense.note = clean(note)
        }
        expense.updatedAt = Date()
        return "Applied expense proposal to \(expense.merchant)."
    }

    @MainActor
    private static func applyReceiptMatch(_ proposal: AgentProposal, context: ModelContext) throws -> String {
        let before = try decodeOptionalPatch(AgentReceiptMatchPatch.self, from: proposal.beforeJSON)
        let after = try decodePatch(AgentReceiptMatchPatch.self, from: proposal.afterJSON)
        let expense = try fetchExpense(id: after.expenseID, context: context)
        let receipt = try fetchReceipt(id: after.receiptAttachmentID, context: context)

        if let before, let updatedAt = before.updatedAt, expense.updatedAt != updatedAt {
            throw AgentWorkspaceError.staleProposal("Expense changed after this receipt-match proposal was created.")
        }
        guard receipt.expenseID == nil || receipt.expenseID == expense.id else {
            throw AgentWorkspaceError.validationFailed("Receipt is already linked to a different expense.")
        }

        ReceiptVault.link(attachment: receipt, to: expense)
        return "Linked \(receipt.originalFilename) to \(expense.merchant)."
    }

    @MainActor
    private static func applyDuplicateResolution(_ proposal: AgentProposal, context: ModelContext) throws -> String {
        let before = try decodeOptionalPatch(AgentDuplicateResolutionPatch.self, from: proposal.beforeJSON)
        let after = try decodePatch(AgentDuplicateResolutionPatch.self, from: proposal.afterJSON)
        let duplicate = try fetchExpense(id: after.duplicateExpenseID, context: context)

        if let before, let updatedAt = before.updatedAt, duplicate.updatedAt != updatedAt {
            throw AgentWorkspaceError.staleProposal("Duplicate candidate changed after this proposal was created.")
        }
        guard after.action == "ignore" || after.action == "archive" || after.action == "supersede" else {
            throw AgentWorkspaceError.validationFailed("Duplicate proposals may only ignore, archive, or supersede.")
        }

        duplicate.status = .ignored
        duplicate.updatedAt = Date()
        return "Marked duplicate candidate \(duplicate.merchant) ignored."
    }

    @MainActor
    private static func applyVendorRule(_ proposal: AgentProposal, context: ModelContext) throws -> String {
        let patch = try decodePatch(AgentVendorRulePatch.self, from: proposal.afterJSON)
        let merchantPattern = clean(patch.merchantPattern)
        let categoryName = clean(patch.categoryName)
        let taxBucket = clean(patch.taxBucket)
        guard !merchantPattern.isEmpty, !categoryName.isEmpty else {
            throw AgentWorkspaceError.validationFailed("Vendor rule proposals need merchantPattern and categoryName.")
        }

        let rules = try context.fetch(FetchDescriptor<VendorRule>())
        if let existing = rules.first(where: {
            $0.merchantPattern.compare(merchantPattern, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            existing.defaultCategoryName = categoryName
            existing.defaultTaxBucket = taxBucket
            existing.isArchived = false
        } else {
            context.insert(
                VendorRule(
                    merchantPattern: merchantPattern,
                    defaultCategoryName: categoryName,
                    defaultTaxBucket: taxBucket
                )
            )
        }
        return "Saved vendor rule for \(merchantPattern)."
    }

    @MainActor
    private static func applyDraftExpense(_ proposal: AgentProposal, context: ModelContext) throws -> String {
        let patch = try decodePatch(AgentDraftExpensePatch.self, from: proposal.afterJSON)
        let receipt = try fetchReceipt(id: patch.receiptAttachmentID, context: context)
        let rules = try context.fetch(FetchDescriptor<VendorRule>())
        guard let expense = ReceiptVault.createDraftExpense(from: receipt, context: context, vendorRules: rules) else {
            throw AgentWorkspaceError.validationFailed("Receipt cannot create a draft expense because it is linked or missing an extracted amount.")
        }
        return "Created draft expense for \(expense.merchant)."
    }

    @MainActor
    private static func validateExpense(before: AgentExpensePatch, current: Expense) throws {
        if before.id != current.id {
            throw AgentWorkspaceError.validationFailed("Proposal beforeJSON references a different expense.")
        }
        if let updatedAt = before.updatedAt, current.updatedAt != updatedAt {
            throw AgentWorkspaceError.staleProposal("Expense changed after this proposal was created.")
        }
        if let categoryName = before.categoryName, categoryName != current.categoryName {
            throw AgentWorkspaceError.staleProposal("Expense category no longer matches the proposal beforeJSON.")
        }
        if let status = before.status, status != current.status {
            throw AgentWorkspaceError.staleProposal("Expense status no longer matches the proposal beforeJSON.")
        }
        if let paymentAccount = before.paymentAccount, paymentAccount != current.paymentAccount {
            throw AgentWorkspaceError.staleProposal("Expense account no longer matches the proposal beforeJSON.")
        }
        if let paymentMethod = before.paymentMethod, paymentMethod != current.paymentMethod {
            throw AgentWorkspaceError.staleProposal("Expense payment method no longer matches the proposal beforeJSON.")
        }
        if let projectName = before.projectName, projectName != current.projectName {
            throw AgentWorkspaceError.staleProposal("Expense project no longer matches the proposal beforeJSON.")
        }
    }

    @MainActor
    private static func fetchExpense(id: UUID, context: ModelContext) throws -> Expense {
        var descriptor = FetchDescriptor<Expense>(
            predicate: #Predicate { expense in
                expense.id == id
            }
        )
        descriptor.fetchLimit = 1
        guard let expense = try context.fetch(descriptor).first else {
            throw AgentWorkspaceError.validationFailed("Expense \(id.uuidString) was not found.")
        }
        return expense
    }

    @MainActor
    private static func fetchReceipt(id: UUID, context: ModelContext) throws -> ReceiptAttachment {
        var descriptor = FetchDescriptor<ReceiptAttachment>(
            predicate: #Predicate { receipt in
                receipt.id == id
            }
        )
        descriptor.fetchLimit = 1
        guard let receipt = try context.fetch(descriptor).first else {
            throw AgentWorkspaceError.validationFailed("Receipt \(id.uuidString) was not found.")
        }
        return receipt
    }

    private static func decodeOptionalPatch<T: Decodable>(_ type: T.Type, from json: String) throws -> T? {
        let cleanJSON = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanJSON.isEmpty, cleanJSON != "{}" else { return nil }
        return try decodePatch(type, from: cleanJSON)
    }

    private static func decodePatch<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw AgentWorkspaceError.invalidProposal
        }
        do {
            return try JSONDecoder.agentDecoder.decode(T.self, from: data)
        } catch {
            throw AgentWorkspaceError.validationFailed("Proposal JSON did not match the expected \(T.self) shape.")
        }
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
