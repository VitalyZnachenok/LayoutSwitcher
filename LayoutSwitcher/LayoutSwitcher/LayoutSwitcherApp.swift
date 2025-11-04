import SwiftUI
import Combine
import os.log
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

// MARK: - Conversion Metrics
@MainActor
final class ConversionMetrics: ObservableObject {
    @Published private(set) var totalConversions: Int = 0
    @Published private(set) var successfulConversions: Int = 0
    @Published private(set) var failedConversions: Int = 0
    @Published private(set) var averageConversionTime: TimeInterval = 0
    
    private var conversionTimes: [TimeInterval] = []
    private let maxStoredTimes = 100 // Храним последние 100 измерений
    
    func recordSuccess(duration: TimeInterval) {
        totalConversions += 1
        successfulConversions += 1
        
        conversionTimes.append(duration)
        if conversionTimes.count > maxStoredTimes {
            conversionTimes.removeFirst()
        }
        
        // Обновляем среднее время
        averageConversionTime = conversionTimes.reduce(0, +) / Double(conversionTimes.count)
        
        Logger.conversion.info("✅ Conversion successful in \(String(format: "%.0f", duration * 1000))ms")
    }
    
    func recordFailure() {
        totalConversions += 1
        failedConversions += 1
        
        Logger.conversion.warning("❌ Conversion failed")
    }
    
    var successRate: Double {
        guard totalConversions > 0 else { return 0 }
        return Double(successfulConversions) / Double(totalConversions)
    }
    
    func reset() {
        totalConversions = 0
        successfulConversions = 0
        failedConversions = 0
        averageConversionTime = 0
        conversionTimes.removeAll()
        
        Logger.conversion.info("Metrics reset")
    }
    
    var summary: String {
        """
        📊 Статистика конвертаций:
        • Всего: \(totalConversions)
        • Успешно: \(successfulConversions)
        • Неудачно: \(failedConversions)
        • Успешность: \(String(format: "%.1f%%", successRate * 100))
        • Среднее время: \(String(format: "%.0f", averageConversionTime * 1000))мс
        """
    }
}

// MARK: - Models
enum HotKeyMode: String, Codable, Equatable, Sendable {
    case customHotkey
    case doubleShift
    case doubleCapsLock
    
    var displayName: String {
        switch self {
        case .customHotkey:
            return "Пользовательская комбинация"
        case .doubleShift:
            return "Двойное нажатие Shift"
        case .doubleCapsLock:
            return "Двойное нажатие Caps Lock"
        }
    }
}

struct HotKeyConfiguration: Codable, Equatable, Sendable {
    var keyCode: UInt16 = 0x25 // L
    var modifierFlags: UInt = NSEvent.ModifierFlags([.command, .shift]).rawValue
    var keyCharacter: String = "L"
    
    // Новый режим вместо простого bool
    var hotKeyMode: HotKeyMode = .customHotkey
    
    // Для обратной совместимости
    var useDoubleShift: Bool {
        get { hotKeyMode == .doubleShift }
        set { if newValue { hotKeyMode = .doubleShift } }
    }
    
    var minDoubleShiftInterval: TimeInterval = 0.05
    var maxDoubleShiftInterval: TimeInterval = 0.8
    
    // Sound settings
    var soundEnabled: Bool = true
    var successSoundName: String = "Glass"
    var errorSoundName: String = "Basso"
    var soundVolume: Float = 0.8 // 0.0 to 1.0
    
    var modifiers: NSEvent.ModifierFlags {
        get { NSEvent.ModifierFlags(rawValue: modifierFlags) }
        set { modifierFlags = newValue.rawValue }
    }
    
    var displayString: String {
        switch hotKeyMode {
        case .doubleShift:
            return "⇧⇧"
        case .doubleCapsLock:
            return "⇪⇪"
        case .customHotkey:
            let mods = modifiers
            let components = [
                mods.contains(.control) ? "⌃" : nil,
                mods.contains(.option) ? "⌥" : nil,
                mods.contains(.shift) ? "⇧" : nil,
                mods.contains(.command) ? "⌘" : nil,
                keyCharacter.uppercased()
            ].compactMap { $0 }
            
            return components.joined()
        }
    }
    
    // Computed property for better validation
    var isValid: Bool {
        switch hotKeyMode {
        case .doubleShift, .doubleCapsLock:
            return minDoubleShiftInterval > 0 &&
                   maxDoubleShiftInterval > minDoubleShiftInterval &&
                   maxDoubleShiftInterval <= 5.0
        case .customHotkey:
            return !keyCharacter.isEmpty && modifierFlags != 0
        }
    }
}

// MARK: - Sound Manager
@MainActor
final class SoundManager {
    static let shared = SoundManager()
    
    private var currentTestSound: NSSound?
    
    private init() {}
    
    func playSound(named soundName: String, volume: Float) {
        guard let sound = NSSound(named: soundName) else {
            Logger.ui.warning("Sound not found: \(soundName)")
            NSSound.beep()
            return
        }
        
        sound.volume = volume
        sound.play()
        Logger.ui.debug("Playing sound: \(soundName) at volume \(volume)")
    }
    
    func testSound(_ soundName: String, volume: Float) {
        // Stop current test sound if playing
        currentTestSound?.stop()
        currentTestSound = nil
        
        guard let sound = NSSound(named: soundName) else {
            Logger.ui.warning("Test sound not found: \(soundName)")
            NSSound.beep()
            return
        }
        
        sound.volume = volume
        currentTestSound = sound
        sound.play()
        Logger.ui.debug("Playing test sound: \(soundName) at volume \(volume)")
    }
    
    static func isValidSoundName(_ name: String) -> Bool {
        return SoundConfiguration.availableSounds.contains(name)
    }
}

// MARK: - Sound Configuration
struct SoundConfiguration {
    static let availableSounds: [String] = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", 
        "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]
    
    static let soundDisplayNames: [String: String] = [
        "Basso": "Бассо",
        "Blow": "Дуновение",
        "Bottle": "Бутылка",
        "Frog": "Лягушка",
        "Funk": "Фанк",
        "Glass": "Стекло",
        "Hero": "Герой",
        "Morse": "Морзе",
        "Ping": "Пинг",
        "Pop": "Поп",
        "Purr": "Мурлыканье",
        "Sosumi": "Сосуми",
        "Submarine": "Подлодка",
        "Tink": "Тинк"
    ]
    
