import SwiftUI
import Combine
import os.log
import Carbon.HIToolbox
import ServiceManagement

// MARK: - Logging
extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.layoutswitcher"
    
    static let hotkeys = Logger(subsystem: subsystem, category: "hotkeys")
    static let conversion = Logger(subsystem: subsystem, category: "conversion")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}

// MARK: - Error Handling
enum LayoutError: LocalizedError {
    case noTextSelected
    case conversionFailed(String)
    case accessibilityPermissionDenied
    case clipboardOperationFailed
    
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
    private let maxStoredTimes = 100
    
    func recordSuccess(duration: TimeInterval) {
        totalConversions += 1
        successfulConversions += 1
        
        conversionTimes.append(duration)
        if conversionTimes.count > maxStoredTimes {
            conversionTimes.removeFirst()
        }
        
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
    case ctrlShift
    case fnShift
    
    var displayName: String {
        switch self {
        case .customHotkey: return "Пользовательская комбинация"
        case .doubleShift: return "Двойное нажатие Shift"
        case .ctrlShift: return "Ctrl + Shift"
        case .fnShift: return "Fn + Shift"
        }
    }
}

struct HotKeyConfiguration: Codable, Equatable, Sendable {
    var keyCode: UInt16 = 0x25 // L
    var modifierFlags: UInt = NSEvent.ModifierFlags([.command, .shift]).rawValue
    var keyCharacter: String = "L"
    var hotKeyMode: HotKeyMode = .customHotkey
    var minDoubleShiftInterval: TimeInterval = 0.05
    var maxDoubleShiftInterval: TimeInterval = 0.8
    var soundEnabled: Bool = true
    var successSoundName: String = "Glass"
    var errorSoundName: String = "Basso"
    var soundVolume: Float = 0.8
    
    var modifiers: NSEvent.ModifierFlags {
        get { NSEvent.ModifierFlags(rawValue: modifierFlags) }
        set { modifierFlags = newValue.rawValue }
    }
    
