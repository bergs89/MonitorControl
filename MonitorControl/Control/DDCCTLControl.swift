//
//  DDCCTLControl.swift
//  Lunar
//
//  Created by Alin Panaitiu on 20.05.2021.
//  Copyright © 2021 Alin. All rights reserved.
//

import Cocoa
import Foundation

struct DDCCTLControl: Control {
    init(display: Display) {
        self.display = display
    }

    static let ddcctlBinary = Bundle.main.path(forResource: "ddcctl", ofType: nil)!

    weak var display: Display?

    var str = "ddcctl"

    var displayControl: DisplayControl = .ddcctl

    var isSoftware: Bool { false }
    var isDDC: Bool { true }

    var displayIndex: Int? {
        guard let display else { return nil }
        return display.nsScreen != nil ? NSScreen.screens.filter { !$0.isBuiltin }.firstIndex(of: display.nsScreen!) : nil
    }

    func propertyArg(_ property: ControlID) -> String {
        switch property {
        case .BRIGHTNESS:
            "-b"
        case .CONTRAST:
            "-c"
        case .AUDIO_MUTE:
            "-m"
        case .INPUT_SOURCE:
            "-i"
        case .AUDIO_SPEAKER_VOLUME:
            "-v"
        case .DPMS:
            "-p"
        case .RESET_BRIGHTNESS_AND_CONTRAST:
            "-rbc"
        case .RED_GAIN:
            "-rg"
        case .GREEN_GAIN:
            "-gg"
        case .BLUE_GAIN:
            "-bg"
        case .RESET_COLOR:
            "-rrgb"
        default:
            ""
        }
    }

    func ddcctlSet(_ property: ControlID, value: UInt16) -> Bool {
        guard let index = displayIndex else { return false }
        let ddcctlSemaphore = DispatchSemaphore(value: 0, name: "ddcctlSemaphore")
        var command = "ddcctl "
        let process: Process
        do {
            var args = ["-d", index.s, propertyArg(property)]
            if property != .RESET_BRIGHTNESS_AND_CONTRAST {
                args.append(value.s)
            }

            command += args.joined(separator: " ")

            process = try Process.run(
                DDCCTLControl.ddcctlBinary.url,
                arguments: args,
                terminationHandler: { process in
                    log.info("`\(command)` status \(process.terminationStatus)")
                    ddcctlSemaphore.signal()
                }
            )
        } catch {
            return false
        }

        guard ddcctlSemaphore.wait(for: 20) != .timedOut else {
            log.error("Timed out on command `\(command)`")
            process.terminate()
            return false
        }

        return process.terminationStatus == 0
    }

    func setRedGain(_ gain: UInt16) -> Bool {
        ddcctlSet(.RED_GAIN, value: gain)
    }

    func setGreenGain(_ gain: UInt16) -> Bool {
        ddcctlSet(.GREEN_GAIN, value: gain)
    }

    func setBlueGain(_ gain: UInt16) -> Bool {
        ddcctlSet(.BLUE_GAIN, value: gain)
    }

    func resetColors() -> Bool {
        ddcctlSet(.RESET_COLOR, value: 1)
    }

    func setBrightness(
        _ value: Brightness,
        oldValue _: Brightness? = nil,
        force: Bool = false,
        transition: BrightnessTransition? = nil,
        onChange: ((Brightness) -> Void)? = nil
    ) -> Bool {
        ddcctlSet(.BRIGHTNESS, value: value)
    }

    func setContrast(
        _ value: Contrast,
        oldValue _: Brightness?,
        transition: BrightnessTransition? = nil,
        onChange: ((Contrast) -> Void)? = nil
    ) -> Bool {
        ddcctlSet(.CONTRAST, value: value)
    }

    func setVolume(_ value: UInt16) -> Bool {
        ddcctlSet(.AUDIO_SPEAKER_VOLUME, value: value)
    }

    func setInput(_ value: VideoInputSource) -> Bool {
        ddcctlSet(.INPUT_SOURCE, value: value.rawValue)
    }

    func setMute(_ value: Bool) -> Bool {
        ddcctlSet(.AUDIO_MUTE, value: value ? 1 : 2)
    }

    func setPower(_ value: PowerState) -> Bool {
        ddcctlSet(.DPMS, value: value == .on ? 1 : 5)
    }

    func getRedGain() -> UInt16? { nil }
    func getGreenGain() -> UInt16? { nil }
    func getBlueGain() -> UInt16? { nil }

    func getBrightness() -> Brightness? {
        nil
    }

    func getContrast() -> Contrast? {
        nil
    }

    func getVolume() -> UInt16? {
        nil
    }

    func getMute() -> Bool? {
        nil
    }

    func getInput() -> VideoInputSource? {
        nil
    }

    func getMaxBrightness() -> Brightness? {
        nil
    }

    func getMaxContrast() -> Contrast? {
        nil
    }

    func getMaxVolume() -> UInt16? {
        nil
    }

    func reset() -> Bool {
        ddcctlSet(.RESET_BRIGHTNESS_AND_CONTRAST, value: 1)
    }

    func resetState() {}

    func isAvailable() -> Bool {
        true
    }

    func isResponsive() -> Bool {
        true
    }

    func supportsSmoothTransition(for _: ControlID) -> Bool {
        false
    }
}