    static func localizedName(for soundName: String) -> String {
        return soundDisplayNames[soundName] ?? soundName
    }
}

// MARK: - Settings Manager
@MainActor
final class SettingsManager: ObservableObject {
    @Published var configuration = HotKeyConfiguration() {
        didSet {
            // Validate configuration on change
            validateConfiguration()
        }
    }
    
    private let userDefaults = UserDefaults.standard
    private let configKey = "hotkey_configuration"
    private var cancellables = Set<AnyCancellable>()
    
    // Configuration validation errors
    @Published private(set) var configurationErrors: [String] = []
    
    var isConfigurationValid: Bool {
        configurationErrors.isEmpty
    }
    
    init() {
        loadConfiguration()
        setupAutoSave()
    }
    
    private func validateConfiguration() {
        var errors: [String] = []
        
        switch configuration.hotKeyMode {
        case .doubleShift, .doubleCapsLock:
            if configuration.minDoubleShiftInterval <= 0 {
                errors.append("Минимальный интервал должен быть больше 0")
            }
            
            if configuration.maxDoubleShiftInterval <= configuration.minDoubleShiftInterval {
                errors.append("Максимальный интервал должен быть больше минимального")
            }
            
            if configuration.maxDoubleShiftInterval > 5.0 {
                errors.append("Максимальный интервал слишком большой (>5 сек)")
            }
            
        case .customHotkey:
            if configuration.keyCharacter.isEmpty {
                errors.append("Символ клавиши не может быть пустым")
            }
            
            if configuration.modifierFlags == 0 {
                errors.append("Необходимо выбрать хотя бы один модификатор")
            }
        }
        
        configurationErrors = errors
        
        if !errors.isEmpty {
            Logger.ui.warning("Configuration validation errors: \(errors.joined(separator: ", "))")
        }
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
        self.showConfigurationSavedFeedback(config.displayString)
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
    // Character mappings with better organization
    private static let rusToEngMappings: [Character: Character] = [
        // First row
        "й": "q", "ц": "w", "у": "e", "к": "r", "е": "t", "н": "y", "г": "u", "ш": "i", "щ": "o", "з": "p", "х": "[", "ъ": "]",
        // Second row  
        "ф": "a", "ы": "s", "в": "d", "а": "f", "п": "g", "р": "h", "о": "j", "л": "k", "д": "l", "ж": ";", "э": "'",
        // Third row
        "я": "z", "ч": "x", "с": "c", "м": "v", "и": "b", "т": "n", "ь": "m", "б": ",", "ю": ".", ".": "/",
        // Uppercase
        "Й": "Q", "Ц": "W", "У": "E", "К": "R", "Е": "T", "Н": "Y", "Г": "U", "Ш": "I", "Щ": "O", "З": "P", "Х": "{", "Ъ": "}",
        "Ф": "A", "Ы": "S", "В": "D", "А": "F", "П": "G", "Р": "H", "О": "J", "Л": "K", "Д": "L", "Ж": ":", "Э": "\"",
        "Я": "Z", "Ч": "X", "С": "C", "М": "V", "И": "B", "Т": "N", "Ь": "M", "Б": "<", "Ю": ">", ",": "?",
        // Special characters
        "ё": "`", "Ё": "~", "№": "#", " ": " "
    ]
    
    let rusToEng: [Character: Character] = LayoutConverter.rusToEngMappings
    
    lazy var engToRus: [Character: Character] = {
        Dictionary(uniqueKeysWithValues: Self.rusToEngMappings.compactMap { key, value in
            (value, key)
        })
    }()
    
    // NSCache для улучшенного кэширования с автоматическим управлением памятью
    private let conversionCache = NSCache<NSString, NSString>()
    
    init() {
        // Настройка кэша
        conversionCache.countLimit = 100 // Максимум 100 элементов
        conversionCache.totalCostLimit = 1024 * 100 // ~100KB
        
        // Очистка кэша при предупреждении о памяти (для macOS используем другой подход)
        // В macOS нет прямого уведомления о памяти, но мы можем очищать кэш вручную
    }
    
    func convert(_ text: String) -> String {
        let cacheKey = text as NSString
        
        // Check cache first for performance
        if let cached = conversionCache.object(forKey: cacheKey) {
            Logger.conversion.debug("Using cached conversion for: \(text.prefix(20))...")
            return cached as String
        }
        
        let isRussian = detectLanguage(text)
        let mapping = isRussian ? rusToEng : engToRus
        
        Logger.conversion.debug("Converting text from \(isRussian ? "Russian" : "English")")
        Logger.conversion.debug("Original text: \(text.prefix(50))...")
        
        let result = String(text.compactMap { char in
            mapping[char] ?? char
        })
        
        Logger.conversion.debug("Converted text: \(result.prefix(50))...")
        
        // Cache the result with cost based on string length
        let cost = text.utf8.count
        conversionCache.setObject(result as NSString, forKey: cacheKey, cost: cost)
        
        return result
    }
    
    func detectLanguage(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        var rusCount = 0
        var engCount = 0
        var totalRelevantChars = 0
        
        // Подсчитываем символы каждого языка
        for char in lowercased {
            if rusToEng.keys.contains(char) {
                rusCount += 1
                totalRelevantChars += 1
            } else if engToRus.keys.contains(char) {
                engCount += 1
                totalRelevantChars += 1
            }
        }
        
        // Если нет релевантных символов, используем Unicode диапазоны
        if totalRelevantChars == 0 {
            return text.contains(where: { char in
                char.unicodeScalars.contains { scalar in
                    scalar.value >= 0x0400 && scalar.value <= 0x04FF // Cyrillic range
                }
            })
        }
        
        // Для смешанного текста - если разница небольшая, смотрим на первые символы
        let difference = abs(rusCount - engCount)
        if difference <= 2 && totalRelevantChars > 3 {
            // Смотрим на первые 3 символа для определения основного языка
            let firstChars = String(lowercased.prefix(3))
            var firstRusCount = 0
            var firstEngCount = 0
            
            for char in firstChars {
                if rusToEng.keys.contains(char) {
                    firstRusCount += 1
                } else if engToRus.keys.contains(char) {
                    firstEngCount += 1
                }
            }
            
            Logger.conversion.debug("Mixed text detected. First chars bias: rus=\(firstRusCount), eng=\(firstEngCount)")
            
            if firstRusCount != firstEngCount {
                return firstRusCount > firstEngCount
            }
        }
        
        return rusCount > engCount
    }
    
    // Clear cache when needed (например, при низкой памяти)
    func clearCache() {
        conversionCache.removeAllObjects()
        Logger.conversion.debug("Conversion cache cleared")
    }
}

// MARK: - Clipboard Manager
@MainActor
final class ClipboardManager {
    // Timing constants for clipboard operations
    private enum Timing {
        /// Время ожидания очистки буфера обмена
        static let clearDelay: UInt64 = 50_000_000 // 50ms
        