    var displayString: String {
        switch hotKeyMode {
        case .doubleShift: return "⇧⇧"
        case .ctrlShift: return "⌃⇧"
        case .fnShift: return "fn⇧"
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
    
    var isValid: Bool {
        switch hotKeyMode {
        case .doubleShift:
            return minDoubleShiftInterval > 0 &&
                   maxDoubleShiftInterval > minDoubleShiftInterval &&
                   maxDoubleShiftInterval <= 5.0
        case .ctrlShift, .fnShift:
            return true // Всегда валидны
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
}

// MARK: - Sound Configuration
struct SoundConfiguration {
    static let availableSounds: [String] = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
        "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]
    
    static let soundDisplayNames: [String: String] = [
        "Basso": "Бассо", "Blow": "Дуновение", "Bottle": "Бутылка",
        "Frog": "Лягушка", "Funk": "Фанк", "Glass": "Стекло",
        "Hero": "Герой", "Morse": "Морзе", "Ping": "Пинг",
        "Pop": "Поп", "Purr": "Мурлыканье", "Sosumi": "Сосуми",
        "Submarine": "Подлодка", "Tink": "Тинк"
    ]
    
    static func localizedName(for soundName: String) -> String {
        return soundDisplayNames[soundName] ?? soundName
    }
}

// MARK: - Settings Manager
@MainActor
final class SettingsManager: ObservableObject {
    @Published var configuration = HotKeyConfiguration() {
        didSet { validateConfiguration() }
    }
    
    private let userDefaults = UserDefaults.standard
    private let configKey = "hotkey_configuration"
    private var cancellables = Set<AnyCancellable>()
    
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
        case .doubleShift:
            if configuration.minDoubleShiftInterval <= 0 {
                errors.append("Минимальный интервал должен быть больше 0")
            }
            if configuration.maxDoubleShiftInterval <= configuration.minDoubleShiftInterval {
                errors.append("Максимальный интервал должен быть больше минимального")
            }
            if configuration.maxDoubleShiftInterval > 5.0 {
                errors.append("Максимальный интервал слишком большой (>5 сек)")
            }
        case .ctrlShift, .fnShift:
            break // Нет дополнительных проверок
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
        // Pass the configuration in userInfo dictionary
        NotificationCenter.default.post(
            name: .hotKeyConfigurationChanged,
            object: nil,
            userInfo: ["configuration": config]
        )
        Logger.ui.info("Saved configuration: \(config.displayString)")
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let hotKeyConfigurationChanged = Notification.Name("hotKeyConfigurationChanged")
    static let accessibilityStatusChanged = Notification.Name("accessibilityStatusChanged")
}

// MARK: - App Version
extension Bundle {
    /// Версия приложения вида "1.5 (1)" из Info.plist (единый источник версии).
    var appVersionString: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

// MARK: - Key Codes Constants
/// Константы для виртуальных кодов клавиш (избегаем magic numbers)
private enum KeyCode {
    static let c: UInt16 = 0x08        // Клавиша C (для Cmd+C)
    static let v: UInt16 = 0x09        // Клавиша V (для Cmd+V)
    static let l: UInt16 = 0x25        // Клавиша L (дефолтная горячая клавиша)
    static let leftShift: UInt16 = 0x38   // Левый Shift
    static let rightShift: UInt16 = 0x3C  // Правый Shift
}

// MARK: - Timing Constants
/// Константы для задержек (в наносекундах)
private enum Timing {
    static let pasteDelay: UInt64 = 50_000_000       // 50ms - задержка перед вставкой
    static let restoreDelay: UInt64 = 100_000_000    // 100ms - задержка перед восстановлением буфера
    static let keyPressDelay: UInt64 = 10_000_000    // 10ms - задержка между keyDown и keyUp
    static let doubleShiftDelay: UInt64 = 100_000_000 // 100ms - задержка после двойного Shift
    static let clipboardPollInterval: UInt64 = 10_000_000  // 10ms - шаг опроса буфера обмена
    static let clipboardPollTimeout: UInt64 = 400_000_000  // 400ms - макс. ожидание копирования
}

// MARK: - Clipboard Helper
/// Структура для сохранения и восстановления содержимого буфера обмена
private struct ClipboardState {
    let changeCount: Int
    let stringContent: String?
    let dataContent: Data?
    
    init(pasteboard: NSPasteboard) {
        self.changeCount = pasteboard.changeCount
        self.stringContent = pasteboard.string(forType: .string)
        self.dataContent = pasteboard.data(forType: .string)
    }
    
    /// Восстанавливает содержимое буфера обмена
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if let data = dataContent {
            pasteboard.setData(data, forType: .string)
            Logger.conversion.debug("Restored clipboard content (data)")
        } else if let string = stringContent {
            pasteboard.setString(string, forType: .string)
            Logger.conversion.debug("Restored clipboard content (string)")
        } else {
            Logger.conversion.debug("Cleared clipboard (was empty)")
        }
    }
}

// MARK: - Layout Converter
@MainActor
final class LayoutConverter {
    private static let rusToEngMappings: [Character: Character] = [
        "й": "q", "ц": "w", "у": "e", "к": "r", "е": "t", "н": "y", "г": "u", "ш": "i", "щ": "o", "з": "p", "х": "[", "ъ": "]",
        "ф": "a", "ы": "s", "в": "d", "а": "f", "п": "g", "р": "h", "о": "j", "л": "k", "д": "l", "ж": ";", "э": "'",
        "я": "z", "ч": "x", "с": "c", "м": "v", "и": "b", "т": "n", "ь": "m", "б": ",", "ю": ".", ".": "/",
        "Й": "Q", "Ц": "W", "У": "E", "К": "R", "Е": "T", "Н": "Y", "Г": "U", "Ш": "I", "Щ": "O", "З": "P", "Х": "{", "Ъ": "}",
        "Ф": "A", "Ы": "S", "В": "D", "А": "F", "П": "G", "Р": "H", "О": "J", "Л": "K", "Д": "L", "Ж": ":", "Э": "\"",
        "Я": "Z", "Ч": "X", "С": "C", "М": "V", "И": "B", "Т": "N", "Ь": "M", "Б": "<", "Ю": ">", ",": "?",
        "ё": "`", "Ё": "~", "№": "#", " ": " "
    ]
    
    let rusToEng: [Character: Character] = LayoutConverter.rusToEngMappings
    
    lazy var engToRus: [Character: Character] = {
        // Строим обратный словарь поэлементно, чтобы дубликаты значений
        // не приводили к краху (Dictionary(uniqueKeysWithValues:) бросает fatalError).
        var result: [Character: Character] = [:]
        result.reserveCapacity(Self.rusToEngMappings.count)
        for (rus, eng) in Self.rusToEngMappings {
            result[eng] = rus
        }
        return result
    }()
    
    // Оптимизация: Set для O(1) поиска вместо O(n) в keys
    private lazy var russianCharSet: Set<Character> = Set(rusToEng.keys)
    private lazy var englishCharSet: Set<Character> = Set(engToRus.keys)
    
    private let conversionCache = NSCache<NSString, NSString>()
    
    init() {
        conversionCache.countLimit = 100
        conversionCache.totalCostLimit = 1024 * 100
    }
    
    func convert(_ text: String) -> String {
        let cacheKey = text as NSString
        
        if let cached = conversionCache.object(forKey: cacheKey) {
            Logger.conversion.debug("Using cached conversion")
            return cached as String
        }
        
        let isRussian = detectLanguage(text)
        let mapping = isRussian ? rusToEng : engToRus
        
        Logger.conversion.debug("Converting from \(isRussian ? "Russian" : "English")")
        
        let result = String(text.compactMap { mapping[$0] ?? $0 })
        
        let cost = text.utf8.count
        conversionCache.setObject(result as NSString, forKey: cacheKey, cost: cost)
        
        return result
    }
    
    func detectLanguage(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        var rusCount = 0
        var engCount = 0
        
        // Оптимизация: использование Set вместо Dictionary.keys для O(1) поиска
        for char in lowercased {
            if russianCharSet.contains(char) {
                rusCount += 1
            } else if englishCharSet.contains(char) {
                engCount += 1
            }
        }
        
        if rusCount == 0 && engCount == 0 {
            return text.contains { $0.unicodeScalars.contains { $0.value >= 0x0400 && $0.value <= 0x04FF } }
        }
        
        return rusCount > engCount
    }
}

// MARK: - Hot Key Manager
@MainActor
final class HotKeyManager: ObservableObject {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Use UInt64 (raw value) instead of CGEventFlags as dictionary key
    // nonisolated(unsafe) потому что доступ из event tap callback (другой поток)
    private nonisolated(unsafe) var lastModifierPressTime: [UInt64: TimeInterval] = [:]
    private nonisolated(unsafe) var modifierPressCount: [UInt64: Int] = [:]
    
    // Debounce для комбинаций клавиш (Ctrl+Shift, Fn+Shift)
    private nonisolated(unsafe) var lastComboTriggerTime: TimeInterval = 0
    private let comboDebounceInterval: TimeInterval = 0.5
    
    private let settings: SettingsManager
    private let converter = LayoutConverter()
    let metrics = ConversionMetrics()
    
    private var cancellables = Set<AnyCancellable>()
    private var accessibilityCheckTimer: Timer?
    private var lastAccessibilityStatus: Bool = false
    
    // КРИТИЧНО: Кэшируем конфигурацию для безопасного доступа из callback
    // Event tap callback выполняется НЕ на main thread!
    private nonisolated(unsafe) var cachedHotKeyMode: HotKeyMode = .customHotkey
    private nonisolated(unsafe) var cachedKeyCode: UInt16 = 0x25
    private nonisolated(unsafe) var cachedModifierFlags: UInt = 0
    private nonisolated(unsafe) var cachedMinInterval: TimeInterval = 0.05
    private nonisolated(unsafe) var cachedMaxInterval: TimeInterval = 0.8
    
    init(settings: SettingsManager) {
        self.settings = settings
        lastAccessibilityStatus = AXIsProcessTrusted()
        updateCachedConfiguration()
        setupConfigurationObserver()
        setupAccessibilityMonitoring()
        setupEventTap()
    }
    
    /// Обновляет кэшированную конфигурацию (вызывается на main thread)
    private func updateCachedConfiguration() {
        let config = settings.configuration
        cachedHotKeyMode = config.hotKeyMode
        cachedKeyCode = config.keyCode
        cachedModifierFlags = config.modifierFlags
        cachedMinInterval = config.minDoubleShiftInterval
        cachedMaxInterval = config.maxDoubleShiftInterval
        Logger.hotkeys.debug("Configuration cached: mode=\(self.cachedHotKeyMode.rawValue)")
    }
    
    deinit {
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = nil
        
        // Cleanup synchronously - deinit cannot be async
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
    }
    
    private func setupAccessibilityMonitoring() {
        // Оптимизация: проверяем права каждые 5 секунд вместо 2,
        // и только при изменении статуса выполняем действия
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let hasAccess = AXIsProcessTrusted()
            
            // Оптимизация: проверяем изменение статуса, чтобы не делать лишнюю работу
            guard hasAccess != self.lastAccessibilityStatus else { return }
            self.lastAccessibilityStatus = hasAccess
            
            // Если права появились и event tap ещё не создан
            if hasAccess && self.eventTap == nil {
                Logger.hotkeys.info("✅ Accessibility permissions granted - setting up event tap")
                Task { @MainActor in
                    self.setupEventTap()
                    // Уведомляем AppDelegate об изменении статуса
                    NotificationCenter.default.post(name: .accessibilityStatusChanged, object: nil)
                }
            }
            // Если права отозваны и event tap существует
            else if !hasAccess && self.eventTap != nil {
                Logger.hotkeys.warning("⚠️ Accessibility permissions revoked - disabling event tap")
                Task { @MainActor in
                    if let tap = self.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: false)
                        CFMachPortInvalidate(tap)
                        self.eventTap = nil
                    }
                    
                    if let source = self.runLoopSource {
                        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
                        self.runLoopSource = nil
                    }
                    // Уведомляем AppDelegate об изменении статуса
                    NotificationCenter.default.post(name: .accessibilityStatusChanged, object: nil)
                }
            }
        }
    }
    
    private func setupConfigurationObserver() {
        NotificationCenter.default
            .publisher(for: .hotKeyConfigurationChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                guard let self = self else { return }
                // Обновляем кэш конфигурации
                self.updateCachedConfiguration()
                // Пересоздаём event tap с новыми настройками
                self.setupEventTap()
            }
            .store(in: &cancellables)
    }
    
    private func setupEventTap() {
        // Сначала проверяем права
        guard AXIsProcessTrusted() else {
            Logger.hotkeys.warning("⚠️ Cannot setup event tap - accessibility permissions not granted")
            return
        }
        
        // Clean up existing tap
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            runLoopSource = nil
        }
        
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue)
        
