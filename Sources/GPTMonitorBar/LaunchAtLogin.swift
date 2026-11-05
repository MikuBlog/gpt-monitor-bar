import Observation
import ServiceManagement

@MainActor
protocol LaunchAtLoginService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LaunchAtLoginService {}

@MainActor @Observable
final class LaunchAtLogin {
    private let service: any LaunchAtLoginService
    private var status: SMAppService.Status
    private(set) var errorMessage: String?

    init(service: any LaunchAtLoginService = SMAppService.mainApp) {
        self.service = service
        status = service.status
    }

    var isRegistered: Bool { status == .enabled || needsApproval }
    var needsApproval: Bool { status == .requiresApproval }

    func refresh() {
        status = service.status
        errorMessage = nil
    }

    func setRegistered(_ registered: Bool) {
        refresh()
        guard registered != isRegistered else { return }
        defer { status = service.status }
        do {
            if registered {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            errorMessage = registered ? "无法开启自启动，请检查系统登录项。" : "无法关闭自启动，请检查系统登录项。"
        }
    }

    func openSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
