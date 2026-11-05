import Foundation
import Testing
@testable import QuotaCore

struct QuotaTests {
    @Test func readsWeeklyWindowAndResetsInExpiryOrder() throws {
        let snapshot = try decode("""
        {
          "rateLimits": {
            "primary": {"usedPercent":7,"windowDurationMins":10080,"resetsAt":1794279844},
            "secondary":null,"credits":{"hasCredits":false,"unlimited":false,"balance":"0"}
          },
          "rateLimitResetCredits":{"availableCount":2,"credits":[
            {"id":"later","title":"Full reset","status":"available","expiresAt":1796161251},
            {"id":"earlier","resetType":"codexRateLimits","status":"available","expiresAt":1796064931}
          ]}
        }
        """)
        let group = try #require(snapshot.groups.first)
        #expect(group.windows.map(\.title) == ["周额度"])
        #expect(group.windows.first?.resetAt == Date(timeIntervalSince1970: 1794279844))
        #expect(snapshot.badgeText == "Codex 93%")
        #expect(snapshot.badgeLevel == .healthy)
        #expect(snapshot.extraCredits == "0")
        #expect(snapshot.resetCount == 2)
        #expect(snapshot.resetCredits?.map(\.id) == ["earlier", "later"])
        #expect(snapshot.resetCredits?.first?.title == "完全重置")
    }

    @Test func prefersNamedBucketsAndUsesTheLowestRemainingWindowForColor() throws {
        let snapshot = try decode("""
        {
          "rateLimits":{"primary":{"usedPercent":7,"windowDurationMins":10080}},
          "rateLimitsByLimitId":{
            "codex":{"primary":{"usedPercent":18,"windowDurationMins":300},
                     "secondary":{"usedPercent":7,"windowDurationMins":10080}},
            "other":{"limitName":"GPT Special","primary":{"usedPercent":100,"windowDurationMins":300}}
          },
          "rateLimitResetCredits":{"availableCount":0,"credits":[]}
        }
        """)
        #expect(snapshot.groups.map(\.title) == ["Codex", "GPT Special"])
        #expect(snapshot.badgeText == "5h 82% · 周 93%")
        #expect(snapshot.badgeLevel == .low)
        #expect(snapshot.groups.last?.windows.first?.remainingPercent == 0)
        #expect(snapshot.resetCount == 0)
        #expect(snapshot.resetCredits?.isEmpty == true)
    }

    @Test func preservesUnknownValuesAndCountOnlyResults() throws {
        let unknown = try decode("""
        {"rateLimits":{"primary":{"windowDurationMins":10080}}}
        """)
        #expect(unknown.badgeText == "Codex —")
        #expect(unknown.badgeLevel == .unknown)
        #expect(unknown.extraCredits == nil)
        #expect(unknown.resetCount == nil)
        #expect(unknown.resetCredits == nil)

        let countOnly = try decode("""
        {"rateLimits":{"primary":{"usedPercent":50,"windowDurationMins":10080}},
         "rateLimitResetCredits":{"availableCount":2,"credits":null}}
        """)
        #expect(countOnly.badgeLevel == .caution)
        #expect(countOnly.resetCount == 2)
        #expect(countOnly.resetCredits == nil)
    }

    @Test func fallsBackWhenTheBucketMapIsEmpty() throws {
        let snapshot = try decode("""
        {"rateLimits":{"primary":{"usedPercent":0,"windowDurationMins":10080}},
         "rateLimitsByLimitId":{}}
        """)
        #expect(snapshot.badgeText == "Codex 100%")
    }

    private func decode(_ json: String) throws -> QuotaSnapshot {
        try JSONDecoder().decode(QuotaSnapshot.self, from: Data(json.utf8))
    }
}
