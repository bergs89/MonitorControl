//
//  BrightnessModel.swift
//  MonitorControl
//
//  Created by Stefano on 04/03/2025.
//  Copyright © 2025 MonitorControl. All rights reserved.
//


import SwiftUI
import Combine

@available(macOS 10.15, *)
class BrightnessModel: ObservableObject {
    @Published var brightness: CGFloat = 0.5
}

@available(macOS 10.15, *)
struct BrightnessIconView: View {
    var brightness: CGFloat  // Plain value
    var body: some View {
      if #available(macOS 11.0, *) {
        Image(systemName: "sun.max.fill")
          .resizable()
          .aspectRatio(contentMode: .fit)
          .rotationEffect(Angle(degrees: (1.0 - Double(brightness)) * -360))
          .foregroundColor(.yellow)
      } else {
        // Fallback on earlier versions
      }
    }
}
