import Foundation
import SwiftData

enum AgentRunStatus: String, Codable, CaseIterable, Identifiable {
    case running
    case completed
    case partial
    case blocked
    case failed

    var id: String { rawValue }
}

enum AgentProposalKind: String, Codable, CaseIterable, Identifiable {
    case classification
    case receiptMatch
    case duplicateResolution
    case vendorRule
    case draftExpense
    case backup
    case auditPackage
    case expenseUpdate
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .classification: "Classification"
        case .receiptMatch: "Receipt Match"
        case .duplicateResolution: "Duplicate Resolution"
        case .vendorRule: "Vendor Rule"
        case .draftExpense: "Draft Expense"
        case .backup: "Backup"
        case .auditPackage: "Audit Package"
        case .expenseUpdate: "Expense Update"
        case .unknown: "Unknown"
        }
    }
}

enum AgentProposalRisk: String, Codable, CaseIterable, Identifiable {
    case low
    case medium
    case high

    var id: String { rawValue }
}

enum AgentProposalStatus: String, Codable, CaseIterable, Identifiable {
    case pending
    case accepted
    case rejected
    case failed

    var id: String { rawValue }
}

@Model
final class AgentRun {
    var id: UUID = UUID()
    var sourceClient: String = ""
    var request: String = ""
    var status: AgentRunStatus = AgentRunStatus.running
    var startedAt: Date = Date()
    var completedAt: Date?
    var toolCallCount: Int = 0
    var summary: String = ""

    init(
        id: UUID = UUID(),
        sourceClient: String,
        request: String,
        status: AgentRunStatus = .running,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        toolCallCount: Int = 0,
        summary: String = ""
    ) {
        self.id = id
        self.sourceClient = sourceClient
        self.request = request
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.toolCallCount = toolCallCount
        self.summary = summary
    }
}

struct AgentToolCallPayload: Codable, Equatable, Identifiable {
    var id: UUID
    var toolName: String
    var status: String
    var calledAt: Date
    var summary: String

    init(
        id: UUID = UUID(),
        toolName: String,
        status: String,
        calledAt: Date = Date(),
        summary: String = ""
    ) {
        self.id = id
        self.toolName = toolName
        self.status = status
        self.calledAt = calledAt
        self.summary = summary
    }
}

struct AgentRunPayload: Codable, Equatable, Identifiable {
    var id: UUID
    var sourceClient: String
    var request: String
    var status: AgentRunStatus
    var startedAt: Date
    var completedAt: Date?
    var toolCallCount: Int
    var summary: String
    var toolCalls: [AgentToolCallPayload]

    init(
        id: UUID = UUID(),
        sourceClient: String,
        request: String = "",
        status: AgentRunStatus = .running,
        startedAt: Date = Date(),
        completedAt: Date? = nil,
        toolCallCount: Int = 0,
        summary: String = "",
        toolCalls: [AgentToolCallPayload] = []
    ) {
        self.id = id
        self.sourceClient = sourceClient
        self.request = request
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.toolCallCount = toolCallCount
        self.summary = summary
        self.toolCalls = toolCalls
    }
}

@Model
final class AgentProposal {
    var id: UUID = UUID()
    var kind: AgentProposalKind = AgentProposalKind.unknown
    var title: String = ""
    var targetIDsJSON: String = "[]"
    var beforeJSON: String = "{}"
    var afterJSON: String = "{}"
    var reason: String = ""
    var confidence: Double = 0
    var risk: AgentProposalRisk = AgentProposalRisk.medium
    var status: AgentProposalStatus = AgentProposalStatus.pending
    var runID: UUID?
    var sourceClient: String = ""
    var createdAt: Date = Date()
    var reviewedAt: Date?
    var validationSummary: String = ""

    init(
        id: UUID = UUID(),
        kind: AgentProposalKind,
        title: String,
        targetIDs: [String] = [],
        beforeJSON: String = "{}",
        afterJSON: String = "{}",
        reason: String = "",
        confidence: Double = 0,
        risk: AgentProposalRisk = .medium,
        status: AgentProposalStatus = .pending,
        runID: UUID? = nil,
        sourceClient: String = "",
        createdAt: Date = Date(),
        reviewedAt: Date? = nil,
        validationSummary: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.targetIDsJSON = AgentProposal.encodeTargetIDs(targetIDs)
        self.beforeJSON = beforeJSON
        self.afterJSON = afterJSON
        self.reason = reason
        self.confidence = confidence
        self.risk = risk
        self.status = status
        self.runID = runID
        self.sourceClient = sourceClient
        self.createdAt = createdAt
        self.reviewedAt = reviewedAt
        self.validationSummary = validationSummary
    }

    var targetIDs: [String] {
        (try? JSONDecoder().decode([String].self, from: Data(targetIDsJSON.utf8))) ?? []
    }

    func setTargetIDs(_ targetIDs: [String]) {
        targetIDsJSON = AgentProposal.encodeTargetIDs(targetIDs)
    }

    private static func encodeTargetIDs(_ targetIDs: [String]) -> String {
        guard let data = try? JSONEncoder().encode(targetIDs),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }
}

@Model
final class AgentActionLog {
    var id: UUID = UUID()
    var proposalID: UUID = UUID()
    var reviewer: String = ""
    var action: String = ""
    var validationResult: String = ""
    var createdAt: Date = Date()

    init(
        id: UUID = UUID(),
        proposalID: UUID,
        reviewer: String,
        action: String,
        validationResult: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.proposalID = proposalID
        self.reviewer = reviewer
        self.action = action
        self.validationResult = validationResult
        self.createdAt = createdAt
    }
}

struct AgentProposalPayload: Codable, Equatable, Identifiable {
    var id: UUID
    var kind: AgentProposalKind
    var title: String
    var targetIDs: [String]
    var beforeJSON: String
    var afterJSON: String
    var reason: String
    var confidence: Double
    var risk: AgentProposalRisk
    var status: AgentProposalStatus
    var runID: UUID?
    var sourceClient: String
    var createdAt: Date
    var reviewedAt: Date?
    var validationSummary: String

    init(
        id: UUID = UUID(),
        kind: AgentProposalKind,
        title: String,
        targetIDs: [String] = [],
        beforeJSON: String = "{}",
        afterJSON: String = "{}",
        reason: String = "",
        confidence: Double = 0,
        risk: AgentProposalRisk = .medium,
        status: AgentProposalStatus = .pending,
        runID: UUID? = nil,
        sourceClient: String = "",
        createdAt: Date = Date(),
        reviewedAt: Date? = nil,
        validationSummary: String = ""
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.targetIDs = targetIDs
        self.beforeJSON = beforeJSON
        self.afterJSON = afterJSON
        self.reason = reason
        self.confidence = confidence
        self.risk = risk
        self.status = status
        self.runID = runID
        self.sourceClient = sourceClient
        self.createdAt = createdAt
        self.reviewedAt = reviewedAt
        self.validationSummary = validationSummary
    }
}

extension AgentProposalPayload {
    init(_ proposal: AgentProposal) {
        self.init(
            id: proposal.id,
            kind: proposal.kind,
            title: proposal.title,
            targetIDs: proposal.targetIDs,
            beforeJSON: proposal.beforeJSON,
            afterJSON: proposal.afterJSON,
            reason: proposal.reason,
            confidence: proposal.confidence,
            risk: proposal.risk,
            status: proposal.status,
            runID: proposal.runID,
            sourceClient: proposal.sourceClient,
            createdAt: proposal.createdAt,
            reviewedAt: proposal.reviewedAt,
            validationSummary: proposal.validationSummary
        )
    }
}
