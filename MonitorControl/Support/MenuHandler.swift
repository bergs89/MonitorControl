import AppKit
import SwiftUI
import ModernSlider
import os.log

// MARK: - ExtraBrightnessSliderView
/// A SwiftUI view using ModernSlider for extra brightness.
/// When the slider value is above 1.0 the extra brightness is considered active.
struct ExtraBrightnessSliderView: View {
    // In this example, brightness is assumed to be in the range 1.0 (no boost) to 1.3 (30% boost).
    @State private var brightness: Double = Double(Vars.shared.brightness)
    
    var body: some View {
        VStack(spacing: 0) {
            Text("Extra Brightness")
              .font(.system(size: 13, weight: .bold))
              .foregroundColor(.primary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.top, 12)
              .offset(x: 16)
            ModernSlider(
              "Boost",
              systemImage: "sun.max.fill", // Provide a system image name
                sliderWidth: 180,
                sliderHeight: 20,
                value: Binding(
                    get: { brightness },
                    set: { newValue in
                        brightness = newValue
                        Vars.shared.brightness = Float(newValue)
                        // Activate extra brightness when above the default value (1.0)
                        Vars.shared.brightintoshActive = (newValue > 1.0)
                        app.brightnessManager?.brightnessTechnique?.adjustBrightness()
                    }
                ),
                in: 1.0...1.3,
                onChangeEnd: { _ in
                    // Optionally, add feedback (e.g. a sound) when the slider adjustment ends.
                }
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 0)
    }
}

// MARK: - MenuHandler
class MenuHandler: NSMenu, NSMenuDelegate {
    
    var combinedSliderHandler: [Command: SliderHandler] = [:]
    var lastMenuRelevantDisplayId: CGDirectDisplayID = 0
    
    // Clear all items and reset slider handlers.
    func clearMenu() {
        var items: [NSMenuItem] = []
        for i in 0..<self.items.count {
            items.append(self.items[i])
        }
        for item in items {
            self.removeItem(item)
        }
        self.combinedSliderHandler.removeAll()
    }
    
    func menuWillOpen(_ menu: NSMenu) {
        self.updateMenuRelevantDisplay()
    }
    
    func closeMenu() {
        self.cancelTrackingWithoutAnimation()
    }
    
    /// Rebuilds the entire menu.
    func updateMenus(dontClose: Bool = false) {
        os_log("Menu update initiated", type: .info)
        if !dontClose {
            self.cancelTrackingWithoutAnimation()
        }
        app.updateStatusItemVisibility(prefs.integer(forKey: PrefKey.menuIcon.rawValue) == MenuIcon.show.rawValue)
        self.clearMenu()
        
        // ----- Existing Display Menu Items -----
        let currentDisplay = DisplayManager.shared.getCurrentDisplay()
        var displays: [Display] = []
        if !prefs.bool(forKey: PrefKey.hideAppleFromMenu.rawValue) {
            displays.append(contentsOf: DisplayManager.shared.getAppleDisplays())
        }
        // Optionally include other displays.
        let relevant = prefs.integer(forKey: PrefKey.multiSliders.rawValue) == MultiSliders.relevant.rawValue
        let combine = prefs.integer(forKey: PrefKey.multiSliders.rawValue) == MultiSliders.combine.rawValue
        let numOfDisplays = displays.filter { !$0.isDummy }.count
        if numOfDisplays != 0 {
            let asSubMenu: Bool = (displays.count > 3 && !relevant && !combine && app.macOS10())
            var iterator = 0
            for display in displays where (!relevant || DisplayManager.resolveEffectiveDisplayID(display.identifier) == DisplayManager.resolveEffectiveDisplayID(currentDisplay!.identifier)) && !display.isDummy {
                iterator += 1
                if !relevant, !combine, iterator != 1, app.macOS10() {
                    self.insertItem(NSMenuItem.separator(), at: 0)
                }
                self.updateDisplayMenu(display: display, asSubMenu: asSubMenu, numOfDisplays: numOfDisplays)
            }
            if combine {
                self.addCombinedDisplayMenuBlock()
            }
        }
        
        // ----- Add Extra Brightness (using SwiftUI & ModernSlider) -----
        self.addBrightnessExtras()
        
        self.addItem(NSMenuItem.separator())

      
        // ----- Add Default Menu Options (Text-based: Settings, Updates, Quit) -----
        self.addDefaultMenuOptions()
    }
    
    // MARK: - Brightness Extras using ModernSlider
    func addBrightnessExtras() {
        // Add a separator to visually separate brightness extras from display sliders.
        self.addItem(NSMenuItem.separator())
        
        // Create an NSMenuItem that hosts the SwiftUI view with ModernSlider.
        let brightnessItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let sliderHostingView = NSHostingView(rootView: ExtraBrightnessSliderView())
        // Adjust the frame as needed.
        sliderHostingView.frame = NSRect(x: 0, y: 0, width: 220, height: 50)
        brightnessItem.view = sliderHostingView
        self.addItem(brightnessItem)
    }
    