        // ВАЖНО: Используем .listenOnly для безопасности!
        // Это гарантирует, что события ВСЕГДА проходят к системе,
        // даже если в нашем коде произойдёт ошибка.
        // Недостаток: для customHotkey символ будет вводиться (можно стереть потом).
        let currentMode = cachedHotKeyMode
        let tapOptions: CGEventTapOptions = currentMode == .customHotkey
            ? .defaultTap  // Для customHotkey нужно блокировать символ
            : .listenOnly  // Для остальных режимов - только слушаем (безопасно)
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: tapOptions,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { proxy, type, event, refcon in
                // КРИТИЧНО: Всегда пропускаем событие при любой ошибке
                guard let refcon = refcon else {
                    return Unmanaged.passUnretained(event)
                }
                
                let manager = Unmanaged<HotKeyManager>.fromOpaque(refcon)
                    .takeUnretainedValue()
                
                // Защита от системных событий (tap disabled и т.д.)
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    // Переактивируем tap если он был отключён системой
                    if let tap = manager.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                
                // Обрабатываем только keyDown и flagsChanged
                guard type == .keyDown || type == .flagsChanged else {
                    return Unmanaged.passUnretained(event)
                }
                
                // КРИТИЧНО: Используем ТОЛЬКО кэшированные значения!
                // НЕ обращаемся к settings - это вызовет deadlock!
                let shouldBlock = manager.handleEventFromCallback(event, type: type)
                
                // Блокируем событие только для customHotkey режима
                if shouldBlock && manager.cachedHotKeyMode == .customHotkey {
                    return nil
                }
                
                // Для всех остальных случаев - ВСЕГДА пропускаем событие
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Logger.hotkeys.error("❌ Failed to create event tap")
            return
        }
        
