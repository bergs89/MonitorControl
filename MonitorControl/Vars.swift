//
//  Vars.swift
//  BrightIntosh
//
//  Created by Niklas Rousset on 23.09.23.
//

import Foundation
import ServiceManagement


final class Vars {
    static let shared: Vars = Vars()
    
    
    public var brightintoshActive: Bool = UserDefaults.standard.object(forKey: "active") != nil ? UserDefaults.standard.bool(forKey: "active") : true {
        didSet {
            UserDefaults.standard.setValue(brightintoshActive, forKey: "active")
            callListeners(setting: "brightintoshActive")
        }
    }
    
    public var brightIntoshOnlyOnBuiltIn: Bool = UserDefaults.standard.object(forKey: "brightIntoshOnlyOnBuiltIn") != nil ? UserDefaults.standard.bool(forKey: "brightIntoshOnlyOnBuiltIn") : false {
        didSet {
            UserDefaults.standard.setValue(brightintoshActive, forKey: "brightIntoshOnlyOnBuiltIn")
            callListeners(setting: "brightIntoshOnlyOnBuiltIn")
        }
    }
    
    public var brightness: Float = UserDefaults.standard.object(forKey: "brightness") != nil ? UserDefaults.standard.float(forKey: "brightness") : getDeviceMaxBrightness() {
        didSet {
            UserDefaults.standard.setValue(brightness, forKey: "brightness")
            callListeners(setting: "brightness")
        }
    }
    
    
    private var listeners: [String: [()->()]] = [:]
  
    public var naturalScrolling: Bool = {
        if let value = UserDefaults.standard.object(forKey: "naturalScrolling") as? Bool {
            return value
        }
        return true // or true if you want natural scrolling enabled by default
    }() {
        didSet {
            UserDefaults.standard.set(naturalScrolling, forKey: "naturalScrolling")
            callListeners(setting: "naturalScrolling")
        }
    }
    
    public func addListener(setting: String, callback: @escaping () ->()) {
        if !listeners.keys.contains(setting) {
            listeners[setting] = []
        }
        listeners[setting]?.append(callback)
    }
    
    private func callListeners(setting: String) {
        if let setting_listeners = listeners[setting] {
            setting_listeners.forEach { callback in
                callback()
            }
        }
    }
}
