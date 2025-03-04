//
//  BrightnessStatusItemView.swift
//  MonitorControl
//
//  Created by Stefano on 04/03/2025.
//  Copyright © 2025 MonitorControl. All rights reserved.
//
import Cocoa
import SwiftUI

@available(macOS 10.15, *)
class BrightnessStatusItemView: NSView {
    var scrollAccumulator: CGFloat = 0.0
    let brightnessStep: CGFloat = 0.0075
    let scrollStepThreshold: CGFloat = 5.0
    
    // Haptic feedback properties
    private var lastHapticFeedbackTime: Date = .distantPast
    private let hapticFeedbackInterval: TimeInterval = 0.025
    private let hapticFeedbackPattern: NSHapticFeedbackManager.FeedbackPattern = .generic
    
    // Hold the current brightness value. Updating it will refresh the SwiftUI view.
    var currentBrightness: CGFloat = 0.5 {
        didSet { updateIconView() }
    }
    
    // SwiftUI hosting view for the brightness icon.
    private var hostingView: NSHostingView<BrightnessIconView>?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        
        if #available(macOS 10.15, *) {
            // If available, set the current brightness from the first display (if any).
            if let firstDisplay = DisplayManager.shared.displays.first {
                self.currentBrightness = CGFloat(firstDisplay.getBrightness())
            }
            // Create the SwiftUI view and wrap it in an NSHostingView.
            let swiftUIView = BrightnessIconView(brightness: self.currentBrightness)
            hostingView = NSHostingView(rootView: swiftUIView)
            if let hostingView = hostingView {
                hostingView.frame = self.bounds
                hostingView.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
                addSubview(hostingView)
            }
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // Update the SwiftUI view when the brightness value changes.
    private func updateIconView() {
        if #available(macOS 10.15, *) {
            hostingView?.rootView = BrightnessIconView(brightness: self.currentBrightness)
        }
    }
    
    override func scrollWheel(with event: NSEvent) {
        // Accumulate scroll delta (invert if needed)
        scrollAccumulator += event.scrollingDeltaY

        // Increase brightness
        while scrollAccumulator >= scrollStepThreshold {
            for display in DisplayManager.shared.displays {
                let current = CGFloat(display.getBrightness())
                if current < 1.0 {
                    let newValue = min(1.0, current + brightnessStep)
                    if newValue != current {
                        _ = display.setBrightness(Float(newValue))
                        performHapticFeedbackIfNeeded()
                        self.currentBrightness = newValue
                    }
                }
            }
            scrollAccumulator = 0
        }

        // Decrease brightness
        while scrollAccumulator <= -scrollStepThreshold {
            for display in DisplayManager.shared.displays {
                let current = CGFloat(display.getBrightness())
                if current > 0.0 {
                    let newValue = max(0.0, current - brightnessStep)
                    if newValue != current {
                        _ = display.setBrightness(Float(newValue))
                        performHapticFeedbackIfNeeded()
                        self.currentBrightness = newValue
                    }
                }
            }
            scrollAccumulator = 0
        }
    }
    
    private func performHapticFeedbackIfNeeded() {
        let now = Date()
        if now.timeIntervalSince(lastHapticFeedbackTime) >= hapticFeedbackInterval {
            NSHapticFeedbackManager.defaultPerformer.perform(hapticFeedbackPattern, performanceTime: .now)
            lastHapticFeedbackTime = now
        }
    }
}
