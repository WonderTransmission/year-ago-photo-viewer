import Foundation
import YearAgoCore

/// Reads and writes viewer settings in user defaults.
struct SettingsStore {
    private let defaults: UserDefaults

    private enum Key {
        static let weeks = "windowWeeks"
        static let showEmptyYears = "showEmptyYears"
        /// Before M5 this was the single folder's date source. It is now the
        /// default for newly added sources.
        static let defaultDateSource = "dateSource"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.weeks: 1,
            Key.showEmptyYears: true,
            Key.defaultDateSource: DateSourceKind.exif.rawValue,
        ])
    }

    var weeks: Int {
        get {
            let stored = defaults.integer(forKey: Key.weeks)
            return min(max(stored, WindowCalculator.allowedWeeks.lowerBound),
                       WindowCalculator.allowedWeeks.upperBound)
        }
        nonmutating set { defaults.set(newValue, forKey: Key.weeks) }
    }

    var showEmptyYears: Bool {
        get { defaults.bool(forKey: Key.showEmptyYears) }
        nonmutating set { defaults.set(newValue, forKey: Key.showEmptyYears) }
    }

    var defaultDateSource: DateSourceKind {
        get { defaults.string(forKey: Key.defaultDateSource).flatMap(DateSourceKind.init(rawValue:)) ?? .exif }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Key.defaultDateSource) }
    }
}
