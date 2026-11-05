import AppKit
import QuotaCore
import SwiftUI

@main
enum GPTMonitorBarApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = MenuBarController()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
private final class MenuBarController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let badge = BadgeHost(rootView: MenuBadge(text: "Codex —", level: .unknown, stale: false))
    private let selection: CLISelection
    private let store: QuotaStore
    private let launchAtLogin = LaunchAtLogin()
    private var timer: Timer?
    private var outsideMouseMonitor: Any?
    private var localMouseMonitor: Any?

    override init() {
        let selection = CLISelection()
        self.selection = selection
        store = QuotaStore {
            guard let executable = selection.resolve() else { return .failed(.missingCLI) }
            return await CodexAppServer(executable: executable).fetch()
        }
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let button = item.button else { return }
        badge.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(badge)
        NSLayoutConstraint.activate([
            badge.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            badge.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        ])
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.setAccessibilityLabel("Codex 套餐额度")

        let panel = NSHostingController(rootView: QuotaPanel(
            store: store, launchAtLogin: launchAtLogin, refresh: { [weak self] in self?.refresh() },
            chooseCLI: { [weak self] in self?.chooseCLI() },
            manageUsage: { [weak self] in self?.manageUsage() },
            quit: { [weak self] in self?.quit() }
        ).preferredColorScheme(.dark))
        panel.sizingOptions = .preferredContentSize
        popover.contentViewController = panel
        popover.behavior = .transient
        popover.delegate = self

        observeBadge()
        refresh()
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopMonitoringOutsideClicks()
        timer?.invalidate()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    func popoverWillShow(_ notification: Notification) {
        launchAtLogin.refresh()
        guard outsideMouseMonitor == nil, localMouseMonitor == nil else { return }
        let buttons: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // AppKit calls both event monitors on the main thread.
        outsideMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: buttons) { [weak self] _ in
            MainActor.assumeIsolated { self?.dismissPanel() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: buttons) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, PopoverDismissal.isOutside(
                    window: event.window, location: event.locationInWindow,
                    panel: self.popover.contentViewController?.view.window, anchor: self.item.button
                ) else { return }
                self.dismissPanel()
            }
            return event
        }
    }

    func popoverDidClose(_ notification: Notification) {
        stopMonitoringOutsideClicks()
    }

    private func stopMonitoringOutsideClicks() {
        if let outsideMouseMonitor { NSEvent.removeMonitor(outsideMouseMonitor) }
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        outsideMouseMonitor = nil
        localMouseMonitor = nil
    }

    private func dismissPanel() {
        if popover.isShown { popover.performClose(nil) }
    }

    private func observeBadge() {
        withObservationTracking {
            let text = store.snapshot?.badgeText ?? "Codex —"
            let level = store.snapshot?.badgeLevel ?? .unknown
            let stale = store.failure != nil
            badge.rootView = MenuBadge(text: text, level: level, stale: stale)
            badge.invalidateIntrinsicContentSize()
            item.length = ceil(badge.fittingSize.width) + 8
            item.button?.setAccessibilityValue(stale ? text + "，数据待更新" : text)
            item.button?.toolTip = stale ? "Codex 额度待更新" : "查看 Codex 套餐额度"
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeBadge() }
        }
    }

    @objc private func clicked() {
        guard let button = item.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            popover.close()
            let menu = NSMenu()
            let actions: [(String, Selector, String)] = [
                ("立即刷新", #selector(refresh), "r"),
                ("管理用量", #selector(manageUsage), ""),
                ("选择 Codex CLI…", #selector(chooseCLI), "")
            ]
            for (title, action, shortcut) in actions {
                menu.addItem(withTitle: title, action: action, keyEquivalent: shortcut).target = self
            }
            menu.addItem(.separator())
            menu.addItem(withTitle: "退出", action: #selector(quit), keyEquivalent: "q").target = self
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
        } else if popover.isShown {
            popover.performClose(nil)
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard !popover.isShown, let button = item.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate()
        Task { await store.refresh(maxAge: 10) }
    }

    @objc private func refresh() {
        Task { await store.refresh() }
    }

    @objc private func didWake(_ notification: Notification) {
        refresh()
    }

    @objc private func manageUsage() {
        popover.close()
        NSWorkspace.shared.open(URL(string: "https://chatgpt.com/settings/usage?tab=overview")!)
    }

    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func chooseCLI() {
        popover.close()
        let picker = NSOpenPanel()
        picker.title = "选择 Codex CLI"
        picker.message = "请选择可执行的 codex 文件，例如 NVM 或 Homebrew 安装目录里的 codex。"
        picker.prompt = "选择"
        picker.resolvesAliases = false
        NSApp.activate()
        picker.begin { [weak self] response in
            guard response == .OK, let url = picker.url else { return }
            guard CLISelection.isExecutable(at: url.path) else {
                let alert = NSAlert()
                alert.messageText = "请选择可执行的 Codex CLI 文件"
                alert.runModal()
                return
            }
            self?.selection.save(url)
            self?.refresh()
            self?.showPanel()
        }
    }
}

@MainActor
enum PopoverDismissal {
    static func isOutside(window: NSWindow?, location: NSPoint, panel: NSWindow?, anchor: NSView?) -> Bool {
        guard let window else { return true }
        if window === panel { return false }
        guard let anchor, window === anchor.window else { return true }
        return !anchor.bounds.contains(anchor.convert(location, from: nil))
    }
}

private final class BadgeHost: NSHostingView<MenuBadge> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
private struct CLISelection {
    private let pathKey = "codexExecutablePath"

    func save(_ executable: URL) {
        UserDefaults.standard.set(executable.path, forKey: pathKey)
    }

    func resolve() -> URL? {
        let manager = FileManager.default
        if let selected = UserDefaults.standard.string(forKey: pathKey) {
            return Self.isExecutable(at: selected) ? URL(fileURLWithPath: selected) : nil
        }
        let environment = ProcessInfo.processInfo.environment
        let path = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let home = manager.homeDirectoryForCurrentUser
        let nvm = environment["NVM_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? home.appending(path: ".nvm")
        let versions = (try? manager.contentsOfDirectory(
            at: nvm.appending(path: "versions/node"), includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []
        let nvmBins = versions.sorted {
            $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending
        }.map { $0.appending(path: "bin").path }
        let directories = path + ["/opt/homebrew/bin", "/usr/local/bin", home.appending(path: ".local/bin").path]
            + nvmBins
        return directories.lazy
            .filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: $0, isDirectory: true).appending(path: "codex") }
            .first { Self.isExecutable(at: $0.path) }
    }

    static func isExecutable(at path: String) -> Bool {
        let manager = FileManager.default
        var isDirectory: ObjCBool = false
        return manager.fileExists(atPath: path, isDirectory: &isDirectory)
            && !isDirectory.boolValue && manager.isExecutableFile(atPath: path)
    }
}
