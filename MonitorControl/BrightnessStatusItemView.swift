//
//  BrightnessStatusItemView.swift
//  MonitorControl
//
//  Created by Stefano on 04/03/2025.
//  Merged and updated on [Your Date].
//  Copyright © 2025 MonitorControl. All rights reserved.
//

import Cocoa
import SwiftUI

@available(macOS 10.15, *)
class BrightnessStatusItemView: NSView {
    
    // MARK: - Properties
    var scrollAccumulator: CGFloat = 0.0
    let brightnessStep: CGFloat = 0.0075
    let scrollStepThreshold: CGFloat = 5.0
    
    // Haptic feedback properties
    private var lastHapticFeedbackTime: Date = .distantPast
    private let hapticFeedbackInterval: TimeInterval = 0.025
    private let hapticFeedbackPattern: NSHapticFeedbackManager.FeedbackPattern = .generic

    // Hold the current brightness value.
    var currentBrightness: CGFloat = 0.5 {
        didSet {
            updateIconView()
        }
    }

    // SwiftUI hosting view for the brightness icon.
    private var hostingView: NSHostingView<BrightnessIconView>?
    
    // MARK: - Intrinsic Content Size
    // This tells the system how large the status item should be.
    override var intrinsicContentSize: NSSize {
        // You can adjust the width as needed. Here we use 32 points.
        return NSSize(width: 40, height: NSStatusBar.system.thickness)
    }
    
  
    // MARK: - SwiftUI View
    struct BrightnessIconView: View {
        var brightness: CGFloat
        @Environment(\.colorScheme) private var colorScheme

        // Use .primary so the icon adapts to the system color (light/dark)
        private var iconColor: Color {
            Color.primary
        }
        
        var body: some View {
          let sunIcoBrt: String = {
              if brightness > 0 && brightness < 0.3 {
                  return "sun.min"
              } else if brightness >= 0.3 && brightness <= 0.6 {
                  return "sun.min.fill"
              } else {
                  return "sun.max.fill"
              }
          }()
          
          if #available(macOS 11.0, *) {
            Image(systemName: sunIcoBrt)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .foregroundColor(iconColor)
            // Rotate the sun icon based on brightness (adjust multiplier if desired)
              .rotationEffect(.degrees(Double(brightness) * 360))
              .frame(width: 16, height: 16)
              .padding(4)
          }
        }
    }
    
    // MARK: - Initializers
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // Setup view by adding the hosting view directly (no background container)
    private func setupView() {
        // Set the initial brightness from the first display, if available.
        if let firstDisplay = DisplayManager.shared.displays.first {
            self.currentBrightness = CGFloat(firstDisplay.getBrightness())
        }
        
        // Create the SwiftUI view and wrap it in an NSHostingView.
        let rootView = BrightnessIconView(brightness: currentBrightness)
        hostingView = NSHostingView(rootView: rootView)
        hostingView?.translatesAutoresizingMaskIntoConstraints = false
        hostingView?.wantsLayer = true
        hostingView?.layer?.backgroundColor = NSColor.clear.cgColor
        
        if let hostingView = hostingView {
            addSubview(hostingView)
            // Constrain the hosting view to fill the entire NSView
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: self.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
            ])
        }
        
        // Observe changes in the system's appearance.
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(updateAppearance),
            name: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil
        )
    }
    
    // MARK: - Appearance Updates
    @objc private func updateAppearance() {
        // Trigger the SwiftUI view update by setting the brightness.
        hostingView?.rootView.brightness = currentBrightness
    }
    
    // Update the SwiftUI view when the brightness value changes.
    private func updateIconView() {
        hostingView?.rootView.brightness = currentBrightness
    }
    
    // MARK: - Scroll Events
    override func scrollWheel(with event: NSEvent) {
        // Accumulate scroll delta.
        let scrollMultiplier: CGFloat = Vars.shared.naturalScrolling ? 1.0 : -1.0
        let delta = -1 * event.scrollingDeltaY * scrollMultiplier
        
        scrollAccumulator += delta
        
        // Increase brightness.
        while scrollAccumulator >= scrollStepThreshold {
            for display in DisplayManager.shared.displays {
                let current = CGFloat(display.getBrightness())
                if current < 1.0 {
                    let newValue = min(1.0, current + brightnessStep)
                    if newValue != current {
                        _ = display.setBrightness(Float(newValue))
                        performHapticFeedbackIfNeeded()
                        self.currentBrightness = newValue
                        OSDUtils.showOsd(displayID: display.identifier, command: .brightness, value: Float(newValue) * 64, maxValue: 64)
                    }
                }
            }
            scrollAccumulator = 0
        }
        
        // Decrease brightness.
        while scrollAccumulator <= -scrollStepThreshold {
            for display in DisplayManager.shared.displays {
                let current = CGFloat(display.getBrightness())
                if current > 0.0 {
                    let newValue = max(0.0, current - brightnessStep)
                    if newValue != current {
                        _ = display.setBrightness(Float(newValue))
                        performHapticFeedbackIfNeeded()
                        self.currentBrightness = newValue
                        OSDUtils.showOsd(displayID: display.identifier, command: .brightness, value: Float(newValue) * 64, maxValue: 64)
                    }
                }
            }
            scrollAccumulator = 0
        }
    }
    
    // MARK: - Haptic Feedback
    private func performHapticFeedbackIfNeeded() {
        let now = Date()
        if now.timeIntervalSince(lastHapticFeedbackTime) >= hapticFeedbackInterval {
            NSHapticFeedbackManager.defaultPerformer.perform(hapticFeedbackPattern, performanceTime: .now)
            lastHapticFeedbackTime = now
        }
    }
}

// MARK: - NSAppearance Extension
extension NSAppearance {
    var isDarkMode: Bool {
        if self.name == .vibrantDark {
            return true
        } else if self.name == .vibrantLight {
            return false
        }
        return self.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
