import SwiftUI
import Combine
import os.log
import UniformTypeIdentifiers
import ServiceManagement
import Carbon.HIToolbox // Для TIS функций

// MARK: - Logging
extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.layoutswitcher"
    
    static let hotkeys = Logger(subsystem: subsystem, category: "hotkeys")
    static let conversion = Logger(subsystem: subsystem, category: "conversion")
    static let ui = Logger(subsystem: subsystem, category: "ui")
    static let clipboard = Logger(subsystem: subsystem, category: "clipboard")
}

// MARK: - Error Handling
enum LayoutError: LocalizedError {
    case noTextSelected
    case conversionFailed(String)
    case accessibilityPermissionDenied
    case clipboardOperationFailed
    case hotkeyRegistrationFailed
    
    var errorDescription: String? {
        switch self {
        case .noTextSelected:
            return "Пожалуйста, выделите текст перед переключением"
        case .conversionFailed(let reason):
            return "Не удалось конвертировать текст: \(reason)"
        case .accessibilityPermissionDenied:
            return "Требуются разрешения доступности"
        case .clipboardOperationFailed:
            return "Ошибка при работе с буфером обмена"
        case .hotkeyRegistrationFailed:
            return "Не удалось зарегистрировать горячую клавишу"
        }
    }
}

// MARK: - Models
struct HotKeyConfiguration: Codable, Equatable {
    var keyCode: UInt16 = 0x25 // L
    var modifierFlags: UInt = NSEvent.ModifierFlags([.command, .shift]).rawValue
    var keyCharacter: String = "L"
    var useDoubleShift: Bool = false
    var minDoubleShiftInterval: TimeInterval = 0.05
    var maxDoubleShiftInterval: TimeInterval = 0.8
    
    var modifiers: NSEvent.ModifierFlags {
        get { NSEvent.ModifierFlags(rawValue: modifierFlags) }
        set { modifierFlags = newValue.rawValue }
    }
    
    var displayString: String {
        if useDoubleShift {
            return "⇧⇧"
        }
        
        var components: [String] = []
        let mods = modifiers
        
        if mods.contains(.control) { components.append("⌃") }
        if mods.contains(.option) { components.append("⌥") }
        if mods.contains(.shift) { components.append("⇧") }
        if mods.contains(.command) { components.append("⌘") }
        
        components.append(keyCharacter.uppercased())
        
        return components.joined()
    }
}

// MARK: - Settings Manager
@MainActor
final class SettingsManager: ObservableObject {
    @Published var configuration = HotKeyConfiguration()
    
    private let userDefaults = UserDefaults.standard
    private let configKey = "hotkey_configuration"
    private var cancellables = Set<AnyCancellable>()
    
    init() {
        loadConfiguration()
        setupAutoSave()
    }
    
    private func setupAutoSave() {
        $configuration
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] config in
                self?.saveConfiguration(config)
            }
            .store(in: &cancellables)
    }
    
    private func loadConfiguration() {
        guard let data = userDefaults.data(forKey: configKey),
              let config = try? JSONDecoder().decode(HotKeyConfiguration.self, from: data) else {
            Logger.ui.info("Loading default configuration")
            return
        }
        
        configuration = config
        Logger.ui.info("Loaded configuration: \(config.displayString)")
    }
    
    private func saveConfiguration(_ config: HotKeyConfiguration) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        userDefaults.set(data, forKey: configKey)
        
        NotificationCenter.default.post(name: .hotKeyConfigurationChanged, object: config)
        Logger.ui.info("Saved configuration: \(config.displayString)")
        
        // Show visual feedback using modern notification
        showConfigurationSavedFeedback(config.displayString)
    }
    
    private func showConfigurationSavedFeedback(_ displayString: String) {
        DispatchQueue.main.async {
            // For macOS 11+, we could use UserNotifications framework
            // For simplicity, just log for now
            Logger.ui.info("Configuration saved: \(displayString)")
            
            // Alternative: Show a temporary window or use NSAlert
            // This avoids deprecated API
        }
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let hotKeyConfigurationChanged = Notification.Name("hotKeyConfigurationChanged")
}