        /// Время ожидания после копирования текста
        static let copyDelay: UInt64 = 200_000_000 // 200ms
        
        /// Время ожидания после вставки текста
        static let pasteDelay: UInt64 = 200_000_000 // 200ms
        
        /// Время между key down и key up событиями
        static let keyPressDelay: UInt64 = 10_000_000 // 10ms
        
        /// Время ожидания перед проверкой буфера обмена
        static let verificationDelay: UInt64 = 100_000_000 // 100ms
        
        /// Время ожидания перед восстановлением оригинального содержимого
        static let restoreDelay: UInt64 = 500_000_000 // 500ms
        
        /// Время ожидания между повторными попытками
        static let retryDelay: UInt64 = 100_000_000 // 100ms
    }
    
    private let pasteboard = NSPasteboard.general
    private let maxRetryAttempts = 3
    
    func getSelectedText() async throws -> String {
        // Retry logic для повышения надежности
        for attempt in 1...maxRetryAttempts {
            do {
                return try await performGetSelectedText()
            } catch LayoutError.noTextSelected where attempt < maxRetryAttempts {
                Logger.clipboard.warning("Attempt \(attempt) failed, retrying...")
                try await Task.sleep(nanoseconds: Timing.retryDelay)
                continue
            } catch {
                throw error
            }
        }
        throw LayoutError.noTextSelected
    }
    
    private func performGetSelectedText() async throws -> String {
        Logger.clipboard.debug("Getting selected text")
        
        // Save current clipboard state
        let originalString = pasteboard.string(forType: .string)
        let originalChangeCount = pasteboard.changeCount
        
        // Clear clipboard to ensure we can detect changes
        pasteboard.clearContents()
        
        // Wait for clipboard to clear
        try await Task.sleep(nanoseconds: Timing.clearDelay)
        
        // Simulate Cmd+C
        try await simulateKeyPress(key: 0x08, modifiers: .command) // C key
        
        // Wait for clipboard to update
        try await Task.sleep(nanoseconds: Timing.copyDelay)
        
        // Check if clipboard changed
        let newChangeCount = pasteboard.changeCount
        
        if newChangeCount == originalChangeCount {
            Logger.clipboard.warning("Clipboard did not change - trying fallback method")
            
            // Fallback: Try double copy to force clipboard update
            try await simulateKeyPress(key: 0x08, modifiers: .command) // C key again
            try await Task.sleep(nanoseconds: Timing.retryDelay)
            
            let fallbackChangeCount = pasteboard.changeCount
            if fallbackChangeCount == originalChangeCount {
                // Restore original clipboard synchronously
                restoreClipboard(originalString)
                throw LayoutError.noTextSelected
            }
        }
        
        guard let copiedText = pasteboard.string(forType: .string),
              !copiedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            Logger.clipboard.warning("Clipboard is empty or whitespace only")
            // Restore original clipboard synchronously
            restoreClipboard(originalString)
            throw LayoutError.noTextSelected
        }
        
        // Allow same text if clipboard change count increased
        if copiedText == originalString && originalString != nil {
            Logger.clipboard.info("Text same as original clipboard, but copy operation detected - proceeding")
        }
        
        Logger.clipboard.debug("Got text: \(copiedText.prefix(50))...")
        
        // Schedule clipboard restoration (исправлено: без захвата self)
        scheduleClipboardRestore(originalString)
        
        return copiedText
    }
    
    private func restoreClipboard(_ originalString: String?) {
        guard let original = originalString else { return }
        pasteboard.clearContents()
        pasteboard.setString(original, forType: .string)
        Logger.clipboard.debug("Restored original clipboard content")
    }
    
    private func scheduleClipboardRestore(_ originalString: String?) {
        guard let original = originalString else { return }
        
        // Используем слабую ссылку чтобы избежать retain cycle
        Task { [weak pasteboard = self.pasteboard] in
            try? await Task.sleep(nanoseconds: Timing.restoreDelay)
            
            guard let pasteboard = pasteboard else { return }
            
            await MainActor.run {
                pasteboard.clearContents()
                pasteboard.setString(original, forType: .string)
                Logger.clipboard.debug("Restored original clipboard content (delayed)")
            }
        }
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
        try await Task.sleep(nanoseconds: Timing.verificationDelay)
        
        // Simulate Cmd+V
        try await simulateKeyPress(key: 0x09, modifiers: .command) // V key
        
        // Wait for paste to complete
        try await Task.sleep(nanoseconds: Timing.pasteDelay)
        
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
        try await Task.sleep(nanoseconds: Timing.keyPressDelay)
        
        // Post key up
        keyUp.post(tap: .cghidEventTap)
        
        Logger.clipboard.debug("Simulated key press: \(key) with modifiers: \(modifiers.rawValue)")
    }
}

// MARK: - Hot Key Manager
@MainActor
final class HotKeyManager: ObservableObject {
    // Timing constants for conversion operations
    private enum ConversionTiming {
        /// Задержка перед началом конвертации (для завершения выделения текста)
        static let preConversionDelay: UInt64 = 50_000_000 // 50ms
        
