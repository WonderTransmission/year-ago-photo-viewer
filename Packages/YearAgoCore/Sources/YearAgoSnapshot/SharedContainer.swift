import Foundation
import Security

/// The App Group folder shared by the app and the widget.
///
/// The group ID comes from the running binary's own entitlements, so it is
/// never hard-coded: each builder sets `APP_GROUP_ID` in Local.xcconfig.
public enum SharedContainer {
    /// The first App Group in this process's entitlements, if any.
    public static var groupIdentifier: String? {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil),
              let groups = value as? [String]
        else { return nil }
        return groups.first
    }

    /// The widget's folder inside the App Group container, or nil when the
    /// process has no App Group.
    public static var widgetFolder: URL? {
        guard let groupIdentifier,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
        else { return nil }
        return container.appendingPathComponent("Widget", isDirectory: true)
    }
}
