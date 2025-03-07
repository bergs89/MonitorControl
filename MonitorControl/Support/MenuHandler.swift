import AppKit
import SwiftUI
import ModernSlider
import os.log
import LaunchAtLogin

// MARK: - ExtraBrightnessSliderView
/// A SwiftUI view using ModernSlider for extra brightness.
/// When the slider value is above 1.0 the extra brightness is considered active.
struct ExtraBrightnessSliderView: View {
    // In this example, brightness is assumed to be in the range 1.0 (no boost) to 1.3 (30% boost).
    @State private var brightness: Double = Double(Vars.shared.brightness)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Boost")
              .font(.system(size: 13, weight: .bold))
              .foregroundColor(.primary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.top, 12)
              .offset(x: 16)
            ModernSlider(
              systemImage: "sun.max.fill",
              sliderWidth: 280,
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
              in: 1.0...1.25,
              onChangeEnd: { _ in }
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

// MARK: - DisplayBrightnessSliderView
/// A SwiftUI view for controlling a display's brightness using ModernSlider.
struct DisplayBrightnessSliderView: View {
    @State var brightness: Double
    var display: Display

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Show a header using the display's friendly name if available.
            Text(display.readPrefAsString(key: .friendlyName).isEmpty ? display.name : display.readPrefAsString(key: .friendlyName))
              .font(.system(size: 13, weight: .bold))
              .foregroundColor(.primary)
              .frame(maxWidth: .infinity, alignment: .leading)
              .padding(.top, 16)
              .offset(x: 16)
            ModernSlider(
              systemImage: "sun.max.fill",
              sliderWidth: 280,
              sliderHeight: 20,
              value: Binding(
                get: {
                        if let appleDisplay = display as? AppleDisplay {
                            return Double(appleDisplay.getBrightness())
                        } else if let otherDisplay = display as? OtherDisplay {
                          if let ddcValues = otherDisplay.readDDCValues(for: .brightness, tries: 3, minReplyDelay: nil) {
                              // Normalize the value between 0 and 1.
                              return Double(ddcValues.current) / Double(ddcValues.max)
                          }
                          return brightness
                        }
                        return brightness
                    },
                set: { newValue in
                      brightness = newValue
                      if let appleDisplay = display as? AppleDisplay {
                          _ = appleDisplay.setBrightness(Float(newValue))
                      } else if let otherDisplay = display as? OtherDisplay {
                          otherDisplay.writeDDCValues(command: .brightness, value: otherDisplay.convValueToDDC(for: .brightness, from: Float(newValue)))
                          otherDisplay.savePref(Float(newValue), for: .brightness)
                      }
                  }
              ),
              in: 0...1,
              onChangeEnd: { _ in }
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
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
        }
        
        // ----- Add Extra Brightness (using SwiftUI & ModernSlider) -----
        self.addBrightnessExtras()
        
        self.addItem(NSMenuItem.separator())
        
        // ----- Add Default Menu Options (Text-based: Settings, Quit) -----
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
        sliderHostingView.frame = NSRect(x: 0, y: 0, width: 305, height: 60)
        brightnessItem.view = sliderHostingView
        self.addItem(brightnessItem)
    }
    
    // MARK: - Update Display Menu for Brightness using ModernSlider
    func updateDisplayMenu(display: Display, asSubMenu: Bool, numOfDisplays: Int) {
        os_log("Adding menu items for display %{public}@", type: .info, "\(display.identifier)")
        let monitorSubMenu: NSMenu = asSubMenu ? NSMenu() : self
        
        // Use a ModernSlider-based SwiftUI view for brightness control.
        if !display.readPrefAsBool(key: .unavailableDDC, for: .brightness),
           !prefs.bool(forKey: PrefKey.hideBrightness.rawValue) {
            
            let sliderItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            let initialBrightness: Double = {
                if let appleDisplay = display as? AppleDisplay {
                    return Double(appleDisplay.getAppleBrightness())
                } else if let otherDisplay = display as? OtherDisplay {
                    return Double(otherDisplay.setupSliderCurrentValue(command: .brightness))
                }
                return 0.5
            }()
            let brightnessView = DisplayBrightnessSliderView(brightness: initialBrightness, display: display)
            let hostingView = NSHostingView(rootView: brightnessView)
            hostingView.frame = NSRect(x: 0, y: 0, width: 305, height: 60)
            sliderItem.view = hostingView
            
            if asSubMenu {
                let headerTitle = display.readPrefAsString(key: .friendlyName).isEmpty ? display.name : display.readPrefAsString(key: .friendlyName)
                let monitorMenuItem = NSMenuItem(title: headerTitle, action: nil, keyEquivalent: "")
                monitorMenuItem.submenu = NSMenu()
                monitorMenuItem.submenu?.addItem(sliderItem)
                self.insertItem(monitorMenuItem, at: 0)
            } else {
                self.insertItem(sliderItem, at: 0)
            }
        }
    }
    
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
      
      // Display Settings menu item.
        self.insertItem(withTitle: NSLocalizedString("Displays Settings...", comment: "Open Display Settings"),
                        action: #selector(app.openDisplaySettings(_:)),
                        keyEquivalent: "",
                        at: self.items.count)
      
        self.addItem(NSMenuItem.separator())
      
        // Natural Scrolling menu item.
        self.insertItem(withTitle: NSLocalizedString("Natural Scrolling", comment: "Toggle natural scrolling for brightness adjustment"),
                         action: #selector(app.toggleNaturalScrolling(_:)),
                         keyEquivalent: "",
                        at: self.items.count)
      
        let launchItem = self.insertItem(withTitle: NSLocalizedString("Launch at Login", comment: "Shown in menu"),
                                       action: #selector(toggleLaunchAtLogin(_:)),
                                       keyEquivalent: "",
                                       at: self.items.count)
        launchItem.target = self
        launchItem.state = LaunchAtLogin.isEnabled ? .on : .off
      
        self.addItem(NSMenuItem.separator())
      
        self.insertItem(withTitle: NSLocalizedString("About", comment: "Shown in menu"),
                        action: #selector(app.showAbout(_:)),
                        keyEquivalent: "",
                        at: self.items.count)
        
        self.insertItem(withTitle: NSLocalizedString("Quit", comment: "Shown in menu"),
                        action: #selector(app.quitClicked),
                        keyEquivalent: "q",
                        at: self.items.count)
    }
  
  @objc func toggleLaunchAtLogin(_ sender: NSMenuItem) {
      LaunchAtLogin.isEnabled.toggle()
      sender.state = LaunchAtLogin.isEnabled ? .on : .off
  }
}
