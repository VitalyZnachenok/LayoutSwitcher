import SwiftUI
import AppKit
import Carbon

// MARK: - Модель настроек
class SettingsManager: ObservableObject {
    @Published var modifierFlags: NSEvent.ModifierFlags = [.command, .shift]
    @Published var keyCode: UInt16 = 0x25 // L по умолчанию
    @Published var keyCharacter: String = "L"
    @Published var useDoubleShift: Bool = false
    
    // Новые настройки тайминга для двойного Shift
    @Published var minDoubleShiftInterval: Double = 0.05 // Минимум 50ms между нажатиями
    @Published var maxDoubleShiftInterval: Double = 0.8  // Максимум 800ms между нажатиями
    
    private let userDefaults = UserDefaults.standard
    
    init() {
        loadSettings()
    }
    
    var displayString: String {
        if useDoubleShift {
            return "⇧⇧ (двойной Shift)"
        }
        
        var components: [String] = []
        
        if modifierFlags.contains(.control) { components.append("⌃") }
        if modifierFlags.contains(.option) { components.append("⌥") }
        if modifierFlags.contains(.shift) { components.append("⇧") }
        if modifierFlags.contains(.command) { components.append("⌘") }
        
        components.append(keyCharacter.uppercased())
        
        return components.joined()
    }
    
    var carbonModifiers: UInt32 {
        var carbonMods: UInt32 = 0
        
        if modifierFlags.contains(.control) { carbonMods |= UInt32(controlKey) }
        if modifierFlags.contains(.option) { carbonMods |= UInt32(optionKey) }
        if modifierFlags.contains(.shift) { carbonMods |= UInt32(shiftKey) }
        if modifierFlags.contains(.command) { carbonMods |= UInt32(cmdKey) }
        
        return carbonMods
    }
    
    func loadSettings() {
        let modFlags = userDefaults.integer(forKey: "modifierFlags")
        if modFlags != 0 {
            modifierFlags = NSEvent.ModifierFlags(rawValue: UInt(modFlags))
        }
        
        let savedKeyCode = userDefaults.integer(forKey: "keyCode")
        if savedKeyCode != 0 {
            keyCode = UInt16(savedKeyCode)
        }
        
        keyCharacter = userDefaults.string(forKey: "keyCharacter") ?? "L"
        useDoubleShift = userDefaults.bool(forKey: "useDoubleShift")
        
        // Загружаем настройки тайминга
        let savedMinInterval = userDefaults.double(forKey: "minDoubleShiftInterval")
        if savedMinInterval > 0 {
            minDoubleShiftInterval = savedMinInterval
        }
        
        let savedMaxInterval = userDefaults.double(forKey: "maxDoubleShiftInterval")
        if savedMaxInterval > 0 {
            maxDoubleShiftInterval = savedMaxInterval
        }
    }
    
    func saveSettings() {
        userDefaults.set(Int(modifierFlags.rawValue), forKey: "modifierFlags")
        userDefaults.set(Int(keyCode), forKey: "keyCode")
        userDefaults.set(keyCharacter, forKey: "keyCharacter")
        userDefaults.set(useDoubleShift, forKey: "useDoubleShift")
        
        // Сохраняем настройки тайминга
        userDefaults.set(minDoubleShiftInterval, forKey: "minDoubleShiftInterval")
        userDefaults.set(maxDoubleShiftInterval, forKey: "maxDoubleShiftInterval")
        
        // Уведомляем об изменениях
        NotificationCenter.default.post(name: .settingsDidChange, object: nil)
    }
}

// MARK: - Расширение для уведомлений
extension Notification.Name {
    static let settingsDidChange = Notification.Name("settingsDidChange")
}

