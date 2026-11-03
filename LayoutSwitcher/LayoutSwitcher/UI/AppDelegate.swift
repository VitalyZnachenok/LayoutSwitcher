//
//  AppDelegate.swift
//  LayoutSwitcher
//
//  Меню в строке состояния, запрос разрешений, точка сборки сервисов.
//

import AppKit
import Combine
import ServiceManagement
import os.log

enum Runtime {
    /// Приложение запущено как host для XCTest или с SKIP_ACCESSIBILITY_CHECK=1:
    /// модальные диалоги о разрешениях заблокировали бы тесты и отладку.
    static let skipsPermissionPrompt: Bool = {
        let env = ProcessInfo.processInfo.environment
        return env["SKIP_ACCESSIBILITY_CHECK"] == "1"
            || env["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }()
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKeyManager: HotKeyManager?
    private let settings = SettingsManager()
    private var accessibilityObserver: NSObjectProtocol?
    private let updates = UpdateChecker.shared
    private var updateCancellable: AnyCancellable?
    /// Версия, о которой уже показывали алерт в этом запуске (повторно не надоедаем).
    private var updateAlertShownFor: String?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.ui.info("Application launched")
        
        setupStatusBar()
        setupAccessibilityObserver()
        hotKeyManager = HotKeyManager(settings: self.settings)
        
        NSApp.setActivationPolicy(.accessory)
        requestAccessibilityPermissions()
        setupUpdateChecker()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Logger.ui.info("Application will terminate")
        
        if let observer = accessibilityObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        hotKeyManager = nil
        
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
    }
    
    private func setupAccessibilityObserver() {
        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: .accessibilityStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateStatusBarIcon() }
        }
    }
    
    private func setupStatusBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusItem?.button else { return }
        
        if let image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Layout Switcher") {
            button.image = image
            button.image?.isTemplate = true
        }
        
        button.action = #selector(statusBarClicked)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        updateStatusBarIcon()
    }
    
    private func updateStatusBarIcon() {
        guard let button = statusItem?.button else { return }
        let hasPermissions = AXIsProcessTrusted()
        let symbolName = hasPermissions ? "keyboard" : "keyboard.badge.exclamationmark"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Layout Switcher") {
            button.image = image
            button.image?.isTemplate = true
        }
    }
    
    @objc private func statusBarClicked() {
        let menu = NSMenu()
        let hasPermissions = AXIsProcessTrusted()
        
        let statusMenuItem = NSMenuItem(
            title: hasPermissions ? L(.menuPermsGranted) : L(.menuPermsRequired),
            action: nil,
            keyEquivalent: ""
        )
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        if let release = updates.available {
            let updateItem = NSMenuItem(
                title: String(format: L(.menuDownloadUpdate), release.version),
                action: #selector(downloadUpdate),
                keyEquivalent: ""
            )
            menu.addItem(updateItem)
        }
        menu.addItem(.separator())
        
        let convertItem = NSMenuItem(
            title: String(format: L(.menuSwitchLayout), self.settings.configuration.displayString),
            action: #selector(manualSwitch),
            keyEquivalent: ""
        )
        convertItem.isEnabled = hasPermissions
        menu.addItem(convertItem)
        
        menu.addItem(.separator())
        
        let soundItem = NSMenuItem(title: L(.menuPlaySounds), action: #selector(toggleSound), keyEquivalent: "")
        soundItem.state = self.settings.configuration.soundEnabled ? .on : .off
        menu.addItem(soundItem)
        
        let launchAtLoginItem = NSMenuItem(title: L(.menuLaunchAtLogin), action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLoginItem)
        
        let autoSwitchItem = NSMenuItem(title: L(.menuAutoSwitch), action: nil, keyEquivalent: "")
        let autoSwitchMenu = NSMenu()
        for mode in AutoSwitchMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(setAutoSwitchMode(_:)), keyEquivalent: "")
            item.state = self.settings.configuration.autoSwitchMode == mode ? .on : .off
            item.representedObject = mode.rawValue
            item.target = self
            item.isEnabled = hasPermissions
            autoSwitchMenu.addItem(item)
        }
        autoSwitchItem.submenu = autoSwitchMenu
        menu.addItem(autoSwitchItem)
        
        menu.addItem(NSMenuItem(title: L(.menuSettings), action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: L(.menuStatistics), action: #selector(showStatistics), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: L(.menuAbout), action: #selector(showAbout), keyEquivalent: ""))
        
        if !hasPermissions {
            menu.addItem(NSMenuItem(title: L(.menuGrantPerms), action: #selector(openAccessibilitySettings), keyEquivalent: ""))
        }
        
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L(.menuQuit), action: #selector(quitApplication), keyEquivalent: "q"))
        
        menu.items.forEach { $0.target = self }
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }
    
    // MARK: - Updates
    
    private func setupUpdateChecker() {
        updateCancellable = updates.$available
            .receive(on: RunLoop.main)
            .sink { [weak self] release in
                guard let self, let release, self.updateAlertShownFor != release.version else { return }
                self.updateAlertShownFor = release.version
                self.showUpdateAlert(for: release)
            }
        updates.start()
    }
    
    private func showUpdateAlert(for release: UpdateChecker.Release) {
        let alert = NSAlert()
        alert.messageText = L(.updAlertTitle)
        alert.informativeText = String(format: L(.updAlertMsg), release.version, updates.currentVersion)
        alert.alertStyle = .informational
        alert.addButton(withTitle: L(.btnDownload))
        alert.addButton(withTitle: L(.btnLater))
        if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            NSWorkspace.shared.open(release.bestURL)
        }
    }
    
    @objc private func downloadUpdate() {
        guard let release = updates.available else { return }
        NSWorkspace.shared.open(release.bestURL)
    }
    
    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    
    @objc private func manualSwitch() {
        Task { await self.hotKeyManager?.convertLayout() }
    }
    
    @objc private func setAutoSwitchMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = AutoSwitchMode(rawValue: raw) else { return }
        self.settings.configuration.autoSwitchMode = mode
        Logger.ui.info("Auto-switch mode set to \(mode.rawValue)")
    }
    
    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
                Logger.ui.info("Launch at login disabled")
            } else {
                try service.register()
                Logger.ui.info("Launch at login enabled")
            }
        } catch {
            Logger.ui.error("Failed to toggle launch at login: \(error)")
        }
    }
    
    @objc private func toggleSound() {
        self.settings.configuration.soundEnabled.toggle()
        Logger.ui.info("Sound \(self.settings.configuration.soundEnabled ? "enabled" : "disabled")")
        
        if self.settings.configuration.soundEnabled {
            SoundManager.shared.playSound(named: self.settings.configuration.successSoundName,
                                          volume: self.settings.configuration.soundVolume)
        }
    }
    
    @objc private func showSettings() {
        SettingsWindow(settings: self.settings).show()
    }
    
    @objc private func showStatistics() {
        guard let metrics = hotKeyManager?.metrics else { return }
        
        let alert = NSAlert()
        alert.messageText = L(.statsAlertTitle)
        alert.informativeText = metrics.summary
        alert.alertStyle = .informational
        alert.addButton(withTitle: L(.btnOk))
        alert.addButton(withTitle: L(.btnReset))
        
        if alert.runModal() == .alertSecondButtonReturn {
            metrics.reset()
            
            let confirmAlert = NSAlert()
            confirmAlert.messageText = L(.statsResetTitle)
            confirmAlert.informativeText = L(.statsResetMsg)
            confirmAlert.alertStyle = .informational
            confirmAlert.addButton(withTitle: L(.btnOk))
            confirmAlert.runModal()
        }
    }
    
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Layout Switcher"
        alert.informativeText = """
        \(L(.aboutDesc))
        
        \(L(.aboutVersionLabel)): \(Bundle.main.appVersionString)
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: L(.btnOk))
        if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }
        alert.runModal()
    }
    
    @objc private func quitApplication() {
        Logger.ui.info("Application terminating via menu")
        NSApplication.shared.terminate(nil)
    }
    
    private func requestAccessibilityPermissions() {
        // prompt: false — не показываем системный диалог, чтобы не дублировать собственное
        // окно ниже. Сам вызов всё равно регистрирует приложение в списке «Универсальный доступ».
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: false]
        
        if AXIsProcessTrustedWithOptions(options) {
            Logger.ui.info("Accessibility permissions granted")
            return
        }
        Logger.ui.warning("Accessibility permissions not granted")
        guard !Runtime.skipsPermissionPrompt else { return }
        
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = L(.accessAlertTitle)
            alert.informativeText = L(.accessAlertMsg)
            alert.alertStyle = .warning
            alert.addButton(withTitle: L(.btnOpenSettings))
            alert.addButton(withTitle: L(.btnLater))
            
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        }
    }
}
