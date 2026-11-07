import AppKit

enum AppearanceMode: String, CaseIterable {
    case light, dark, system

    var title: String {
        switch self {
        case .light: "浅色"
        case .dark: "深色"
        case .system: "跟随系统"
        }
    }

    var appearance: NSAppearance? {
        switch self {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case .system: nil
        }
    }
}

@MainActor
final class AppearancePreference: NSObject {
    private let defaults: UserDefaults
    private let onChange: (NSAppearance?) -> Void
    private(set) var mode: AppearanceMode

    init(defaults: UserDefaults = .standard, onChange: @escaping (NSAppearance?) -> Void) {
        self.defaults = defaults
        self.onChange = onChange
        mode = defaults.string(forKey: "appearanceMode").flatMap(AppearanceMode.init(rawValue:)) ?? .system
        super.init()
    }

    func apply() { onChange(mode.appearance) }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "样式")
        for option in AppearanceMode.allCases {
            let item = menu.addItem(withTitle: option.title, action: #selector(selectAppearance(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            item.state = option == mode ? .on : .off
        }
        return menu
    }

    @objc private func selectAppearance(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let selected = AppearanceMode(rawValue: rawValue) else { return }
        mode = selected
        defaults.set(selected.rawValue, forKey: "appearanceMode")
        sender.menu?.items.forEach { item in
            item.state = (item.representedObject as? String) == selected.rawValue ? .on : .off
        }
        apply()
    }
}
