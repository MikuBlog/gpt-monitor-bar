import Darwin
import Foundation
import Testing
@testable import QuotaCore

struct AppServerTests {
    @Test func queriesThroughStdioAndSkipsNotifications() async throws {
        try await withServer(rateReply: validRateReply) { cli in
            let result = await CodexAppServer(executable: cli).fetch()
            #expect(result.account?.planType == "pro")
            let snapshot = try result.snapshot.get()
            #expect(snapshot.badgeText == "Codex 93%")
        }
    }

    @Test func launchesScriptsWithTheInstallDirectoryOnPATH() async throws {
        try await withServer(interpreter: "/usr/bin/env codex-test-interpreter", rateReply: validRateReply) { cli in
            try FileManager.default.createSymbolicLink(
                at: cli.deletingLastPathComponent().appending(path: "codex-test-interpreter"),
                withDestinationURL: URL(fileURLWithPath: "/bin/bash")
            )
            let result = await CodexAppServer(executable: cli).fetch()
            let snapshot = try result.snapshot.get()
            #expect(snapshot.badgeText == "Codex 93%")
        }
    }

    @Test func timesOutWhenServerStopsResponding() async throws {
        try await withServer(rateReply: "IFS= read -r unused") { cli in
            let result = await CodexAppServer(executable: cli, timeout: 3).fetch()
            #expect(result.account?.planType == "pro")
            #expect(throws: QuotaFailure.timedOut) { try result.snapshot.get() }
        }
    }

    @Test func cleansUpAStalledServerThatIgnoresTermination() async throws {
        let stall = """
        trap '' TERM
        printf '%s' "$$" > "${0%/*}/server.pid"
        while true; do /bin/sleep 0.1; done
        """
        try await withServer(rateReply: stall) { cli in
            let result = await CodexAppServer(executable: cli, timeout: 3).fetch()
            #expect(throws: QuotaFailure.timedOut) { try result.snapshot.get() }
            let pidFile = cli.deletingLastPathComponent().appending(path: "server.pid")
            let pid = try #require(Int32(String(contentsOf: pidFile, encoding: .utf8)))
            defer { if kill(pid, 0) == 0 { _ = kill(pid, SIGKILL) } }
            for _ in 0..<20 {
                if kill(pid, 0) != 0 { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            Issue.record("Stalled App Server was still running after the timeout")
        }
    }

    @Test @MainActor func retainsDataOnDisconnectAndRecoversOnNextRefresh() async throws {
        try await withServer(rateReply: validRateReply) { readyCLI in
            try await withServer(rateReply: "exit 0") { disconnectedCLI in
                var cli = readyCLI
                let store = QuotaStore { await CodexAppServer(executable: cli).fetch() }
                await store.refresh()
                let lastUpdate = try #require(store.updatedAt)
                cli = disconnectedCLI
                await store.refresh()
                #expect(store.failure == .disconnected)
                #expect(store.snapshot?.badgeText == "Codex 93%")
                #expect(store.updatedAt == lastUpdate)
                cli = readyCLI
                await store.refresh()
                #expect(store.failure == nil)
                #expect(store.snapshot?.badgeText == "Codex 93%")
            }
        }
    }

    @Test @MainActor func clearsOldSnapshotWhenNewAccountCannotFetchOrSignsOut() async throws {
        try await withServer(rateReply: validRateReply) { readyCLI in
            try await withServer(workspaceID: "second-workspace", rateReply: "exit 0") { switchedCLI in
                try await withServer(account: "null", rateReply: "exit 99") { signedOutCLI in
                    var cli = readyCLI
                    let store = QuotaStore { await CodexAppServer(executable: cli).fetch() }
                    await store.refresh()
                    #expect(store.snapshot != nil)
                    cli = switchedCLI
                    await store.refresh()
                    #expect(store.snapshot == nil)
                    #expect(store.updatedAt == nil)
                    cli = readyCLI
                    await store.refresh()
                    #expect(store.snapshot != nil)
                    cli = signedOutCLI
                    await store.refresh()
                    #expect(store.failure == .signInRequired)
                    #expect(store.snapshot == nil)
                }
            }
        }
    }

    @Test @MainActor func coalescesConcurrentRefreshAndSkipsFreshSnapshots() async throws {
        try await withServer(rateReply: "/bin/sleep 0.3\n" + validRateReply) { cli in
            var requests = 0
            let store = QuotaStore {
                requests += 1
                return await CodexAppServer(executable: cli).fetch()
            }
            async let first: Void = store.refresh()
            async let second: Void = store.refresh()
            _ = await (first, second)
            await store.refresh(maxAge: 10)
            #expect(requests == 1)
            #expect(store.snapshot?.badgeText == "Codex 93%")
        }
    }
}

private let validRateReply = """
printf '%s\\n' '{"method":"account/rateLimits/updated","params":{}}' '{"id":3,"result":{"accountId":"sample","rateLimits":{"primary":{"usedPercent":7,"windowDurationMins":10080}}}}'
"""

private func withServer(
    email: String = "first@example.com",
    workspaceID: String = "first-workspace",
    account: String? = nil,
    interpreter: String = "/bin/bash",
    rateReply: String,
    isolation: isolated (any Actor)? = #isolation,
    _ run: (URL) async throws -> Void
) async throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let executable = directory.appending(path: "codex")
    let accountJSON = account ?? #"{"type":"chatgpt","email":"\#(email)","planType":"pro"}"#
    let script = """
    #!\(interpreter)
    set -e
    [[ "$*" == 'app-server --listen stdio://' ]]
    IFS= read -r line; [[ "$line" == *'"initialize"'* ]]
    printf '%s\\n' '{"id":1,"result":{}}'
    IFS= read -r line; [[ "$line" == *'"initialized"'* ]]
    IFS= read -r line; [[ "$line" == *'"account/read"'* ]]
    printf '%s\\n' '{"id":2,"result":{"account":\(accountJSON),"workspaceRouting":{"chatgptAccountId":"\(workspaceID)"}}}'
    IFS= read -r line; [[ "$line" == *'"account/rateLimits/read"'* ]]
    \(rateReply)
    """
    try script.write(to: executable, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    try await run(executable)
}
