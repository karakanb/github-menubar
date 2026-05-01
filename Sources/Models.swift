import Foundation

// MARK: - App Models

enum CheckStatus: Comparable {
    case success
    case pending
    case failure
    case noChecks

    var icon: String {
        switch self {
        case .success, .noChecks: "checkmark.circle.fill"
        case .failure: "xmark.circle.fill"
        case .pending: "clock.arrow.circlepath"
        }
    }

    var colorName: String {
        switch self {
        case .success: "green"
        case .failure: "red"
        case .pending: "orange"
        case .noChecks: "gray"
        }
    }
}

enum ReviewState {
    case required
    case approved
    case changesRequested
    case none

    var label: String {
        switch self {
        case .required: "Review required"
        case .approved: "Approved"
        case .changesRequested: "Changes requested"
        case .none: ""
        }
    }
}

enum PRCategory: Int, CaseIterable {
    case approved = 0
    case readyForReview = 1
    case needsAttention = 2
    case inProgress = 3
    case stale = 4

    var title: String {
        switch self {
        case .approved: "Ready to Merge"
        case .readyForReview: "Ready for Review"
        case .needsAttention: "Needs Attention"
        case .inProgress: "In Progress"
        case .stale: "Stale"
        }
    }
}

enum MergeableState {
    case mergeable
    case conflicting
    case unknown
}

struct PullRequest: Identifiable {
    let id: String
    let title: String
    let number: Int
    let url: String
    let repoName: String
    let isDraft: Bool
    let createdAt: Date
    let checkStatus: CheckStatus
    let reviewState: ReviewState
    let mergeableState: MergeableState

    var isStale: Bool {
        createdAt < Date.now.addingTimeInterval(-15 * 24 * 60 * 60)
    }

    var category: PRCategory {
        if isStale { return .stale }
        if mergeableState == .conflicting {
            return .needsAttention
        }
        if reviewState == .approved && checkStatus != .failure {
            return .approved
        }
        if isDraft || checkStatus == .pending {
            return .inProgress
        }
        if checkStatus == .failure || reviewState == .changesRequested {
            return .needsAttention
        }
        if reviewState == .required || reviewState == .none {
            return .readyForReview
        }
        return .inProgress
    }
}

// MARK: - GraphQL Response Types

struct GraphQLResponse: Decodable {
    let data: ResponseData
}

struct ResponseData: Decodable {
    let search: SearchResult
}

struct SearchResult: Decodable {
    let nodes: [PRNode]
}

struct PRNode: Decodable {
    let id: String
    let title: String
    let number: Int
    let url: String
    let createdAt: String
    let isDraft: Bool
    let mergeable: String
    let reviewDecision: String?
    let repository: Repository
    let commits: CommitConnection

    struct Repository: Decodable {
        let nameWithOwner: String
    }

    struct CommitConnection: Decodable {
        let nodes: [CommitNode]
    }

    struct CommitNode: Decodable {
        let commit: Commit
    }

    struct Commit: Decodable {
        let statusCheckRollup: StatusCheckRollup?
    }

    struct StatusCheckRollup: Decodable {
        let contexts: ContextConnection
    }

    struct ContextConnection: Decodable {
        let nodes: [ContextNode]
    }

    struct ContextNode: Decodable {
        let typeName: String
        // CheckRun fields
        let name: String?
        let status: String?
        let conclusion: String?
        // StatusContext fields
        let context: String?
        let state: String?

        enum CodingKeys: String, CodingKey {
            case typeName = "__typename"
            case name, status, conclusion
            case context, state
        }
    }

    func toPullRequest(dateParser: ISO8601DateFormatter) -> PullRequest {
        let checkStatus = resolveCheckStatus()
        let reviewState = resolveReviewState()
        let repoShortName = repository.nameWithOwner.components(separatedBy: "/").last
            ?? repository.nameWithOwner

        let mergeState: MergeableState = switch mergeable.uppercased() {
        case "MERGEABLE": .mergeable
        case "CONFLICTING": .conflicting
        default: .unknown
        }

        return PullRequest(
            id: id,
            title: title,
            number: number,
            url: url,
            repoName: repoShortName,
            isDraft: isDraft,
            createdAt: dateParser.date(from: createdAt) ?? .now,
            checkStatus: checkStatus,
            reviewState: reviewState,
            mergeableState: mergeState
        )
    }

    private func resolveCheckStatus() -> CheckStatus {
        guard let rollup = commits.nodes.first?.commit.statusCheckRollup else {
            return .noChecks
        }
        let contexts = rollup.contexts.nodes
        if contexts.isEmpty { return .noChecks }

        var hasFailure = false
        var hasPending = false

        for ctx in contexts {
            if ctx.typeName == "CheckRun" {
                if let conclusion = ctx.conclusion?.uppercased() {
                    switch conclusion {
                    case "FAILURE", "TIMED_OUT", "CANCELLED", "ACTION_REQUIRED":
                        hasFailure = true
                    case "SUCCESS", "NEUTRAL", "SKIPPED":
                        break
                    default:
                        break
                    }
                } else if let status = ctx.status?.uppercased(),
                    status == "IN_PROGRESS" || status == "QUEUED" || status == "WAITING"
                {
                    hasPending = true
                }
            } else if ctx.typeName == "StatusContext" {
                if let state = ctx.state?.uppercased() {
                    switch state {
                    case "FAILURE", "ERROR":
                        hasFailure = true
                    case "PENDING":
                        hasPending = true
                    case "SUCCESS":
                        break
                    default:
                        break
                    }
                }
            }
        }

        if hasFailure { return .failure }
        if hasPending { return .pending }
        return .success
    }

    private func resolveReviewState() -> ReviewState {
        guard let decision = reviewDecision?.uppercased() else {
            return .none
        }
        switch decision {
        case "APPROVED": return .approved
        case "CHANGES_REQUESTED": return .changesRequested
        case "REVIEW_REQUIRED": return .required
        default: return .none
        }
    }
}
