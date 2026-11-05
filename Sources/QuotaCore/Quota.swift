import Foundation

public enum BadgeLevel: Sendable {
    case unknown, healthy, caution, low
}

public struct QuotaWindow: Decodable, Sendable {
    public let windowDurationMins: Int?
    private let usedPercent: Double?
    private let resetsAt: Double?

    public var usagePercent: Int? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        return Int(min(100, max(0, usedPercent)).rounded())
    }

    public var remainingPercent: Int? { usagePercent.map { 100 - $0 } }
    public var resetAt: Date? { resetsAt.map(Date.init(timeIntervalSince1970:)) }

    public var title: String {
        switch windowDurationMins {
        case 300: "5 小时额度"
        case 10_080: "周额度"
        case let minutes? where minutes > 0 && minutes.isMultiple(of: 1_440): "\(minutes / 1_440) 天额度"
        case let minutes? where minutes > 0 && minutes.isMultiple(of: 60): "\(minutes / 60) 小时额度"
        case let minutes? where minutes > 0: "\(minutes) 分钟额度"
        default: "套餐额度"
        }
    }
}

public struct QuotaGroup: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let windows: [QuotaWindow]
}

public struct ResetCredit: Decodable, Identifiable, Sendable {
    public let id: String
    private let expiresAt: Double?
    private let resetType: String?
    private let serverTitle: String?

    private enum CodingKeys: String, CodingKey {
        case id, expiresAt, resetType
        case serverTitle = "title"
    }

    public var expiration: Date? { expiresAt.map(Date.init(timeIntervalSince1970:)) }

    public var title: String {
        if serverTitle?.lowercased() == "full reset" { return "完全重置" }
        if let serverTitle, !serverTitle.isEmpty { return serverTitle }
        return resetType == "codexRateLimits" ? "完全重置" : "用量重置"
    }
}

public struct QuotaSnapshot: Decodable, Sendable {
    public let groups: [QuotaGroup]
    public let resetCount: Int?
    public let resetCredits: [ResetCredit]?
    public let extraCredits: String?

    public var badgeText: String {
        let windows = groups.first?.windows ?? []
        let fiveHour = windows.first { $0.windowDurationMins == 300 }?.remainingPercent
        let weekly = windows.first { $0.windowDurationMins == 10_080 }?.remainingPercent
        if let fiveHour, let weekly { return "5h \(fiveHour)% · 周 \(weekly)%" }
        guard let remaining = weekly ?? windows.compactMap(\.remainingPercent).first else {
            return "Codex —"
        }
        return "Codex \(remaining)%"
    }

    public var badgeLevel: BadgeLevel {
        guard let lowest = groups.flatMap(\.windows).compactMap(\.remainingPercent).min() else {
            return .unknown
        }
        if lowest > 50 { return .healthy }
        if lowest > 20 { return .caution }
        return .low
    }

    private struct Payload: Decodable {
        let rateLimits: Bucket?
        let rateLimitsByLimitId: [String: Bucket]?
        let rateLimitResetCredits: ResetCredits?
    }

    private struct Bucket: Decodable {
        let limitId: String?
        let limitName: String?
        let primary: QuotaWindow?
        let secondary: QuotaWindow?
        let credits: ExtraCredits?
    }

    private struct ResetCredits: Decodable {
        let availableCount: Int?
        let credits: [ResetCredit]?
    }

    private struct ExtraCredits: Decodable {
        let balance: String?
        let unlimited: Bool?
    }

    public init(from decoder: any Decoder) throws {
        let payload = try Payload(from: decoder)
        let mainID = payload.rateLimits?.limitId ?? "codex"
        var buckets = payload.rateLimitsByLimitId ?? [:]
        if buckets.isEmpty, let fallback = payload.rateLimits { buckets[mainID] = fallback }
        let orderedIDs = buckets.keys.sorted { lhs, rhs in
            if lhs == mainID { return rhs != mainID }
            if rhs == mainID { return false }
            return lhs < rhs
        }
        groups = orderedIDs.compactMap { id in
            guard let bucket = buckets[id] else { return nil }
            let windows = [bucket.primary, bucket.secondary].compactMap { $0 }.sorted {
                ($0.windowDurationMins ?? Int.max) < ($1.windowDurationMins ?? Int.max)
            }
            guard !windows.isEmpty else { return nil }
            let title = bucket.limitName.flatMap { $0.isEmpty ? nil : $0 } ?? (id == "codex" ? "Codex" : id)
            return QuotaGroup(id: id, title: title, windows: windows)
        }

        resetCount = payload.rateLimitResetCredits?.availableCount
        resetCredits = payload.rateLimitResetCredits?.credits?.sorted {
            ($0.expiration ?? .distantFuture, $0.id) < ($1.expiration ?? .distantFuture, $1.id)
        }
        let credits = payload.rateLimits?.credits ?? buckets[mainID]?.credits
        extraCredits = credits?.unlimited == true ? "不限" : credits?.balance
    }
}