        /// Задержка после двойного нажатия Shift перед конвертацией
        static let postDoubleShiftDelay: UInt64 = 100_000_000 // 100ms
    }
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var shiftMonitor: Any?
    private var capsLockMonitor: Any?
    
    private var lastShiftPressTime: TimeInterval = 0
    private var shiftPressCount = 0
    
    private var lastCapsLockPressTime: TimeInterval = 0
    private var capsLockPressCount = 0
    
    private let settings: SettingsManager
    private let converter = LayoutConverter()
    private let clipboard = ClipboardManager()
    
    // Public для доступа из AppDelegate
    let metrics = ConversionMetrics()
    
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
        let capsMonitor = capsLockMonitor
        
        // Remove event monitors synchronously
        if let m = monitor {
            NSEvent.removeMonitor(m)
        }
        
        if let cm = capsMonitor {
            NSEvent.removeMonitor(cm)
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
        
        switch settings.configuration.hotKeyMode {
        case .doubleShift:
            setupShiftMonitoring()
        case .doubleCapsLock:
            setupCapsLockMonitoring()
        case .customHotkey:
            setupGlobalHotKey()
        }
    }
    
    private func setupShiftMonitoring() {
        Logger.hotkeys.info("Setting up double shift monitoring")
        
        // Reset all shift state
        lastShiftPressTime = 0
        shiftPressCount = 0
        
        shiftMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }
            
