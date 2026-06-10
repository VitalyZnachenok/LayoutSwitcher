import SwiftUI
import Combine
import os.log
import Carbon.HIToolbox
import ServiceManagement
import UniformTypeIdentifiers

// MARK: - Localization

/// Поддерживаемые языки интерфейса.
/// Чтобы добавить новый язык: добавьте кейс сюда, его код в `LocalizationManager.supportedCodes`
/// и колонку (значение для нового кода) в таблице переводов `LocalizationManager.translations`.
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case ru
    case en

    var id: String { rawValue }

    /// Человекочитаемое имя для пикера языка.
    var displayName: String {
        switch self {
        case .system: return LocalizationManager.shared.string(.langSystem)
        case .ru: return "Русский"
        case .en: return "English"
        }
    }
}

/// Типобезопасные ключи локализуемых строк.
enum LK: String {
    // Ошибки конвертации
    case errNoText, errConversionFailed, errAccessibility, errClipboard
    // Статистика
    case statsHeader, statsTotal, statsSuccess, statsFailed, statsRate, statsAvgTime, statsMsSuffix
    // HotKeyMode.displayName
    case hkCustom, hkDoubleShift, hkCtrlShift, hkFnShift, hkSingleAlt, hkDoubleAlt
    // AutoSwitchMode.displayName
    case asOff, asWarnSound, asAutoSwitch
    // DetectionEngine.displayName
    case deDictionary, deNgram
    // Валидация
    case valMinIntervalGt0, valMaxGtMin, valMaxTooBig, valKeyEmpty, valNeedModifier, valMinWordLength
    // Меню статус-бара
    case menuPermsGranted, menuPermsRequired, menuSwitchLayout, menuPlaySounds, menuLaunchAtLogin
    case menuAutoSwitch, menuSettings, menuStatistics, menuAbout, menuGrantPerms, menuQuit
    // Кнопки
    case btnOk, btnReset, btnOpenSettings, btnLater, btnDone
    // Алерты
    case statsAlertTitle, statsResetTitle, statsResetMsg
    case aboutDesc, aboutDesc2, aboutVersionLabel
    case accessAlertTitle, accessAlertMsg
    // Окно настроек
    case settingsWindowTitle, headerSubtitle
    // Секция горячей клавиши
    case secHotkey, lblActivationMode, modeLabel
    case dsHint, lblMinInterval, lblMaxInterval
    case ctrlShiftDesc, fnShiftDesc, fnShiftNote
    case singleAltDesc, singleAltNote, doubleAltHint
    case fmtMs, lblCurrentCombo, lblDefaultCombo
    // Секция автопереключения
    case secAutoSwitch, autoSwitchDesc, lblDetectionEngine, engineNgramDesc, engineDictDesc
    case lblMinWordLength, lblWarnSound, helpPlaySound
    // Секция пары раскладок
    case secLayoutPair, layoutPairDesc, lblLayout1, lblLayout2, layoutAuto
    case lblExcludedApps, helpAddApp, excludedEmpty, helpRemoveFromList, openPanelTitle
    // Секция звука
    case secSound, lblVolume, lblVolumePlain, lblSuccessSound, lblErrorSound
    // Прочее
    case secConfigErrors, statusValid, statusInvalid
    case secLanguage, langSystem
    case cmdAbout, cmdQuit
}

/// Менеджер локализации интерфейса: хранит выбранный язык, разрешает эффективный
/// языковой код и выдаёт переводы. Реактивный (`ObservableObject`) — SwiftUI-вьюхи,
/// подписанные на него, перестраиваются при смене языка без перезапуска приложения.
final class LocalizationManager: ObservableObject {
    static let shared = LocalizationManager()

    /// Языковые коды, для которых есть переводы (порядок не важен).
    static let supportedCodes = ["ru", "en"]

    private static let storageKey = "app_language"

    @Published var language: AppLanguage {
        didSet {
            guard oldValue != language else { return }
            UserDefaults.standard.set(language.rawValue, forKey: Self.storageKey)
        }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey)
        language = raw.flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// Эффективный код языка ("ru"/"en"): для `.system` берётся язык системы
    /// (если поддерживается), иначе английский.
    var effectiveLanguageCode: String {
        switch language {
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            let code = String(preferred.prefix(2)).lowercased()
            return Self.supportedCodes.contains(code) ? code : "en"
        case .ru:
            return "ru"
        case .en:
            return "en"
        }
    }

    /// Перевод для текущего эффективного языка с фолбэком: язык → английский → имя ключа.
    func string(_ key: LK) -> String {
        let code = effectiveLanguageCode
        let entry = Self.translations[key]
        return entry?[code] ?? entry?["en"] ?? key.rawValue
    }

