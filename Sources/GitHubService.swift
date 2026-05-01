import Foundation

@MainActor
final class GitHubService: ObservableObject {
    @Published var pullRequests: [PullRequest] = []
    @Published var lastRefreshed: Date? = nil
    @Published var isLoading = false
    @Published var errorMessage: String? = nil
    private var refreshTask: Task<Void, Never>?

    init() {
        refreshTask = Task {
            await fetchPRs()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(300))
                await fetchPRs()
            }
        }
    }

    private static let query = """
        query {
          search(query: "is:pr is:open author:@me archived:false", type: ISSUE, first: 50) {
            nodes {
              ... on PullRequest {
                id
                title
                number
                url
                createdAt
                isDraft
                mergeable
                reviewDecision
                repository {
                  nameWithOwner
                }
                commits(last: 1) {
                  nodes {
                    commit {
                      statusCheckRollup {
                        contexts(first: 100) {
                          nodes {
                            __typename
                            ... on CheckRun {
                              name
                              status
                              conclusion
                            }
                            ... on StatusContext {
                              context
                              state
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
        """

    private static let ghSearchPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"

    func fetchPRs() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let json = try await runGH()
            let response = try JSONDecoder().decode(GraphQLResponse.self, from: json)
            let decoder = ISO8601DateFormatter()
            pullRequests = response.data.search.nodes.map { $0.toPullRequest(dateParser: decoder) }
            lastRefreshed = Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runGH() async throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "api", "graphql", "-f", "query=\(Self.query)"]
        var environment = ProcessInfo.processInfo.environment
        if let path = environment["PATH"], !path.isEmpty {
            environment["PATH"] = "\(path):\(Self.ghSearchPath)"
        } else {
            environment["PATH"] = Self.ghSearchPath
        }
        process.environment = environment

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { _ in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                if process.terminationStatus != 0 {
                    let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                    let errMsg = String(data: errData, encoding: .utf8) ?? "gh command failed"
                    continuation.resume(
                        throwing: NSError(
                            domain: "GitHubService", code: Int(process.terminationStatus),
                            userInfo: [NSLocalizedDescriptionKey: errMsg]))
                } else {
                    continuation.resume(returning: data)
                }
            }
        }
    }
}
