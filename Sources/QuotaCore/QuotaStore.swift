import Foundation
import Observation

public enum QuotaFailure: Error, Equatable, Sendable {
    case missingCLI, launchFailed, signInRequired, timedOut, disconnected, invalidResponse
    case requestFailed
}

public struct CodexAccount: Decodable, Sendable {
    let type: String
    let email: String?
    public let planType: String?
    var workspaceID: String? = nil

    func differs(from previous: Self?) -> Bool {
        guard let previous else { return false }
        if let workspaceID, let oldWorkspace = previous.workspaceID, workspaceID != oldWorkspace { return true }
        if let email, let oldEmail = previous.email, email != oldEmail { return true }
        if let planType, let oldPlan = previous.planType, planType != oldPlan { return true }
        return false
    }
}

public struct QuotaLookup: Sendable {
    public let account: CodexAccount?
    public let snapshot: Result<QuotaSnapshot, QuotaFailure>

    public static func failed(_ failure: QuotaFailure) -> Self {
        Self(account: nil, snapshot: .failure(failure))
    }
}

@MainActor @Observable
public final class QuotaStore {
    public private(set) var snapshot: QuotaSnapshot?
    public private(set) var updatedAt: Date?
    public private(set) var planType: String?
    public private(set) var failure: QuotaFailure?
    public private(set) var isRefreshing = false
    @ObservationIgnored private var lastAccount: CodexAccount?
    private let fetch: @MainActor () async -> QuotaLookup

    public init(fetch: @escaping @MainActor () async -> QuotaLookup) {
        self.fetch = fetch
    }

    public func refresh(maxAge: TimeInterval = 0) async {
        guard !isRefreshing else { return }
        if failure == nil, let updatedAt, Date.now.timeIntervalSince(updatedAt) < maxAge { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let result = await fetch()
        if let account = result.account {
            if account.differs(from: lastAccount) { clearSnapshot() }
            lastAccount = account
            planType = account.planType
        }

        switch result.snapshot {
        case let .success(snapshot):
            self.snapshot = snapshot
            updatedAt = .now
            failure = nil
        case let .failure(failure):
            if failure == .signInRequired {
                clearSnapshot()
                planType = nil
                lastAccount = nil
            }
            self.failure = failure
        }
    }

    private func clearSnapshot() {
        snapshot = nil
        updatedAt = nil
    }
}
