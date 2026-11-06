import UIKit

enum KeyboardStatus {
    static let keyboardBundleID = "com.hieudinh.vikey.ios.keyboard"
    /// Whether the user has added Vikey in Settings › Keyboards.
    static var isAdded: Bool {
        (UserDefaults.standard.object(forKey: "AppleKeyboards") as? [String])?.contains { $0.hasPrefix(keyboardBundleID) } ?? false
    }
    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
    }
}
