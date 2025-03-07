//
//  AppleNativeControl.swift
//  Lunar
//
//  Created by Alin Panaitiu on 18.02.2021.
//  Copyright © 2021 Alin. All rights reserved.
//

import Defaults
import Foundation
import SwiftDate

// MARK: - AppleNativeMethod

enum AppleNativeMethod {
    case coreDisplay
    case displayServices
}

// MARK: - AppleNativeControl

final class AppleNativeControl: Control {
    init(display: Display) {
        self.display = display
    }

    @Atomic static var sliderTracking = false

    var displayControl: DisplayControl = .appleNative

    weak var display: Display?
    lazy var responsive: Bool = testReadAndWrite(method: .displayServices) || testReadAndWrite(method: .coreDisplay)
    let str = "AppleNative Control"
    var method = AppleNativeMethod.displayServices

    var smoothTransitionTask: DispatchWorkItem?

    var nitsUpdateRepeater: Repeater? = nil

    var smoothTransitionWatcher: Repeater?

    var isSoftware: Bool { false }
    var isDDC: Bool { true }

    static func isAvailable(for display: Display) -> Bool {
        guard display.active else { return false }
        guard let enabledForDisplay = display.enabledControls[.appleNative], enabledForDisplay else { return false }
        #if DEBUG
            return display.isForTesting || display.canChangeBrightnessDS
        #else
            return display.canChangeBrightnessDS
        #endif
        // return (
        //     display.isAppleDisplay() ||
        //         (display.isBuiltin && (DisplayController.panel(with: display.id)?.isSmartDisplay ?? false)) ||
        //         display.isForTesting
        // )
    }

    static func readBrightnessDisplayServices(id: CGDirectDisplayID) -> Double {
        var br: Float = 0.0
        DisplayServicesGetBrightness(id, &br)
        return br.d
    }

    static func readBrightnessCoreDisplay(id: CGDirectDisplayID) -> Double {
        CoreDisplay_Display_GetUserBrightness(id)
    }

    func testReadAndWrite(method: AppleNativeMethod) -> Bool {
        guard let display else { return false }

        switch method {
        case .coreDisplay:
            let currentBrightness = CoreDisplay_Display_GetUserBrightness(display.id)
            let brightnessToSet = currentBrightness < 0.5 ? currentBrightness + 0.01 : currentBrightness - 0.01
            CoreDisplay_Display_SetUserBrightness(display.id, brightnessToSet)

            let newBrightness = CoreDisplay_Display_GetUserBrightness(display.id)

            guard newBrightness == brightnessToSet else {
                return false
            }

            CoreDisplay_Display_SetUserBrightness(display.id, currentBrightness)
            self.method = method
            return true
        case .displayServices:
            if DisplayServicesCanChangeBrightness(display.id) {
                self.method = method
                return true
            }

            var currentBrightness: Float = 0.0
            guard DisplayServicesGetBrightness(display.id, &currentBrightness) == KERN_SUCCESS else {
                return false
            }

            let brightnessToSet = currentBrightness < 0.5 ? currentBrightness + 0.01 : currentBrightness - 0.01
            guard DisplayServicesSetBrightness(display.id, brightnessToSet) == KERN_SUCCESS else {
                return false
            }

            var newBrightness: Float = 0.0
            guard DisplayServicesGetBrightness(display.id, &newBrightness) == KERN_SUCCESS else {
                return false
            }

            guard newBrightness == brightnessToSet else {
                return false
            }

            DisplayServicesSetBrightness(display.id, currentBrightness)
            self.method = method
            return true
        }
    }

    func isAvailable() -> Bool {
        guard let display else { return false }
        return Self.isAvailable(for: display)
    }

    func isResponsive() -> Bool {
        true
//        #if DEBUG
//            guard let display = display else { return false }
//            return responsive || TEST_IDS.contains(display.id)
//        #else
//            return responsive
//        #endif
    }

    func resetState() {
        responsive = testReadAndWrite(method: .displayServices) || testReadAndWrite(method: .coreDisplay)
    }

    func writeBrightness(_ brightness: Brightness, preciseBrightness: PreciseBrightness? = nil) -> Bool {
        guard let display else { return false }
        let br = preciseBrightness ?? (brightness.d / 100.0)
        var success = true

        switch method {
        case .coreDisplay:
            CoreDisplay_Display_SetUserBrightness(display.id, br)
        case .displayServices:
            success = DisplayServicesSetBrightness(display.id, br.f) == KERN_SUCCESS
            if success, br == 1.0 {
                DisplayServicesSetLinearBrightness(display.id, br.f)
            }
            updateNits()
        }

        display.lastNativeBrightness = br
        return success
    }

    func setPower(_ power: PowerState) -> Bool {
        guard let display else { return false }
        guard let control = display.alternativeControlForAppleNative else { return false }
        return control.setPower(power)
    }

    func setRedGain(_ gain: UInt16) -> Bool {
        guard let display else { return false }
        guard let control = display.alternativeControlForAppleNative else { return false }
        return control.setRedGain(gain)
    }