// MARK: - Layout Converter
@MainActor
final class LayoutConverter {
    let rusToEng: [Character: Character] = [
        "й": "q", "ц": "w", "у": "e", "к": "r", "е": "t", "н": "y", "г": "u", "ш": "i", "щ": "o", "з": "p", "х": "[", "ъ": "]",
        "ф": "a", "ы": "s", "в": "d", "а": "f", "п": "g", "р": "h", "о": "j", "л": "k", "д": "l", "ж": ";", "э": "'",
        "я": "z", "ч": "x", "с": "c", "м": "v", "и": "b", "т": "n", "ь": "m", "б": ",", "ю": ".", ".": "/",
        "Й": "Q", "Ц": "W", "У": "E", "К": "R", "Е": "T", "Н": "Y", "Г": "U", "Ш": "I", "Щ": "O", "З": "P", "Х": "{", "Ъ": "}",
        "Ф": "A", "Ы": "S", "В": "D", "А": "F", "П": "G", "Р": "H", "О": "J", "Л": "K", "Д": "L", "Ж": ":", "Э": "\"",
        "Я": "Z", "Ч": "X", "С": "C", "М": "V", "И": "B", "Т": "N", "Ь": "M", "Б": "<", "Ю": ">", ",": "?",
        "ё": "`", "Ё": "~", "№": "#", " ": " "
    ]
    
    lazy var engToRus: [Character: Character] = {
        Dictionary(uniqueKeysWithValues: rusToEng.compactMap { key, value in
            (value, key)
        })
    }()
    
    func convert(_ text: String) -> String {
        let isRussian = detectLanguage(text)
        let mapping = isRussian ? rusToEng : engToRus
        
        Logger.conversion.debug("Converting text from \(isRussian ? "Russian" : "English")")
        Logger.conversion.debug("Original text: \(text.prefix(50))...")
        
        let result = String(text.map { mapping[$0] ?? $0 })
        
        Logger.conversion.debug("Converted text: \(result.prefix(50))...")
        
        return result
    }
    
    // Сделаем метод публичным для использования в HotKeyManager
    func detectLanguage(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        var rusCount = 0
        var engCount = 0
        
        for char in lowercased {
            if rusToEng.keys.contains(char) {
                rusCount += 1
            } else if engToRus.keys.contains(char) {
                engCount += 1
            }
        }
        
        return rusCount > engCount
    }
}

// MARK: - Clipboard Manager
@MainActor
final class ClipboardManager {
    private let pasteboard = NSPasteboard.general
    
    func getSelectedText() async throws -> String {
        Logger.clipboard.debug("Getting selected text")
        
        // Save current clipboard state
        let originalString = pasteboard.string(forType: .string)
        let originalChangeCount = pasteboard.changeCount
        
        // Clear clipboard to ensure we can detect changes
        pasteboard.clearContents()
        
        // Wait for clipboard to clear
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        
        // Simulate Cmd+C
        try await simulateKeyPress(key: 0x08, modifiers: .command) // C key
        
        // Wait for clipboard to update
        try await Task.sleep(nanoseconds: 150_000_000) // 150ms
        
        // Check if clipboard changed
        let newChangeCount = pasteboard.changeCount
        
        guard newChangeCount != originalChangeCount else {
            Logger.clipboard.warning("Clipboard did not change - no text selected")
            // Restore original clipboard
            if let original = originalString {
                pasteboard.clearContents()
                pasteboard.setString(original, forType: .string)
            }
            throw LayoutError.noTextSelected
        }
        
        guard let copiedText = pasteboard.string(forType: .string),
              !copiedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Logger.clipboard.warning("Clipboard is empty or whitespace only")
            // Restore original clipboard
            if let original = originalString {
                pasteboard.clearContents()
                pasteboard.setString(original, forType: .string)
            }
            throw LayoutError.noTextSelected
        }
        
        Logger.clipboard.debug("Got text: \(copiedText.prefix(50))...")
        