    // MARK: - Removed Toggle and NSSlider Handlers
    // The previous methods for handling toggleExtraBrightness and brightnessSliderChanged have been removed
    // since the SwiftUI ModernSlider now controls extra brightness directly.
    
    // MARK: - Existing MenuHandler Functions
    func addSliderItem(monitorSubMenu: NSMenu, sliderHandler: SliderHandler) {
        let item = NSMenuItem()
        item.view = sliderHandler.view
        monitorSubMenu.insertItem(item, at: 0)
        if app.macOS10() {
            let sliderHeaderItem = NSMenuItem()
            let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemGray, .font: NSFont.systemFont(ofSize: 12)]
            sliderHeaderItem.attributedTitle = NSAttributedString(string: sliderHandler.title, attributes: attrs)
            monitorSubMenu.insertItem(sliderHeaderItem, at: 0)
        }
    }
    
    func setupMenuSliderHandler(command: Command, display: Display, title: String) -> SliderHandler {
        if prefs.integer(forKey: PrefKey.multiSliders.rawValue) == MultiSliders.combine.rawValue,
           let combinedHandler = self.combinedSliderHandler[command] {
            combinedHandler.addDisplay(display)
            display.sliderHandler[command] = combinedHandler
            return combinedHandler
        } else {
            let sliderHandler = SliderHandler(display: display, command: command, title: title)
            if prefs.integer(forKey: PrefKey.multiSliders.rawValue) == MultiSliders.combine.rawValue {
                self.combinedSliderHandler[command] = sliderHandler
            }
            display.sliderHandler[command] = sliderHandler
            return sliderHandler
        }
    }
    