    func setGreenGain(_ gain: UInt16) -> Bool {
        guard let display else { return false }
        guard let control = display.alternativeControlForAppleNative else { return false }
        return control.setGreenGain(gain)
    }

    func setBlueGain(_ gain: UInt16) -> Bool {
        guard let display else { return false }
        guard let control = display.alternativeControlForAppleNative else { return false }
        return control.setBlueGain(gain)
    }

    func getRedGain() -> UInt16? {
        guard let display else { return nil }
        guard let control = display.alternativeControlForAppleNative else { return nil }
        return control.getRedGain()
    }

    func getGreenGain() -> UInt16? {
        guard let display else { return nil }
        guard let control = display.alternativeControlForAppleNative else { return nil }
        return control.getGreenGain()
    }

    func getBlueGain() -> UInt16? {
        guard let display else { return nil }
        guard let control = display.alternativeControlForAppleNative else { return nil }
        return control.getBlueGain()
    }

    func resetColors() -> Bool {
        guard let display else { return false }
        guard let control = display.alternativeControlForAppleNative else { return false }
        return control.resetColors()
    }

    func updateNits() {
        #if arch(arm64)
            mainAsync { [self] in
                guard let display, let maxNits = display.possibleMaxNits else {
                    return
                }

                var brightness: Float = 0.0
                DisplayServicesGetLinearBrightness(display.id, &brightness)
                let nits = maxNits * brightness.d
                display.nits = nits

                if let osd = display.osdWindowController?.window as? OSDWindow,
                   let osdAlpha = osd.contentView?.superview?.alphaValue,
                   osdAlpha == 1, display.osdState.text.contains("nits"), display.userNits != nits
                {
                    display.userNits = nits
                    display.softwareOSDTask = nil
                    display.osdState.text = "\(nits.str(decimals: 0)) nits"
                    osd.show(verticalOffset: 100)
                } else if CachedDefaults[.hideOSD], timeSince(DC.lastTimeBrightnessKeyPressed) < 1, display.userNits != nits {
                    display.userNits = nits
                }

                if DC.supportsXDRContrast, timeSince(lastXDRContrastResetTime) > 3 {
                    let xdrContrast = display.computeXDRContrast(xdrBrightness: nits.f.capped(between: 600, and: 1600), xdrContrastFactor: CachedDefaults[.xdrContrastFactor] + 0.3, minBrightness: 600, maxBrightness: 1600, gamma: 2.2)
                    if xdrContrast != DC.xdrContrast {
                        DC.setXDRContrast(xdrContrast)
                    }
                }
            }
        #endif
    }

    func setBrightness(
        _ brightness: Brightness,
        oldValue: Brightness? = nil,
        force: Bool = false,
        transition: BrightnessTransition? = nil,
        onChange: ((Brightness) -> Void)? = nil
    ) -> Bool {
        guard let display else { return false }
        guard !display.isForTesting else { return false }

        let brightnessTransition = transition ?? brightnessTransition
        if brightnessTransition != .instant, !Self.sliderTracking, supportsSmoothTransition(for: .BRIGHTNESS), var oldValue,
           oldValue != brightness
        {
            if display.inSmoothTransition {
                display.shouldStopBrightnessTransition = true
                oldValue = display.lastWrittenBrightness
            }

            display.inSmoothTransition = true
            display.shouldStopBrightnessTransition = true

            smoothTransitionTask?.cancel()
            smoothTransitionTask = DispatchWorkItem(name: "smoothTransitionDisplayServices: \(display)", flags: .barrier) { [weak self] in
                guard let self, let display = self.display else {
                    return
                }

                guard brightnessTransition == .slow else {
                    let br = brightness.d / 100.0
                    var oldBrFloat = oldValue.f / 100.0
                    DisplayServicesGetBrightness(display.id, &oldBrFloat)

                    let id = display.id
                    display.inSmoothTransition = true
                    display.shouldStopBrightnessTransition = false

                    DisplayServicesSetBrightnessSmooth(id, br.f - oldBrFloat)

                    updateNitsWithRetry()
                    smoothTransitionWatcher = Repeater(every: 0.01, times: 50, name: "smoothTransitionWatcherAppleNative", onFinish: {
                        DisplayServicesSetBrightness(id, br.f)
                        if br == 1.0 {
                            DisplayServicesSetLinearBrightness(id, br.f)
                        }
                        display.lastWrittenBrightness = self.getBrightness() ?? display.lastWrittenBrightness
                        display.inSmoothTransition = false
                    }, onCancel: {
                        display.lastWrittenBrightness = self.getBrightness() ?? display.lastWrittenBrightness
                    }) {
                        guard display.shouldStopBrightnessTransition else {
                            return
                        }
                        log.debug("Stopping smooth transition on brightness=\(brightness) using \(self) for \(display)")
                        display.lastWrittenBrightness = self.getBrightness() ?? display.lastWrittenBrightness
                    }

                    return
                }

                let step = brightness > oldValue ? 0.002 : -0.002
                let prevBrightness = oldValue.d / 100.0
                let nextBrightness = brightness.d / 100.0
                let interval = (brightnessTransition == .smooth ? 0.004 : 0.025)

                display.inSmoothTransition = true
                display.shouldStopBrightnessTransition = false

                for brightness in stride(from: prevBrightness, through: nextBrightness, by: step) {
                    guard !display.shouldStopBrightnessTransition else {
                        log.debug("Stopping smooth transition on brightness=\(brightness) using \(self) for \(display)")
                        return
                    }

                    // log.debug("Writing brightness=\(brightness) using \(self) to \(display)")
                    _ = writeBrightness(0, preciseBrightness: brightness)
                    let br = (brightness * 100).intround.u16
                    display.lastWrittenBrightness = br
                    onChange?(br)
                    Thread.sleep(forTimeInterval: interval)
                }
                _ = writeBrightness(brightness)
                display.lastWrittenBrightness = brightness
                onChange?(brightness)
                display.inSmoothTransition = false
            }

            smoothDisplayServicesQueue.asyncAfter(deadline: DispatchTime.now(), execute: smoothTransitionTask!.workItem)
            return true
        }

        #if DEBUG
            if brightnessTransition == .smooth {
                log.debug(
                    "Skipping smooth transition on brightness=\(brightness) using \(self) for \(display)",
                    context: [
                        "sliderTracking": Self.sliderTracking,
                        "supportsSmoothTransition": supportsSmoothTransition(for: .BRIGHTNESS),
                        "oldValue": oldValue as Any,
                    ]
                )
            }
        #endif
        onChange?(brightness)
        return writeBrightness(brightness)
    }
    func updateNitsWithRetry() {
        nitsUpdateRepeater = Repeater(every: 0.05, times: 10, name: "nitsUpdater") { [weak self] in
            guard let self else { return }
            updateNits()
        }
    }

