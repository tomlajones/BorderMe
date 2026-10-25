import Foundation

/// The app and the Share extension read and write the same last-used
/// settings through their shared App Group.
enum SettingsStore {
    static let appGroup = "group.com.tomlajones.borderme"
    private static let key = "lastSettings"

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func load() -> RenderSettings {
        guard
            let data = defaults.data(forKey: key),
            let settings = try? JSONDecoder().decode(RenderSettings.self, from: data)
        else {
            return .standard
        }
        return settings
    }

    static func save(_ settings: RenderSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: key)
    }
}
