//
//  Models.swift
//  LayoutSwitcher
//
//  Модели конфигурации, константы клавиш и таймингов, служебные расширения.
//

import AppKit
import os.log

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
    case secureField
    
    var errorDescription: String? {
        switch self {
        case .noTextSelected:
            return L(.errNoText)
        case .conversionFailed(let reason):
            return String(format: L(.errConversionFailed), reason)
        case .accessibilityPermissionDenied:
            return L(.errAccessibility)
        case .clipboardOperationFailed:
            return L(.errClipboard)
        case .secureField:
            return L(.errSecureField)
        }
    }
}

// MARK: - Hotkey / detection modes
enum HotKeyMode: String, Codable, Equatable, Sendable, CaseIterable {
    case customHotkey
    case doubleShift
    case ctrlShift
    case fnShift
    case singleAlt
    case doubleAlt
    
    var displayName: String {
        switch self {
        case .customHotkey: return L(.hkCustom)
        case .doubleShift: return L(.hkDoubleShift)
        case .ctrlShift: return L(.hkCtrlShift)
        case .fnShift: return L(.hkFnShift)
        case .singleAlt: return L(.hkSingleAlt)
        case .doubleAlt: return L(.hkDoubleAlt)
        }
    }
    
    /// Для пользовательской комбинации event tap должен уметь глотать событие
    /// (`.defaultTap`); остальные режимы только слушают. Смена этого признака —
    /// единственный случай, когда tap нужно пересоздавать.
    var needsBlockingTap: Bool { self == .customHotkey }
}

/// Реакция на ввод в неправильной раскладке (автодетекция).
enum AutoSwitchMode: String, Codable, Equatable, Sendable, CaseIterable {
    case off         // Выключено
    case warnSound   // Только звук-предупреждение
    case autoSwitch  // Авто-исправление: меняет слово и переключает раскладку
    
    var displayName: String {
        switch self {
        case .off: return L(.asOff)
        case .warnSound: return L(.asWarnSound)
        case .autoSwitch: return L(.asAutoSwitch)
        }
    }
}

/// Движок детекции неправильной раскладки.
enum DetectionEngine: String, Codable, Equatable, Sendable, CaseIterable {
    case spellChecker  // Системный NSSpellChecker (по словарям)
    case ngram         // Статистическая модель триграмм (работает и для несловарных слов)
    
    var displayName: String {
        switch self {
        case .spellChecker: return L(.deDictionary)
        case .ngram: return L(.deNgram)
        }
    }
}

// MARK: - Configuration
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
    
    // Автодетекция неправильной раскладки
    var autoSwitchMode: AutoSwitchMode = .off
    var minWordLength: Int = 3
    var wrongLayoutSoundName: String = "Submarine"
    var excludedAppBundleIDs: [String] = []
    var detectionEngine: DetectionEngine = .ngram
    
    // Пара раскладок для конвертации/переключения по точному ID.
    // Пустая строка означает автоопределение (английская ↔ кириллическая).
    var layout1ID: String = ""
    var layout2ID: String = ""
    
    /// Читать и заменять текст через Accessibility API сфокусированного поля
    /// (без буфера обмена и синтетических нажатий), с откатом на ⌘C/⌘V там,
    /// где приложение этого не поддерживает.
    var useAccessibilityReplacement: Bool = true
    
    var modifiers: NSEvent.ModifierFlags {
        get { NSEvent.ModifierFlags(rawValue: modifierFlags) }
        set { modifierFlags = newValue.rawValue }
    }
    
    var displayString: String {
        switch hotKeyMode {
        case .doubleShift: return "⇧⇧"
        case .ctrlShift: return "⌃⇧"
        case .fnShift: return "fn⇧"
        case .singleAlt: return "⌥"
        case .doubleAlt: return "⌥⌥"
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
        case .doubleShift, .doubleAlt:
            return minDoubleShiftInterval > 0 &&
                   maxDoubleShiftInterval > minDoubleShiftInterval &&
                   maxDoubleShiftInterval <= 5.0
        case .ctrlShift, .fnShift, .singleAlt:
            return true // Всегда валидны
        case .customHotkey:
            return !keyCharacter.isEmpty && modifierFlags != 0
        }
    }
}

extension HotKeyConfiguration {
    private enum CodingKeys: String, CodingKey {
        case keyCode, modifierFlags, keyCharacter, hotKeyMode
        case minDoubleShiftInterval, maxDoubleShiftInterval
        case soundEnabled, successSoundName, errorSoundName, soundVolume
        case autoSwitchMode, minWordLength, wrongLayoutSoundName, excludedAppBundleIDs
        case layout1ID, layout2ID
        case detectionEngine
        case useAccessibilityReplacement
    }
    