    func setContrast(
        _ contrast: Contrast,
        oldValue: Contrast? = nil,
        transition: BrightnessTransition? = nil,
        onChange: ((Contrast) -> Void)? = nil
    ) -> Bool {
        guard let display else { return false }
        guard let control = display.alternativeControlForAppleNative else { return false }
        return control.setContrast(contrast, oldValue: oldValue, transition: transition, onChange: onChange)
    }

    func setVolume(_ volume: UInt16) -> Bool {
        guard let display else { return false }
        guard let control = display.alternativeControlForAppleNative else { return false }
        return control.setVolume(volume)
    }

    func setMute(_ muted: Bool) -> Bool {
        guard let display else { return false }
        guard let control = display.alternativeControlForAppleNative else { return false }
        return control.setMute(muted)
    }

    func setInput(_ input: VideoInputSource) -> Bool {
        guard let display else { return false }
        guard let control = display.alternativeControlForAppleNative else { return false }
        return control.setInput(input)
    }

    func getBrightness() -> Brightness? {
        guard let display else { return nil }
        guard !display.isForTesting else { return display.brightness.uint16Value }

        switch method {
        case .coreDisplay:
            return (CoreDisplay_Display_GetUserBrightness(display.id) * 100.0).u16
        case .displayServices:
            var br = display.preciseBrightness.f
            DisplayServicesGetBrightness(display.id, &br)
            return (br * 100.0).u16
        }
    }

    func getContrast() -> Contrast? {
        guard let display else { return nil }
        guard let control = display.alternativeControlForAppleNative else { return nil }
        return control.getContrast()
    }

    func getMaxBrightness() -> Brightness? {
        guard let display else { return nil }
        guard let control = display.alternativeControlForAppleNative else { return nil }
        return control.getMaxBrightness()
    }

    func getMaxContrast() -> Contrast? {
        guard let display else { return nil }
        guard let control = display.alternativeControlForAppleNative else { return nil }
        return control.getMaxContrast()
    }

    func getMaxVolume() -> UInt16? {
        guard let display else { return nil }
        guard let control = display.alternativeControlForAppleNative else { return nil }
        return control.getMaxVolume()
    }

    func getVolume() -> UInt16? {
        guard let display else { return nil }
        guard let control = display.alternativeControlForAppleNative else { return nil }
        return control.getVolume()
    }

    func getMute() -> Bool? {
        guard let display else { return nil }
        guard let control = display.alternativeControlForAppleNative else { return nil }
        return control.getMute()
    }

    func getInput() -> VideoInputSource? {
        guard let display else { return nil }
        guard let control = display.alternativeControlForAppleNative else { return nil }
        return control.getInput()
    }

    func reset() -> Bool {
        guard let display else { return false }
        guard let control = display.alternativeControlForAppleNative else { return false }
        return control.reset()
    }

    func supportsSmoothTransition(for controlID: ControlID) -> Bool {
        switch controlID {
        case .BRIGHTNESS:
            return true
        default:
            guard let display else { return false }
            guard let control = display.alternativeControlForAppleNative else { return false }
            return control.supportsSmoothTransition(for: controlID)
        }
    }
}
