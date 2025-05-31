//
//  Utils.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 01.01.24.
//

import IOKit
import Cocoa

func getXDRDisplays() -> [NSScreen] {
    var xdrScreens: [NSScreen] = []
    for screen in NSScreen.screens {
        if ((isBuiltInScreen(screen: screen) && isDeviceSupported()) || (externalXdrDisplays.contains(screen.localizedName) && !Vars.shared.brightIntoshOnlyOnBuiltIn)) {
            xdrScreens.append(screen)
        }
    }
    return xdrScreens
}

func isBuiltInScreen(screen: NSScreen) -> Bool {
    let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
    let displayId: CGDirectDisplayID = screenNumber as! CGDirectDisplayID
    return CGDisplayIsBuiltin(displayId) != 0
}

@available(macOS 12.0, *)
func getModelIdentifier() -> String? {
    let service = IOServiceGetMatchingService(
        kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
    var modelIdentifier: String?
    if let modelData = IORegistryEntryCreateCFProperty(
        service, "model" as CFString, kCFAllocatorDefault, 0
    ).takeRetainedValue() as? Data {
        modelIdentifier = String(data: modelData, encoding: .utf8)?.trimmingCharacters(
            in: .controlCharacters)
    }

    IOObjectRelease(service)
    return modelIdentifier
}

@available(macOS 12.0, *)
func isDeviceSupported() -> Bool {
    if let device = getModelIdentifier(), supportedDevices.contains(device) {
        return true
    }
    return false
}

@available(macOS 12.0, *)
func getDeviceMaxBrightness() -> Float {
    if let device = getModelIdentifier(),
        sdr600nitsDevices.contains(device)
    {
        return 1.535
    }
    return 1.59
}