        // Store original clipboard for later restoration
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
            if let original = originalString {
                await MainActor.run {
                    self.pasteboard.clearContents()
                    self.pasteboard.setString(original, forType: .string)
                }
            }
        }
        
        return copiedText
    }
    
    func replaceSelectedText(with text: String) async throws {
        Logger.clipboard.debug("Replacing selected text with: \(text.prefix(50))...")
        
        // Clear clipboard and set new text
        pasteboard.clearContents()
        
        guard pasteboard.setString(text, forType: .string) else {
            Logger.clipboard.error("Failed to set text to clipboard")
            throw LayoutError.clipboardOperationFailed
        }
        
        // Verify clipboard has the correct text
        guard pasteboard.string(forType: .string) == text else {
            Logger.clipboard.error("Clipboard verification failed")
            throw LayoutError.clipboardOperationFailed
        }
        
        Logger.clipboard.debug("Text verified in clipboard, simulating paste...")
        
        // Wait to ensure clipboard is ready
        try await Task.sleep(nanoseconds: 100_000_000) // 100ms
        
        // Simulate Cmd+V
        try await simulateKeyPress(key: 0x09, modifiers: .command) // V key
        
        // Wait for paste to complete
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        Logger.clipboard.debug("Paste operation completed")
    }
    
    private func simulateKeyPress(key: UInt16, modifiers: NSEvent.ModifierFlags) async throws {
        // Check accessibility permissions first
        guard AXIsProcessTrusted() else {
            Logger.clipboard.error("No accessibility permissions for key simulation")
            throw LayoutError.accessibilityPermissionDenied
        }
        
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Create events with proper timing
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            Logger.clipboard.error("Failed to create CGEvent for key simulation")
            throw LayoutError.clipboardOperationFailed
        }
        
        // Set flags
        let flags = CGEventFlags(rawValue: UInt64(modifiers.rawValue))
        keyDown.flags = flags
        keyUp.flags = flags
        
        // Post key down
        keyDown.post(tap: .cghidEventTap)
        
        // Small delay between down and up for more reliable simulation
        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
        
        // Post key up
        keyUp.post(tap: .cghidEventTap)
        
        Logger.clipboard.debug("Simulated key press: \(key) with modifiers: \(modifiers.rawValue)")
    }
}

// MARK: - Hot Key Manager
@MainActor
final class HotKeyManager: ObservableObject {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var shiftMonitor: Any?
    
    private var lastShiftPressTime: TimeInterval = 0
    private var shiftPressCount = 0
    
    private let settings: SettingsManager
    private let converter = LayoutConverter()
    private let clipboard = ClipboardManager()
    
    private var cancellables = Set<AnyCancellable>()
    
    init(settings: SettingsManager) {
        self.settings = settings
        setupConfigurationObserver()
        setupHotKey()
    }
    
