//  Copyright © MonitorControl. @JoniVR, @theOneyouseek, @waydabber and others

import Cocoa
import Foundation
import os.log
import ServiceManagement
import Settings
import LaunchAtLogin

class AppDelegate: NSObject, NSApplicationDelegate {
  let statusItem: NSStatusItem = {
    let item = NSStatusBar.system.statusItem(withLength: 20)
    item.behavior = .removalAllowed
    return item
  }()
  var accessibilityObserver: NSObjectProtocol!
  var statusItemObserver: NSObjectProtocol!
  var statusItemVisibilityChangedByUser = true
  var reconfigureID: Int = 0 // dispatched reconfigure command ID
  var sleepID: Int = 0 // sleep event ID
  var safeMode = false
  var jobRunning = false
  var startupActionWriteCounter: Int = 0

  var brightnessManager: BrightnessManager?
  
  func applicationDidFinishLaunching(_: Notification) {
    app = self
    self.subscribeEventListeners()
    self.showSafeModeAlertIfNeeded()
    if !prefs.bool(forKey: PrefKey.appAlreadyLaunched.rawValue) {
    }
    self.setPrefsBuildNumber()
    self.setDefaultPrefs()
    self.setMenu()
    CGDisplayRegisterReconfigurationCallback({ _, _, _ in app.displayReconfigured() }, nil)
    self.configure(firstrun: true)
    DisplayManager.shared.createGammaActivityEnforcer()
    
    // Initialize your brightness manager (using your modified BrightIntosh version)
    brightnessManager = BrightnessManager(isExtraBrightnessAllowed: { _ in return true })
    
    if #available(macOS 10.15, *) {
        if let button = statusItem.button {
            button.image = nil // Remove default image
            let customView = BrightnessStatusItemView(frame: button.bounds)
            button.addSubview(customView)
        }
    }

  }

  @objc func quitClicked(_: AnyObject) {
    os_log("Quit clicked", type: .info)
    menu.closeMenu()
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
      NSApplication.shared.terminate(self)
    }
  }

  func applicationWillTerminate(_: Notification) {
    os_log("Goodbye!", type: .info)
    DisplayManager.shared.resetSwBrightnessForAllDisplays(noPrefSave: true)
    self.updateStatusItemVisibility(true)
  }

  private func setPrefsBuildNumber() {
    let currentBuildNumber = Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1") ?? 1
    let previousBuildNumber: Int = (Int(prefs.string(forKey: PrefKey.buildNumber.rawValue) ?? "0") ?? 0)
    if self.safeMode || ((previousBuildNumber < MIN_PREVIOUS_BUILD_NUMBER) && previousBuildNumber > 0) || (previousBuildNumber > currentBuildNumber), let bundleID = Bundle.main.bundleIdentifier {
      if !self.safeMode {
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Incompatible previous version", comment: "Shown in the alert dialog")
        alert.informativeText = NSLocalizedString("Settings for an incompatible previous app version detected. Default settings are reloaded.", comment: "Shown in the alert dialog")
        alert.runModal()
      }
      prefs.removePersistentDomain(forName: bundleID)
    }
    prefs.set(currentBuildNumber, forKey: PrefKey.buildNumber.rawValue)
  }

  func setDefaultPrefs() {
    if !prefs.bool(forKey: PrefKey.appAlreadyLaunched.rawValue) {
      // Only settings that are not false, 0 or "" by default are set here. Assumes pre-wiped database.
      prefs.set(true, forKey: PrefKey.appAlreadyLaunched.rawValue)
      prefs.set(true, forKey: PrefKey.SUEnableAutomaticChecks.rawValue)
    }
  }

  @objc func displayReconfigured() {
    DisplayManager.shared.resetSwBrightnessForAllDisplays(noPrefSave: true)
    CGDisplayRestoreColorSyncSettings()
    self.reconfigureID += 1
    os_log("Bumping reconfigureID to %{public}@", type: .info, String(self.reconfigureID))
    _ = DisplayManager.shared.destroyAllShades()
    if self.sleepID == 0 {
      let dispatchedReconfigureID = self.reconfigureID
      os_log("Display to be reconfigured with reconfigureID %{public}@", type: .info, String(dispatchedReconfigureID))
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        self.configure(dispatchedReconfigureID: dispatchedReconfigureID)
      }
    }
  }

  func configure(dispatchedReconfigureID: Int = 0, firstrun: Bool = false) {
    guard self.sleepID == 0, dispatchedReconfigureID == self.reconfigureID else {
      return
    }
    os_log("Request for configuration with reconfigreID %{public}@", type: .info, String(dispatchedReconfigureID))
    self.reconfigureID = 0
    DisplayManager.shared.gammaInterferenceCounter = 0
    DisplayManager.shared.configureDisplays()
    DisplayManager.shared.addDisplayCounterSuffixes()
    // DisplayManager.shared.updateArm64AVServices()
    if firstrun && prefs.integer(forKey: PrefKey.startupAction.rawValue) != StartupAction.write.rawValue {
      DisplayManager.shared.resetSwBrightnessForAllDisplays(prefsOnly: true)
    }
    self.updateMenusAndKeys()
    if !firstrun || prefs.integer(forKey: PrefKey.startupAction.rawValue) == StartupAction.write.rawValue {
      if !prefs.bool(forKey: PrefKey.disableCombinedBrightness.rawValue) {
        DisplayManager.shared.restoreSwBrightnessForAllDisplays(async: !prefs.bool(forKey: PrefKey.disableSmoothBrightness.rawValue))
      }
    }
    displaysPrefsVc?.loadDisplayList()
    self.job(start: true)
  }

  func updateMenusAndKeys() {
    menu.updateMenus()
  }

  private func subscribeEventListeners() {
    DistributedNotificationCenter.default.addObserver(self, selector: #selector(self.displayReconfigured), name: NSNotification.Name(rawValue: kColorSyncDisplayDeviceProfilesNotification.takeRetainedValue() as String), object: nil) // ColorSync change
    NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.sleepNotification), name: NSWorkspace.screensDidSleepNotification, object: nil) // sleep and wake listeners
    NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.wakeNotification), name: NSWorkspace.screensDidWakeNotification, object: nil)
    NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.sleepNotification), name: NSWorkspace.willSleepNotification, object: nil)
    NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(self.wakeNotification), name: NSWorkspace.didWakeNotification, object: nil)
    self.statusItemObserver = statusItem.observe(\.isVisible, options: [.old, .new]) { _, _ in self.statusItemVisibilityChanged() }
  }

  @objc private func sleepNotification() {
    self.sleepID += 1
    os_log("Sleeping with sleep %{public}@", type: .info, String(self.sleepID))
  }

  @objc private func wakeNotification() {
    if self.sleepID != 0 {
      os_log("Waking up from sleep %{public}@", type: .info, String(self.sleepID))
      let dispatchedSleepID = self.sleepID
      DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { // Some displays take time to recover...
        self.soberNow(dispatchedSleepID: dispatchedSleepID)
      }
    }
  }

  private func soberNow(dispatchedSleepID: Int) {
    if self.sleepID == dispatchedSleepID {
      os_log("Sober from sleep %{public}@", type: .info, String(self.sleepID))
      self.sleepID = 0
      if self.reconfigureID != 0 {
        let dispatchedReconfigureID = self.reconfigureID
        os_log("Displays need reconfig after sober with reconfigureID %{public}@", type: .info, String(dispatchedReconfigureID))
        self.configure(dispatchedReconfigureID: dispatchedReconfigureID)
      } else if Arm64DDC.isArm64 {
        os_log("Displays don't need reconfig after sober but might need AVServices update", type: .info)
        DisplayManager.shared.updateArm64AVServices()
        self.job(start: true)
      }
      self.startupActionWriteRepeatAfterSober()
    }
  }

  private func startupActionWriteRepeatAfterSober(dispatchedCounter: Int = 0) {
    let counter = dispatchedCounter == 0 ? 10 : dispatchedCounter
    self.startupActionWriteCounter = dispatchedCounter == 0 ? counter : self.startupActionWriteCounter
    guard prefs.integer(forKey: PrefKey.startupAction.rawValue) == StartupAction.write.rawValue, self.startupActionWriteCounter == counter else {
      return
    }
    os_log("Sober write action repeat for DDC - %{public}@", type: .info, String(counter))
    DisplayManager.shared.restoreOtherDisplays()
    self.startupActionWriteCounter = counter - 1
    if counter > 1 {
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        self.startupActionWriteRepeatAfterSober(dispatchedCounter: counter - 1)
      }
    }
  }

  private func job(start: Bool = false) {
    guard !(self.jobRunning && start) else {
      return
    }
    if self.sleepID == 0, self.reconfigureID == 0 {
      if !self.jobRunning {
        os_log("MonitorControl job started.", type: .info)
        self.jobRunning = true
      }
      var refreshedSomething = false
      for display in DisplayManager.shared.displays {
        let delta = display.refreshBrightness()
        if delta != 0 {
          refreshedSomething = true
          if prefs.bool(forKey: PrefKey.enableBrightnessSync.rawValue) {
            for targetDisplay in DisplayManager.shared.displays where targetDisplay != display {
              os_log("Updating delta from display %{public}@ to display %{public}@", type: .info, String(display.identifier), String(targetDisplay.identifier))
              let newValue = max(0, min(1, targetDisplay.getBrightness() + delta))
              _ = targetDisplay.setBrightness(newValue)
              if let slider = targetDisplay.sliderHandler[.brightness] {
                slider.setValue(newValue, displayID: targetDisplay.identifier)
              }
            }
          }
        }
      }
      let nextRefresh = refreshedSomething ? 0.1 : 1.0
      DispatchQueue.main.asyncAfter(deadline: .now() + nextRefresh) {
        self.job()
      }
    } else {
      self.jobRunning = false
      os_log("MonitorControl job died because of sleep or reconfiguration.", type: .info)
    }
  }
  
  func settingsReset() {
    os_log("Resetting all settings.")
    if !prefs.bool(forKey: PrefKey.disableCombinedBrightness.rawValue) {
      DisplayManager.shared.resetSwBrightnessForAllDisplays(async: false)
    }
    if let bundleID = Bundle.main.bundleIdentifier {
      prefs.removePersistentDomain(forName: bundleID)
    }
    app.updateStatusItemVisibility(true)
    self.setDefaultPrefs()
    self.configure(firstrun: true)
  }
  
  func getSystemSettings() -> [String: AnyObject]? {
    var propertyListFormat = PropertyListSerialization.PropertyListFormat.xml
    let plistPath = NSString(string: "~/Library/Preferences/.GlobalPreferences.plist").expandingTildeInPath
    guard let plistXML = FileManager.default.contents(atPath: plistPath) else {
      return nil
    }
    do {
      return try PropertyListSerialization.propertyList(from: plistXML, options: .mutableContainersAndLeaves, format: &propertyListFormat) as? [String: AnyObject]
    } catch {
      os_log("Error reading system prefs plist: %{public}@", type: .info, error.localizedDescription)
      return nil
    }
  }

  func macOS10() -> Bool {
    if !DEBUG_MACOS10, #available(macOS 11.0, *) {
      return false
    } else {
      return true
    }
  }

  private func setMenu() {
    menu = MenuHandler()
    menu.delegate = menu
    self.statusItem.button?.image = NSImage(named: "status")
    self.statusItem.menu = menu
  }

  private func showSafeModeAlertIfNeeded() {
    if NSEvent.modifierFlags.contains(NSEvent.ModifierFlags.shift) {
      self.safeMode = true
      let alert = NSAlert()
      alert.messageText = NSLocalizedString("Safe Mode Activated", comment: "Shown in the alert dialog")
      alert.informativeText = NSLocalizedString("Shift was pressed during launch. MonitorControl started in safe mode. Default settings are reloaded, DDC read is blocked.", comment: "Shown in the alert dialog")
      alert.runModal()
    }
  }
  
  private func statusItemVisibilityChanged() {
    if !self.statusItem.isVisible, self.statusItemVisibilityChangedByUser {
      prefs.set(MenuIcon.hide.rawValue, forKey: PrefKey.menuIcon.rawValue)
    }
  }
  
  func updateStatusItemVisibility(_ visible: Bool) {
    statusItemVisibilityChangedByUser = false
    statusItem.isVisible = visible
    statusItemVisibilityChangedByUser = true
  }
  
  @objc func showAbout(_ sender: Any?) {
      NSApp.orderFrontStandardAboutPanel(nil)
  }
  
  @objc func toggleNaturalScrolling(_ sender: NSMenuItem) {
      Vars.shared.naturalScrolling.toggle()
      sender.state = Vars.shared.naturalScrolling ? .on : .off
  }
  
  @objc func openDisplaySettings(_ sender: Any?) {
      if let url = URL(string: "x-apple.systempreferences:com.apple.preference.displays") {
          NSWorkspace.shared.open(url)
      }
  }
  
  
  
}