    /// Таблица переводов: ключ строки → значения по языковым кодам.
    /// Добавление языка = добавление значения по новому коду в каждую запись.
    private static let translations: [LK: [String: String]] = [
        // Ошибки конвертации
        .errNoText: ["ru": "Пожалуйста, выделите текст перед переключением",
                     "en": "Please select some text before switching"],
        .errConversionFailed: ["ru": "Не удалось конвертировать текст: %@",
                               "en": "Failed to convert text: %@"],
        .errAccessibility: ["ru": "Требуются разрешения доступности",
                            "en": "Accessibility permissions are required"],
        .errClipboard: ["ru": "Ошибка при работе с буфером обмена",
                        "en": "Clipboard operation failed"],

        // Статистика
        .statsHeader: ["ru": "📊 Статистика конвертаций:", "en": "📊 Conversion statistics:"],
        .statsTotal: ["ru": "Всего", "en": "Total"],
        .statsSuccess: ["ru": "Успешно", "en": "Successful"],
        .statsFailed: ["ru": "Неудачно", "en": "Failed"],
        .statsRate: ["ru": "Успешность", "en": "Success rate"],
        .statsAvgTime: ["ru": "Среднее время", "en": "Average time"],
        .statsMsSuffix: ["ru": "мс", "en": "ms"],

        // HotKeyMode.displayName
        .hkCustom: ["ru": "Пользовательская комбинация", "en": "Custom shortcut"],
        .hkDoubleShift: ["ru": "Двойное нажатие Shift", "en": "Double Shift"],
        .hkCtrlShift: ["ru": "Ctrl + Shift", "en": "Ctrl + Shift"],
        .hkFnShift: ["ru": "Fn + Shift", "en": "Fn + Shift"],
        .hkSingleAlt: ["ru": "Нажатие Alt (⌥)", "en": "Alt (⌥) tap"],
        .hkDoubleAlt: ["ru": "Двойное нажатие Alt (⌥⌥)", "en": "Double Alt (⌥⌥)"],

        // AutoSwitchMode.displayName
        .asOff: ["ru": "Выключено", "en": "Off"],
        .asWarnSound: ["ru": "Только звук", "en": "Sound only"],
        .asAutoSwitch: ["ru": "Авто (бета)", "en": "Auto (beta)"],

        // DetectionEngine.displayName
        .deDictionary: ["ru": "Словарь", "en": "Dictionary"],
        .deNgram: ["ru": "N-граммы", "en": "N-grams"],

        // Валидация
        .valMinIntervalGt0: ["ru": "Минимальный интервал должен быть больше 0",
                             "en": "Minimum interval must be greater than 0"],
        .valMaxGtMin: ["ru": "Максимальный интервал должен быть больше минимального",
                       "en": "Maximum interval must be greater than the minimum"],
        .valMaxTooBig: ["ru": "Максимальный интервал слишком большой (>5 сек)",
                        "en": "Maximum interval is too large (>5 sec)"],
        .valKeyEmpty: ["ru": "Символ клавиши не может быть пустым",
                       "en": "Key character cannot be empty"],
        .valNeedModifier: ["ru": "Необходимо выбрать хотя бы один модификатор",
                           "en": "At least one modifier must be selected"],
        .valMinWordLength: ["ru": "Минимальная длина слова должна быть не меньше 2",
                            "en": "Minimum word length must be at least 2"],

        // Меню статус-бара
        .menuPermsGranted: ["ru": "✅ Разрешения предоставлены", "en": "✅ Permissions granted"],
        .menuPermsRequired: ["ru": "⚠️ Требуются разрешения", "en": "⚠️ Permissions required"],
        .menuSwitchLayout: ["ru": "Переключить раскладку (%@)", "en": "Switch layout (%@)"],
        .menuPlaySounds: ["ru": "Проигрывать звуки", "en": "Play sounds"],
        .menuLaunchAtLogin: ["ru": "Запускать при старте системы", "en": "Launch at login"],
        .menuAutoSwitch: ["ru": "Автопереключение раскладки", "en": "Auto layout switching"],
        .menuSettings: ["ru": "Настройки...", "en": "Settings..."],
        .menuStatistics: ["ru": "Статистика...", "en": "Statistics..."],
        .menuAbout: ["ru": "О программе...", "en": "About..."],
        .menuGrantPerms: ["ru": "Предоставить разрешения...", "en": "Grant permissions..."],
        .menuQuit: ["ru": "Выйти", "en": "Quit"],

        // Кнопки
        .btnOk: ["ru": "OK", "en": "OK"],
        .btnReset: ["ru": "Сбросить", "en": "Reset"],
        .btnOpenSettings: ["ru": "Открыть настройки", "en": "Open Settings"],
        .btnLater: ["ru": "Позже", "en": "Later"],
        .btnDone: ["ru": "Готово", "en": "Done"],

        // Алерты
        .statsAlertTitle: ["ru": "Статистика работы", "en": "Usage statistics"],
        .statsResetTitle: ["ru": "Статистика сброшена", "en": "Statistics reset"],
        .statsResetMsg: ["ru": "Счетчики обнулены", "en": "Counters have been reset"],
        .aboutDesc: ["ru": "Утилита для переключения раскладки клавиатуры",
                     "en": "Keyboard layout switcher utility"],
        .aboutDesc2: ["ru": "Переключение раскладки клавиатуры",
                      "en": "Keyboard layout switching"],
        .aboutVersionLabel: ["ru": "Версия", "en": "Version"],
        .accessAlertTitle: ["ru": "Требуются разрешения доступности",
                            "en": "Accessibility permissions are required"],
        .accessAlertMsg: ["ru": """
        Layout Switcher требует разрешения доступности.

        Откройте: Системные настройки → Конфиденциальность и безопасность → Универсальный доступ
        """,
                          "en": """
        Layout Switcher requires Accessibility permissions.

        Open: System Settings → Privacy & Security → Accessibility
        """],

        // Окно настроек
        .settingsWindowTitle: ["ru": "Настройки Layout Switcher", "en": "Layout Switcher Settings"],
        .headerSubtitle: ["ru": "Настройка горячих клавиш для переключения раскладки",
                          "en": "Configure hotkeys for switching the layout"],

        // Секция горячей клавиши
        .secHotkey: ["ru": "Горячая клавиша", "en": "Hotkey"],
        .lblActivationMode: ["ru": "Режим активации:", "en": "Activation mode:"],
        .modeLabel: ["ru": "Режим", "en": "Mode"],
        .dsHint: ["ru": "Настройте интервал между нажатиями Shift",
                  "en": "Adjust the interval between Shift presses"],
        .lblMinInterval: ["ru": "Мин. интервал:", "en": "Min. interval:"],
        .lblMaxInterval: ["ru": "Макс. интервал:", "en": "Max. interval:"],
        .ctrlShiftDesc: ["ru": "Нажмите обе клавиши одновременно для переключения раскладки",
                         "en": "Press both keys at once to switch the layout"],
        .fnShiftDesc: ["ru": "Нажмите Fn и Shift одновременно для переключения раскладки",
                       "en": "Press Fn and Shift at once to switch the layout"],
        .fnShiftNote: ["ru": "⚠️ Примечание: Fn клавиша может работать по-разному на разных клавиатурах",
                       "en": "⚠️ Note: the Fn key may behave differently on different keyboards"],
        .singleAltDesc: ["ru": "Коротко нажмите и отпустите Alt (Option) для переключения раскладки",
                         "en": "Briefly press and release Alt (Option) to switch the layout"],
        .singleAltNote: ["ru": "⚠️ Срабатывает только при одиночном коротком нажатии. Alt в сочетании с другими клавишами (например ⌥+буква) не считается.",
                         "en": "⚠️ Triggers only on a single short tap. Alt combined with other keys (e.g. ⌥+letter) doesn't count."],
        .doubleAltHint: ["ru": "Дважды нажмите Alt (⌥). Настройте интервал между нажатиями",
                         "en": "Press Alt (⌥) twice. Adjust the interval between presses"],
        .fmtMs: ["ru": "%.0f мс", "en": "%.0f ms"],
        .lblCurrentCombo: ["ru": "Текущая комбинация:", "en": "Current shortcut:"],
        .lblDefaultCombo: ["ru": "По умолчанию: ⌘⇧L", "en": "Default: ⌘⇧L"],

        // Секция автопереключения
        .secAutoSwitch: ["ru": "Автопереключение раскладки", "en": "Auto layout switching"],
        .autoSwitchDesc: ["ru": "Определяет ввод в неправильной раскладке: предупреждает звуком или авто-исправляет (бета)",
                          "en": "Detects typing in the wrong layout: warns with a sound or auto-corrects (beta)"],
        .lblDetectionEngine: ["ru": "Движок детекции:", "en": "Detection engine:"],
        .engineNgramDesc: ["ru": "Статистика n-грамм: ловит и несловарные слова (имена, сленг)",
                           "en": "N-gram statistics: also catches non-dictionary words (names, slang)"],
        .engineDictDesc: ["ru": "Системный словарь: точен для словарных слов",
                          "en": "System dictionary: accurate for dictionary words"],
        .lblMinWordLength: ["ru": "Мин. длина слова:", "en": "Min. word length:"],
        .lblWarnSound: ["ru": "Звук предупреждения:", "en": "Warning sound:"],
        .helpPlaySound: ["ru": "Прослушать звук", "en": "Play sound"],

        // Секция пары раскладок
        .secLayoutPair: ["ru": "Пара раскладок", "en": "Layout pair"],
        .layoutPairDesc: ["ru": "Раскладки для конвертации и переключения. «Авто» определяет английскую и кириллическую раскладки автоматически.",
                          "en": "Layouts for conversion and switching. \u{201C}Auto\u{201D} detects the Latin and Cyrillic layouts automatically."],
        .lblLayout1: ["ru": "Раскладка 1:", "en": "Layout 1:"],
        .lblLayout2: ["ru": "Раскладка 2:", "en": "Layout 2:"],
        .layoutAuto: ["ru": "Авто", "en": "Auto"],
        .lblExcludedApps: ["ru": "Исключённые приложения:", "en": "Excluded apps:"],
        .helpAddApp: ["ru": "Добавить приложение", "en": "Add app"],
        .excludedEmpty: ["ru": "Список пуст — детекция работает во всех приложениях",
                         "en": "The list is empty — detection works in all apps"],
        .helpRemoveFromList: ["ru": "Удалить из списка", "en": "Remove from list"],
        .openPanelTitle: ["ru": "Выберите приложение для исключения",
                          "en": "Choose an app to exclude"],

        // Секция звука
        .secSound: ["ru": "Звуковые уведомления", "en": "Sound notifications"],
        .lblVolume: ["ru": "Громкость:", "en": "Volume:"],
        .lblVolumePlain: ["ru": "Громкость", "en": "Volume"],
        .lblSuccessSound: ["ru": "Звук успеха:", "en": "Success sound:"],
        .lblErrorSound: ["ru": "Звук ошибки:", "en": "Error sound:"],

        // Прочее
        .secConfigErrors: ["ru": "Ошибки конфигурации", "en": "Configuration errors"],
        .statusValid: ["ru": "Настройки корректны", "en": "Settings are valid"],
        .statusInvalid: ["ru": "Есть ошибки", "en": "There are errors"],
        .secLanguage: ["ru": "Язык", "en": "Language"],
        .langSystem: ["ru": "Система", "en": "System"],
        .cmdAbout: ["ru": "О программе Layout Switcher", "en": "About Layout Switcher"],
        .cmdQuit: ["ru": "Выйти из Layout Switcher", "en": "Quit Layout Switcher"],
    ]
}