    deinit {
        // Cleanup should be called synchronously before deinit completes
        // Store references locally to avoid capture issues
        let tap = eventTap
        let source = runLoopSource
        let monitor = shiftMonitor
        
        // Remove event monitor synchronously
        if let m = monitor {
            NSEvent.removeMonitor(m)
        }
        
        // Disable and invalidate tap synchronously
        if let t = tap {
            CGEvent.tapEnable(tap: t, enable: false)
            CFMachPortInvalidate(t)
        }
        
        // Remove run loop source synchronously
        if let s = source {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), s, .commonModes)
        }
    }
    
    private func setupConfigurationObserver() {
        NotificationCenter.default
            .publisher(for: .hotKeyConfigurationChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.setupHotKey()
            }
            .store(in: &cancellables)
    }
    
    private func setupHotKey() {
        cleanup()
        
        if settings.configuration.useDoubleShift {
            setupShiftMonitoring()
        } else {
            setupGlobalHotKey()
        }
    }
    
    private func setupShiftMonitoring() {
        Logger.hotkeys.info("Setting up double shift monitoring")
        
        shiftMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }
            
            if event.modifierFlags.contains(.shift) {
                Task { @MainActor in
                    await self.handleShiftPress()
                }
            }
        }
    }
    
    private func handleShiftPress() async {
        let currentTime = Date.timeIntervalSinceReferenceDate
        let config = settings.configuration
        
        defer { lastShiftPressTime = currentTime }
        
        let timeSinceLastPress = currentTime - lastShiftPressTime
        
        if timeSinceLastPress < config.minDoubleShiftInterval {
            Logger.hotkeys.debug("Shift press too fast, ignoring")
            return
        }
        
        if timeSinceLastPress > config.maxDoubleShiftInterval {
            shiftPressCount = 1
            Logger.hotkeys.debug("Shift press timeout, restarting count")
            return
        }
        
        shiftPressCount += 1
        
        if shiftPressCount == 2 {
            Logger.hotkeys.info("Double shift detected, converting layout")
            shiftPressCount = 0
            await convertLayout()
        }
    }
    
    private func setupGlobalHotKey() {
        Logger.hotkeys.info("Setting up global hotkey")
        
        let eventMask = (1 << CGEventType.keyDown.rawValue)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                
                let manager = Unmanaged<HotKeyManager>.fromOpaque(refcon).takeUnretainedValue()
                
                if manager.shouldHandleEvent(event) {
                    Task { @MainActor in
                        await manager.convertLayout()
                    }
                    return nil // Consume the event
                }
                
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Logger.hotkeys.error("Failed to create event tap")
            return
        }
        
        self.eventTap = eventTap
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }
    
    private func shouldHandleEvent(_ event: CGEvent) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        
        let config = settings.configuration
        // Исправлено: правильное преобразование типов
        let expectedFlags = CGEventFlags(rawValue: UInt64(config.modifierFlags))
        
        return keyCode == config.keyCode && flags.contains(expectedFlags)
    }
    
    func convertLayout() async {
        do {
            Logger.conversion.info("Starting layout conversion...")
            
            // Get selected text
            let originalText = try await clipboard.getSelectedText()
            
            guard !originalText.isEmpty else {
                Logger.conversion.warning("Selected text is empty")
                throw LayoutError.noTextSelected
            }
            
            // Convert the text
            let convertedText = converter.convert(originalText)
            
            Logger.conversion.info("Original: '\(originalText.prefix(30))...'")
            Logger.conversion.info("Converted: '\(convertedText.prefix(30))...'")
            
            // Verify conversion actually changed the text
            if convertedText == originalText {
                Logger.conversion.warning("Text unchanged after conversion, trying force convert")
                let forcedText = forceConvert(originalText)
                
                if forcedText == originalText {
                    Logger.conversion.error("Text cannot be converted - may not contain convertible characters")
                    await playErrorSound()
                    return
                }
                
                try await clipboard.replaceSelectedText(with: forcedText)
            } else {
                // Replace with converted text
                try await clipboard.replaceSelectedText(with: convertedText)
            }
            
            // Switch keyboard layout based on original text
            let wasRussian = converter.detectLanguage(originalText)
            await switchKeyboardLayout(toRussian: !wasRussian)
            
            await playSuccessSound()
            Logger.conversion.info("Layout conversion completed successfully")
            
        } catch LayoutError.noTextSelected {
            Logger.conversion.warning("No text selected")
            await playErrorSound()
        } catch {
            Logger.conversion.error("Conversion failed: \(error.localizedDescription)")
            await playErrorSound()
        }
    }
    
    // Force conversion when auto-detection fails
    private func forceConvert(_ text: String) -> String {
        // Try both conversions and see which one produces more changes
        let toEng = String(text.map { converter.rusToEng[$0] ?? $0 })
        let toRus = String(text.map { converter.engToRus[$0] ?? $0 })
        
        // Count how many characters changed
        let engChanges = zip(text, toEng).filter { $0 != $1 }.count
        let rusChanges = zip(text, toRus).filter { $0 != $1 }.count
        
        Logger.conversion.debug("Force convert: eng changes=\(engChanges), rus changes=\(rusChanges)")
        
        return engChanges > rusChanges ? toEng : toRus
    }
    
    private func switchKeyboardLayout(toRussian: Bool) async {
        // Исправлено: добавлен правильный импорт и типы
        guard let inputSources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return
        }
        
        for inputSource in inputSources {
            guard let sourceID = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else { continue }
            let sourceIDString = Unmanaged<CFString>.fromOpaque(sourceID).takeUnretainedValue() as String
            
            if (toRussian && sourceIDString.contains("Russian")) ||
               (!toRussian && (sourceIDString.contains("U.S.") || sourceIDString.contains("ABC"))) {
                TISSelectInputSource(inputSource)
                Logger.conversion.debug("Switched keyboard to \(toRussian ? "Russian" : "English")")
                break
            }
        }
    }
    
    private func playSuccessSound() async {
        NSSound(named: "Glass")?.play()
    }
    
    private func playErrorSound() async {
        NSSound.beep()
    }
    
    private func cleanup() {
        if let monitor = shiftMonitor {
            NSEvent.removeMonitor(monitor)
            shiftMonitor = nil
        }
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
    }
}