            Task { @MainActor in
                await self.handleShiftEvent(event)
            }
        }
        
        // Also monitor local events for better detection
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return event }
            
            Task { @MainActor in
                await self.handleShiftEvent(event)
            }
            
            return event
        }
    }
    
    private func setupCapsLockMonitoring() {
        Logger.hotkeys.info("Setting up double Caps Lock monitoring")
        
        // Reset all caps lock state
        lastCapsLockPressTime = 0
        capsLockPressCount = 0
        
        capsLockMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }
            
            Task { @MainActor in
                await self.handleCapsLockEvent(event)
            }
        }
        
        // Also monitor local events for better detection
        NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return event }
            
            Task { @MainActor in
                await self.handleCapsLockEvent(event)
            }
            
            return event
        }
    }
    
    private func handleCapsLockEvent(_ event: NSEvent) async {
        let hasCapsLock = event.modifierFlags.contains(.capsLock)
        let hasOnlyCapsLock = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
        
        // Only process if ONLY caps lock state changed (no other modifiers)
        guard hasOnlyCapsLock else {
            // Reset count if other modifiers are pressed
            if !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty {
                capsLockPressCount = 0
                lastCapsLockPressTime = 0
                Logger.hotkeys.debug("Reset caps lock count due to other modifiers")
            }
            return
        }
        
        if hasCapsLock {
            // Caps Lock activated
            await handleCapsLockPress()
        } else {
            // Caps Lock deactivated - important for detecting separate presses
            Logger.hotkeys.debug("Caps Lock released")
        }
    }
    
    private func handleCapsLockPress() async {
        let currentTime = Date.timeIntervalSinceReferenceDate
        let config = settings.configuration
        
        // Calculate time since last press
        let timeSinceLastPress = lastCapsLockPressTime > 0 ? currentTime - lastCapsLockPressTime : Double.infinity
        
        Logger.hotkeys.debug("Caps Lock press: count=\(self.capsLockPressCount), timeSince=\(String(format: "%.0f", timeSinceLastPress * 1000))ms")
        
        // Check if this is a new sequence or continuation
        if timeSinceLastPress > config.maxDoubleShiftInterval {
            // Too long, start new sequence
            capsLockPressCount = 1
            lastCapsLockPressTime = currentTime
            Logger.hotkeys.debug("Starting new caps lock sequence (timeout)")
        } else if timeSinceLastPress < config.minDoubleShiftInterval {
            // Too fast, might be key repeat - ignore
            Logger.hotkeys.debug("Ignoring - too fast (possible key repeat)")
            return
        } else {
            // Valid timing for double caps lock
            capsLockPressCount += 1
            
            if capsLockPressCount == 2 {
                Logger.hotkeys.info("Double Caps Lock detected! Converting layout...")
                // Reset immediately to prevent triple+ triggers
                capsLockPressCount = 0
                lastCapsLockPressTime = 0
                
                // Add small delay to let user release caps lock before conversion
                try? await Task.sleep(nanoseconds: ConversionTiming.postDoubleShiftDelay)
                
                // Perform conversion
                await convertLayout()
            } else if capsLockPressCount > 2 {
                // Reset if somehow we got more than 2
                capsLockPressCount = 0
                lastCapsLockPressTime = 0
            } else {
                // First press in valid sequence
                lastCapsLockPressTime = currentTime
            }
        }
    }
    
    private func handleShiftEvent(_ event: NSEvent) async {
        let hasShift = event.modifierFlags.contains(.shift)
        let hasOnlyShift = event.modifierFlags.intersection([.command, .option, .control]).isEmpty
        
        // Only process if ONLY shift is pressed (no other modifiers)
        guard hasOnlyShift else {
            // Reset count if other modifiers are pressed
            if !event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                shiftPressCount = 0
                lastShiftPressTime = 0
                Logger.hotkeys.debug("Reset shift count due to other modifiers")
            }
            return
        }
        
        if hasShift {
            // Shift pressed
            await handleShiftPress()
        } else {
            // Shift released - important for detecting separate presses
            Logger.hotkeys.debug("Shift released")
        }
    }
    
    private func handleShiftPress() async {
        let currentTime = Date.timeIntervalSinceReferenceDate
        let config = settings.configuration
        
        // Calculate time since last press
        let timeSinceLastPress = lastShiftPressTime > 0 ? currentTime - lastShiftPressTime : Double.infinity
        
        Logger.hotkeys.debug("Shift press: count=\(self.shiftPressCount), timeSince=\(String(format: "%.0f", timeSinceLastPress * 1000))ms")
        
        // Check if this is a new sequence or continuation
        if timeSinceLastPress > config.maxDoubleShiftInterval {
            // Too long, start new sequence
            shiftPressCount = 1
            lastShiftPressTime = currentTime
            Logger.hotkeys.debug("Starting new shift sequence (timeout)")
        } else if timeSinceLastPress < config.minDoubleShiftInterval {
            // Too fast, might be key repeat - ignore
            Logger.hotkeys.debug("Ignoring - too fast (possible key repeat)")
            return
        } else {
            // Valid timing for double shift
            shiftPressCount += 1
            
            if shiftPressCount == 2 {
                Logger.hotkeys.info("Double shift detected! Converting layout...")
                // Reset immediately to prevent triple+ triggers
                shiftPressCount = 0
                lastShiftPressTime = 0
                
                // Add small delay to let user release shift before conversion
                try? await Task.sleep(nanoseconds: ConversionTiming.postDoubleShiftDelay)
                
                // Perform conversion
                await convertLayout()
            } else if shiftPressCount > 2 {
                // Reset if somehow we got more than 2
                shiftPressCount = 0
                lastShiftPressTime = 0
            } else {
                // First press in valid sequence
                lastShiftPressTime = currentTime
            }
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
                
                // Check if this is our hotkey
                if manager.shouldHandleEvent(event) {
                    // Additional check: ignore if arrow keys or navigation keys are involved
                    let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                    let navigationKeys: Set<UInt16> = [
                        123, 124, 125, 126,  // Arrow keys
                        115, 116, 119, 121,  // Home, End, Page Up, Page Down
                        96, 97, 98, 99, 100, 101  // F-keys that might be used for navigation
                    ]
                    
                    if navigationKeys.contains(keyCode) {
                        Logger.hotkeys.debug("Ignoring hotkey with navigation key")
                        return Unmanaged.passUnretained(event)
                    }
                    
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
        let startTime = Date()
        let result = await performLayoutConversion()
        let duration = Date().timeIntervalSince(startTime)
        
        await handleConversionResult(result, duration: duration)
    }
    
    private func performLayoutConversion() async -> Result<ConversionResult, LayoutError> {
        // Add a small delay to ensure selection is complete
        try? await Task.sleep(nanoseconds: ConversionTiming.preConversionDelay)
        
        // Pre-flight checks
        if let error = await validateConversionPreconditions() {
            return .failure(error)
        }
        
        do {
            Logger.conversion.info("Starting layout conversion...")
            
            let originalText = try await clipboard.getSelectedText()
            
            guard !originalText.isEmpty else {
                return .failure(.noTextSelected)
            }
            
            // Validate text selection
            if let validationError = validateTextSelection(originalText) {
                return .failure(validationError)
            }
            
            let wasRussian = converter.detectLanguage(originalText)
            let convertedText = converter.convert(originalText)
            
            Logger.conversion.info("Original: '\(originalText.prefix(30))...'")
            Logger.conversion.info("Converted: '\(convertedText.prefix(30))...'")
            
            // Handle conversion results
            let finalText: String
            let targetLanguageIsRussian: Bool
            
            if convertedText == originalText {
                Logger.conversion.warning("Text unchanged after conversion, trying force convert")
                let forcedText = forceConvert(originalText)
                
                guard forcedText != originalText else {
                    return .failure(.conversionFailed("Text contains no convertible characters"))
                }
                
                finalText = forcedText
                targetLanguageIsRussian = !wasRussian
            } else {
                finalText = convertedText
                targetLanguageIsRussian = converter.detectLanguage(convertedText)
            }
            
            try await clipboard.replaceSelectedText(with: finalText)
            await switchKeyboardLayout(toRussian: targetLanguageIsRussian)
            
            return .success(ConversionResult(
                originalText: originalText,
                convertedText: finalText,
                wasForced: convertedText == originalText
            ))
            
        } catch let error as LayoutError {
            return .failure(error)
        } catch {
            return .failure(.clipboardOperationFailed)
        }
    }
    
    private func validateConversionPreconditions() async -> LayoutError? {
        let currentModifiers = NSEvent.modifierFlags
        
        if currentModifiers.contains(.shift) && settings.configuration.hotKeyMode != .doubleShift {
            Logger.conversion.warning("Shift still pressed, might be selecting text - aborting")
            return .conversionFailed("Shift key interference")
        }
        
        if currentModifiers.contains(.function) {
            Logger.conversion.warning("Function/Arrow key detected - aborting conversion")
            return .conversionFailed("Function key interference")
        }
        
        return nil
    }
    
    private func validateTextSelection(_ text: String) -> LayoutError? {
        if text.contains("\n") || text.count > 200 {
            Logger.conversion.warning("Text appears to be auto-selected (contains newlines or very long) - aborting")
            return .conversionFailed("Auto-selected text detected")
        }
        return nil
    }
    
    private func handleConversionResult(_ result: Result<ConversionResult, LayoutError>, duration: TimeInterval) async {
        switch result {
        case .success(let conversionResult):
            metrics.recordSuccess(duration: duration)
            await playSuccessSound()
            
            // Optional: Show brief success notification
            if conversionResult.wasForced {
                Logger.conversion.info("Used forced conversion for: \(conversionResult.originalText.prefix(20))...")
            }
            
        case .failure(.noTextSelected):
            // Не записываем как ошибку - это обычная ситуация
            Logger.conversion.warning("No text selected")
            // Don't play error sound for no selection - this is often intentional
            
        case .failure(let error):
            metrics.recordFailure()
            Logger.conversion.error("Conversion failed: \(error.localizedDescription)")
            await playErrorSound()
        }
    }
    
    private struct ConversionResult {
        let originalText: String
        let convertedText: String
        let wasForced: Bool
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
        guard let inputSources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            Logger.conversion.error("Failed to get input source list")
            return
        }
        
        // Debug: List all available layouts
        Logger.conversion.debug("Switching to \(toRussian ? "Russian" : "English") layout")
        Logger.conversion.debug("Available keyboard layouts:")
        for inputSource in inputSources {
            if let sourceID = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) {
                let sourceIDString = Unmanaged<CFString>.fromOpaque(sourceID).takeUnretainedValue() as String
                Logger.conversion.debug("  - \(sourceIDString)")
            }
        }
        
        // Try to find and switch to the requested layout
        for inputSource in inputSources {
            guard let sourceID = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else { continue }
            let sourceIDString = Unmanaged<CFString>.fromOpaque(sourceID).takeUnretainedValue() as String
            
            // Skip non-keyboard sources
            guard !sourceIDString.contains(".SCIM") &&
                  !sourceIDString.contains("Emoji") &&
                  !sourceIDString.contains("Dictation") else { continue }
            
            let sourceIDLower = sourceIDString.lowercased()
            
            if toRussian {
                // Looking for Russian layout
                let isRussianLayout = sourceIDLower.contains("russian") ||
                                      sourceIDLower.contains("cyrillic")
                
                if isRussianLayout {
                    TISSelectInputSource(inputSource)
                    Logger.conversion.info("✅ Switched to Russian layout: \(sourceIDString)")
                    return
                }
            } else {
                // Looking for English layout - IMPORTANT: exclude Russian layouts first
                let isRussianLayout = sourceIDLower.contains("russian") ||
                                      sourceIDLower.contains("cyrillic")
                
                // Skip if this is a Russian layout
                if isRussianLayout {
                    continue
                }
                
                // Check if this is an English layout
                let isEnglishLayout = sourceIDString == "com.apple.keylayout.US" ||
                                      sourceIDString == "com.apple.keylayout.ABC" ||
                                      sourceIDString == "com.apple.keylayout.USExtended" ||
                                      sourceIDString == "com.apple.keylayout.USInternational-PC" ||
                                      sourceIDString == "com.apple.keylayout.British" ||
                                      sourceIDString == "com.apple.keylayout.Canadian" ||
                                      sourceIDString == "com.apple.keylayout.Australian" ||
                                      sourceIDString == "com.apple.keylayout.Irish" ||
                                      sourceIDLower.contains("u.s") ||
                                      sourceIDLower.contains(".us") ||
                                      sourceIDLower.contains("abc") ||
                                      sourceIDLower.contains("british") ||
                                      sourceIDLower.contains("english")
                
                if isEnglishLayout {
                    TISSelectInputSource(inputSource)
                    Logger.conversion.info("✅ Switched to English layout: \(sourceIDString)")
                    return
                }
            }
        }
        
        // If we didn't find the specific layout, try fallback for English
        if !toRussian {
            Logger.conversion.warning("⚠️ Specific English layout not found, trying fallback")
            
            for inputSource in inputSources {
                guard let sourceID = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else { continue }
                let sourceIDString = Unmanaged<CFString>.fromOpaque(sourceID).takeUnretainedValue() as String
                let sourceIDLower = sourceIDString.lowercased()
                
                // Use any non-Russian keyboard layout as fallback
                if sourceIDString.contains("com.apple.keylayout") &&
                   !sourceIDLower.contains("russian") &&
                   !sourceIDLower.contains("cyrillic") &&
                   !sourceIDString.contains("Emoji") &&
                   !sourceIDString.contains("Dictation") {
                    TISSelectInputSource(inputSource)
                    Logger.conversion.info("✅ Fallback: Switched to layout: \(sourceIDString)")
                    return
                }
            }
        }
        
        Logger.conversion.error("❌ Could not find \(toRussian ? "Russian" : "English") keyboard layout")
    }
    
    // Helper method to list available layouts
    func listAvailableLayouts() async {
        guard let inputSources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            Logger.conversion.error("Failed to get input source list")
            return
        }
        
        var layoutList: [String] = []
        
        Logger.conversion.info("📋 Available Keyboard Layouts:")
        
        for inputSource in inputSources {
            if let sourceID = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) {
                let sourceIDString = Unmanaged<CFString>.fromOpaque(sourceID).takeUnretainedValue() as String
                
                // Skip non-keyboard sources
                if !sourceIDString.contains("Emoji") && !sourceIDString.contains("Dictation") {
                    layoutList.append(sourceIDString)
                    Logger.conversion.info("  • \(sourceIDString)")
                }
            }
        }
        
        // Also show in an alert for easy viewing
        let alert = NSAlert()
        alert.messageText = "Доступные раскладки клавиатуры"
        alert.informativeText = layoutList.joined(separator: "\n• ")
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func playSuccessSound() async {
        guard settings.configuration.soundEnabled else { return }
        
        await SoundManager.shared.playSound(
            named: settings.configuration.successSoundName, 
            volume: settings.configuration.soundVolume
        )
    }
    
    private func playErrorSound() async {
        guard settings.configuration.soundEnabled else { return }
        
        await SoundManager.shared.playSound(
            named: settings.configuration.errorSoundName, 
            volume: settings.configuration.soundVolume
        )
    }
    
    private func cleanup() {
        if let monitor = shiftMonitor {
            NSEvent.removeMonitor(monitor)
            shiftMonitor = nil
        }
        
        if let monitor = capsLockMonitor {
            NSEvent.removeMonitor(monitor)
            capsLockMonitor = nil
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
        hotKeyManager = HotKeyManager(settings: self.settings)
        
        NSApp.setActivationPolicy(.accessory)
        requestAccessibilityPermissions()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        Logger.ui.info("Application will terminate")
        
        // Cleanup hotkey manager
        hotKeyManager = nil
        
        // Remove status bar item
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        
        Logger.ui.info("Application cleanup completed")
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
            title: "Переключить раскладку (\(self.settings.configuration.displayString))",
            action: #selector(manualSwitch),
            keyEquivalent: ""
        )
        convertItem.isEnabled = hasPermissions
        menu.addItem(convertItem)
        
        menu.addItem(.separator())
        
        // Sound toggle menu item
        let soundItem = NSMenuItem(
            title: "Проигрывать звуки",
            action: #selector(toggleSound),
            keyEquivalent: ""
        )
        soundItem.state = self.settings.configuration.soundEnabled ? .on : .off
        menu.addItem(soundItem)
        
        menu.addItem(NSMenuItem(
            title: "Настройки...",
            action: #selector(showSettings),
            keyEquivalent: ","
        ))
        
        menu.addItem(NSMenuItem(
            title: "Статистика...",
            action: #selector(showStatistics),
            keyEquivalent: ""
        ))
        
        menu.addItem(NSMenuItem(
            title: "О программе...",
            action: #selector(showAbout),
            keyEquivalent: ""
        ))
        
        // Debug menu item to show available keyboards
        menu.addItem(NSMenuItem(
            title: "Показать доступные раскладки",
            action: #selector(showAvailableLayouts),
            keyEquivalent: ""
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
            action: #selector(quitApplication),
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
    
    @objc private func showAvailableLayouts() {
        Task {
            await self.hotKeyManager?.listAvailableLayouts()
        }
    }
    
    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    
    @objc private func manualSwitch() {
        Task {
            await self.hotKeyManager?.convertLayout()
        }
    }
    
    @objc private func toggleSound() {
        self.settings.configuration.soundEnabled.toggle()
        Logger.ui.info("Sound \(self.settings.configuration.soundEnabled ? "enabled" : "disabled")")
        
        // Play a test sound if enabled
        if self.settings.configuration.soundEnabled {
            Task { @MainActor in
                await SoundManager.shared.playSound(
                    named: self.settings.configuration.successSoundName,
                    volume: self.settings.configuration.soundVolume
                )
            }
        }
    }
    
    @objc private func showSettings() {
        let settingsWindow = SettingsWindow(settings: self.settings)
        settingsWindow.show()
    }
    
    @objc private func showStatistics() {
        guard let metrics = hotKeyManager?.metrics else { return }
        
        let alert = NSAlert()
        alert.messageText = "Статистика работы"
        alert.informativeText = metrics.summary
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Сбросить")
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            metrics.reset()
            
            // Show confirmation
            let confirmAlert = NSAlert()
            confirmAlert.messageText = "Статистика сброшена"
            confirmAlert.informativeText = "Счетчики обнулены"
            confirmAlert.alertStyle = .informational
            confirmAlert.addButton(withTitle: "OK")
            confirmAlert.runModal()
        }
    }
    
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Layout Switcher"
        alert.informativeText = """
        Утилита для быстрого переключения раскладки клавиатуры
        
        Версия: 1.0
        Разработано с использованием SwiftUI и современных технологий Apple
        
        Функции:
        • Автоматическое преобразование текста между раскладками
        • Поддержка горячих клавиш и двойного нажатия Shift  
        • Умное определение языка
        • Современный интерфейс настроек
        
        Для работы требуются разрешения доступности в системных настройках.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        
        // Set application icon if available
        if let appIcon = NSApp.applicationIconImage {
            alert.icon = appIcon
        }
        
        alert.runModal()
    }
    
    @objc private func quitApplication() {
        Logger.ui.info("Application terminating via menu")
        
        // Perform clean shutdown
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Logger.ui.info("Application should terminate")
        return .terminateNow
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
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 650),
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
        
        // Автоматически подстроить размер под контент
        newWindow.setContentSize(hostingView.fittingSize)
        
        // Установить минимальный размер
        newWindow.minSize = NSSize(width: 600, height: 550)
        
        // Центрировать после изменения размера
        newWindow.center()
        
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
        PresetConfiguration(config: HotKeyConfiguration(
            keyCode: 0, 
            modifierFlags: 0, 
            keyCharacter: "", 
            hotKeyMode: .doubleShift,
            minDoubleShiftInterval: 0.05,
            maxDoubleShiftInterval: 0.8,
            soundEnabled: true,
            successSoundName: "Glass",
            errorSoundName: "Basso",
            soundVolume: 0.8
        )),
        PresetConfiguration(config: HotKeyConfiguration(
            keyCode: 0, 
            modifierFlags: 0, 
            keyCharacter: "", 
            hotKeyMode: .doubleCapsLock,
            minDoubleShiftInterval: 0.05,
            maxDoubleShiftInterval: 0.8,
            soundEnabled: true,
            successSoundName: "Ping",
            errorSoundName: "Basso",
            soundVolume: 0.8
        )),
        PresetConfiguration(config: HotKeyConfiguration(
            keyCode: 0x25, 
            modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue, 
            keyCharacter: "L", 
            hotKeyMode: .customHotkey,
            minDoubleShiftInterval: 0.05,
            maxDoubleShiftInterval: 0.8,
            soundEnabled: true,
            successSoundName: "Glass",
            errorSoundName: "Basso",
            soundVolume: 0.8
        )),
        PresetConfiguration(config: HotKeyConfiguration(
            keyCode: 0x11, 
            modifierFlags: NSEvent.ModifierFlags([.command, .shift]).rawValue, 
            keyCharacter: "T", 
            hotKeyMode: .customHotkey,
            minDoubleShiftInterval: 0.05,
            maxDoubleShiftInterval: 0.8,
            soundEnabled: true,
            successSoundName: "Ping",
            errorSoundName: "Basso",
            soundVolume: 0.6
        ))
    ]
}

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    @State private var isRecording = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with modern styling
            headerView
            
            // Main content
            ScrollView {
                LazyVStack(spacing: 24) {
                    hotKeySection
                    soundSection
                    presetsSection
                    
                    // Show validation errors if any
                    if !settings.configurationErrors.isEmpty {
                        validationErrorsView
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            
            // Footer
            footerView
        }
        .frame(minWidth: 600, maxWidth: .infinity,
               minHeight: 550, maxHeight: .infinity)
    }
    
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "keyboard")
                    .font(.system(size: 32, weight: .medium))
                    .foregroundStyle(.tint)
                
                Text("Layout Switcher")
                    .font(.title.weight(.semibold))
            }
            
            Text("Настройка горячих клавиш для переключения раскладки")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
        .padding(.bottom, 20)
    }
    
    private var hotKeySection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                // Режим горячей клавиши
                VStack(alignment: .leading, spacing: 8) {
                    Text("Режим активации:")
                        .font(.subheadline.weight(.medium))
                    
                    Picker("Режим", selection: $settings.configuration.hotKeyMode) {
                        Text(HotKeyMode.customHotkey.displayName).tag(HotKeyMode.customHotkey)
                        Text(HotKeyMode.doubleShift.displayName).tag(HotKeyMode.doubleShift)
                        Text(HotKeyMode.doubleCapsLock.displayName).tag(HotKeyMode.doubleCapsLock)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                
                Divider()
                
                // Показываем настройки в зависимости от режима
                switch settings.configuration.hotKeyMode {
                case .doubleShift, .doubleCapsLock:
                    doubleKeySettings
                case .customHotkey:
                    hotKeySettings
                }
            }
            .padding(.vertical, 8)
        } label: {
            Label("Горячая клавиша", systemImage: "command.square")
                .font(.headline)
        }
    }
    
    private var soundSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Проигрывать звуки", isOn: $settings.configuration.soundEnabled)
                    .toggleStyle(.switch)
                
                if settings.configuration.soundEnabled {
                    VStack(alignment: .leading, spacing: 16) {
                        // Volume slider
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Громкость:")
                                    .font(.caption.weight(.medium))
                                    .foregroundStyle(.secondary)
                                
                                Spacer()
                                
                                Text("\(Int(settings.configuration.soundVolume * 100))%")
                                    .font(.caption.monospacedDigit().weight(.medium))
                                    .foregroundStyle(.primary)
                            }
                            
                            Slider(value: $settings.configuration.soundVolume, in: 0.0...1.0) {
                                Text("Громкость")
                            } minimumValueLabel: {
                                Image(systemName: "speaker.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            } maximumValueLabel: {
                                Image(systemName: "speaker.wave.3.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        
                        // Success sound picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Звук успеха:")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                Picker("Звук успеха", selection: $settings.configuration.successSoundName) {
                                    ForEach(SoundConfiguration.availableSounds, id: \.self) { soundName in
                                        Text(SoundConfiguration.localizedName(for: soundName))
                                            .tag(soundName)
                                    }
                                }
                                .pickerStyle(.menu)
                                
                                Button("▶️") {
                                    playTestSound(settings.configuration.successSoundName)
                                }
                                .buttonStyle(.borderless)
                                .help("Прослушать звук")
                            }
                        }
                        
                        // Error sound picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Звук ошибки:")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                Picker("Звук ошибки", selection: $settings.configuration.errorSoundName) {
                                    ForEach(SoundConfiguration.availableSounds, id: \.self) { soundName in
                                        Text(SoundConfiguration.localizedName(for: soundName))
                                            .tag(soundName)
                                    }
                                }
                                .pickerStyle(.menu)
                                
                                Button("▶️") {
                                    playTestSound(settings.configuration.errorSoundName)
                                }
                                .buttonStyle(.borderless)
                                .help("Прослушать звук")
                            }
                        }
                    }
                    .padding(.leading, 16)
                }
            }
            .padding(.vertical, 8)
        } label: {
            Label("Звуковые уведомления", systemImage: "speaker.wave.2")
                .font(.headline)
        }
    }
    
    private func playTestSound(_ soundName: String) {
        SoundManager.shared.testSound(soundName, volume: self.settings.configuration.soundVolume)
    }
    
    private var doubleKeySettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(settings.configuration.hotKeyMode == .doubleShift 
                 ? "Настройте интервал между нажатиями Shift" 
                 : "Настройте интервал между нажатиями Caps Lock")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            intervalSlider(
                title: "Мин. интервал:",
                value: $settings.configuration.minDoubleShiftInterval,
                range: 0.01...0.5,
                format: "%.0f мс"
            )
            
            intervalSlider(
                title: "Макс. интервал:",
                value: $settings.configuration.maxDoubleShiftInterval,
                range: 0.1...2.0,
                format: "%.0f мс"
            )
        }
        .padding(.leading, 16)
    }
    
    private func intervalSlider(
        title: String,
        value: Binding<TimeInterval>,
        range: ClosedRange<TimeInterval>,
        format: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(String(format: format, value.wrappedValue * 1000))
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.primary)
            }
            
            Slider(value: value, in: range) {
                Text(title)
            } minimumValueLabel: {
                Text(String(format: "%.0f", range.lowerBound * 1000))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } maximumValueLabel: {
                Text(String(format: "%.0f", range.upperBound * 1000))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }
    
    private var hotKeySettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Текущая комбинация:")
                    .font(.subheadline.weight(.medium))
                
                Spacer()
                
                Text(settings.configuration.displayString)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.tint.opacity(0.1))
                    .foregroundStyle(.tint)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            
            Button(isRecording ? "Остановить запись..." : "Записать новую комбинацию") {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isRecording.toggle()
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }
    
    private var validationErrorsView: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(settings.configurationErrors, id: \.self) { error in
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.subheadline)
                        Spacer()
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("Ошибки конфигурации", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.headline)
        }
    }
    
    private var footerView: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack {
                // Status indicator
                HStack(spacing: 6) {
                    Circle()
                        .fill(settings.isConfigurationValid ? .green : .orange)
                        .frame(width: 8, height: 8)
                    
                    Text(settings.isConfigurationValid ? "Настройки корректны" : "Есть ошибки")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button("Готово") {
                    closeWindow()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!settings.isConfigurationValid)
            }
            .padding(20)
        }
    }
    
    private func closeWindow() {
        guard let window = NSApplication.shared.windows.first(where: { 
            $0.title == "Настройки Layout Switcher" 
        }) else { return }
        
        window.close()
    }
    
    private var presetsSection: some View {
        GroupBox {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 100), spacing: 12)
            ], spacing: 12) {
                ForEach(PresetConfiguration.presets) { preset in
                    PresetButton(preset: preset.config, current: settings.configuration) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            settings.configuration = preset.config
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        } label: {
            Label("Быстрые настройки", systemImage: "square.grid.2x2")
                .font(.headline)
        }
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
                .foregroundStyle(isSelected ? .white : .primary)
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
        .commands {
            // Add standard menu commands including Quit
            CommandGroup(replacing: .appInfo) {
                Button("О программе Layout Switcher") {
                    showAboutWindow()
                }
            }
            
            CommandGroup(replacing: .appTermination) {
                Button("Выйти из Layout Switcher") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
    }
    
    private func showAboutWindow() {
        let alert = NSAlert()
        alert.messageText = "Layout Switcher"
        alert.informativeText = """
        Утилита для быстрого переключения раскладки клавиатуры
        
        Версия: 1.0
        Разработано с использованием SwiftUI и современных технологий Apple
        
        Используйте горячие клавиши или двойное нажатие Shift для преобразования текста между русской и английской раскладками.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
