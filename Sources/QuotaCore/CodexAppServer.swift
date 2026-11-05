import Darwin
import Foundation

public struct CodexAppServer: Sendable {
    public let executable: URL
    public let timeout: TimeInterval

    public init(executable: URL, timeout: TimeInterval = 15) {
        self.executable = executable
        self.timeout = timeout
    }

    public func fetch() async -> QuotaLookup {
        await Task.detached(priority: .utility) { fetchBlocking() }.value
    }

    private func fetchBlocking() -> QuotaLookup {
        var account: CodexAccount?
        do {
            let session = try StdioSession(executable: executable, timeout: timeout)
            defer { session.close() }
            let _: IgnoredResult = try session.request(
                id: 1, method: "initialize",
                params: ["clientInfo": ["name": "gpt_monitor_bar", "version": "0.1.0"]]
            )
            try session.send(["method": "initialized"])
            let accountResponse: AccountResponse = try session.request(
                id: 2, method: "account/read", params: ["refreshToken": false]
            )
            guard var signedIn = accountResponse.account, signedIn.type == "chatgpt" else {
                return .failed(.signInRequired)
            }
            signedIn.workspaceID = accountResponse.workspaceRouting?.chatgptAccountId
            account = signedIn
            let snapshot: QuotaSnapshot = try session.request(id: 3, method: "account/rateLimits/read")
            return QuotaLookup(account: account, snapshot: .success(snapshot))
        } catch let failure as QuotaFailure {
            return QuotaLookup(account: account, snapshot: .failure(failure))
        } catch {
            return QuotaLookup(account: account, snapshot: .failure(.invalidResponse))
        }
    }

    private struct IgnoredResult: Decodable {}
    private struct AccountResponse: Decodable {
        struct WorkspaceRouting: Decodable { let chatgptAccountId: String? }
        let account: CodexAccount?
        let workspaceRouting: WorkspaceRouting?
    }
}

private final class StdioSession {
    private let process = Process()
    private let input: FileHandle
    private let output: FileHandle
    private let deadline: DispatchTime
    private var pending = Data()
    private let decoder = JSONDecoder()

    init(executable: URL, timeout: TimeInterval) throws {
        let stdin = Pipe()
        let stdout = Pipe()
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        deadline = .now() + timeout
        // A server that exits between requests should cause EPIPE, not SIGPIPE.
        guard fcntl(input.fileDescriptor, F_SETNOSIGPIPE, 1) != -1 else {
            throw QuotaFailure.launchFailed
        }
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        let path = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["PATH"] = executable.deletingLastPathComponent().path + ":" + path
        process.environment = environment
        do { try process.run() } catch { throw QuotaFailure.launchFailed }
    }

    func close() {
        try? input.close()
        try? output.close()
        guard process.isRunning else { return }
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + .milliseconds(250)) { [process] in
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    func send(_ packet: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: packet)
        data.append(0x0a)
        do { try input.write(contentsOf: data) } catch { throw QuotaFailure.disconnected }
    }

    func request<Value: Decodable>(
        id: Int, method: String, params: [String: Any]? = nil
    ) throws -> Value {
        var packet: [String: Any] = ["id": id, "method": method]
        if let params { packet["params"] = params }
        try send(packet)
        while true {
            let line = try readLine()
            guard (try? decoder.decode(ResponseID.self, from: line))?.id == id else { continue }
            let response = try decoder.decode(Response<Value>.self, from: line)
            if let value = response.result { return value }
            if response.error != nil { throw QuotaFailure.requestFailed }
            throw QuotaFailure.invalidResponse
        }
    }

    private func readLine() throws -> Data {
        var buffer = [UInt8](repeating: 0, count: 8_192)
        while true {
            let now = DispatchTime.now()
            guard now < deadline else { throw QuotaFailure.timedOut }
            if let newline = pending.firstIndex(of: 0x0a) {
                let line = Data(pending[..<newline])
                pending.removeSubrange(...newline)
                return line
            }
            guard pending.count < 1_048_576 else { throw QuotaFailure.invalidResponse }
            let nanoseconds = deadline.uptimeNanoseconds - now.uptimeNanoseconds
            let milliseconds = Int32(clamping: (nanoseconds + 999_999) / 1_000_000)
            var descriptor = pollfd(fd: output.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, milliseconds)
            if ready == 0 { throw QuotaFailure.timedOut }
            if ready < 0 {
                if errno == EINTR { continue }
                throw QuotaFailure.disconnected
            }
            let count = Darwin.read(output.fileDescriptor, &buffer, buffer.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw QuotaFailure.disconnected }
            pending.append(contentsOf: buffer.prefix(count))
        }
    }

    private struct ResponseID: Decodable { let id: Int? }
    private struct Response<Value: Decodable>: Decodable {
        struct RPCError: Decodable { let code: Int }
        let result: Value?
        let error: RPCError?
    }
}