// MARK: - App Delegate
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKeyManager: HotKeyManager?
    private let settings = SettingsManager()
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.ui.info("Application launched")
        
        setupStatusBar()
        hotKeyManager = HotKeyManager(settings: settings)
        
        NSApp.setActivationPolicy(.accessory)
        requestAccessibilityPermissions()
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
    }
    
    @objc private func statusBarClicked() {
        let menu = NSMenu()
        
        // Add status indicator
        let hasPermissions = AXIsProcessTrusted()
        let statusMenuItem = NSMenuItem(title: hasPermissions ? "✅ Разрешения предоставлены" : "⚠️ Требуются разрешения", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        
        let convertItem = NSMenuItem(
            title: "Переключить раскладку (\(settings.configuration.displayString))",
            action: #selector(manualSwitch),
            keyEquivalent: ""
        )
        convertItem.isEnabled = hasPermissions
        menu.addItem(convertItem)
        
        menu.addItem(.separator())
        
        menu.addItem(NSMenuItem(
            title: "Настройки...",
            action: #selector(showSettings),
            keyEquivalent: ","
        ))
        
        if !hasPermissions {
            menu.addItem(NSMenuItem(
                title: "Предоставить разрешения...",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            ))
        }
        
        menu.addItem(.separator())
        
        menu.addItem(NSMenuItem(
            title: "Выйти",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
        
        // Set target for all menu items
        menu.items.forEach { $0.target = self }
        
        // Show menu
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        
        // Clean up menu after showing (important for click-through behavior)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }
    
    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    
    @objc private func manualSwitch() {
        Task {
            await hotKeyManager?.convertLayout()
        }
    }
    
    @objc private func showSettings() {
        let settingsWindow = SettingsWindow(settings: settings)
        settingsWindow.show()
    }
    
    private func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        
        if !AXIsProcessTrustedWithOptions(options) {
            Logger.ui.warning("Accessibility permissions not granted")
            
            // Show alert to user
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Требуются разрешения доступности"
                alert.informativeText = """
                Layout Switcher требует разрешения доступности для:
                • Перехвата горячих клавиш
                • Копирования выделенного текста
                • Вставки конвертированного текста
                
                Пожалуйста, предоставьте разрешения в:
                Системные настройки → Конфиденциальность и безопасность → Универсальный доступ
                
                После предоставления разрешений перезапустите приложение.
                """
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Открыть настройки")
                alert.addButton(withTitle: "Позже")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    // Open System Preferences
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        } else {
            Logger.ui.info("Accessibility permissions granted")
        }
    }
}

// MARK: - Settings Window
@MainActor
final class SettingsWindow {
    private static var window: NSWindow?
    private static var windowDelegate: WindowDelegate?
    private let settings: SettingsManager
    
    init(settings: SettingsManager) {
        self.settings = settings
    }
    
    func show() {
        // Check if window is already visible
        if let existing = Self.window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Create new window
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 500),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "Настройки Layout Switcher"
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        
        let contentView = SettingsView(settings: settings)
        let hostingView = NSHostingView(rootView: contentView)
        newWindow.contentView = hostingView
        
        // Store window reference
        Self.window = newWindow
        
        // Create and store delegate
        let delegate = WindowDelegate()
        Self.windowDelegate = delegate
        newWindow.delegate = delegate
        
        // Show window
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private class WindowDelegate: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            SettingsWindow.window = nil
            SettingsWindow.windowDelegate = nil
        }
    }
}

