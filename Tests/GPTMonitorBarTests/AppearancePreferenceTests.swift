import AppKit
import Testing
@testable import GPTMonitorBar

@MainActor
struct AppearancePreferenceTests {
    @Test func missingOrUnrecognizedPreferenceFollowsSystem() {
        let suite = "AppearancePreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var applied: NSAppearance? = NSAppearance(named: .darkAqua)
        let preference = AppearancePreference(defaults: defaults) { applied = $0 }
        preference.apply()
        #expect(preference.mode == .system)
        #expect(applied == nil)

        defaults.set("unsupported-theme", forKey: "appearanceMode")
        let recovered = AppearancePreference(defaults: defaults) { applied = $0 }
        recovered.apply()
        #expect(recovered.mode == .system)
        #expect(applied == nil)
    }

    @Test func menuSelectionAppliesPersistsAndRestoresSystemInheritance() throws {
        _ = NSApplication.shared
        let suite = "AppearancePreferenceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let host = NSView()
        let preference = AppearancePreference(defaults: defaults) { host.appearance = $0 }
        let menu = preference.makeMenu()
        #expect(menu.title == "样式")
        #expect(menu.items.map(\.title) == ["浅色", "深色", "跟随系统"])
        #expect(menu.items.map(\.state) == [.off, .off, .on])

        let expectedModes: [AppearanceMode] = [.light, .dark, .system]
        let expectedNames: [NSAppearance.Name?] = [.aqua, .darkAqua, nil]
        for index in 0..<3 {
            menu.performActionForItem(at: index)
            #expect(preference.mode == expectedModes[index])
            #expect(host.appearance?.name == expectedNames[index])
            #expect(menu.items[index].state == .on)
            #expect(menu.items.filter { $0.state == .on }.count == 1)

            let restarted = AppearancePreference(defaults: defaults) { host.appearance = $0 }
            #expect(restarted.mode == expectedModes[index])
            restarted.apply()
            #expect(host.appearance?.name == expectedNames[index])
            #expect(restarted.makeMenu().items[index].state == .on)
        }
    }
}
