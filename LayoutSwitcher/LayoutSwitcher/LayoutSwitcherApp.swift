//
//  LayoutSwitcherApp.swift
//  LayoutSwitcher
//
//  Точка входа. Вся логика — в Core/, Hotkeys/ и UI/.
//

import SwiftUI
import AppKit

@main
struct LayoutSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button(L(.cmdAbout)) { showAboutWindow() }
            }
            CommandGroup(replacing: .appTermination) {
                Button(L(.cmdQuit)) { NSApplication.shared.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
    
    private func showAboutWindow() {
        let alert = NSAlert()
        alert.messageText = "Layout Switcher"
        alert.informativeText = """
        \(L(.aboutDesc2))
        
        \(L(.aboutVersionLabel)): \(Bundle.main.appVersionString)
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: L(.btnOk))
        alert.runModal()
    }
}