// MARK: - Preset Configuration
struct PresetConfiguration: Identifiable {
    let id = UUID()
    let config: HotKeyConfiguration
    
    static let presets: [PresetConfiguration] = [
        PresetConfiguration(config: HotKeyConfiguration(keyCode: 0, modifierFlags: 0, keyCharacter: "", useDoubleShift: true)),
        PresetConfiguration(config: HotKeyConfiguration(keyCode: 0x25, modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue, keyCharacter: "L", useDoubleShift: false)),
        PresetConfiguration(config: HotKeyConfiguration(keyCode: 0x11, modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue, keyCharacter: "T", useDoubleShift: false)),
        PresetConfiguration(config: HotKeyConfiguration(keyCode: 0x25, modifierFlags: NSEvent.ModifierFlags([.control, .option]).rawValue, keyCharacter: "L", useDoubleShift: false))
    ]
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    @State private var isRecording = false
    @State private var windowIsPresented = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 10) {
                HStack {
                    Image(systemName: "keyboard")
                        .font(.largeTitle)
                        .foregroundColor(.accentColor)
                    Text("Настройки Layout Switcher")
                        .font(.title2)
                        .fontWeight(.semibold)
                }
                .padding(.top, 20)
                .padding(.bottom, 10)
            }
            
            // Main content with scroll view
            ScrollView {
                VStack(spacing: 20) {
                    // Hot key section
                    GroupBox(label: Label("Горячая клавиша", systemImage: "command.square")) {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Использовать двойное нажатие Shift", isOn: $settings.configuration.useDoubleShift)
                            
                            if settings.configuration.useDoubleShift {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("Мин. интервал:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(Int(settings.configuration.minDoubleShiftInterval * 1000))ms")
                                            .font(.caption.monospacedDigit())
                                    }
                                    Slider(value: $settings.configuration.minDoubleShiftInterval, in: 0.01...0.5)
                                    
                                    HStack {
                                        Text("Макс. интервал:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Spacer()
                                        Text("\(Int(settings.configuration.maxDoubleShiftInterval * 1000))ms")
                                            .font(.caption.monospacedDigit())
                                    }
                                    Slider(value: $settings.configuration.maxDoubleShiftInterval, in: 0.1...2.0)
                                }
                                .padding(.leading)
                            } else {
                                HStack {
                                    Text("Текущая комбинация:")
                                    Spacer()
                                    Text(settings.configuration.displayString)
                                        .font(.system(.body, design: .monospaced))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.accentColor.opacity(0.1))
                                        .cornerRadius(6)
                                }
                                
                                Button(isRecording ? "Остановить запись..." : "Записать новую комбинацию") {
                                    isRecording.toggle()
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // Presets section
                    GroupBox(label: Label("Быстрые настройки", systemImage: "square.grid.2x2")) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: 10) {
                            ForEach(PresetConfiguration.presets) { preset in
                                PresetButton(preset: preset.config, current: settings.configuration) {
                                    settings.configuration = preset.config
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            
            // Footer with Close button
            Divider()
            HStack {
                Spacer()
                Button("Готово") {
                    if let window = NSApplication.shared.windows.first(where: { $0.title == "Настройки Layout Switcher" }) {
                        window.close()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(minWidth: 450, idealWidth: 500, maxWidth: 600,
               minHeight: 400, idealHeight: 450, maxHeight: 600)
        .background(Color(NSColor.windowBackgroundColor))
    }
}

struct PresetButton: View {
    let preset: HotKeyConfiguration
    let current: HotKeyConfiguration
    let action: () -> Void
    
    var isSelected: Bool {
        preset == current
    }
    
    var body: some View {
        Button(action: action) {
            Text(preset.displayString)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - App Entry Point
@main
struct LayoutSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