/// Короткий помощник доступа к переводам: `L(.someKey)`.
func L(_ key: LK) -> String { LocalizationManager.shared.string(key) }

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
            return L(.errNoText)
        case .conversionFailed(let reason):
            return String(format: L(.errConversionFailed), reason)
        case .accessibilityPermissionDenied:
            return L(.errAccessibility)
        case .clipboardOperationFailed:
            return L(.errClipboard)
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
        \(L(.statsHeader))
        • \(L(.statsTotal)): \(totalConversions)
        • \(L(.statsSuccess)): \(successfulConversions)
        • \(L(.statsFailed)): \(failedConversions)
        • \(L(.statsRate)): \(String(format: "%.1f%%", successRate * 100))
        • \(L(.statsAvgTime)): \(String(format: "%.0f", averageConversionTime * 1000))\(L(.statsMsSuffix))
        """
    }
}

// MARK: - Models
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
}

/// Реакция на ввод в неправильной раскладке (автодетекция).
enum AutoSwitchMode: String, Codable, Equatable, Sendable, CaseIterable {
    case off         // Выключено
    case warnSound   // Только звук-предупреждение
    case autoSwitch  // Авто-исправление (бета): меняет слово и переключает раскладку
    
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
    case ngram         // Статистическая модель n-грамм (работает и для несловарных слов)
    
    var displayName: String {
        switch self {
        case .spellChecker: return L(.deDictionary)
        case .ngram: return L(.deNgram)
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
    
    // Автодетекция неправильной раскладки (Фаза 1: предупреждение)
    var autoSwitchMode: AutoSwitchMode = .off
    var minWordLength: Int = 3
    var wrongLayoutSoundName: String = "Submarine"
    var excludedAppBundleIDs: [String] = []
    var detectionEngine: DetectionEngine = .ngram
    
    // Пара раскладок для конвертации/переключения по точному ID.
    // Пустая строка означает автоопределение (английская ↔ кириллическая).
    var layout1ID: String = ""
    var layout2ID: String = ""
    
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
    
    /// Локализованные имена звуков по языковым кодам. Для английского используются
    /// системные (английские) названия звуков macOS.
    static let soundDisplayNames: [String: [String: String]] = [
        "Basso": ["ru": "Бассо", "en": "Basso"],
        "Blow": ["ru": "Дуновение", "en": "Blow"],
        "Bottle": ["ru": "Бутылка", "en": "Bottle"],
        "Frog": ["ru": "Лягушка", "en": "Frog"],
        "Funk": ["ru": "Фанк", "en": "Funk"],
        "Glass": ["ru": "Стекло", "en": "Glass"],
        "Hero": ["ru": "Герой", "en": "Hero"],
        "Morse": ["ru": "Морзе", "en": "Morse"],
        "Ping": ["ru": "Пинг", "en": "Ping"],
        "Pop": ["ru": "Поп", "en": "Pop"],
        "Purr": ["ru": "Мурлыканье", "en": "Purr"],
        "Sosumi": ["ru": "Сосуми", "en": "Sosumi"],
        "Submarine": ["ru": "Подлодка", "en": "Submarine"],
        "Tink": ["ru": "Тинк", "en": "Tink"]
    ]
    
    static func localizedName(for soundName: String) -> String {
        let code = LocalizationManager.shared.effectiveLanguageCode
        return soundDisplayNames[soundName]?[code] ?? soundName
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
        case .doubleShift, .doubleAlt:
            if configuration.minDoubleShiftInterval <= 0 {
                errors.append(L(.valMinIntervalGt0))
            }
            if configuration.maxDoubleShiftInterval <= configuration.minDoubleShiftInterval {
                errors.append(L(.valMaxGtMin))
            }
            if configuration.maxDoubleShiftInterval > 5.0 {
                errors.append(L(.valMaxTooBig))
            }
        case .ctrlShift, .fnShift, .singleAlt:
            break // Нет дополнительных проверок
        case .customHotkey:
            if configuration.keyCharacter.isEmpty {
                errors.append(L(.valKeyEmpty))
            }
            if configuration.modifierFlags == 0 {
                errors.append(L(.valNeedModifier))
            }
        }
        
        if configuration.autoSwitchMode != .off && configuration.minWordLength < 2 {
            errors.append(L(.valMinWordLength))
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

// MARK: - Self-Event Marker
/// Метка, которой помечаются CGEvent'ы, сгенерированные самим приложением
/// (Cmd+C, Cmd+V, Shift+←). Event tap игнорирует события с этой меткой, чтобы
/// не учитывать их в счётчиках набора и не зацикливать обработку.
private let kLayoutSwitcherEventMarker: Int64 = 0x4C53_5357  // "LSSW"

// MARK: - Key Codes Constants
/// Константы для виртуальных кодов клавиш (избегаем magic numbers)
private enum KeyCode {
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
    static let leftArrow: UInt16 = 0x7B   // ←
    static let rightArrow: UInt16 = 0x7C  // →
    static let downArrow: UInt16 = 0x7D   // ↓
    static let upArrow: UInt16 = 0x7E     // ↑
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
    static let selectionKeyDelay: UInt64 = 3_000_000       // 3ms - шаг между нажатиями Shift+← при выделении
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
    
    /// Конвертация с явно заданным направлением (без автодетекции).
    /// Используется автопереключателем, который уже знает текущую раскладку.
    func convert(_ text: String, currentLayoutIsRussian: Bool) -> String {
        let mapping = currentLayoutIsRussian ? rusToEng : engToRus
        return String(text.compactMap { mapping[$0] ?? $0 })
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

// MARK: - Layout Manager
/// Низкоуровневая работа с раскладками через TIS: получение текущей, списка
/// установленных, переключение по точному ID и переключение на «противоположную»
/// в паре. Пустой ID в паре означает автоопределение (английская/кириллическая).
enum LayoutManager {
    /// ID-фрагменты служебных источников, которые не являются настоящими раскладками.
    private static let serviceMarkers = [".SCIM", "Emoji", "Dictation", "CharacterPalette", "PressAndHold"]
    
    /// ID текущей активной раскладки.
    static func currentLayoutID() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return "" }
        return sourceID(source)
    }
    
    /// Список установленных раскладок (только выбираемые клавиатурные источники).
    static func installedLayouts() -> [TISInputSource] {
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return sources.filter { source in
            let id = sourceID(source)
            guard !id.isEmpty else { return false }
            return !serviceMarkers.contains { id.contains($0) }
        }
    }
    
    /// Точный ID источника (kTISPropertyInputSourceID).
    static func sourceID(_ source: TISInputSource) -> String {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
    
    /// Человекочитаемое имя раскладки (kTISPropertyLocalizedName).
    static func sourceName(_ source: TISInputSource) -> String {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return sourceID(source) }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
    
    /// Активирует раскладку по точному ID. Возвращает true при успехе.
    @discardableResult
    static func switchTo(layoutID: String) -> Bool {
        guard !layoutID.isEmpty,
              let source = installedLayouts().first(where: { sourceID($0) == layoutID }) else {
            return false
        }
        let status = TISSelectInputSource(source)
        if status == noErr {
            Logger.conversion.info("✅ Switched layout to \(layoutID)")
            return true
        }
        Logger.conversion.error("❌ TISSelectInputSource failed (\(status)) for \(layoutID)")
        return false
    }
    
    /// Переключает на «противоположную» раскладку из пары. Пустые ID в паре
    /// автоматически заменяются на определённые из системы.
    @discardableResult
    static func switchToOpposite(layout1ID: String, layout2ID: String) -> Bool {
        let (id1, id2) = resolvePair(layout1ID: layout1ID, layout2ID: layout2ID)
        guard !id1.isEmpty, !id2.isEmpty else {
            Logger.conversion.error("❌ Could not resolve layout pair")
            return false
        }
        let current = currentLayoutID()
        let target = (current == id1) ? id2 : id1
        return switchTo(layoutID: target)
    }
    
    /// Возвращает конкретную пару ID, заменяя пустые значения автоопределением.
    static func resolvePair(layout1ID: String, layout2ID: String) -> (String, String) {
        let layouts = installedLayouts()
        let id1 = layout1ID.isEmpty ? autoDetectLatin(layouts) : layout1ID
        let id2 = layout2ID.isEmpty ? autoDetectCyrillic(layouts) : layout2ID
        return (id1, id2)
    }
    
    /// Автоопределение латинской (английской) раскладки.
    private static func autoDetectLatin(_ layouts: [TISInputSource]) -> String {
        let ids = layouts.map { sourceID($0) }
        let preferred = ["com.apple.keylayout.US", "com.apple.keylayout.ABC", "com.apple.keylayout.USExtended"]
        if let exact = preferred.first(where: { ids.contains($0) }) { return exact }
        return ids.first {
            let l = $0.lowercased()
            return !(l.contains("russian") || l.contains("cyrillic"))
        } ?? ""
    }
    
    /// Автоопределение кириллической (русской) раскладки.
    private static func autoDetectCyrillic(_ layouts: [TISInputSource]) -> String {
        layouts.map { sourceID($0) }.first {
            let l = $0.lowercased()
            return l.contains("russian") || l.contains("cyrillic")
        } ?? ""
    }
}

// MARK: - Dynamic Key Mapping
/// Динамический маппинг символов между двумя раскладками через UCKeyTranslate.
/// В отличие от жёстко зашитой таблицы, строит соответствие из реальных раскладок
/// системы по их 'uchr'-данным, поэтому работает для произвольных пар (не только RU/EN).
enum DynamicKeyMapping {
    /// Кэш построенных карт: ключ "fromID→toID".
    nonisolated(unsafe) private static var cache: [String: [Character: Character]] = [:]
    
    /// Виртуальные коды печатных клавиш основного блока (буквы/цифры/пунктуация).
    private static let printableKeycodes: [UInt16] = Array(0...50)
    
    /// Результат конвертации: преобразованный текст и ID раскладки, в которую он
    /// относится (для переключения клавиатуры на правильную раскладку).
    struct Result {
        let text: String
        let targetLayoutID: String
    }
    
    /// Конвертирует текст между раскладками пары. Направление определяется по
    /// СОДЕРЖИМОМУ текста (пробуются обе стороны), а не по текущей раскладке —
    /// поэтому работает, даже если клавиатура уже переключена на другую раскладку.
    /// Возвращает nil, если ни одно направление не меняет текст (вызывающий — фолбэк).
    static func convert(_ text: String, layout1ID: String, layout2ID: String) -> Result? {
        let (id1, id2) = LayoutManager.resolvePair(layout1ID: layout1ID, layout2ID: layout2ID)
        guard !id1.isEmpty, !id2.isEmpty else { return nil }
        
        let layouts = LayoutManager.installedLayouts()
        guard let source1 = layouts.first(where: { LayoutManager.sourceID($0) == id1 }),
              let source2 = layouts.first(where: { LayoutManager.sourceID($0) == id2 }) else {
            return nil
        }
        
        let map12 = buildMap(from: source1, fromID: id1, to: source2, toID: id2)
        let map21 = buildMap(from: source2, fromID: id2, to: source1, toID: id1)
        
        // Определяем направление по тому, какая карта реально меняет текст.
        let converted12 = String(text.map { map12[$0] ?? $0 })
        if converted12 != text {
            return Result(text: converted12, targetLayoutID: id2)
        }
        let converted21 = String(text.map { map21[$0] ?? $0 })
        if converted21 != text {
            return Result(text: converted21, targetLayoutID: id1)
        }
        return nil
    }
    
    /// Строит (с кэшированием) карту символ→символ между двумя раскладками.
    private static func buildMap(from: TISInputSource, fromID: String,
                                 to: TISInputSource, toID: String) -> [Character: Character] {
        let cacheKey = "\(fromID)→\(toID)"
        if let cached = cache[cacheKey] { return cached }
        
        var map: [Character: Character] = [:]
        let modifiers: [UInt32] = [0, UInt32(shiftKey >> 8) & 0xFF]  // без Shift и с Shift
        for keycode in printableKeycodes {
            for mod in modifiers {
                guard let fromChar = translate(keycode: keycode, modifiers: mod, source: from),
                      let toChar = translate(keycode: keycode, modifiers: mod, source: to),
                      fromChar != toChar else { continue }
                map[fromChar] = toChar
            }
        }
        cache[cacheKey] = map
        return map
    }
    
    /// Переводит виртуальный keycode в символ для конкретной раскладки через UCKeyTranslate.
    private static func translate(keycode: UInt16, modifiers: UInt32, source: TISInputSource) -> Character? {
        guard let layoutDataPtr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(layoutDataPtr).takeUnretainedValue() as Data
        
        return layoutData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Character? in
            guard let base = raw.baseAddress else { return nil }
            let keyLayout = base.assumingMemoryBound(to: UCKeyboardLayout.self)
            
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                keyLayout,
                keycode,
                UInt16(kUCKeyActionDown),
                modifiers,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysMask),
                &deadKeyState,
                chars.count,
                &length,
                &chars
            )
            guard status == noErr, length > 0,
                  let ch = String(utf16CodeUnits: chars, count: length).first,
                  !ch.isWhitespace else {
                return nil
            }
            return ch
        }
    }
}

// MARK: - Wrong Layout Detector
/// Детектор ввода в неправильной раскладке на базе системного NSSpellChecker.
/// Слово считается набранным не в той раскладке, если оно некорректно в текущем
/// языке, а его конвертация — корректное слово в другом языке.
@MainActor
final class WrongLayoutDetector {
    private let checker = NSSpellChecker.shared
    private let converter: LayoutConverter
    
    // Разрешаем коды языков к доступным в системе словарям (например, "ru" -> "ru_RU").
    private lazy var resolvedRussian: String = resolveLanguage(prefix: "ru")
    private lazy var resolvedEnglish: String = resolveLanguage(prefix: "en")
    
    init(converter: LayoutConverter) {
        self.converter = converter
    }
    
    /// Прогрев словарей в фоне, чтобы первая проверка не тормозила ввод.
    func warmUp() {
        _ = resolvedRussian
        _ = resolvedEnglish
        _ = isMisspelled("warmup", language: resolvedEnglish)
    }
    
    /// Возвращает конвертированный текст, если слово похоже на набранное
    /// в неправильной раскладке, иначе nil.
    func detect(word: String, currentLayoutIsRussian: Bool, minLength: Int) -> String? {
        guard word.count >= minLength else { return nil }
        guard word.allSatisfy({ $0.isLetter }) else { return nil }
        
        let currentLang = currentLayoutIsRussian ? resolvedRussian : resolvedEnglish
        let otherLang = currentLayoutIsRussian ? resolvedEnglish : resolvedRussian
        
        // Если слово корректно в текущем языке — раскладка верная, ничего не делаем.
        guard isMisspelled(word, language: currentLang) else { return nil }
        
        let converted = converter.convert(word, currentLayoutIsRussian: currentLayoutIsRussian)
        guard converted != word else { return nil }
        
        // Конвертация должна быть корректным словом в другом языке.
        guard !isMisspelled(converted, language: otherLang) else { return nil }
        
        return converted
    }
    
    private func isMisspelled(_ word: String, language: String) -> Bool {
        let range = checker.checkSpelling(
            of: word,
            startingAt: 0,
            language: language,
            wrap: false,
            inSpellDocumentWithTag: 0,
            wordCount: nil
        )
        return range.location != NSNotFound
    }
    
    private func resolveLanguage(prefix: String) -> String {
        let available = checker.availableLanguages
        if let exact = available.first(where: { $0 == prefix }) { return exact }
        if let prefixed = available.first(where: { $0.lowercased().hasPrefix(prefix.lowercased()) }) { return prefixed }
        return prefix
    }
}

// MARK: - N-Gram Language Model
/// Символьная биграм-модель Маркова: оценивает «правдоподобие» слова как
/// нормального текста на данном языке. Обучается на встроенном списке частых слов
/// (компактные самодостаточные данные). Используется для детекции неправильной
/// раскладки сравнением: «слово как есть» против «слово, сконвертированное в др. язык».
final class NGramLanguageModel {
    private var bigramCount: [String: Int] = [:]
    private var contextCount: [Character: Int] = [:]
    private var vocabulary: Set<Character> = []
    private let smoothing = 0.5
    /// Маркер границы слова (управляющий символ, не встречается в обычном тексте).
    private static let boundary: Character = "\u{2}"
    
    init(words: [String]) {
        for word in words {
            let chars = [Self.boundary] + Array(word.lowercased()) + [Self.boundary]
            for ch in chars where ch != Self.boundary { vocabulary.insert(ch) }
            for i in 1..<chars.count {
                let prev = chars[i - 1]
                let cur = chars[i]
                bigramCount["\(prev)\(cur)", default: 0] += 1
                contextCount[prev, default: 0] += 1
            }
        }
    }
    
    /// Средний логарифм вероятности перехода на символ (чем выше — тем «нормальнее»
    /// слово для этого языка). Несловарные символы дают равномерно низкую оценку.
    func score(_ word: String) -> Double {
        let chars = [Self.boundary] + Array(word.lowercased()) + [Self.boundary]
        guard chars.count > 1 else { return -20 }
        // +1 — учитываем границу как возможный следующий символ.
        let vocabSize = Double(vocabulary.count + 1)
        var total = 0.0
        var steps = 0
        for i in 1..<chars.count {
            let prev = chars[i - 1]
            let cur = chars[i]
            let bc = Double(bigramCount["\(prev)\(cur)"] ?? 0)
            let cc = Double(contextCount[prev] ?? 0)
            let p = (bc + smoothing) / (cc + smoothing * vocabSize)
            total += log(p)
            steps += 1
        }
        return steps > 0 ? total / Double(steps) : -20
    }
}

// MARK: - N-Gram Layout Detector
/// Детектор неправильной раскладки на статистике n-грамм. Сравнивает правдоподобие
/// слова «как набрано» с правдоподобием его конверсии в другой язык. Работает на
/// несловарных словах (имена, сленг, обрывки), в отличие от детектора по словарю.
@MainActor
final class NGramLayoutDetector {
    private let converter: LayoutConverter
    private lazy var russianModel = NGramLanguageModel(words: NGramCorpus.russian)
    private lazy var englishModel = NGramLanguageModel(words: NGramCorpus.english)
    /// Минимальный перевес правдоподобия (в логах на символ) для срабатывания.
    private let threshold = 0.7
    
    init(converter: LayoutConverter) {
        self.converter = converter
    }
    
    /// Прогрев моделей, чтобы первая проверка не тормозила ввод.
    func warmUp() {
        _ = russianModel.score("прогрев")
        _ = englishModel.score("warmup")
    }
    
    /// Возвращает конвертированный текст, если статистика указывает на неправильную
    /// раскладку, иначе nil.
    func detect(word: String, currentLayoutIsRussian: Bool, minLength: Int) -> String? {
        guard word.count >= minLength else { return nil }
        
        let converted = converter.convert(word, currentLayoutIsRussian: currentLayoutIsRussian)
        guard converted != word else { return nil }
        
        let typedModel = currentLayoutIsRussian ? russianModel : englishModel
        let convertedModel = currentLayoutIsRussian ? englishModel : russianModel
        
        let typedScore = typedModel.score(word)
        let convertedScore = convertedModel.score(converted)
        
        // Конверсия должна быть существенно правдоподобнее набранного варианта.
        guard convertedScore - typedScore > threshold else { return nil }
        return converted
    }
}

// MARK: - N-Gram Training Corpus
/// Встроенные списки частых слов для обучения биграм-моделей (компактные данные,
/// вкомпилированы в бинарь). Покрывают типичные буквенные сочетания каждого языка.
private enum NGramCorpus {
    static let english: [String] = [
        "the", "of", "and", "to", "in", "is", "you", "that", "it", "he", "was", "for", "on",
        "are", "as", "with", "his", "they", "at", "be", "this", "have", "from", "or", "one",
        "had", "by", "word", "but", "not", "what", "all", "were", "we", "when", "your", "can",
        "said", "there", "use", "an", "each", "which", "she", "do", "how", "their", "if",
        "will", "up", "other", "about", "out", "many", "then", "them", "these", "so", "some",
        "her", "would", "make", "like", "him", "into", "time", "has", "look", "two", "more",
        "write", "go", "see", "number", "no", "way", "could", "people", "my", "than", "first",
        "water", "been", "call", "who", "its", "now", "find", "long", "down", "day", "did",
        "get", "come", "made", "may", "part", "over", "new", "sound", "take", "only", "little",
        "work", "know", "place", "year", "live", "me", "back", "give", "most", "very", "after",
        "thing", "our", "just", "name", "good", "sentence", "man", "think", "say", "great",
        "where", "help", "through", "much", "before", "line", "right", "too", "mean", "old",
        "any", "same", "tell", "boy", "follow", "came", "want", "show", "also", "around",
        "form", "three", "small", "set", "put", "end", "does", "another", "well", "large",
        "must", "big", "even", "such", "because", "turn", "here", "why", "ask", "went", "men",
        "read", "need", "land", "different", "home", "us", "move", "try", "kind", "hand",
        "picture", "again", "change", "off", "play", "spell", "air", "away", "animal", "house",
        "point", "page", "letter", "mother", "answer", "found", "study", "still", "learn",
        "should", "world", "high", "every", "near", "add", "food", "between", "own", "below",
        "country", "plant", "last", "school", "father", "keep", "tree", "never", "start",
        "city", "earth", "eye", "light", "thought", "head", "under", "story", "saw", "left",
        "few", "while", "along", "might", "close", "something", "seem", "next", "hard", "open",
        "example", "begin", "life", "always", "those", "both", "paper", "together", "got",
        "group", "often", "run", "important", "until", "children", "side", "feet", "car",
        "mile", "night", "walk", "white", "sea", "began", "grow", "took", "river", "four",
        "carry", "state", "once", "book", "hear", "stop", "without", "second", "later", "miss",
        "idea", "enough", "eat", "face", "watch", "far", "really", "almost", "let", "above",
        "girl", "sometimes", "mountain", "cut", "young", "talk", "soon", "list", "song",
        "being", "leave", "family", "it's"
    ]
    
    static let russian: [String] = [
        "и", "в", "не", "на", "я", "быть", "он", "с", "что", "а", "по", "это", "этот", "к",
        "но", "они", "мы", "как", "из", "у", "который", "то", "за", "свой", "весь", "год",
        "от", "так", "о", "для", "ты", "же", "все", "тот", "мочь", "вы", "человек", "такой",
        "его", "только", "или", "время", "какой", "наш", "очень", "люди", "надо", "без",
        "день", "больше", "есть", "себя", "один", "ещё", "бы", "тоже", "говорить", "знать",
        "мой", "до", "когда", "уже", "если", "дело", "можно", "при", "два", "другой", "после",
        "над", "через", "эти", "нас", "про", "всего", "какая", "много", "разве", "три", "эту",
        "моя", "хорошо", "свою", "этой", "перед", "иногда", "лучше", "чуть", "том", "нельзя",
        "более", "всегда", "конечно", "всю", "между", "чтобы", "жизнь", "будет", "тогда",
        "кто", "потому", "совсем", "здесь", "этом", "почти", "дом", "слово", "место", "рука",
        "глаз", "друг", "работа", "жить", "думать", "сказать", "новый", "первый", "вода",
        "большой", "идти", "стать", "мир", "лицо", "ребёнок", "видеть", "хотеть", "голова",
        "должен", "любить", "начать", "дать", "страна", "вопрос", "ночь", "утро", "город",
        "сила", "конец", "земля", "путь", "машина", "делать", "спросить", "дверь", "сторона",
        "женщина", "понимать", "минута", "голос", "отец", "мать", "сердце", "история", "вечер",
        "деньги", "сегодня", "никто", "имя", "нога", "общество", "хозяин", "вода", "звук",
        "пора", "слышать", "сразу", "стоять", "каждый", "белый", "далеко", "пусть", "девочка",
        "гора", "холодный", "молодой", "поговорить", "скоро", "список", "песня", "семья",
        "оставить", "ответ", "вопрос", "понять", "система", "число", "ребята", "сторона",
        "правда", "сейчас", "очень", "пример", "начало", "вместе", "получить", "важный",
        "комната", "окно", "стол", "ветер", "снег", "свет", "цвет", "книга", "письмо", "число",
        "русский", "язык", "буква", "пример", "ошибка", "клавиша", "текст", "привет", "спасибо",
        "пожалуйста", "сообщение", "программа", "компьютер", "работать", "переключить",
        "раскладка", "набор", "проверка", "хорошо", "плохо", "быстро", "медленно", "снова"
    ]
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
    
    // Детект одиночного тапа Alt: флаг «Alt нажат в одиночку» и момент нажатия.
    // Любое нажатие обычной клавиши во время удержания сбрасывает флаг (это комбинация).
    private nonisolated(unsafe) var altPressedAlone = false
    private nonisolated(unsafe) var altPressTime: TimeInterval = 0
    private let singleAltMaxHold: TimeInterval = 0.4
    
    private let settings: SettingsManager
    private let converter = LayoutConverter()
    private let wrongLayoutDetector: WrongLayoutDetector
    private let ngramDetector: NGramLayoutDetector
    let metrics = ConversionMetrics()
    
    // Автопереключатель: буфер текущего набираемого слова (для детектора по NSSpellChecker).
    // Доступ только из callback (поток run loop), поэтому nonisolated(unsafe).
    private nonisolated(unsafe) var typingBuffer: String = ""
    private let maxTypingBufferLength = 64
    
    // Счётчики набора по keycode (для конвертации последнего слова без выделения).
    // currentWordLength — длина текущего слова; wordBeforeBoundaryLength/boundaryCount —
    // слово перед границей (например, перед пробелом) и число границ после него.
    private nonisolated(unsafe) var currentWordLength: Int = 0
    private nonisolated(unsafe) var wordBeforeBoundaryLength: Int = 0
    private nonisolated(unsafe) var boundaryCount: Int = 0
    
    // Снимок счётчиков на момент ПЕРЕД текущим событием. Нужен потому, что событие
    // горячей клавиши (например, ⌘⇧L) само сбрасывает счётчики в feedTyping до того,
    // как convertLayout успеет их прочитать. convertLayout использует именно снимок.
    private nonisolated(unsafe) var snapWordLength: Int = 0
    private nonisolated(unsafe) var snapBeforeLength: Int = 0
    private nonisolated(unsafe) var snapBoundary: Int = 0
    
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
    private nonisolated(unsafe) var cachedAutoSwitchMode: AutoSwitchMode = .off
    private nonisolated(unsafe) var cachedMinWordLength: Int = 3
    
    init(settings: SettingsManager) {
        self.settings = settings
        self.wrongLayoutDetector = WrongLayoutDetector(converter: converter)
        self.ngramDetector = NGramLayoutDetector(converter: converter)
        lastAccessibilityStatus = AXIsProcessTrusted()
        updateCachedConfiguration()
        setupConfigurationObserver()
        setupAccessibilityMonitoring()
        setupEventTap()
        // Прогреваем детекторы в фоне, чтобы не тормозить первый ввод.
        Task { @MainActor in
            self.wrongLayoutDetector.warmUp()
            self.ngramDetector.warmUp()
        }
    }
    
    /// Обновляет кэшированную конфигурацию (вызывается на main thread)
    private func updateCachedConfiguration() {
        let config = settings.configuration
        cachedHotKeyMode = config.hotKeyMode
        cachedKeyCode = config.keyCode
        cachedModifierFlags = config.modifierFlags
        cachedMinInterval = config.minDoubleShiftInterval
        cachedMaxInterval = config.maxDoubleShiftInterval
        cachedAutoSwitchMode = config.autoSwitchMode
        cachedMinWordLength = config.minWordLength
        resetWordTracking()
        Logger.hotkeys.debug("Configuration cached: mode=\(self.cachedHotKeyMode.rawValue), autoSwitch=\(self.cachedAutoSwitchMode.rawValue)")
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
        
        // Слушаем клики мыши всегда, чтобы сбрасывать счётчики набираемого слова при
        // смене позиции курсора (нужно как автопереключателю, так и конвертации
        // последнего слова по горячей клавише).
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue) |
                        (1 << CGEventType.leftMouseDown.rawValue) |
                        (1 << CGEventType.rightMouseDown.rawValue)
        
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
                
                // Игнорируем события, сгенерированные самим приложением
                // (Cmd+C, Cmd+V, Shift+←): не учитываем в счётчиках и не обрабатываем.
                if event.getIntegerValueField(.eventSourceUserData) == kLayoutSwitcherEventMarker {
                    return Unmanaged.passUnretained(event)
                }
                
                // Снимок счётчиков ДО обработки события (feedTyping сбросит их, если
                // это горячая клавиша с модификаторами).
                manager.snapshotWordTracking()
                
                // Кормим монитор набора (keyDown + клики мыши): счётчики слова и детектор.
                // Никогда не блокирует событие.
                manager.feedTyping(event, type: type)
                
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
        case .doubleAlt:
            return handleDoubleModifierFromCallback(event, type: type, targetFlag: .maskAlternate, keyCodes: [KeyCode.leftAlt, KeyCode.rightAlt])
        case .singleAlt:
            return handleSingleAltFromCallback(event, type: type)
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
        
        // Все модификаторы, КРОМЕ целевого: их наличие означает комбинацию, а не
        // одиночное двойное нажатие целевого модификатора.
        var otherModifiers: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        otherModifiers.remove(targetFlag)
        
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
    
    /// Детект одиночного тапа Alt: срабатывает при отпускании Alt, если он был
    /// нажат в одиночку (без других модификаторов и без нажатия обычных клавиш)
    /// и удержание было коротким. Обрабатывает и keyDown (для отмены тапа), и flagsChanged.
    nonisolated private func handleSingleAltFromCallback(_ event: CGEvent, type: CGEventType) -> Bool {
        // Любая обычная клавиша во время удержания Alt — это комбинация, не тап.
        if type == .keyDown {
            altPressedAlone = false
            return false
        }
        
        guard type == .flagsChanged else { return false }
        
        let flags = event.flags
        let altDown = flags.contains(.maskAlternate)
        let hasOthers = !flags.intersection([.maskCommand, .maskControl, .maskShift]).isEmpty
        
        if altDown {
            // Alt нажат: кандидат на тап только если без других модификаторов.
            altPressedAlone = !hasOthers
            altPressTime = Date.timeIntervalSinceReferenceDate
        } else if altPressedAlone {
            // Alt отпущен — проверяем длительность удержания.
            altPressedAlone = false
            let elapsed = Date.timeIntervalSinceReferenceDate - altPressTime
            if elapsed < singleAltMaxHold {
                let now = Date.timeIntervalSinceReferenceDate
                guard now - lastComboTriggerTime > comboDebounceInterval else { return false }
                lastComboTriggerTime = now
                
                Logger.hotkeys.info("✅ Single Alt tap detected!")
                Task { @MainActor in
                    await self.convertLayout()
                }
            }
        }
        
        return false
    }
    
    // MARK: - Auto Layout Switcher & Word Tracking
    
    /// Полный сброс отслеживания набираемого слова (буфер + все счётчики).
    private nonisolated func resetWordTracking() {
        typingBuffer = ""
        currentWordLength = 0
        wordBeforeBoundaryLength = 0
        boundaryCount = 0
    }
    
    /// Сохраняет текущее состояние счётчиков (вызывается в начале callback'а,
    /// до feedTyping), чтобы convertLayout видел слово до срабатывания горячей клавиши.
    nonisolated func snapshotWordTracking() {
        snapWordLength = currentWordLength
        snapBeforeLength = wordBeforeBoundaryLength
        snapBoundary = boundaryCount
    }
    
    /// Завершает текущее слово на границе (пробел/пунктуация): отдаёт его на анализ
    /// детектору (если включён режим предупреждения) и обнуляет буфер слова.
    private nonisolated func finishWordForDetection() {
        let word = typingBuffer
        typingBuffer = ""
        guard cachedAutoSwitchMode != .off, word.count >= cachedMinWordLength else { return }
        Task { @MainActor in await self.analyzeWord(word) }
    }
    
    /// Монитор набора: ведёт счётчики слова по keycode (для конвертации последнего
    /// слова без выделения) и, при включённом автопереключателе, отдаёт завершённые
    /// слова детектору. Вызывается из event tap callback, ничего не блокирует.
    nonisolated func feedTyping(_ event: CGEvent, type: CGEventType) {
        // Клик мышью — курсор сместился, отслеживание больше не актуально.
        if type == .leftMouseDown || type == .rightMouseDown {
            resetWordTracking()
            return
        }
        
        guard type == .keyDown else { return }
        
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags
        
        // Пробел — мягкая граница: запоминаем длину слова перед ним (для конвертации
        // «слова перед пробелом») и завершаем слово для детектора.
        if keyCode == KeyCode.space {
            if currentWordLength > 0 {
                wordBeforeBoundaryLength = currentWordLength
                boundaryCount = 1
            } else if wordBeforeBoundaryLength > 0 {
                boundaryCount += 1
            }
            currentWordLength = 0
            finishWordForDetection()
            return
        }
        
        // Enter/Tab — завершают слово и сбрасывают отслеживание.
        if keyCode == KeyCode.return || keyCode == KeyCode.tab {
            finishWordForDetection()
            resetWordTracking()
            return
        }
        
        // Backspace — укорачиваем текущее слово; если слова нет, сбрасываем.
        if keyCode == KeyCode.delete {
            if currentWordLength > 0 {
                currentWordLength -= 1
                if !typingBuffer.isEmpty { typingBuffer.removeLast() }
            } else {
                resetWordTracking()
            }
            return
        }
        
        // Навигация/удаление вперёд/Escape — позиция курсора меняется, сброс.
        if keyCode == KeyCode.leftArrow || keyCode == KeyCode.rightArrow ||
           keyCode == KeyCode.downArrow || keyCode == KeyCode.upArrow ||
           keyCode == 0x75 || keyCode == 0x35 ||
           keyCode == 0x73 || keyCode == 0x77 || keyCode == 0x74 || keyCode == 0x79 {
            resetWordTracking()
            return
        }
        
        // Комбинации с Cmd/Ctrl/Opt — это команды, а не набор текста.
        if flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) {
            resetWordTracking()
            return
        }
        
        // Получаем символ, реально набранный в текущей раскладке.
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
        guard length > 0, let ch = String(utf16CodeUnits: chars, count: length).first else { return }
        
        if ch.isLetter || ch == "'" || ch == "-" {
            currentWordLength += 1
            wordBeforeBoundaryLength = 0
            boundaryCount = 0
            typingBuffer.append(ch)
            if typingBuffer.count > maxTypingBufferLength {
                typingBuffer.removeFirst(typingBuffer.count - maxTypingBufferLength)
            }
            return
        }
        
        // Прочий печатный символ (знак препинания и т.п.) — граница слова.
        currentWordLength = 0
        finishWordForDetection()
    }
    
    /// Анализирует завершённое слово на MainActor: проверяет исключения и детектор.
    private func analyzeWord(_ word: String) async {
        // 1. Поле пароля (глобальный secure input) — пропускаем.
        if IsSecureEventInputEnabled() {
            Logger.conversion.debug("Auto-switch skipped: secure input active")
            return
        }
        // 2. Исключённое приложение.
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           settings.configuration.excludedAppBundleIDs.contains(bundleID) {
            Logger.conversion.debug("Auto-switch skipped: excluded app \(bundleID)")
            return
        }
        // 3. Сфокусировано защищённое поле ввода (доп. заслон для паролей).
        if isSecureFieldFocused() {
            Logger.conversion.debug("Auto-switch skipped: secure text field focused")
            return
        }
        
        let isRussian = currentLayoutIsRussian()
        let minLength = settings.configuration.minWordLength
        let converted: String?
        switch settings.configuration.detectionEngine {
        case .spellChecker:
            converted = wrongLayoutDetector.detect(word: word, currentLayoutIsRussian: isRussian, minLength: minLength)
        case .ngram:
            converted = ngramDetector.detect(word: word, currentLayoutIsRussian: isRussian, minLength: minLength)
        }
        guard let converted else { return }
        
        Logger.conversion.info("⚠️ Wrong layout suspected: '\(word)' → '\(converted)'")
        
        switch settings.configuration.autoSwitchMode {
        case .warnSound:
            // Фаза 1: только звук-предупреждение.
            SoundManager.shared.playSound(
                named: settings.configuration.wrongLayoutSoundName,
                volume: settings.configuration.soundVolume
            )
        case .autoSwitch:
            // Фаза 2 (бета): исправляем последнее слово и переключаем раскладку.
            await performAutoCorrection(word: word, converted: converted)
        case .off:
            break
        }
    }
    
    /// Авто-исправление (бета): слово только что завершено границей (пробел/пунктуация),
    /// поэтому курсор стоит после "слово<граница>". Уходим влево за границу, выделяем
    /// слово, заменяем сконвертированным текстом, возвращаем курсор и переключаем раскладку.
    private func performAutoCorrection(word: String, converted: String) async {
        let pasteboard = NSPasteboard.general
        let clipboardState = ClipboardState(pasteboard: pasteboard)
        let boundary = 1  // граница, на которой слово было завершено
        let wordLength = word.count
        
        do {
            try await moveCursor(boundary, left: true)
            try await selectBack(wordLength)
            
            pasteboard.clearContents()
            pasteboard.setString(converted, forType: .string)
            try await Task.sleep(nanoseconds: Timing.pasteDelay)
            try await simulateKeyPress(key: KeyCode.v, modifiers: .maskCommand)
            
            try await moveCursor(boundary, left: false)
            
            try await Task.sleep(nanoseconds: Timing.restoreDelay)
            clipboardState.restore(to: pasteboard)
            
            // Слово было набрано в текущей (неправильной) раскладке — переключаем на противоположную.
            let cfg = settings.configuration
            LayoutManager.switchToOpposite(layout1ID: cfg.layout1ID, layout2ID: cfg.layout2ID)
            
            resetWordTracking()
            
            // Звук при переключении.
            SoundManager.shared.playSound(
                named: cfg.wrongLayoutSoundName,
                volume: cfg.soundVolume
            )
            Logger.conversion.info("✅ Auto-corrected: '\(word)' → '\(converted)'")
        } catch {
            Logger.conversion.error("Auto-correction failed: \(error)")
            clipboardState.restore(to: pasteboard)
        }
    }
    
    /// Определяет, активна ли русская/кириллическая раскладка.
    private func currentLayoutIsRussian() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else {
            return false
        }
        let id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        let lower = id.lowercased()
        return lower.contains("russian") || lower.contains("cyrillic")
    }
    
    /// Проверяет, сфокусировано ли защищённое текстовое поле (пароль).
    private func isSecureFieldFocused() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return false
        }
        let element = focused as! AXUIElement
        var subrole: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success,
              let subroleString = subrole as? String else {
            return false
        }
        return subroleString == (kAXSecureTextFieldSubrole as String)
    }
    
    func convertLayout() async {
        let startTime = Date()
        Logger.conversion.info("Starting layout conversion...")
        
        let pasteboard = NSPasteboard.general
        let clipboardState = ClipboardState(pasteboard: pasteboard)
        
        // Снимок счётчиков слова на момент перед горячей клавишей.
        let snapWord = snapWordLength
        let snapBefore = snapBeforeLength
        let snapBound = snapBoundary
        
        do {
            // 1. Сначала пробуем уже выделенный пользователем текст.
            try await simulateKeyPress(key: KeyCode.c, modifiers: .maskCommand)
            var copiedText = await waitForCopiedText(
                initialChangeCount: clipboardState.changeCount,
                pasteboard: pasteboard
            )
            
            // Сколько позиций вернуть курсор вправо после вставки (для слова перед границей).
            var restoreCursorRight = 0
            
            // 2. Выделения нет — выделяем последнее набранное слово по счётчикам keycode.
            if copiedText == nil || copiedText!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if snapWord > 0 {
                    try await selectBack(snapWord)
                } else if snapBefore > 0 && snapBound > 0 {
                    // Курсор после "слово␣␣": уходим влево за границы, выделяем слово,
                    // позже вернём курсор вправо на то же число границ.
                    try await moveCursor(snapBound, left: true)
                    try await selectBack(snapBefore)
                    restoreCursorRight = snapBound
                } else {
                    Logger.conversion.warning("Nothing selected and no tracked word - aborting")
                    clipboardState.restore(to: pasteboard)
                    metrics.recordFailure()
                    await playErrorSound()
                    return
                }
                let beforeCount = pasteboard.changeCount
                try await simulateKeyPress(key: KeyCode.c, modifiers: .maskCommand)
                copiedText = await waitForCopiedText(initialChangeCount: beforeCount, pasteboard: pasteboard)
            }
            
            guard let text = copiedText,
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Logger.conversion.warning("Failed to copy text - restoring clipboard")
                clipboardState.restore(to: pasteboard)
                metrics.recordFailure()
                await playErrorSound()
                return
            }
            
            Logger.conversion.info("Source text (\(text.count) chars): '\(text.prefix(50))'")
            
            // 3. Конвертация: динамический UCKeyTranslate-маппинг с фолбэком на таблицу.
            // Направление определяется по содержимому текста (см. DynamicKeyMapping).
            let cfg = settings.configuration
            let dynamicResult = DynamicKeyMapping.convert(text, layout1ID: cfg.layout1ID, layout2ID: cfg.layout2ID)
            let convertedText = dynamicResult?.text ?? converter.convert(text)
            
            guard convertedText != text else {
                Logger.conversion.warning("Text unchanged after conversion")
                clipboardState.restore(to: pasteboard)
                metrics.recordFailure()
                await playErrorSound()
                return
            }
            
            Logger.conversion.info("Converted (\(convertedText.count) chars): '\(convertedText.prefix(50))'")
            
            // 4. Вставляем результат вместо выделения.
            pasteboard.clearContents()
            pasteboard.setString(convertedText, forType: .string)
            try await Task.sleep(nanoseconds: Timing.pasteDelay)
            try await simulateKeyPress(key: KeyCode.v, modifiers: .maskCommand)
            
            // 5. Возвращаем курсор за границы (если конвертировали слово перед пробелами).
            if restoreCursorRight > 0 {
                try await moveCursor(restoreCursorRight, left: false)
            }
            
            // 6. Восстанавливаем оригинальный буфер обмена.
            try await Task.sleep(nanoseconds: Timing.restoreDelay)
            clipboardState.restore(to: pasteboard)
            
            // 7. Переключаем клавиатуру на раскладку сконвертированного текста.
            // Если направление известно из динамического маппинга — по точному ID,
            // иначе (фолбэк) — на противоположную из пары.
            if let targetLayoutID = dynamicResult?.targetLayoutID {
                LayoutManager.switchTo(layoutID: targetLayoutID)
            } else {
                LayoutManager.switchToOpposite(layout1ID: cfg.layout1ID, layout2ID: cfg.layout2ID)
            }
            
            // 8. Слово сконвертировано — сбрасываем отслеживание.
            resetWordTracking()
            
            metrics.recordSuccess(duration: Date().timeIntervalSince(startTime))
            await playSuccessSound()
            
        } catch {
            Logger.conversion.error("Conversion failed: \(error)")
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
    
    /// Создаёт источник событий, помеченный нашим маркером, чтобы event tap
    /// игнорировал сгенерированные нами нажатия (Cmd+C, Cmd+V, Shift+←).
    private func makeMarkedEventSource() -> CGEventSource? {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.userData = kLayoutSwitcherEventMarker
        return source
    }
    
    private func simulateKeyPress(key: UInt16, modifiers: CGEventFlags = []) async throws {
        guard AXIsProcessTrusted() else {
            throw LayoutError.accessibilityPermissionDenied
        }
        
        let source = makeMarkedEventSource()
        
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false) else {
            throw LayoutError.clipboardOperationFailed
        }
        
        keyDown.flags = modifiers
        keyUp.flags = modifiers
        // Дублируем маркер в самих событиях (на случай, если источник не сохранит userData).
        keyDown.setIntegerValueField(.eventSourceUserData, value: kLayoutSwitcherEventMarker)
        keyUp.setIntegerValueField(.eventSourceUserData, value: kLayoutSwitcherEventMarker)
        
        keyDown.post(tap: .cghidEventTap)
        try await Task.sleep(nanoseconds: Timing.keyPressDelay)
        keyUp.post(tap: .cghidEventTap)
    }
    
    /// Выделяет `count` символов слева от курсора через Shift+←.
    private func selectBack(_ count: Int) async throws {
        guard count > 0 else { return }
        for _ in 0..<count {
            try await simulateKeyPress(key: KeyCode.leftArrow, modifiers: .maskShift)
            try? await Task.sleep(nanoseconds: Timing.selectionKeyDelay)
        }
    }
    
    /// Перемещает курсор на `count` позиций стрелкой (влево или вправо), без выделения.
    private func moveCursor(_ count: Int, left: Bool) async throws {
        guard count > 0 else { return }
        let key = left ? KeyCode.leftArrow : KeyCode.rightArrow
        for _ in 0..<count {
            try await simulateKeyPress(key: key)
            try? await Task.sleep(nanoseconds: Timing.selectionKeyDelay)
        }
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
            title: hasPermissions ? L(.menuPermsGranted) : L(.menuPermsRequired),
            action: nil,
            keyEquivalent: ""
        )
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        menu.addItem(.separator())
        
        let convertItem = NSMenuItem(
            title: String(format: L(.menuSwitchLayout), self.settings.configuration.displayString),
            action: #selector(manualSwitch),
            keyEquivalent: ""
        )
        convertItem.isEnabled = hasPermissions
        menu.addItem(convertItem)
        
        menu.addItem(.separator())
        
        let soundItem = NSMenuItem(
            title: L(.menuPlaySounds),
            action: #selector(toggleSound),
            keyEquivalent: ""
        )
        soundItem.state = self.settings.configuration.soundEnabled ? .on : .off
        menu.addItem(soundItem)
        
        let launchAtLoginItem = NSMenuItem(
            title: L(.menuLaunchAtLogin),
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
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
            menu.addItem(NSMenuItem(
                title: L(.menuGrantPerms),
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            ))
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
        alert.messageText = L(.statsAlertTitle)
        alert.informativeText = metrics.summary
        alert.alertStyle = .informational
        alert.addButton(withTitle: L(.btnOk))
        alert.addButton(withTitle: L(.btnReset))
        
        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
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
        
        © 2024
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
        
        if !AXIsProcessTrustedWithOptions(options) {
            Logger.ui.warning("Accessibility permissions not granted")
            
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
    @ObservedObject private var loc = LocalizationManager.shared
    @State private var isVisible = false
    
    var body: some View {
        VStack(spacing: 0) {
            headerView
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : -20)
            
            ScrollView {
                LazyVStack(spacing: 20) {
                    languageSection
                        .opacity(isVisible ? 1 : 0)
                        .offset(y: isVisible ? 0 : 20)
                    
                    hotKeySection
                        .opacity(isVisible ? 1 : 0)
                        .offset(y: isVisible ? 0 : 20)
                    
                    autoSwitchSection
                        .opacity(isVisible ? 1 : 0)
                        .offset(y: isVisible ? 0 : 20)
                    
                    layoutPairSection
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
            
            Text(L(.headerSubtitle))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity)
    }
    
    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L(.secLanguage), systemImage: "globe.badge.chevron.backward")
                .font(.headline)
            
            Picker(L(.secLanguage), selection: $loc.language) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.menu)
            .frame(maxWidth: .infinity, alignment: .leading)
            .labelsHidden()
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var hotKeySection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L(.secHotkey), systemImage: "command.square")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(L(.lblActivationMode))
                    .font(.subheadline.weight(.medium))
                
                Picker(L(.modeLabel), selection: $settings.configuration.hotKeyMode) {
                    ForEach(HotKeyMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }
            
            Divider()
            
            switch settings.configuration.hotKeyMode {
            case .doubleShift:
                doubleKeySettings
            case .doubleAlt:
                doubleAltSettings
            case .singleAlt:
                singleAltSettings
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
            Text(L(.dsHint))
                .font(.caption)
                .foregroundStyle(.secondary)
            
            intervalSlider(
                title: L(.lblMinInterval),
                value: $settings.configuration.minDoubleShiftInterval,
                range: 0.01...0.5
            )
            
            intervalSlider(
                title: L(.lblMaxInterval),
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
                    Text(L(.hkCtrlShift))
                        .font(.headline)
                    Text(L(.ctrlShiftDesc))
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
                    Text(L(.hkFnShift))
                        .font(.headline)
                    Text(L(.fnShiftDesc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            
            Text(L(.fnShiftNote))
                .font(.caption2)
                .foregroundStyle(.orange)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.leading, 16)
    }
    
    private var singleAltSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "option")
                    .font(.title2)
                    .foregroundStyle(.tint)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(L(.hkSingleAlt))
                        .font(.headline)
                    Text(L(.singleAltDesc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            
            Text(L(.singleAltNote))
                .font(.caption2)
                .foregroundStyle(.orange)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        }
        .padding(.leading, 16)
    }
    
    private var doubleAltSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L(.doubleAltHint))
                .font(.caption)
                .foregroundStyle(.secondary)
            
            intervalSlider(
                title: L(.lblMinInterval),
                value: $settings.configuration.minDoubleShiftInterval,
                range: 0.01...0.5
            )
            
            intervalSlider(
                title: L(.lblMaxInterval),
                value: $settings.configuration.maxDoubleShiftInterval,
                range: 0.1...2.0
            )
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
                
                Text(String(format: L(.fmtMs), value.wrappedValue * 1000))
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
                Text(L(.lblCurrentCombo))
                    .font(.subheadline.weight(.medium))
                
                Spacer()
                
                Text(settings.configuration.displayString)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(Color.accentColor)
            }
            
            Text(L(.lblDefaultCombo))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    
    private var autoSwitchSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L(.secAutoSwitch), systemImage: "character.cursor.ibeam")
                .font(.headline)
            
            Text(L(.autoSwitchDesc))
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Picker(L(.modeLabel), selection: $settings.configuration.autoSwitchMode) {
                ForEach(AutoSwitchMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            
            if settings.configuration.autoSwitchMode != .off {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L(.lblDetectionEngine))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        Picker(L(.lblDetectionEngine), selection: $settings.configuration.detectionEngine) {
                            ForEach(DetectionEngine.allCases, id: \.self) { engine in
                                Text(engine.displayName).tag(engine)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        Text(settings.configuration.detectionEngine == .ngram
                             ? L(.engineNgramDesc)
                             : L(.engineDictDesc))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    
                    Stepper(value: $settings.configuration.minWordLength, in: 2...20) {
                        HStack {
                            Text(L(.lblMinWordLength))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(settings.configuration.minWordLength)")
                                .font(.caption.monospacedDigit().weight(.medium))
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L(.lblWarnSound))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Picker(L(.lblWarnSound), selection: $settings.configuration.wrongLayoutSoundName) {
                                ForEach(SoundConfiguration.availableSounds, id: \.self) { soundName in
                                    Text(SoundConfiguration.localizedName(for: soundName)).tag(soundName)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            
                            Button("▶️") {
                                Task { @MainActor in
                                    SoundManager.shared.testSound(
                                        settings.configuration.wrongLayoutSoundName,
                                        volume: settings.configuration.soundVolume
                                    )
                                }
                            }
                            .buttonStyle(.borderless)
                            .help(L(.helpPlaySound))
                        }
                    }
                    
                    excludedAppsView
                }
                .padding(.leading, 16)
            }
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private var layoutPairSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L(.secLayoutPair), systemImage: "globe")
                .font(.headline)
            
            Text(L(.layoutPairDesc))
                .font(.caption)
                .foregroundStyle(.secondary)
            
            layoutPicker(title: L(.lblLayout1), selection: $settings.configuration.layout1ID)
            layoutPicker(title: L(.lblLayout2), selection: $settings.configuration.layout2ID)
        }
        .padding(20)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
    
    private func layoutPicker(title: String, selection: Binding<String>) -> some View {
        HStack {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Picker(title, selection: selection) {
                Text(L(.layoutAuto)).tag("")
                ForEach(installedLayoutOptions, id: \.id) { layout in
                    Text(layout.name).tag(layout.id)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: 260)
        }
    }
    
    /// Список установленных раскладок для пикеров (id + локализованное имя).
    private var installedLayoutOptions: [(id: String, name: String)] {
        LayoutManager.installedLayouts().map {
            (id: LayoutManager.sourceID($0), name: LayoutManager.sourceName($0))
        }
    }
    
    private var excludedAppsView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L(.lblExcludedApps))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    addExcludedApp()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help(L(.helpAddApp))
            }
            
            if settings.configuration.excludedAppBundleIDs.isEmpty {
                Text(L(.excludedEmpty))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                VStack(spacing: 4) {
                    ForEach(settings.configuration.excludedAppBundleIDs, id: \.self) { bundleID in
                        HStack {
                            Image(systemName: "app.dashed")
                                .foregroundStyle(.secondary)
                            Text(appDisplayName(for: bundleID))
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Button {
                                settings.configuration.excludedAppBundleIDs.removeAll { $0 == bundleID }
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .help(L(.helpRemoveFromList))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
    }
    
    private func appDisplayName(for bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            let name = FileManager.default.displayName(atPath: url.path)
            return "\(name)  ·  \(bundleID)"
        }
        return bundleID
    }
    
    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.title = L(.openPanelTitle)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        
        guard panel.runModal() == .OK,
              let url = panel.url,
              let bundle = Bundle(url: url),
              let bundleID = bundle.bundleIdentifier else { return }
        
        if !settings.configuration.excludedAppBundleIDs.contains(bundleID) {
            settings.configuration.excludedAppBundleIDs.append(bundleID)
            Logger.ui.info("Added excluded app: \(bundleID)")
        }
    }
    
    private var soundSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(L(.secSound), systemImage: "speaker.wave.2")
                .font(.headline)
            
            Toggle(L(.menuPlaySounds), isOn: $settings.configuration.soundEnabled)
                .toggleStyle(.switch)
            
            if settings.configuration.soundEnabled {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L(.lblVolume))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.secondary)
                            
                            Spacer()
                            
                            Text("\(Int(settings.configuration.soundVolume * 100))%")
                                .font(.caption.monospacedDigit().weight(.medium))
                        }
                        
                        Slider(value: $settings.configuration.soundVolume, in: 0.0...1.0) {
                            Text(L(.lblVolumePlain))
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
                        Text(L(.lblSuccessSound))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Picker(L(.lblSuccessSound), selection: $settings.configuration.successSoundName) {
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
                            .help(L(.helpPlaySound))
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L(.lblErrorSound))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        
                        HStack {
                            Picker(L(.lblErrorSound), selection: $settings.configuration.errorSoundName) {
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
                            .help(L(.helpPlaySound))
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
            Label(L(.secConfigErrors), systemImage: "exclamationmark.triangle")
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
                    
                    Text(settings.isConfigurationValid ? L(.statusValid) : L(.statusInvalid))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                Button(L(.btnDone)) {
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
            $0.identifier?.rawValue == SettingsWindow.windowIdentifier
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
                Button(L(.cmdAbout)) {
                    showAboutWindow()
                }
            }
            
            CommandGroup(replacing: .appTermination) {
                Button(L(.cmdQuit)) {
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
        \(L(.aboutDesc2))
        
        \(L(.aboutVersionLabel)): \(Bundle.main.appVersionString)
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: L(.btnOk))
        alert.runModal()
    }
}
