//
//  Utils.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 01.01.24.
//

import IOKit
import StoreKit
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

@available(macOS 13.0, *)
private func getAppTransaction() async -> VerificationResult<AppTransaction>? {
    do {
        let shared = try await AppTransaction.shared
        return shared
    } catch {
        print("Fetching app transaction failed")
    }
    return nil
}

@available(macOS 10.15, *)
func generateReport() async -> String {
    var report = "BrightIntosh Report:\n"
    report += "OS-Version: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
    #if STORE
        report += "Version: BrightIntosh SE v\(appVersion)\n"
    #else
        report += "Version: BrightIntosh v\(appVersion)\n"
    #endif
    report += "Model Identifier: \(getModelIdentifier() ?? "N/A")\n"
  if #available(macOS 13.0, *) {
    if let sharedAppTransaction = await getAppTransaction() {
      if case .verified(let appTransaction) = sharedAppTransaction {
        report += "Original Purchase Date: \(appTransaction.originalPurchaseDate)\n"
        report += "Original App Version: \(appTransaction.originalAppVersion)\n"
        report += "Transaction for App Version: \(appTransaction.appVersion)\n"
        report += "Transaction Environment: \(appTransaction.environment.rawValue)\n"
      }
      if case .unverified(_, let verificationError) = sharedAppTransaction {
        report +=
        "Error: App Transaction: \(verificationError.errorDescription ?? "no error description") - \(verificationError.failureReason ?? "no failure reason")\n"
      }
    } else {
      report += "Error: App Transaction could not be fetched \n"
    }
  } else {
    // Fallback on earlier versions
  }

  let isUnrestricted = true
    report += "Unrestricted user: \(isUnrestricted)\n"
    report += "Screens: \(NSScreen.screens.map{$0.localizedName}.joined(separator: ", "))\n"
    for screen in NSScreen.screens {
        report += " - Screen \(NSScreen.screens.map{$0.localizedName}): \(screen.frame.width)x\(screen.frame.height)px\n"
    }
    return report
}
