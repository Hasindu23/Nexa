import AppKit
import ColorSync

enum NexaDisplays {
    static func identifier(_ screen: NSScreen) -> String {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return screen.localizedName }
        if let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() {
            return "display:" + (CFUUIDCreateString(nil, uuid) as String)
        }
        return "display-id:\(number.uint32Value)"
    }
    static func matches(_ screen: NSScreen, preference: String) -> Bool {
        identifier(screen) == preference || screen.localizedName == preference
    }
    static func resolve(_ preference: String) -> NSScreen? {
        NSScreen.screens.first(where: { matches($0, preference: preference) })
            ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }
}