@main
struct LayoutSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private var statusBarItem: NSStatusItem?
    private var hotKeyRef: EventHotKeyRef?
    private weak var settingsWindow: NSWindow? // ИЗМЕНЕНО: weak ссылка
    private let settings = SettingsManager()
    
    // Для двойного нажатия Shift - гибридный подход
    private var leftShiftHotKeyRef: EventHotKeyRef?
    private var rightShiftHotKeyRef: EventHotKeyRef?
    private var lastShiftPressTime: TimeInterval = 0
    
    // Дополнительные переменные для мониторинга
    private var wasShiftPressed = false
    private var shiftPollingTimer: Timer?
    private var previousShiftState = false
    private var lastShiftReleaseTime: TimeInterval = 0 // Время последнего отпускания Shift
    private var shiftPressCount = 0 // Счетчик нажатий Shift
    private var isShiftSequenceActive = false // Флаг активной последовательности
    
    // Сохраняем ссылки на мониторы для корректного удаления
    private var localShiftMonitor: Any?
    private var globalShiftMonitor: Any?
    
    // Карты для конвертации между русской и английской раскладками
    let rusToEng: [Character: Character] = [
        "й": "q", "ц": "w", "у": "e", "к": "r", "е": "t", "н": "y", "г": "u", "ш": "i", "щ": "o", "з": "p", "х": "[", "ъ": "]",
        "ф": "a", "ы": "s", "в": "d", "а": "f", "п": "g", "р": "h", "о": "j", "л": "k", "д": "l", "ж": ";", "э": "'",
        "я": "z", "ч": "x", "с": "c", "м": "v", "и": "b", "т": "n", "ь": "m", "б": ",", "ю": ".", ".": "/",
        
        "Й": "Q", "Ц": "W", "У": "E", "К": "R", "Е": "T", "Н": "Y", "Г": "U", "Ш": "I", "Щ": "O", "З": "P", "Х": "{", "Ъ": "}",
        "Ф": "A", "Ы": "S", "В": "D", "А": "F", "П": "G", "Р": "H", "О": "J", "Л": "K", "Д": "L", "Ж": ":", "Э": "\"",
        "Я": "Z", "Ч": "X", "С": "C", "М": "V", "И": "B", "Т": "N", "Ь": "M", "Б": "<", "Ю": ">", ",": "?",
        
        "ё": "`", "Ё": "~", "№": "#", " ": " "
    ]
    
    let engToRus: [Character: Character] = [
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е", "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з", "[": "х", "]": "ъ",
        "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п", "h": "р", "j": "о", "k": "л", "l": "д", ";": "ж", "'": "э",
        "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и", "n": "т", "m": "ь", ",": "б", ".": "ю", "/": ".",
        
        "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е", "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З", "{": "Х", "}": "Ъ",
        "A": "Ф", "S": "Ы", "D": "В", "F": "А", "G": "П", "H": "Р", "J": "О", "K": "Л", "L": "Д", ":": "Ж", "\"": "Э",
        "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И", "N": "Т", "M": "Ь", "<": "Б", ">": "Ю", "?": ",",
        
        "`": "ё", "~": "Ё", "#": "№", " ": " "
    ]
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        print("🚀 Layout Switcher запущен")
        setupMenuBar()
        setupHotKeySystem()
        NSApp.setActivationPolicy(.accessory)
        requestAccessibilityPermissions()
        
        // Подписываемся на изменения настроек
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(settingsDidChange),
            name: .settingsDidChange,
            object: nil
        )
    }
    
    @objc private func settingsDidChange() {
        setupHotKeySystem()
    }
    
    // Функция для настройки системы горячих клавиш
    private func setupHotKeySystem() {
        // Отключаем предыдущие системы
        unregisterHotKey()
        removeShiftKeyMonitor()
        
        if settings.useDoubleShift {
            setupDoubleShiftMonitor()
        } else {
            setupGlobalHotKey()
        }
    }
    
    private func setupMenuBar() {
        print("📱 Создаем status bar...")
        statusBarItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        guard let button = statusBarItem?.button else {
            print("❌ Не удалось создать кнопку status bar")
            return
        }
        
        // Устанавливаем иконку
        if let image = createCustomIcon() {
            button.image = image
            button.title = ""
        } else if let image = NSImage(systemSymbolName: "textformat.abc", accessibilityDescription: "Layout Switcher") {
            button.image = image
            button.title = ""
        } else {
            // Fallback - текст
            button.title = "RU"
            button.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        }
        
        button.imagePosition = .imageOnly
        
        // Настраиваем кнопку для обработки кликов
        button.target = self
        button.action = #selector(statusBarButtonClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        
        print("✅ Status bar создан успешно")
    }
    
    // Создаем собственную иконку
    private func createCustomIcon() -> NSImage? {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        
        image.lockFocus()
        
        // Получаем цвет текста системы
        let textColor = NSColor.controlTextColor
        
        // Рисуем фон (опционально)
        let rect = NSRect(origin: .zero, size: size)
        
        // Рисуем RU и EN с стрелочкой между ними
        let font = NSFont.systemFont(ofSize: 7, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]
        
        // Позиции текста
        let ruText = "RU"
        let enText = "EN"
        
        // Рисуем RU вверху
        let ruSize = ruText.size(withAttributes: attributes)
        let ruRect = NSRect(
            x: (size.width - ruSize.width) / 2,
            y: size.height - ruSize.height - 1,
            width: ruSize.width,
            height: ruSize.height
        )
        ruText.draw(in: ruRect, withAttributes: attributes)
        
        // Рисуем стрелочку в центре
        let arrowPath = NSBezierPath()
        let centerY = size.height / 2
        let centerX = size.width / 2
        
        // Маленькая стрелочка вправо-влево
        arrowPath.move(to: NSPoint(x: centerX - 4, y: centerY))
        arrowPath.line(to: NSPoint(x: centerX + 4, y: centerY))
        arrowPath.move(to: NSPoint(x: centerX + 2, y: centerY - 1.5))
        arrowPath.line(to: NSPoint(x: centerX + 4, y: centerY))
        arrowPath.line(to: NSPoint(x: centerX + 2, y: centerY + 1.5))
        
        textColor.setStroke()
        arrowPath.lineWidth = 0.8
        arrowPath.stroke()
        
        // Рисуем EN внизу
        let enSize = enText.size(withAttributes: attributes)
        let enRect = NSRect(
            x: (size.width - enSize.width) / 2,
            y: 1,
            width: enSize.width,
            height: enSize.height
        )
        enText.draw(in: enRect, withAttributes: attributes)
        
        image.unlockFocus()
        
        // Делаем изображение template для автоматической адаптации к темной теме
        image.isTemplate = true
        
        return image
    }
    
    @objc private func statusBarButtonClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            // При левом клике также показываем меню
            showContextMenu()
        }
    }
    
    private func showContextMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "🔄 Переключить раскладку (\(settings.displayString))", action: #selector(switchLayout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "⚙️ Настройки...", action: #selector(showSettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "ℹ️ О программе", action: #selector(showAbout), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "❌ Выйти", action: #selector(quit), keyEquivalent: "q"))
        
        // Устанавливаем target для всех элементов
        for item in menu.items {
            item.target = self
        }
        
        // Показываем меню
        guard let button = statusBarItem?.button else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }
    
    // Мониторинг двойного нажатия Shift - новый гибридный подход
    private func setupDoubleShiftMonitor() {
        print("⌨️ Настраиваем мониторинг двойного Shift...")
        
        // Сбрасываем состояние
        wasShiftPressed = false
        previousShiftState = false
        lastShiftPressTime = 0
        lastShiftReleaseTime = 0
        shiftPressCount = 0
        isShiftSequenceActive = false
        
        // Метод 1: Глобальный мониторинг через NSEvent (основной)
        setupGlobalShiftMonitor()
        
        // Метод 2: Локальный мониторинг для работы внутри приложения
        setupLocalShiftMonitor()
        
        print("✅ Мониторинг Shift активирован")
        print("📝 Настройки: мин=\(String(format: "%.0f", settings.minDoubleShiftInterval * 1000))ms, макс=\(String(format: "%.0f", settings.maxDoubleShiftInterval * 1000))ms")
    }
    
    // Локальный мониторинг для работы внутри приложения
    private func setupLocalShiftMonitor() {
        localShiftMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return event }
            
            let hasShift = event.modifierFlags.contains(.shift)
            
            // Отслеживаем только изменения состояния Shift
            if hasShift && !self.wasShiftPressed {
                // Shift нажат
                self.handleShiftPress()
                self.wasShiftPressed = true
            } else if !hasShift && self.wasShiftPressed {
                // Shift отпущен
                self.handleShiftRelease()
                self.wasShiftPressed = false
            }
            
            return event
        }
        
        print("✅ Локальный мониторинг Shift настроен")
    }
    
    // Глобальный мониторинг (основной метод)
    private func setupGlobalShiftMonitor() {
        // Мониторим flagsChanged глобально
        globalShiftMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            guard let self = self else { return }
            
            let hasShift = event.modifierFlags.contains(.shift)
            
            // Отслеживаем только изменения состояния Shift
            if hasShift && !self.previousShiftState {
                // Shift нажат
                self.handleShiftPress()
            } else if !hasShift && self.previousShiftState {
                // Shift отпущен
                self.handleShiftRelease()
            }
            
            self.previousShiftState = hasShift
        }
        
        if globalShiftMonitor != nil {
            print("✅ Глобальный мониторинг Shift настроен")
        } else {
            print("❌ Не удалось настроить глобальный мониторинг")
        }
    }
    
    // Polling как резервный метод
    private func setupShiftPolling() {
        shiftPollingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            let currentFlags = NSEvent.modifierFlags
            let currentShiftState = currentFlags.contains(.shift)
            
            if currentShiftState != self.previousShiftState {
                if currentShiftState {
                    print("⏰ POLLING Shift НАЖАТ")
                    self.handleShiftPress()
                } else {
                    print("⏰ POLLING Shift ОТПУЩЕН")
                    self.handleShiftRelease()
                }
                self.previousShiftState = currentShiftState
            }
        }
        
        print("✅ Polling мониторинг запущен (каждые 100ms, отслеживает нажатие + отпускание)")
    }
    
    // Регистрация отдельной клавиши Shift как горячей клавиши
    private func setupShiftHotKey(keyCode: UInt32, hotKeyRef: inout EventHotKeyRef?, id: UInt32, description: String) {
        let hotKeyId = EventHotKeyID(signature: OSType(fourCharCode("LSWT")), id: id)
        
        // Регистрируем Shift БЕЗ модификаторов (только саму клавишу)
        let status = RegisterEventHotKey(
            keyCode,
            0, // Никаких модификаторов!
            hotKeyId,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr {
            print("✅ Зарегистрирован \(description) как глобальная горячая клавиша")
        } else {
            print("❌ Ошибка регистрации \(description): \(status)")
            
            // Пробуем альтернативный подход с минимальными модификаторами
            tryAlternativeShiftRegistration(keyCode: keyCode, hotKeyRef: &hotKeyRef, id: id, description: description)
        }
    }
    
    // Альтернативный подход - регистрируем с самим Shift как модификатором
    private func tryAlternativeShiftRegistration(keyCode: UInt32, hotKeyRef: inout EventHotKeyRef?, id: UInt32, description: String) {
        print("🔄 Пробуем альтернативную регистрацию \(description)...")
        
        let hotKeyId = EventHotKeyID(signature: OSType(fourCharCode("LSWT")), id: id)
        
        // Пробуем зарегистрировать как Shift+Shift (сам себе модификатор)
        let status = RegisterEventHotKey(
            keyCode,
            UInt32(shiftKey),
            hotKeyId,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr {
            print("✅ Альтернативная регистрация \(description) успешна")
        } else {
            print("❌ Альтернативная регистрация \(description) не удалась: \(status)")
        }
    }
    
    // Единый обработчик для всех горячих клавиш
    private func setupUnifiedHotKeyHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, theEvent, userData) -> OSStatus in
                if let userData = userData {
                    let appDelegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                    
                    // Получаем ID горячей клавиши
                    var hotKeyId = EventHotKeyID()
                    GetEventParameter(theEvent, OSType(kEventParamDirectObject), OSType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyId)
                    
                    DispatchQueue.main.async {
                        if hotKeyId.id == 1 {
                            // Обычная горячая клавиша
                            appDelegate.handleHotKey()
                        } else if hotKeyId.id == 2 || hotKeyId.id == 3 {
                            // Shift нажат
                            print("🌍 ГЛОБАЛЬНЫЙ Shift нажат: ID \(hotKeyId.id)")
                            appDelegate.handleShiftPress()
                        }
                    }
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            nil
        )
    }
    
    private func setupGlobalHotKey() {
        // Сначала отменяем предыдущую горячую клавишу
        unregisterHotKey()
        
        print("⌨️ Настраиваем горячую клавишу \(settings.displayString)...")
        
        let hotKeyId = EventHotKeyID(signature: OSType(fourCharCode("LSWT")), id: 1)
        let modifiers = settings.carbonModifiers
        let keyCode = UInt32(settings.keyCode)
        
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyId,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr {
            print("✅ Горячая клавиша \(settings.displayString) зарегистрирована")
        } else {
            print("❌ Ошибка регистрации горячей клавиши: \(status)")
        }
    }
    
    private func unregisterHotKey() {
        if let hotKeyRef = hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
    
    private func removeShiftKeyMonitor() {
        print("🧹 Начинаем очистку мониторов Shift...")
        
        // Отключаем горячие клавиши Shift
        if let leftShiftHotKeyRef = leftShiftHotKeyRef {
            let status = UnregisterEventHotKey(leftShiftHotKeyRef)
            print("🔑 Отключена левая горячая клавиша Shift, статус: \(status)")
            self.leftShiftHotKeyRef = nil
        }
        
        if let rightShiftHotKeyRef = rightShiftHotKeyRef {
            let status = UnregisterEventHotKey(rightShiftHotKeyRef)
            print("🔑 Отключена правая горячая клавиша Shift, статус: \(status)")
            self.rightShiftHotKeyRef = nil
        }
        
        // Отключаем мониторы NSEvent
        if let localMonitor = localShiftMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localShiftMonitor = nil
            print("🏠 Локальный монитор отключен")
        }
        
        if let globalMonitor = globalShiftMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalShiftMonitor = nil
            print("🌍 Глобальный монитор отключен")
        }
        
        // Отключаем polling timer
        if let timer = shiftPollingTimer {
            timer.invalidate()
            self.shiftPollingTimer = nil
            print("⏰ Polling timer отключен")
        }
        
        // Сбрасываем все состояния
        wasShiftPressed = false
        previousShiftState = false
        lastShiftPressTime = 0
        lastShiftReleaseTime = 0
        shiftPressCount = 0
        isShiftSequenceActive = false
        
        print("✅ Все мониторы Shift отключены и состояния сброшены")
    }
    
    func handleHotKey() {
        print("🔥 Горячая клавиша нажата!")
        switchLayout()
    }
    
    private func handleShiftPress() {
        let currentTime = Date().timeIntervalSince1970
        
        // Если это первое нажатие или прошло много времени с последнего
        if shiftPressCount == 0 || (currentTime - lastShiftReleaseTime) > settings.maxDoubleShiftInterval {
            shiftPressCount = 1
            lastShiftPressTime = currentTime
            isShiftSequenceActive = true
            print("🔵 Shift #1 - начало новой последовательности")
            return
        }
        
        // Проверяем интервал между нажатиями
        let timeSinceLastPress = currentTime - lastShiftPressTime
        
        if timeSinceLastPress < settings.minDoubleShiftInterval {
            // Слишком быстро, игнорируем
            print("⚡ Слишком быстрое нажатие, игнорируем (интервал: \(String(format: "%.0f", timeSinceLastPress * 1000))ms)")
            return
        }
        
        if timeSinceLastPress > settings.maxDoubleShiftInterval {
            // Слишком долго, начинаем заново
            shiftPressCount = 1
            lastShiftPressTime = currentTime
            print("⏰ Таймаут, начинаем заново (интервал: \(String(format: "%.0f", timeSinceLastPress * 1000))ms)")
            return
        }
        
        // Увеличиваем счетчик
        shiftPressCount += 1
        
        if shiftPressCount == 2 {
            // Второе нажатие в правильном интервале!
            print("🟢 Shift #2 - ДВОЙНОЕ НАЖАТИЕ! (интервал: \(String(format: "%.0f", timeSinceLastPress * 1000))ms)")
            
            // Выполняем переключение
            DispatchQueue.main.async { [weak self] in
                self?.switchLayout()
            }
            
            // Сбрасываем состояние
            shiftPressCount = 0
            isShiftSequenceActive = false
            lastShiftPressTime = 0
        } else {
            // Больше двух нажатий
            print("🔴 Shift #\(shiftPressCount) - слишком много нажатий, сбрасываем")
            shiftPressCount = 0
            isShiftSequenceActive = false
        }
        
        lastShiftPressTime = currentTime
    }
    
    private func handleShiftRelease() {
        let currentTime = Date().timeIntervalSince1970
        lastShiftReleaseTime = currentTime
        
        // Просто фиксируем отпускание, основная логика в handleShiftPress
        print("🔻 Shift отпущен")
    }
    
    // Тестовый метод для проверки двойного Shift
    func testDoubleShift() {
        print("🧪 Тестируем систему переключения раскладки...")
        
        // Прямо вызываем switchLayout для проверки основной функциональности
        switchLayout()
        
        print("✅ Если вы услышали звук - основная функция работает!")
        print("📝 Теперь попробуйте реальное двойное нажатие Shift")
    }
    
    @objc func switchLayout() {
        print("🔄 Переключаем раскладку...")
        
        // Получаем выделенный текст
        guard let selectedText = getSelectedText() else {
            print("❌ Текст не выделен")
            playErrorSound()
            return
        }
        
        print("📝 Выделенный текст: '\(selectedText)'")
        
        // Определяем язык текста для переключения раскладки
        let isRussianText = detectIfRussianText(selectedText)
        
        // Конвертируем текст
        let convertedText = convertLayout(selectedText)
        print("✨ Конвертированный текст: '\(convertedText)'")
        
        // Заменяем выделенный текст
        replaceSelectedText(with: convertedText)
        
        // Переключаем раскладку клавиатуры
        switchKeyboardLayout(toRussian: !isRussianText)
        
        // Играем звук успеха
        playSuccessSound()
    }
    
    // Определяем, является ли текст русским
    private func detectIfRussianText(_ text: String) -> Bool {
        let lowercaseText = text.lowercased()
        var rusCount = 0
        var engCount = 0
        
        for char in lowercaseText {
            if rusToEng.keys.contains(char) {
                rusCount += 1
            } else if engToRus.keys.contains(char) {
                engCount += 1
            }
        }
        
        return rusCount > engCount
    }
    
    // Переключаем раскладку клавиатуры
    private func switchKeyboardLayout(toRussian: Bool) {
        // Получаем список источников ввода
        guard let inputSources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            print("❌ Не удалось получить список источников ввода")
            return
        }
        
        // Ищем нужную раскладку
        for inputSource in inputSources {
            guard let sourceID = TISGetInputSourceProperty(inputSource, kTISPropertyInputSourceID) else { continue }
            let sourceIDString = Unmanaged<CFString>.fromOpaque(sourceID).takeUnretainedValue() as String
            
            // Проверяем ID раскладки
            if toRussian && sourceIDString.contains("Russian") {
                TISSelectInputSource(inputSource)
                print("✅ Переключено на русскую раскладку")
                break
            } else if !toRussian && (sourceIDString.contains("U.S.") || sourceIDString.contains("ABC")) {
                TISSelectInputSource(inputSource)
                print("✅ Переключено на английскую раскладку")
                break
            }
        }
    }
    
    // Звуковые эффекты
    private func playSuccessSound() {
        // Пробуем системные звуки
        let successSounds = ["Tink", "Glass", "Pop", "Bottle"]
        
        for soundName in successSounds {
            if let sound = NSSound(named: soundName) {
                sound.play()
                return
            }
        }
        
        // Если не найден ни один - создаем программный звук
        createSuccessBeep()
    }
    
    private func playErrorSound() {
        // Пробуем системные звуки ошибки
        let errorSounds = ["Sosumi", "Basso", "Ping"]
        
        for soundName in errorSounds {
            if let sound = NSSound(named: soundName) {
                sound.play()
                return
            }
        }
        
        // Fallback - два коротких beep
        NSSound.beep()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSSound.beep()
        }
    }
    
    // Создаем программный звук успеха
    private func createSuccessBeep() {
        // Быстрый высокий звук
        let duration: TimeInterval = 0.1
        let frequency: Float = 800.0
        
        createTone(frequency: frequency, duration: duration)
    }
    
    // Генерируем простой тон
    private func createTone(frequency: Float, duration: TimeInterval) {
        DispatchQueue.global(qos: .background).async {
            // Простая генерация звука через системный beep как fallback
            DispatchQueue.main.async {
                NSSound.beep()
            }
        }
    }
    
    func getSelectedText() -> String? {
        let pasteboard = NSPasteboard.general
        
        // Сохраняем оригинальное содержимое буфера
        let originalChangeCount = pasteboard.changeCount
        let originalContents = pasteboard.string(forType: .string)
        
        // Очищаем буфер перед копированием
        pasteboard.clearContents()
        
        // Симулируем Cmd+C
        let source = CGEventSource(stateID: .hidSystemState)
        
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let cDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true),
              let cUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            print("❌ Не удалось создать события клавиатуры")
            return nil
        }
        
        cmdDown.flags = .maskCommand
        cDown.flags = .maskCommand
        cUp.flags = .maskCommand
        
        cmdDown.post(tap: .cghidEventTap)
        cDown.post(tap: .cghidEventTap)
        cUp.post(tap: .cghidEventTap)
        cmdUp.post(tap: .cghidEventTap)
        
        // Задержка для завершения копирования
        usleep(100000) // 100ms
        
        // Проверяем, изменился ли буфер обмена
        let newChangeCount = pasteboard.changeCount
        
        if newChangeCount == originalChangeCount {
            // Буфер не изменился - значит ничего не было выделено
            print("⚠️ Ничего не выделено")
            // Восстанавливаем оригинальное содержимое если было
            if let original = originalContents {
                pasteboard.clearContents()
                pasteboard.setString(original, forType: .string)
            }
            return nil
        }
        
        let copiedText = pasteboard.string(forType: .string)
        
        // Восстанавливаем оригинальное содержимое буфера
        if let original = originalContents {
            pasteboard.clearContents()
            pasteboard.setString(original, forType: .string)
        }
        
        // Проверяем что текст не пустой и не состоит только из пробелов
        guard let text = copiedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        
        return text
    }
    
    func replaceSelectedText(with text: String) {
        let pasteboard = NSPasteboard.general
        let originalContents = pasteboard.string(forType: .string)
        
        // Помещаем новый текст в буфер
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        
        // Симулируем Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)
        
        guard let cmdDown = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: true),
              let vDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true),
              let vUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false),
              let cmdUp = CGEvent(keyboardEventSource: source, virtualKey: 0x37, keyDown: false) else {
            print("❌ Не удалось создать события клавиатуры для вставки")
            return
        }
        
        cmdDown.flags = .maskCommand
        vDown.flags = .maskCommand
        vUp.flags = .maskCommand
        
        cmdDown.post(tap: .cghidEventTap)
        vDown.post(tap: .cghidEventTap)
        vUp.post(tap: .cghidEventTap)
        cmdUp.post(tap: .cghidEventTap)
        
        // Восстанавливаем оригинальное содержимое буфера через некоторое время
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            if let original = originalContents {
                pasteboard.clearContents()
                pasteboard.setString(original, forType: .string)
            }
        }
    }
    
    func convertLayout(_ text: String) -> String {
        var result = ""
        let lowercaseText = text.lowercased()
        
        // Определяем язык по преобладанию символов
        var rusCount = 0
        var engCount = 0
        
        for char in lowercaseText {
            if rusToEng.keys.contains(char) {
                rusCount += 1
            } else if engToRus.keys.contains(char) {
                engCount += 1
            }
        }
        
        // Определяем направление конвертации
        let isRussianToEnglish = rusCount > engCount
        
        print("🔍 Анализ текста: рус=\(rusCount), eng=\(engCount), направление: \(isRussianToEnglish ? "RU→EN" : "EN→RU")")
        
        for char in text {
            if isRussianToEnglish {
                // Конвертируем из русской в английскую
                if let converted = rusToEng[char] {
                    result.append(converted)
                } else {
                    result.append(char)
                }
            } else {
                // Конвертируем из английской в русскую
                if let converted = engToRus[char] {
                    result.append(converted)
                } else {
                    result.append(char)
                }
            }
        }
        
        return result
    }
    
    func requestAccessibilityPermissions() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as NSString: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        
        if !accessEnabled {
            print("⚠️ Требуются разрешения доступности")
            showNotification("🔐 Требуются разрешения", "Предоставьте разрешения в Настройках → Безопасность и конфиденциальность → Доступность")
        } else {
            print("✅ Разрешения доступности предоставлены")
        }
    }
    
    // Оставляем функцию уведомлений только для системных сообщений
    private func showNotification(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        
        // Показываем алерт в отдельном потоке
        DispatchQueue.main.async {
            alert.runModal()
        }
    }
    
    @objc func showSettings() {
        // ИЗМЕНЕНО: Проверяем существующее окно
        if let existingWindow = settingsWindow, existingWindow.isVisible {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Создаем новое окно настроек
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 650),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "Настройки Layout Switcher"
        newWindow.isReleasedWhenClosed = false // ИЗМЕНЕНО: предотвращаем автоматическое освобождение
        
        // ИЗМЕНЕНО: Создаем SettingsView с замыканием для закрытия окна
        let settingsView = SettingsView(settings: settings) { [weak newWindow] in
            newWindow?.close()
        }
        
        newWindow.contentView = NSHostingView(rootView: settingsView)
        newWindow.delegate = self
        
        // Сохраняем weak ссылку
        settingsWindow = newWindow
        
        newWindow.center()
        newWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Layout Switcher v1.0"
        alert.informativeText = """
        🔄 Переключатель раскладки клавиатуры
        
        Горячая клавиша: \(settings.displayString)
        
        Как использовать:
        1. Выделите текст в любом приложении
        2. Нажмите \(settings.displayString)
        3. Текст автоматически переключится между русской и английской раскладкой
        
        Примеры:
        • ghbdtn → привет
        • руддщ → hello
        
        Настройте свою горячую клавишу в настройках!
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    @objc private func quit() {
        // Очищаем горячие клавиши
        unregisterHotKey()
        removeShiftKeyMonitor()
        
        // Убираем наблюдатель
        NotificationCenter.default.removeObserver(self)
        
        NSApp.terminate(nil)
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // ИЗМЕНЕНО: Закрываем окно настроек если оно открыто
        settingsWindow?.close()
        settingsWindow = nil
        
        unregisterHotKey()
        removeShiftKeyMonitor()
        NotificationCenter.default.removeObserver(self)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}

// MARK: - Расширение для обработки закрытия окна настроек
extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        // ИЗМЕНЕНО: улучшенная проверка
        if let window = notification.object as? NSWindow, window == settingsWindow {
            // Обнуляем ссылку
            settingsWindow = nil
        }
    }
    
    // ИЗМЕНЕНО: добавлен метод
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        // Разрешаем закрытие окна
        return true
    }
}

// MARK: - Интерфейс настроек
struct SettingsView: View {
    @ObservedObject var settings: SettingsManager
    let onClose: (() -> Void)? // ИЗМЕНЕНО: добавлено замыкание
    
    @State private var isRecording = false
    @State private var tempKeyCode: UInt16 = 0
    @State private var tempModifiers: NSEvent.ModifierFlags = []
    @State private var tempCharacter: String = ""
    @State private var keyEventMonitor: Any?
    
    // Словарь кодов клавиш
    let keyMappings: [UInt16: String] = [
        0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G", 0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V",
        0x0B: "B", 0x0C: "Q", 0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T", 0x12: "1", 0x13: "2", 0x14: "3",
        0x15: "4", 0x16: "6", 0x17: "5", 0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0", 0x1E: "]",
        0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P", 0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
        0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".", 0x32: "`", 0x41: ".", 0x43: "*", 0x45: "+",
        0x47: "⌧", 0x4B: "/", 0x4C: "⏎", 0x4E: "-", 0x51: "=", 0x52: "0", 0x53: "1", 0x54: "2", 0x55: "3", 0x56: "4",
        0x57: "5", 0x58: "6", 0x59: "7", 0x5B: "8", 0x5C: "9", 0x24: "⏎", 0x30: "⇥", 0x31: "Space", 0x33: "⌫",
        0x35: "⎋", 0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4", 0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
        0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12"
    ]
    
    // ИЗМЕНЕНО: добавлен инициализатор
    init(settings: SettingsManager, onClose: (() -> Void)? = nil) {
        self.settings = settings
        self.onClose = onClose
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Заголовок
            HStack {
                Image(systemName: "keyboard")
                    .font(.title)
                    .foregroundColor(.blue)
                Text("Настройки горячих клавиш")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .padding(.top)
            
            Divider()
            
            // Текущая горячая клавиша
            VStack(alignment: .leading, spacing: 12) {
                Text("Текущая горячая клавиша:")
                    .font(.headline)
                
                HStack {
                    Text(settings.displayString)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue, lineWidth: 2)
                        )
                    
                    Spacer()
                }
            }
            
            // Переключатель двойного Shift
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Использовать двойное нажатие Shift", isOn: $settings.useDoubleShift)
                    .font(.headline)
                    .onChange(of: settings.useDoubleShift) { _ in
                        settings.saveSettings()
                    }
                
                if settings.useDoubleShift {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("💡 Быстро нажмите Shift два раза подряд для переключения раскладки")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Настройки тайминга
                        VStack(alignment: .leading, spacing: 8) {
                            Text("⏱️ Настройки тайминга:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            HStack {
                                Text("Минимальный интервал:")
                                    .font(.caption)
                                Spacer()
                                Text("\(Int(settings.minDoubleShiftInterval * 1000))мс")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            
                            Slider(value: $settings.minDoubleShiftInterval, in: 0.01...0.5, step: 0.01) {
                                Text("Минимум")
                            }
                            .onChange(of: settings.minDoubleShiftInterval) { _ in
                                // Обеспечиваем что минимум меньше максимума
                                if settings.minDoubleShiftInterval >= settings.maxDoubleShiftInterval {
                                    settings.maxDoubleShiftInterval = settings.minDoubleShiftInterval + 0.1
                                }
                                settings.saveSettings()
                            }
                            
                            HStack {
                                Text("Максимальный интервал:")
                                    .font(.caption)
                                Spacer()
                                Text("\(Int(settings.maxDoubleShiftInterval * 1000))мс")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            
                            Slider(value: $settings.maxDoubleShiftInterval, in: 0.1...2.0, step: 0.1) {
                                Text("Максимум")
                            }
                            .onChange(of: settings.maxDoubleShiftInterval) { _ in
                                // Обеспечиваем что максимум больше минимума
                                if settings.maxDoubleShiftInterval <= settings.minDoubleShiftInterval {
                                    settings.minDoubleShiftInterval = settings.maxDoubleShiftInterval - 0.1
                                }
                                settings.saveSettings()
                            }
                            
                            // Предустановленные значения тайминга
                            HStack {
                                Button("Быстро") {
                                    settings.minDoubleShiftInterval = 0.02
                                    settings.maxDoubleShiftInterval = 0.4
                                    settings.saveSettings()
                                }
                                .font(.caption)
                                .buttonStyle(PlainButtonStyle())
                                .foregroundColor(.green)
                                
                                Button("Средне") {
                                    settings.minDoubleShiftInterval = 0.05
                                    settings.maxDoubleShiftInterval = 0.8
                                    settings.saveSettings()
                                }
                                .font(.caption)
                                .buttonStyle(PlainButtonStyle())
                                .foregroundColor(.blue)
                                
                                Button("Медленно") {
                                    settings.minDoubleShiftInterval = 0.1
                                    settings.maxDoubleShiftInterval = 1.5
                                    settings.saveSettings()
                                }
                                .font(.caption)
                                .buttonStyle(PlainButtonStyle())
                                .foregroundColor(.orange)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.05))
                        .cornerRadius(6)
                        
                        HStack(spacing: 12) {
                            // Кнопка для тестирования основной функции
                            Button("🧪 Тест переключения") {
                                if let appDelegate = NSApp.delegate as? AppDelegate {
                                    appDelegate.testDoubleShift()
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .foregroundColor(.green)
                            .font(.caption)
                            
                            // Кнопка для ручного переключения
                            Button("🔄 Переключить сейчас") {
                                if let appDelegate = NSApp.delegate as? AppDelegate {
                                    appDelegate.switchLayout()
                                }
                            }
                            .buttonStyle(PlainButtonStyle())
                            .foregroundColor(.blue)
                            .font(.caption)
                        }
                        
                        Text("👆 Сначала выделите текст для проверки: 'ghbdtn' или 'привет'")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    .padding(.leading, 20)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.gray.opacity(0.1))
            .cornerRadius(8)
            
            Divider()
            
            // Кнопка записи новой комбинации
            VStack(alignment: .leading, spacing: 12) {
                Text("Изменить горячую клавишу:")
                    .font(.headline)
                
                Button(action: startRecording) {
                    HStack {
                        Image(systemName: isRecording ? "stop.circle.fill" : "play.circle.fill")
                        Text(isRecording ? "Нажмите новую комбинацию клавиш..." : "Записать новую комбинацию")
                    }
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(isRecording ? Color.red : Color.blue)
                    .cornerRadius(10)
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(settings.useDoubleShift) // Отключаем если используется двойной Shift
                
                if isRecording {
                    Text("💡 Нажмите желаемую комбинацию клавиш (например: ⌘F, ⌃⌥L, ⇧⌘K)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                } else if settings.useDoubleShift {
                    Text("🔒 Отключите двойной Shift для настройки других комбинаций")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                }
            }
            
            Divider()
            
            // Предустановленные варианты
            VStack(alignment: .leading, spacing: 12) {
                Text("Популярные комбинации:")
                    .font(.headline)
                
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                    // Специальная кнопка для двойного Shift
                    Button(action: {
                        settings.useDoubleShift = true
                        settings.saveSettings()
                    }) {
                        Text("⇧⇧")
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundColor(settings.useDoubleShift ? .white : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(settings.useDoubleShift ? Color.blue : Color.gray.opacity(0.2))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(settings.useDoubleShift ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    PresetButton(displayString: "⌘⇧L", modifiers: [.command, .shift], keyCode: 0x25, character: "L", settings: settings)
                    PresetButton(displayString: "⌘⇧T", modifiers: [.command, .shift], keyCode: 0x11, character: "T", settings: settings)
                    PresetButton(displayString: "⌃⌥L", modifiers: [.control, .option], keyCode: 0x25, character: "L", settings: settings)
                    PresetButton(displayString: "⌘F12", modifiers: [.command], keyCode: 0x6F, character: "F12", settings: settings)
                    PresetButton(displayString: "⌥⇧K", modifiers: [.option, .shift], keyCode: 0x28, character: "K", settings: settings)
                }
            }
            
            Spacer()
            
            // Кнопки действий
            HStack {
                Button("Сбросить по умолчанию") {
                    resetToDefault()
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.orange)
                
                Spacer()
                
                Button("Готово") {
                    // ИЗМЕНЕНО: используем замыкание
                    onClose?()
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundColor(.blue)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.bottom)
        }
        .padding()
        .frame(width: 600, height: 650)
        .frame(minWidth: 500, maxWidth: 800, minHeight: 600, maxHeight: 800)
        .onAppear {
            // ИЗМЕНЕНО: проверка существования монитора
            if keyEventMonitor == nil {
                setupKeyEventMonitor()
            }
        }
        .onDisappear {
            // Обязательно удаляем монитор при исчезновении view
            removeKeyEventMonitor()
        }
    }
    
    private func removeKeyEventMonitor() {
        if let monitor = keyEventMonitor {
            NSEvent.removeMonitor(monitor)
            keyEventMonitor = nil
        }
    }
    
    private func startRecording() {
        isRecording.toggle()
        if !isRecording && tempKeyCode != 0 {
            // Применяем записанную комбинацию
            settings.modifierFlags = tempModifiers
            settings.keyCode = tempKeyCode
            settings.keyCharacter = tempCharacter
            settings.saveSettings()
            
            // Сбрасываем временные значения
            tempKeyCode = 0
            tempModifiers = []
            tempCharacter = ""
        }
    }
    
    private func resetToDefault() {
        settings.modifierFlags = [.command, .shift]
        settings.keyCode = 0x25
        settings.keyCharacter = "L"
        settings.useDoubleShift = false // ИЗМЕНЕНО: добавлен сброс
        settings.saveSettings()
    }
    
    private func setupKeyEventMonitor() {
        // Для struct не нужен weak self, так как нет retain cycle
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if self.isRecording {
                self.tempModifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
                self.tempKeyCode = event.keyCode
                self.tempCharacter = self.keyMappings[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "?"
                
                // Останавливаем запись если есть модификаторы
                if !self.tempModifiers.isEmpty && self.tempKeyCode != 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.startRecording() // Останавливаем запись
                    }
                }
                
                return nil // Перехватываем событие
            }
            return event
        }
    }
}

struct PresetButton: View {
    let displayString: String
    let modifiers: NSEvent.ModifierFlags
    let keyCode: UInt16
    let character: String
    @ObservedObject var settings: SettingsManager
    
    var isSelected: Bool {
        !settings.useDoubleShift && settings.modifierFlags == modifiers && settings.keyCode == keyCode
    }
    
    var body: some View {
        Button(action: {
            settings.useDoubleShift = false // Отключаем двойной Shift
            settings.modifierFlags = modifiers
            settings.keyCode = keyCode
            settings.keyCharacter = character
            settings.saveSettings()
        }) {
            Text(displayString)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color.gray.opacity(0.2))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// Вспомогательная функция для создания четырехсимвольного кода
func fourCharCode(_ string: String) -> FourCharCode {
    assert(string.count == 4)
    var result: FourCharCode = 0
    for char in string.utf16 {
        result = (result << 8) + FourCharCode(char)
    }
    return result
}