    func addDisplayMenuBlock(addedSliderHandlers: [SliderHandler], blockName: String, monitorSubMenu: NSMenu, numOfDisplays: Int, asSubMenu: Bool) {
        if numOfDisplays > 1, prefs.integer(forKey: PrefKey.multiSliders.rawValue) != MultiSliders.relevant.rawValue, !DEBUG_MACOS10, #available(macOS 11.0, *) {
            class BlockView: NSView {
                override func draw(_ dirtyRect: NSRect) {
                    let radius = prefs.bool(forKey: PrefKey.showTickMarks.rawValue) ? CGFloat(4) : CGFloat(11)
                    let outerMargin = CGFloat(15)
                    let blockRect = self.frame.insetBy(dx: outerMargin, dy: outerMargin / 2 + 2).offsetBy(dx: 0, dy: outerMargin / 2 * -1 + 7)
                    for i in 1...5 {
                        let blockPath = NSBezierPath(roundedRect: blockRect.insetBy(dx: CGFloat(i) * -1, dy: CGFloat(i) * -1),
                                                     xRadius: radius + CGFloat(i) * 0.5,
                                                     yRadius: radius + CGFloat(i) * 0.5)
                        NSColor.black.withAlphaComponent(0.1 / CGFloat(i)).setStroke()
                        blockPath.stroke()
                    }
                    let blockPath = NSBezierPath(roundedRect: blockRect, xRadius: radius, yRadius: radius)
                    if [NSAppearance.Name.darkAqua, NSAppearance.Name.vibrantDark].contains(self.effectiveAppearance.name) {
                        NSColor.systemGray.withAlphaComponent(0.3).setStroke()
                        blockPath.stroke()
                    }
                    if ![NSAppearance.Name.darkAqua, NSAppearance.Name.vibrantDark].contains(self.effectiveAppearance.name) {
                        NSColor.white.withAlphaComponent(0.5).setFill()
                        blockPath.fill()
                    }
                }
            }
            var contentWidth: CGFloat = 0
            var contentHeight: CGFloat = 0
            for addedSliderHandler in addedSliderHandlers {
                contentWidth = max(addedSliderHandler.view!.frame.width, contentWidth)
                contentHeight += addedSliderHandler.view!.frame.height
            }
            let margin = CGFloat(13)
            var blockNameView: NSTextField?
            if blockName != "" {
                contentHeight += 21
                let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.textColor, .font: NSFont.boldSystemFont(ofSize: 12)]
                blockNameView = NSTextField(labelWithAttributedString: NSAttributedString(string: blockName, attributes: attrs))
                blockNameView?.frame.size.width = contentWidth - margin * 2
                blockNameView?.alphaValue = 0.5
            }
            let itemView = BlockView(frame: NSRect(x: 0, y: 0, width: contentWidth + margin * 2, height: contentHeight + margin * 2))
            var sliderPosition = CGFloat(margin * -1 + 1)
            for addedSliderHandler in addedSliderHandlers {
                addedSliderHandler.view!.setFrameOrigin(NSPoint(x: margin, y: margin + sliderPosition + 13))
                itemView.addSubview(addedSliderHandler.view!)
                sliderPosition += addedSliderHandler.view!.frame.height
            }
            if let blockNameView = blockNameView {
                blockNameView.setFrameOrigin(NSPoint(x: margin + 13, y: contentHeight - 8))
                itemView.addSubview(blockNameView)
            }
            let item = NSMenuItem()
            item.view = itemView
            if addedSliderHandlers.count != 0 {
                monitorSubMenu.insertItem(item, at: 0)
            }
        } else {
            for addedSliderHandler in addedSliderHandlers {
                self.addSliderItem(monitorSubMenu: monitorSubMenu, sliderHandler: addedSliderHandler)
            }
        }
        self.appendMenuHeader(friendlyName: blockName, monitorSubMenu: monitorSubMenu, asSubMenu: asSubMenu, numOfDisplays: numOfDisplays)
    }
    
    func addCombinedDisplayMenuBlock() {
        if let sliderHandler = self.combinedSliderHandler[.audioSpeakerVolume] {
            self.addSliderItem(monitorSubMenu: self, sliderHandler: sliderHandler)
        }
        if let sliderHandler = self.combinedSliderHandler[.contrast] {
            self.addSliderItem(monitorSubMenu: self, sliderHandler: sliderHandler)
        }
        if let sliderHandler = self.combinedSliderHandler[.brightness] {
            self.addSliderItem(monitorSubMenu: self, sliderHandler: sliderHandler)
        }
    }
    
    func updateDisplayMenu(display: Display, asSubMenu: Bool, numOfDisplays: Int) {
        os_log("Adding menu items for display %{public}@", type: .info, "\(display.identifier)")
        let monitorSubMenu: NSMenu = asSubMenu ? NSMenu() : self
        var addedSliderHandlers: [SliderHandler] = []
        display.sliderHandler[.audioSpeakerVolume] = nil
        // Uncomment and adjust for volume slider if needed.
        display.sliderHandler[.contrast] = nil
        if !display.readPrefAsBool(key: .unavailableDDC, for: .brightness), !prefs.bool(forKey: PrefKey.hideBrightness.rawValue) {
            let title = NSLocalizedString("Brightness", comment: "Shown in menu")
            addedSliderHandlers.append(self.setupMenuSliderHandler(command: .brightness, display: display, title: title))
        }
        if prefs.integer(forKey: PrefKey.multiSliders.rawValue) != MultiSliders.combine.rawValue {
            self.addDisplayMenuBlock(addedSliderHandlers: addedSliderHandlers,
                                     blockName: (display.readPrefAsString(key: .friendlyName) != "" ? display.readPrefAsString(key: .friendlyName) : display.name),
                                     monitorSubMenu: monitorSubMenu,
                                     numOfDisplays: numOfDisplays,
                                     asSubMenu: asSubMenu)
        }
        if addedSliderHandlers.count > 0, prefs.integer(forKey: PrefKey.menuIcon.rawValue) == MenuIcon.sliderOnly.rawValue {
            app.updateStatusItemVisibility(true)
        }
    }
    
    private func appendMenuHeader(friendlyName: String, monitorSubMenu: NSMenu, asSubMenu: Bool, numOfDisplays: Int) {
        let monitorMenuItem = NSMenuItem()
        if asSubMenu {
            monitorMenuItem.title = "\(friendlyName)"
            monitorMenuItem.submenu = monitorSubMenu
            self.insertItem(monitorMenuItem, at: 0)
        } else if app.macOS10(), numOfDisplays > 1 {
            let attrs: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.systemGray, .font: NSFont.boldSystemFont(ofSize: 12)]
            monitorMenuItem.attributedTitle = NSAttributedString(string: "\(friendlyName)", attributes: attrs)
            self.insertItem(monitorMenuItem, at: 0)
        }
    }
    
    func updateMenuRelevantDisplay() {
        if prefs.integer(forKey: PrefKey.multiSliders.rawValue) == MultiSliders.relevant.rawValue {
            if let display = DisplayManager.shared.getCurrentDisplay(), display.identifier != self.lastMenuRelevantDisplayId {
                os_log("Menu must be refreshed as relevant display changed since last time.")
                self.lastMenuRelevantDisplayId = display.identifier
                self.updateMenus(dontClose: true)
            }
        }
    }
    
    // MARK: - Default Menu Options (Text-based)
    func addDefaultMenuOptions() {
        if app.macOS10() {
            self.insertItem(NSMenuItem.separator(), at: self.items.count)
        }
        self.insertItem(withTitle: NSLocalizedString("Settings…", comment: "Shown in menu"),
                        action: #selector(app.prefsClicked),
                        keyEquivalent: ",",
                        at: self.items.count)
        // let updateItem = NSMenuItem(title: NSLocalizedString("Check for updates…", comment: "Shown in menu"),
        //                            action: #selector(app.updaterController.checkForUpdates(_:)),
        //                            keyEquivalent: "")
        //updateItem.target = app.updaterController
        //self.insertItem(updateItem, at: self.items.count)
        self.insertItem(withTitle: NSLocalizedString("Quit", comment: "Shown in menu"),
                        action: #selector(app.quitClicked),
                        keyEquivalent: "q",
                        at: self.items.count)
    }
}