    /// Декодер, устойчивый к отсутствию новых полей: значения, которых нет
    /// в сохранённой конфигурации, берутся из дефолтов (без сброса настроек).
    init(from decoder: Decoder) throws {
        let defaults = HotKeyConfiguration()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        keyCode = try c.decodeIfPresent(UInt16.self, forKey: .keyCode) ?? defaults.keyCode
        modifierFlags = try c.decodeIfPresent(UInt.self, forKey: .modifierFlags) ?? defaults.modifierFlags
        keyCharacter = try c.decodeIfPresent(String.self, forKey: .keyCharacter) ?? defaults.keyCharacter
        hotKeyMode = try c.decodeIfPresent(HotKeyMode.self, forKey: .hotKeyMode) ?? defaults.hotKeyMode
        minDoubleShiftInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .minDoubleShiftInterval) ?? defaults.minDoubleShiftInterval
        maxDoubleShiftInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .maxDoubleShiftInterval) ?? defaults.maxDoubleShiftInterval
        soundEnabled = try c.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? defaults.soundEnabled
        successSoundName = try c.decodeIfPresent(String.self, forKey: .successSoundName) ?? defaults.successSoundName
        errorSoundName = try c.decodeIfPresent(String.self, forKey: .errorSoundName) ?? defaults.errorSoundName
        soundVolume = try c.decodeIfPresent(Float.self, forKey: .soundVolume) ?? defaults.soundVolume
        autoSwitchMode = try c.decodeIfPresent(AutoSwitchMode.self, forKey: .autoSwitchMode) ?? defaults.autoSwitchMode
        minWordLength = try c.decodeIfPresent(Int.self, forKey: .minWordLength) ?? defaults.minWordLength
        wrongLayoutSoundName = try c.decodeIfPresent(String.self, forKey: .wrongLayoutSoundName) ?? defaults.wrongLayoutSoundName
        excludedAppBundleIDs = try c.decodeIfPresent([String].self, forKey: .excludedAppBundleIDs) ?? defaults.excludedAppBundleIDs
        layout1ID = try c.decodeIfPresent(String.self, forKey: .layout1ID) ?? defaults.layout1ID
        layout2ID = try c.decodeIfPresent(String.self, forKey: .layout2ID) ?? defaults.layout2ID
        detectionEngine = try c.decodeIfPresent(DetectionEngine.self, forKey: .detectionEngine) ?? defaults.detectionEngine
        useAccessibilityReplacement = try c.decodeIfPresent(Bool.self, forKey: .useAccessibilityReplacement) ?? defaults.useAccessibilityReplacement
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let hotKeyConfigurationChanged = Notification.Name("hotKeyConfigurationChanged")
    static let accessibilityStatusChanged = Notification.Name("accessibilityStatusChanged")
}

// MARK: - App Version
extension Bundle {
    /// Версия приложения вида "3.0 (1)" из Info.plist (единый источник версии).
    var appVersionString: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}

// MARK: - Self-Event Marker
/// Метка, которой помечаются CGEvent'ы, сгенерированные самим приложением
/// (Cmd+C, Cmd+V, Shift+←). Event tap игнорирует события с этой меткой, чтобы
/// не учитывать их в счётчиках набора и не зацикливать обработку.
enum SelfEventMarker {
    static let value: Int64 = 0x4C53_5357  // "LSSW"
}

// MARK: - Key Codes Constants
/// Константы для виртуальных кодов клавиш (избегаем magic numbers)
enum KeyCode {
    static let c: UInt16 = 0x08        // Клавиша C (для Cmd+C)
    static let v: UInt16 = 0x09        // Клавиша V (для Cmd+V)
    static let l: UInt16 = 0x25        // Клавиша L (дефолтная горячая клавиша)
    static let leftShift: UInt16 = 0x38   // Левый Shift
    static let rightShift: UInt16 = 0x3C  // Правый Shift
    static let leftAlt: UInt16 = 0x3A     // Левый Alt (Option)
    static let rightAlt: UInt16 = 0x3D    // Правый Alt (Option)
    static let space: UInt16 = 0x31    // Пробел
    static let `return`: UInt16 = 0x24 // Enter/Return
    static let tab: UInt16 = 0x30      // Tab
    static let delete: UInt16 = 0x33   // Backspace
    static let forwardDelete: UInt16 = 0x75
    static let escape: UInt16 = 0x35
    static let home: UInt16 = 0x73
    static let end: UInt16 = 0x77
    static let pageUp: UInt16 = 0x74
    static let pageDown: UInt16 = 0x79
    static let leftArrow: UInt16 = 0x7B   // ←
    static let rightArrow: UInt16 = 0x7C  // →
    static let downArrow: UInt16 = 0x7D   // ↓
    static let upArrow: UInt16 = 0x7E     // ↑
    
    /// Клавиши, после которых позиция курсора неизвестна.
    static let navigation: Set<UInt16> = [
        leftArrow, rightArrow, downArrow, upArrow, forwardDelete, escape, home, end, pageUp, pageDown
    ]
}

// MARK: - Timing Constants
/// Константы для задержек (в наносекундах)
enum Timing {
    static let pasteDelay: UInt64 = 50_000_000       // 50ms - задержка перед вставкой
    static let restoreDelay: UInt64 = 100_000_000    // 100ms - задержка перед восстановлением буфера
    static let keyPressDelay: UInt64 = 10_000_000    // 10ms - задержка между keyDown и keyUp
    static let doubleShiftDelay: UInt64 = 100_000_000 // 100ms - задержка после двойного Shift
    static let clipboardPollInterval: UInt64 = 10_000_000  // 10ms - шаг опроса буфера обмена
    static let clipboardPollTimeout: UInt64 = 400_000_000  // 400ms - макс. ожидание копирования
    static let selectionKeyDelay: UInt64 = 3_000_000       // 3ms - шаг между нажатиями Shift+← при выделении
}