        self.eventTap = eventTap
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        Logger.hotkeys.info("✅ Event tap created for mode: \(currentMode.rawValue), options: \(tapOptions == .listenOnly ? "listenOnly" : "defaultTap")")
    }
    
    /// Обработчик событий для вызова из callback (nonisolated, thread-safe)
    /// КРИТИЧНО: Не обращается к @MainActor свойствам напрямую!
    nonisolated func handleEventFromCallback(_ event: CGEvent, type: CGEventType) -> Bool {
        switch cachedHotKeyMode {
        case .customHotkey:
            return handleCustomHotkeyFromCallback(event, type: type)
        case .doubleShift:
            return handleDoubleModifierFromCallback(event, type: type, targetFlag: .maskShift, keyCodes: [KeyCode.leftShift, KeyCode.rightShift])
        case .ctrlShift:
            return handleCtrlShiftFromCallback(event, type: type)
        case .fnShift:
            return handleFnShiftFromCallback(event, type: type)
        }
    }
    
    // MARK: - Thread-safe handlers (для вызова из event tap callback)
    // Эти методы используют ТОЛЬКО кэшированные значения, не обращаются к @MainActor
    
    nonisolated private func handleCustomHotkeyFromCallback(_ event: CGEvent, type: CGEventType) -> Bool {
        guard type == .keyDown else { return false }
        
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        
        let expectedFlags = CGEventFlags(rawValue: UInt64(cachedModifierFlags))
        
        if keyCode == cachedKeyCode && flags.contains(expectedFlags) {
            Logger.hotkeys.info("Custom hotkey triggered")
            Task { @MainActor in
                await self.convertLayout()
            }
            return true
        }
        
        return false
    }
    
    nonisolated private func handleDoubleModifierFromCallback(
        _ event: CGEvent,
        type: CGEventType,
        targetFlag: CGEventFlags,
        keyCodes: [UInt16]
    ) -> Bool {
        guard type == .flagsChanged else { return false }
        
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCodes.contains(keyCode) else { return false }
        
        let flags = event.flags
        let hasTargetFlag = flags.contains(targetFlag)
        
        var otherModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl]
        if targetFlag != .maskShift {
            otherModifiers.insert(.maskShift)
        }
        
