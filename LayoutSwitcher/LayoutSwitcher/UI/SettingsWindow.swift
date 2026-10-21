//
//  SettingsWindow.swift
//  LayoutSwitcher
//
//  Окно настроек (NSWindow + NSHostingView), одно на приложение.
//

import AppKit
import SwiftUI

@MainActor
final class SettingsWindow {
    private static var window: NSWindow?
    private static var windowDelegate: WindowDelegate?
    /// Идентификатор окна настроек (не зависит от языка — для надёжного поиска/закрытия).
    static let windowIdentifier = "LayoutSwitcherSettingsWindow"
    private let settings: SettingsManager
    
    init(settings: SettingsManager) {
        self.settings = settings
    }
    
    func show() {
        if let existing = Self.window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = L(.settingsWindowTitle)
        newWindow.identifier = NSUserInterfaceItemIdentifier(Self.windowIdentifier)
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        newWindow.contentView = NSHostingView(rootView: SettingsView(settings: settings))
        newWindow.minSize = NSSize(width: 600, height: 500)
        
        Self.window = newWindow
        
        let delegate = WindowDelegate()
        Self.windowDelegate = delegate
        newWindow.delegate = delegate
        
        NSApp.setActivationPolicy(.regular)
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private class WindowDelegate: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            SettingsWindow.window = nil
            SettingsWindow.windowDelegate = nil
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
