//
//  Localization.swift
//  LayoutSwitcher
//
//  Язык интерфейса, ключи строк и таблица переводов.
//

import Foundation

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
    case errNoText, errConversionFailed, errAccessibility, errClipboard, errSecureField
    // Статистика
    case statsHeader, statsTotal, statsSuccess, statsFailed, statsRate, statsAvgTime, statsMsSuffix, statsAxShare
    // HotKeyMode.displayName
    case hkCustom, hkDoubleShift, hkCtrlShift, hkFnShift, hkSingleAlt, hkDoubleAlt
    // AutoSwitchMode.displayName
    case asOff, asWarnSound, asAutoSwitch
    // DetectionEngine.displayName
    case deDictionary, deNgram
    // Валидация
    case valMinIntervalGt0, valMaxGtMin, valMaxTooBig, valKeyEmpty, valNeedModifier, valMinWordLength, valLayoutsSame
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
    case hotkeyRecording, hotkeyRecordingHint, helpRecordHotkey
    // Секция автопереключения
    case secAutoSwitch, autoSwitchDesc, lblDetectionEngine, engineNgramDesc, engineDictDesc
    case lblMinWordLength, lblWarnSound, helpPlaySound
    // Секция пары раскладок
    case secLayoutPair, layoutPairDesc, lblLayout1, lblLayout2, layoutAuto
    case lblExcludedApps, helpAddApp, excludedEmpty, helpRemoveFromList, openPanelTitle
    // Секция замены текста
    case secReplacement, lblUseAX, axDesc
    // Секция звука
    case secSound, lblVolume, lblVolumePlain, lblSuccessSound, lblErrorSound
    // Прочее
    case secConfigErrors, statusValid, statusInvalid
    case secLanguage, langSystem
    case cmdAbout, cmdQuit
    // Обновления
    case menuDownloadUpdate, updAlertTitle, updAlertMsg, btnDownload
    case secUpdates, lblCheckUpdates, updDesc, btnCheckNow
    case updStatusNever, updStatusChecking, updStatusUpToDate, updStatusAvailable, updStatusFailed
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
            effectiveLanguageCode = Self.resolveCode(for: language)
        }
    }

    /// Эффективный код языка ("ru"/"en"). Кэшируется: `L()` вызывается из каждого
    /// `body` SwiftUI, а чтение `Locale.preferredLanguages` не бесплатно.
    private(set) var effectiveLanguageCode: String

    private init() {
        let raw = UserDefaults.standard.string(forKey: Self.storageKey)
        let lang = raw.flatMap(AppLanguage.init(rawValue:)) ?? .system
        language = lang
        effectiveLanguageCode = Self.resolveCode(for: lang)
    }

    /// Для `.system` берётся язык системы (если поддерживается), иначе английский.
    private static func resolveCode(for language: AppLanguage) -> String {
        switch language {
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            let code = String(preferred.prefix(2)).lowercased()
            return supportedCodes.contains(code) ? code : "en"
        case .ru:
            return "ru"
        case .en:
            return "en"
        }
    }

    /// Перевод для текущего эффективного языка с фолбэком: язык → английский → имя ключа.
    func string(_ key: LK) -> String {
        let entry = Self.translations[key]
        return entry?[effectiveLanguageCode] ?? entry?["en"] ?? key.rawValue
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
        .errSecureField: ["ru": "Поле пароля не конвертируется",
                          "en": "Secure fields are not converted"],

        // Статистика
        .statsHeader: ["ru": "📊 Статистика конвертаций:", "en": "📊 Conversion statistics:"],
        .statsTotal: ["ru": "Всего", "en": "Total"],
        .statsSuccess: ["ru": "Успешно", "en": "Successful"],
        .statsFailed: ["ru": "Неудачно", "en": "Failed"],
        .statsRate: ["ru": "Успешность", "en": "Success rate"],
        .statsAvgTime: ["ru": "Среднее время", "en": "Average time"],
        .statsMsSuffix: ["ru": "мс", "en": "ms"],
        .statsAxShare: ["ru": "Через Accessibility", "en": "Via Accessibility"],

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
        .asAutoSwitch: ["ru": "Авто", "en": "Auto"],

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
        .valLayoutsSame: ["ru": "Раскладка 1 и раскладка 2 не могут совпадать",
                          "en": "Layout 1 and Layout 2 cannot be the same"],

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
        .hotkeyRecording: ["ru": "Нажмите комбинацию…", "en": "Press a shortcut…"],
        .hotkeyRecordingHint: ["ru": "Esc — отменить запись", "en": "Esc — cancel recording"],
        .helpRecordHotkey: ["ru": "Нажать, затем ввести новую комбинацию",
                            "en": "Click, then press a new shortcut"],

        // Секция автопереключения
        .secAutoSwitch: ["ru": "Автопереключение раскладки", "en": "Auto layout switching"],
        .autoSwitchDesc: ["ru": "Определяет ввод в неправильной раскладке: предупреждает звуком или исправляет слово и переключает раскладку",
                          "en": "Detects typing in the wrong layout: warns with a sound or corrects the word and switches the layout"],
        .lblDetectionEngine: ["ru": "Движок детекции:", "en": "Detection engine:"],
        .engineNgramDesc: ["ru": "Статистика триграмм (ru, en, uk, de): ловит и несловарные слова (имена, сленг). Для других языков используется словарь.",
                           "en": "Trigram statistics (ru, en, uk, de): also catches non-dictionary words (names, slang). Other languages fall back to the dictionary."],
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

        // Секция замены текста
        .secReplacement: ["ru": "Замена текста", "en": "Text replacement"],
        .lblUseAX: ["ru": "Заменять через Accessibility (быстрее, без буфера обмена)",
                    "en": "Replace via Accessibility (faster, no clipboard)"],
        .axDesc: ["ru": "Текст читается и заменяется напрямую в поле ввода. Если приложение этого не поддерживает, используется обычный путь через ⌘C/⌘V.",
                  "en": "Text is read and replaced directly in the input field. Apps that don't support it fall back to the ⌘C/⌘V path."],

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

        // Обновления
        .menuDownloadUpdate: ["ru": "⬆️ Скачать версию %@…", "en": "⬆️ Download version %@…"],
        .updAlertTitle: ["ru": "Доступна новая версия", "en": "A new version is available"],
        .updAlertMsg: ["ru": "Вышла версия %@ Layout Switcher (установлена %@).\n\nСкачать DMG с GitHub?",
                       "en": "Layout Switcher %@ is out (you have %@).\n\nDownload the DMG from GitHub?"],
        .btnDownload: ["ru": "Скачать", "en": "Download"],
        .secUpdates: ["ru": "Обновления", "en": "Updates"],
        .lblCheckUpdates: ["ru": "Проверять новые версии при запуске и раз в сутки",
                           "en": "Check for new versions at launch and once a day"],
        .updDesc: ["ru": "Приложение запрашивает у GitHub последний релиз и сравнивает его с установленной версией. Ничего не скачивается и не устанавливается само.",
                   "en": "The app asks GitHub for the latest release and compares it with the installed version. Nothing is downloaded or installed automatically."],
        .btnCheckNow: ["ru": "Проверить сейчас", "en": "Check now"],
        .updStatusNever: ["ru": "Ещё не проверялось", "en": "Not checked yet"],
        .updStatusChecking: ["ru": "Проверка…", "en": "Checking…"],
        .updStatusUpToDate: ["ru": "Установлена последняя версия (проверено %@)",
                             "en": "You have the latest version (checked %@)"],
        .updStatusAvailable: ["ru": "Доступна версия %@", "en": "Version %@ is available"],
        .updStatusFailed: ["ru": "Не удалось проверить (%@)", "en": "Check failed (%@)"],
    ]
}

/// Короткий помощник доступа к переводам: `L(.someKey)`.
func L(_ key: LK) -> String { LocalizationManager.shared.string(key) }