        let hasOtherModifiers = !flags.intersection(otherModifiers).isEmpty
        let flagKey = targetFlag.rawValue
        
        if hasOtherModifiers {
            modifierPressCount[flagKey] = 0
            lastModifierPressTime[flagKey] = 0
            return false
        }
        
        if hasTargetFlag {
            return handleModifierPressFromCallback(targetFlag: targetFlag)
        }
        
        return false
    }
    
    nonisolated private func handleModifierPressFromCallback(targetFlag: CGEventFlags) -> Bool {
        let currentTime = Date.timeIntervalSinceReferenceDate
        let flagKey = targetFlag.rawValue
        
        let lastTime = lastModifierPressTime[flagKey] ?? 0
        let count = modifierPressCount[flagKey] ?? 0
        let timeSinceLastPress = lastTime > 0 ? currentTime - lastTime : Double.infinity
        
        if timeSinceLastPress > cachedMaxInterval {
            modifierPressCount[flagKey] = 1
            lastModifierPressTime[flagKey] = currentTime
        } else if timeSinceLastPress < cachedMinInterval {
            return false
        } else {
            modifierPressCount[flagKey] = count + 1
            
            if modifierPressCount[flagKey] == 2 {
                Logger.hotkeys.info("Double press detected!")
                modifierPressCount[flagKey] = 0
                lastModifierPressTime[flagKey] = 0
                
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: Timing.doubleShiftDelay)
                    await self.convertLayout()
                }
            } else {
                lastModifierPressTime[flagKey] = currentTime
            }
        }
        
        return false
    }
    
    nonisolated private func handleCtrlShiftFromCallback(_ event: CGEvent, type: CGEventType) -> Bool {
        guard type == .flagsChanged else { return false }
        
        let flags = event.flags
        let hasCtrl = flags.contains(.maskControl)
        let hasShift = flags.contains(.maskShift)
        let hasOthers = flags.contains(.maskCommand) || flags.contains(.maskAlternate)
        
        if hasCtrl && hasShift && !hasOthers {
            let now = Date.timeIntervalSinceReferenceDate
            guard now - lastComboTriggerTime > comboDebounceInterval else {
                return false
            }
            lastComboTriggerTime = now
            
            Logger.hotkeys.info("✅ Ctrl+Shift detected!")
            Task { @MainActor in
                await self.convertLayout()
            }
        }
        
        return false
    }
    
    nonisolated private func handleFnShiftFromCallback(_ event: CGEvent, type: CGEventType) -> Bool {
        guard type == .flagsChanged else { return false }
        
        let flags = event.flags
        let hasFn = flags.contains(.maskSecondaryFn)
        let hasShift = flags.contains(.maskShift)
        let hasOthers = flags.contains(.maskCommand) || flags.contains(.maskAlternate) || flags.contains(.maskControl)
        
        if hasFn && hasShift && !hasOthers {
            let now = Date.timeIntervalSinceReferenceDate
            guard now - lastComboTriggerTime > comboDebounceInterval else {
                return false
            }
            lastComboTriggerTime = now
            
            Logger.hotkeys.info("✅ Fn+Shift detected!")
            Task { @MainActor in
                await self.convertLayout()
            }
        }
        
        return false
    }
    
    func convertLayout() async {
        let startTime = Date()
        
        Logger.conversion.info("Starting layout conversion via clipboard...")
        
        let pasteboard = NSPasteboard.general
        // Сохраняем текущее содержимое буфера обмена
        let clipboardState = ClipboardState(pasteboard: pasteboard)
        
        do {
            Logger.conversion.debug("Old clipboard count: \(clipboardState.changeCount), content: '\(clipboardState.stringContent?.prefix(30) ?? "nil")...'")
            
            // НЕ очищаем буфер - пусть остается старое содержимое
            // Это позволит нам определить, действительно ли было что-то скопировано
            
            // Симулируем Cmd+C для копирования выделенного текста
            try await simulateKeyPress(key: KeyCode.c, modifiers: .maskCommand)
            
            // Опрашиваем буфер обмена, пока не появится скопированный текст.
            // Это быстрее и надёжнее фиксированной задержки: возврат происходит
            // сразу после готовности буфера, а на медленной системе ждём дольше.
            let copiedTextOptional = await waitForCopiedText(
                initialChangeCount: clipboardState.changeCount,
                pasteboard: pasteboard
            )
            
            // Проверяем, что текст был выделен и скопирован
            guard let copiedText = copiedTextOptional,
                  !copiedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Logger.conversion.warning("Failed to copy selected text - restoring clipboard")
                clipboardState.restore(to: pasteboard)
                metrics.recordFailure()
                await playErrorSound()
                return
            }
            
            Logger.conversion.info("Copied text (\(copiedText.count) chars): '\(copiedText.prefix(50))...'")
            
            // Конвертируем текст (используем скопированный из буфера для надежности)
            let convertedText = converter.convert(copiedText)
            
            guard convertedText != copiedText else {
                Logger.conversion.warning("Text unchanged after conversion")
                clipboardState.restore(to: pasteboard)
                metrics.recordFailure()
                await playErrorSound()
                return
            }
            
            Logger.conversion.info("Converted to (\(convertedText.count) chars): '\(convertedText.prefix(50))...'")
            
            // Помещаем конвертированный текст в буфер
            pasteboard.clearContents()
            pasteboard.setString(convertedText, forType: .string)
            
            // Вставляем конвертированный текст
            try await Task.sleep(nanoseconds: Timing.pasteDelay)
            try await simulateKeyPress(key: KeyCode.v, modifiers: .maskCommand)
            
            // Восстанавливаем оригинальное содержимое буфера обмена
            try await Task.sleep(nanoseconds: Timing.restoreDelay)
            clipboardState.restore(to: pasteboard)
            
            // Переключаем раскладку клавиатуры на основе скопированного текста
            let wasRussian = converter.detectLanguage(copiedText)
            await switchKeyboardLayout(toRussian: !wasRussian)
            
            let duration = Date().timeIntervalSince(startTime)
            metrics.recordSuccess(duration: duration)
            await playSuccessSound()
            
        } catch {
            Logger.conversion.error("Conversion failed: \(error)")
            // Восстанавливаем буфер при ошибке
            clipboardState.restore(to: pasteboard)
            metrics.recordFailure()
            await playErrorSound()
        }
    }
    
    /// Ожидает изменения буфера обмена после Cmd+C, опрашивая `changeCount`
    /// с шагом `clipboardPollInterval` до таймаута `clipboardPollTimeout`.
    /// Возвращает скопированный текст или nil, если буфер так и не изменился.
    private func waitForCopiedText(initialChangeCount: Int, pasteboard: NSPasteboard) async -> String? {
        var waited: UInt64 = 0
        while waited < Timing.clipboardPollTimeout {
            if pasteboard.changeCount > initialChangeCount {
                return pasteboard.string(forType: .string)
            }
            try? await Task.sleep(nanoseconds: Timing.clipboardPollInterval)
            waited += Timing.clipboardPollInterval
        }
        // Финальная проверка на случай изменения у самой границы таймаута
        guard pasteboard.changeCount > initialChangeCount else { return nil }
        return pasteboard.string(forType: .string)
    }
    
    private func simulateKeyPress(key: UInt16, modifiers: CGEventFlags = []) async throws {
        guard AXIsProcessTrusted() else {
            throw LayoutError.accessibilityPermissionDenied
        }
        
        let source = CGEventSource(stateID: .hidSystemState)
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            throw LayoutError.clipboardOperationFailed
        }
        
        keyDown.flags = modifiers
        keyUp.flags = modifiers
        
        keyDown.post(tap: .cghidEventTap)
        try await Task.sleep(nanoseconds: Timing.keyPressDelay)
        keyUp.post(tap: .cghidEventTap)
    }
    
    private func switchKeyboardLayout(toRussian: Bool) async {
        guard let inputSources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            Logger.conversion.error("Failed to get input source list")
            return
        }
        
        Logger.conversion.debug("Switching to \(toRussian ? "Russian" : "English") layout")
        
        for inputSource in inputSources {
            guard let sourceID = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else { continue }
            let sourceIDString = Unmanaged<CFString>.fromOpaque(sourceID).takeUnretainedValue() as String
            
            guard !sourceIDString.contains(".SCIM") &&
                  !sourceIDString.contains("Emoji") &&
                  !sourceIDString.contains("Dictation") else { continue }
            
            let sourceIDLower = sourceIDString.lowercased()
            
            if toRussian {
                let isRussianLayout = sourceIDLower.contains("russian") || sourceIDLower.contains("cyrillic")
                
                if isRussianLayout {
                    TISSelectInputSource(inputSource)
                    Logger.conversion.info("✅ Switched to Russian: \(sourceIDString)")
                    return
                }
            } else {
                let isRussianLayout = sourceIDLower.contains("russian") || sourceIDLower.contains("cyrillic")
                if isRussianLayout { continue }
                
                let isEnglishLayout = sourceIDString == "com.apple.keylayout.US" ||
                                      sourceIDString == "com.apple.keylayout.ABC" ||
                                      sourceIDString == "com.apple.keylayout.USExtended" ||
                                      sourceIDLower.contains("u.s") ||
                                      sourceIDLower.contains(".us") ||
                                      sourceIDLower.contains("abc") ||
                                      sourceIDLower.contains("english")
                
                if isEnglishLayout {
                    TISSelectInputSource(inputSource)
                    Logger.conversion.info("✅ Switched to English: \(sourceIDString)")
                    return
                }
            }
        }
        
        Logger.conversion.error("❌ Could not find \(toRussian ? "Russian" : "English") layout")
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
    
}

