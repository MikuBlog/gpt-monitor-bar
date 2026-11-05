import AppKit
import ServiceManagement
import Testing
@testable import GPTMonitorBar

@MainActor
struct PanelBehaviorTests {
    @Test func outsideClickClosesButPanelAndBadgeClicksPassThrough() {
        _ = NSApplication.shared
        let panel = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                             styleMask: .borderless, backing: .buffered, defer: true)
        let host = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                            styleMask: .borderless, backing: .buffered, defer: true)
        let badge = NSView(frame: NSRect(x: 10, y: 10, width: 25, height: 25))
        host.contentView?.addSubview(badge)

        #expect(!PopoverDismissal.isOutside(window: panel, location: .zero, panel: panel, anchor: badge))
        #expect(!PopoverDismissal.isOutside(window: host, location: NSPoint(x: 20, y: 20),
                                           panel: panel, anchor: badge))
        #expect(PopoverDismissal.isOutside(window: host, location: .zero, panel: panel, anchor: badge))
        #expect(PopoverDismissal.isOutside(window: nil, location: .zero, panel: panel, anchor: badge))
        #expect(PopoverDismissal.isOutside(window: nil, location: .zero, panel: nil, anchor: badge))
    }

    @Test func loginSwitchReflectsApprovalAndCanCancelPendingRegistration() {
        let service = TestLoginService()
        let settings = LaunchAtLogin(service: service)
        #expect(!settings.isRegistered)
        settings.setRegistered(true)
        #expect(settings.isRegistered)
        #expect(settings.needsApproval)
        settings.setRegistered(false)
        #expect(!settings.isRegistered)
        #expect(!settings.needsApproval)
    }

    @Test func failedRegistrationLeavesSwitchOffAndRefreshReadsSystemState() {
        let service = TestLoginService()
        service.failRegistration = true
        let settings = LaunchAtLogin(service: service)
        settings.setRegistered(true)
        #expect(!settings.isRegistered)
        #expect(settings.errorMessage != nil)
        service.status = .enabled
        settings.refresh()
        #expect(settings.isRegistered)
        #expect(settings.errorMessage == nil)
    }
}

@MainActor
private final class TestLoginService: LaunchAtLoginService {
    var status: SMAppService.Status = .notRegistered
    var failRegistration = false

    func register() throws {
        if failRegistration { throw CocoaError(.fileWriteUnknown) }
        status = .requiresApproval
    }

    func unregister() throws { status = .notRegistered }
}
