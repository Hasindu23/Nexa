import AppKit

struct NotchGeometry: Equatable {
    let screenFrame: NSRect
    let hardwareWidth: CGFloat
    let hardwareHeight: CGFloat
    let hardwareCenterX: CGFloat
    let detachedTopInset: CGFloat
    var hasNotch: Bool { hardwareHeight > 0 }
    init(screen: NSScreen) {
        screenFrame = screen.frame; hardwareHeight = screen.safeAreaInsets.top
        // Reserve the menu bar even when auto-hidden, so revealing it never
        // puts the detached island over menu titles or system status controls.
        detachedTopInset = max(NSStatusBar.system.thickness, screen.frame.maxY - screen.visibleFrame.maxY) + 6
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            hardwareWidth = max(120, right.minX - left.maxX)
            hardwareCenterX = (left.maxX + right.minX) / 2
        } else { hardwareWidth = 170; hardwareCenterX = screen.frame.midX }
    }
    init(frame: NSRect, hardwareWidth: CGFloat, hardwareHeight: CGFloat, hardwareCenterX: CGFloat? = nil, menuBarHeight: CGFloat = 0) {
        screenFrame = frame; self.hardwareWidth = hardwareWidth; self.hardwareHeight = hardwareHeight
        self.hardwareCenterX = hardwareCenterX ?? frame.midX
        detachedTopInset = max(0, menuBarHeight) + 6
    }
    func cameraWidth(preferences: AppPreferences) -> CGFloat {
        preferences.notchWidth > 0 ? max(120, CGFloat(preferences.notchWidth)).rounded() : hardwareWidth
    }
    func frame(expanded: Bool, banner: Bool, preferences: AppPreferences, home: Bool = false) -> NSRect {
        let baseWidth = cameraWidth(preferences: preferences)
        let requestedWidth = expanded ? preferences.expandedWidth : banner ? max(360, baseWidth + 80) : baseWidth + (hasNotch ? 64 : 0)
        // AppKit rounds window origins to whole points. Match the width parity
        // to the cutout so an odd-width camera stays centered after rounding.
        let width = min(screenFrame.width, hasNotch ? 2 * (hardwareCenterX - floor(hardwareCenterX - requestedWidth / 2)) : requestedWidth)
        // Scaled displays can report a fractional cutout height; NSWindow rounds
        // it to whole points. Round before positioning to keep the top edge fixed.
        let inset = hasNotch ? 0 : detachedTopInset
        let height = min(max(1, screenFrame.height - inset), ceil(expanded ? (home ? preferences.homeHeight : preferences.expandedHeight) : banner ? max(78, hardwareHeight + 50) : max(30, hardwareHeight)))
        let offset = hasNotch ? 0 : preferences.horizontalOffset
        let centerX = hasNotch ? hardwareCenterX : screenFrame.midX
        let x = min(max(centerX - width / 2 + offset, screenFrame.minX), screenFrame.maxX - width)
        return NSRect(x: x, y: screenFrame.maxY - height - inset, width: width, height: height)
    }
}