// MARK: - App Delegate
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var hotKeyManager: HotKeyManager?
    private let settings = SettingsManager()
    private var accessibilityObserver: NSObjectProtocol?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        Logger.ui.info("Application launched")
        
        setupStatusBar()
        setupAccessibilityObserver()
        hotKeyManager = HotKeyManager(settings: self.settings)
        
        NSApp.setActivationPolicy(.accessory)
        requestAccessibilityPermissions()
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
        // Оптимизация: обновляем иконку только при изменении статуса прав,
        // а не каждую секунду через polling
        accessibilityObserver = NotificationCenter.default.addObserver(
            forName: .accessibilityStatusChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateStatusBarIcon()
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
        
        // Начальное обновление иконки
        updateStatusBarIcon()
    }
    
    private func updateStatusBarIcon() {
        guard let button = statusItem?.button else { return }
        
        let hasPermissions = AXIsProcessTrusted()
        
        // Меняем иконку в зависимости от статуса прав
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
            title: hasPermissions ? "✅ Разрешения предоставлены" : "⚠️ Требуются разрешения",
            action: nil,
            keyEquivalent: ""
        )
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
        
        let soundItem = NSMenuItem(
            title: "Проигрывать звуки",
            action: #selector(toggleSound),
            keyEquivalent: ""
        )
        soundItem.state = self.settings.configuration.soundEnabled ? .on : .off
        menu.addItem(soundItem)
        
        let launchAtLoginItem = NSMenuItem(
            title: "Запускать при старте системы",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLoginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(launchAtLoginItem)
        
        menu.addItem(NSMenuItem(title: "Настройки...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Статистика...", action: #selector(showStatistics), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "О программе...", action: #selector(showAbout), keyEquivalent: ""))
        
        if !hasPermissions {
            menu.addItem(NSMenuItem(
                title: "Предоставить разрешения...",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            ))
        }
        
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выйти", action: #selector(quitApplication), keyEquivalent: "q"))
        
        menu.items.forEach { $0.target = self }
        
        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }
    
    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    
    @objc private func manualSwitch() {
        Task { await self.hotKeyManager?.convertLayout() }
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
        Утилита для переключения раскладки клавиатуры
        
        Версия: \(Bundle.main.appVersionString)
        
        © 2024
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        
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
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        
        if !AXIsProcessTrustedWithOptions(options) {
            Logger.ui.warning("Accessibility permissions not granted")
            
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Требуются разрешения доступности"
                alert.informativeText = """
                Layout Switcher требует разрешения доступности.
                
                Откройте: Системные настройки → Конфиденциальность и безопасность → Универсальный доступ
                """
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Открыть настройки")
                alert.addButton(withTitle: "Позже")
                
                if alert.runModal() == .alertFirstButtonReturn {
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
        
        newWindow.title = "Настройки Layout Switcher"
        newWindow.center()
        newWindow.isReleasedWhenClosed = false
        
        let contentView = SettingsView(settings: settings)
        let hostingView = NSHostingView(rootView: contentView)
        newWindow.contentView = hostingView
        
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

// MARK: - Settings View
struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    @State private var isVisible = false
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : -20)
            
            ScrollView {
                LazyVStack(spacing: 20) {
                    hotKeySection
                        .opacity(isVisible ? 1 : 0)
                        .offset(y: isVisible ? 0 : 20)
                    
                    soundSection
                        .opacity(isVisible ? 1 : 0)
                        .offset(y: isVisible ? 0 : 20)
                    
                    if !settings.configurationErrors.isEmpty {
                        validationErrorsView
                            .opacity(isVisible ? 1 : 0)
                            .offset(y: isVisible ? 0 : 20)
                    }
                }
                .padding(20)
            }
            
            footerView
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : 20)
        }
        .frame(minWidth: 600, minHeight: 500)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                isVisible = true
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "keyboard")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(.tint)
                
                Text("Layout Switcher")
                    .font(.system(size: 26, weight: .bold))
            }
            
            Text("Настройка горячих клавиш для переключения раскладки")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }
    
    private var hotKeySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Горячая клавиша", systemImage: "command.square")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Режим активации:")
                    .font(.subheadline.weight(.medium))
                
                Picker("Режим", selection: $settings.configuration.hotKeyMode) {
                    Text(HotKeyMode.customHotkey.displayName).tag(HotKeyMode.customHotkey)
                    Text(HotKeyMode.doubleShift.displayName).tag(HotKeyMode.doubleShift)
                    Text(HotKeyMode.ctrlShift.displayName).tag(HotKeyMode.ctrlShift)
                    Text(HotKeyMode.fnShift.displayName).tag(HotKeyMode.fnShift)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            
            Divider()
            
            switch settings.configuration.hotKeyMode {
            case .doubleShift:
                doubleKeySettings
            case .ctrlShift:
                ctrlShiftSettings
            case .fnShift:
                fnShiftSettings
            case .customHotkey:
                customHotkeySettings
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var doubleKeySettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Настройте интервал между нажатиями Shift")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            intervalSlider(
                title: "Мин. интервал:",
                value: $settings.configuration.minDoubleShiftInterval,
                range: 0.01...0.5
            )
            
            intervalSlider(
                title: "Макс. интервал:",
                value: $settings.configuration.maxDoubleShiftInterval,
                range: 0.1...2.0
            )
        }
        .padding(.leading, 16)
    }
    
    private var ctrlShiftSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "command.square")
                    .font(.title2)
                    .foregroundStyle(.tint)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ctrl + Shift")
                        .font(.headline)
                    Text("Нажмите обе клавиши одновременно для переключения раскладки")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.leading, 16)
    }
    
    private var fnShiftSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "keyboard")
                    .font(.title2)
                    .foregroundStyle(.tint)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Fn + Shift")
                        .font(.headline)
                    Text("Нажмите Fn и Shift одновременно для переключения раскладки")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            
            Text("⚠️ Примечание: Fn клавиша может работать по-разному на разных клавиатурах")
                .font(.caption2)
                .foregroundStyle(.orange)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.leading, 16)
    }
    
    private func intervalSlider(
        title: String,
        value: Binding<TimeInterval>,
        range: ClosedRange<TimeInterval>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text(String(format: "%.0f мс", value.wrappedValue * 1000))
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
    
    private var customHotkeySettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Текущая комбинация:")
                    .font(.subheadline.weight(.medium))
                
                Spacer()
                
                Text(settings.configuration.displayString)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(Color.accentColor)
            }
            
            Text("По умолчанию: ⌘⇧L")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Звуковые уведомления", systemImage: "speaker.wave.2")
                .font(.headline)
            
            Toggle("Проигрывать звуки", isOn: $settings.configuration.soundEnabled)
                .toggleStyle(.switch)
            
            if settings.configuration.soundEnabled {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Громкость:")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Text("\(Int(settings.configuration.soundVolume * 100))%")
                                .font(.caption.monospacedDigit().weight(.medium))
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
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Звук успеха:")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Picker("Звук успеха", selection: $settings.configuration.successSoundName) {
                                ForEach(SoundConfiguration.availableSounds, id: \.self) { soundName in
                                    Text(SoundConfiguration.localizedName(for: soundName)).tag(soundName)
                                }
                            }
                            .pickerStyle(.menu)
                            
                            Button("▶️") {
                                Task { @MainActor in
                                    SoundManager.shared.testSound(
                                        settings.configuration.successSoundName,
                                        volume: settings.configuration.soundVolume
                                    )
                                }
                            }
                            .buttonStyle(.borderless)
                            .help("Прослушать звук")
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Звук ошибки:")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Picker("Звук ошибки", selection: $settings.configuration.errorSoundName) {
                                ForEach(SoundConfiguration.availableSounds, id: \.self) { soundName in
                                    Text(SoundConfiguration.localizedName(for: soundName)).tag(soundName)
                                }
                            }
                            .pickerStyle(.menu)
                            
                            Button("▶️") {
                                Task { @MainActor in
                                    SoundManager.shared.testSound(
                                        settings.configuration.errorSoundName,
                                        volume: settings.configuration.soundVolume
                                    )
                                }
                            }
                            .buttonStyle(.borderless)
                            .help("Прослушать звук")
                        }
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var validationErrorsView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ошибки конфигурации", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.headline)
            
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
        }
        .padding(20)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var footerView: some View {
        VStack(spacing: 0) {
            Divider()
            
            HStack {
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
        .background(.regularMaterial)
    }
    
    private func closeWindow() {
        guard let window = NSApplication.shared.windows.first(where: {
            $0.title == "Настройки Layout Switcher"
        }) else { return }
        
        window.close()
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
        Переключение раскладки клавиатуры
        
        Версия: \(Bundle.main.appVersionString)
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
