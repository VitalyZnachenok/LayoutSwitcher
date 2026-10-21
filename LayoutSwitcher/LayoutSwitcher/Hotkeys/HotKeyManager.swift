//
//  HotKeyManager.swift
//  LayoutSwitcher
//
//  Глобальный event tap, распознавание горячих клавиш, отслеживание набираемого
//  слова, автодетекция неправильной раскладки и сама конвертация
//  (Accessibility → откат на буфер обмена).
//

import AppKit
import Combine
import Carbon.HIToolbox
import os.log

@MainActor
final class HotKeyManager: ObservableObject {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// С какими опциями создан текущий tap (блокирующий — для custom-комбинации).
    private var tapIsBlocking = false

    // КРИТИЧНО: event tap крутится на ВЫДЕЛЕННОМ потоке с собственным run loop,
    // а НЕ на main run loop. Иначе любой стопор главного потока блокирует доставку
    // глобального ввода (active session tap) — вплоть до полного зависания клавиатуры.
    // Поток создаётся один раз (лениво) и переиспользуется при пересоздании tap.
    private nonisolated(unsafe) var eventRunLoop: CFRunLoop?
    private var eventThread: Thread?
    
    // Состояние распознавания, живущее на потоке event tap (nonisolated(unsafe):
    // мутируется только из callback'а; с главного потока изменения планируются
    // через performOnEventThread).
    private nonisolated(unsafe) var doubleTap = DoubleTapDetector(minInterval: 0.05, maxInterval: 0.8)
    private nonisolated(unsafe) var lastComboTriggerTime: TimeInterval = 0
    private let comboDebounceInterval: TimeInterval = 0.5
    private nonisolated(unsafe) var altPressedAlone = false
    private nonisolated(unsafe) var altPressTime: TimeInterval = 0
    private let singleAltMaxHold: TimeInterval = 0.4
    private nonisolated(unsafe) var tracker = WordTracker()
    /// Снимок счётчиков ПЕРЕД текущим событием: событие горячей клавиши само
    /// сбрасывает счётчики до того, как convertLayout успеет их прочитать.
    private nonisolated(unsafe) var lastSnapshot = WordTracker.Snapshot()
    
    // Кэш конфигурации для чтения из callback'а (не трогаем settings с чужого потока).
    private nonisolated(unsafe) var cachedHotKeyMode: HotKeyMode = .customHotkey
    private nonisolated(unsafe) var cachedKeyCode: UInt16 = 0x25
    private nonisolated(unsafe) var cachedModifierFlags: UInt = 0
    private nonisolated(unsafe) var cachedAutoSwitchMode: AutoSwitchMode = .off
    private nonisolated(unsafe) var cachedMinWordLength: Int = 3
    
    private let settings: SettingsManager
    private let detection = LayoutDetectionService()
    let metrics = ConversionMetrics()

    // Защита от повторного входа: без неё удержание customHotkey (авто-повтор клавиши
    // системой) спавнит несколько параллельных convertLayout(), гоняющихся за одним
    // NSPasteboard. Распространяется и на авто-исправление.
    private var isConverting = false
    
    private var cancellables = Set<AnyCancellable>()
    private var accessibilityCheckTimer: Timer?
    private var lastAccessibilityStatus: Bool = false
    
    init(settings: SettingsManager) {
        self.settings = settings
        lastAccessibilityStatus = AXIsProcessTrusted()
        updateCachedConfiguration()
        setupConfigurationObserver()
        setupAccessibilityMonitoring()
        setupEventTap()
        // Прогреваем детекторы, чтобы не тормозить первый ввод.
        let cfg = settings.configuration
        Task { @MainActor in
            self.detection.warmUp(configuration: cfg)
        }
    }
    
    deinit {
        accessibilityCheckTimer?.invalidate()
        accessibilityCheckTimer = nil
        
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource, let rl = eventRunLoop {
            CFRunLoopRemoveSource(rl, source, .commonModes)
        }
        // Останавливаем выделенный поток: помечаем отмену и будим его run loop.
        eventThread?.cancel()
        if let rl = eventRunLoop {
            CFRunLoopStop(rl)
            CFRunLoopWakeUp(rl)
        }
    }
    
    // MARK: - Configuration
    
    /// Обновляет кэш конфигурации для callback'а. Состояние, которое целиком живёт
    /// на потоке event tap (детектор двойного нажатия, счётчики слова), меняется
    /// там же через performOnEventThread.
    private func updateCachedConfiguration() {
        let config = settings.configuration
        cachedHotKeyMode = config.hotKeyMode
        cachedKeyCode = config.keyCode
        cachedModifierFlags = config.modifierFlags
        cachedAutoSwitchMode = config.autoSwitchMode
        cachedMinWordLength = config.minWordLength
        let minInterval = config.minDoubleShiftInterval
        let maxInterval = config.maxDoubleShiftInterval
        performOnEventThread { [weak self] in
            guard let self else { return }
            self.doubleTap = DoubleTapDetector(minInterval: minInterval, maxInterval: maxInterval)
            self.tracker.reset()
        }
        Logger.hotkeys.debug("Configuration cached: mode=\(self.cachedHotKeyMode.rawValue), autoSwitch=\(self.cachedAutoSwitchMode.rawValue)")
    }
    
    private func setupConfigurationObserver() {
        NotificationCenter.default
            .publisher(for: .hotKeyConfigurationChanged)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateCachedConfiguration()
                // Пересоздаём tap только если изменились его опции (блокирующий ↔
                // слушающий). Любая другая настройка (громкость, звуки, пара
                // раскладок) tap не касается — лишнее пересоздание только
                // провоцирует «протухшие» разрешения TCC.
                let needsBlocking = self.settings.configuration.hotKeyMode.needsBlockingTap
                if self.eventTap == nil || needsBlocking != self.tapIsBlocking {
                    self.setupEventTap()
                }
            }
            .store(in: &cancellables)
    }
    
    private func setupAccessibilityMonitoring() {
        // Проверяем права каждые 5 секунд и реагируем только на изменение статуса.
        accessibilityCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let hasAccess = AXIsProcessTrusted()
            guard hasAccess != self.lastAccessibilityStatus else { return }
            self.lastAccessibilityStatus = hasAccess
            
            Task { @MainActor in
                if hasAccess && self.eventTap == nil {
                    Logger.hotkeys.info("✅ Accessibility permissions granted - setting up event tap")
                    self.setupEventTap()
                } else if !hasAccess && self.eventTap != nil {
                    Logger.hotkeys.warning("⚠️ Accessibility permissions revoked - disabling event tap")
                    self.tearDownEventTap()
                }
                NotificationCenter.default.post(name: .accessibilityStatusChanged, object: nil)
            }
        }
    }
    
    // MARK: - Event tap
    
    private func tearDownEventTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        if let source = runLoopSource {
            if let rl = eventRunLoop {
                CFRunLoopRemoveSource(rl, source, .commonModes)
            }
            runLoopSource = nil
        }
    }
    
    private func setupEventTap() {
        guard AXIsProcessTrusted() else {
            Logger.hotkeys.warning("⚠️ Cannot setup event tap - accessibility permissions not granted")
            return
        }
        
        tearDownEventTap()
        ensureEventThread()

        // Клики мыши слушаем всегда: смена позиции курсора сбрасывает счётчики слова.
        let eventMask = (1 << CGEventType.keyDown.rawValue) |
                        (1 << CGEventType.flagsChanged.rawValue) |
                        (1 << CGEventType.leftMouseDown.rawValue) |
                        (1 << CGEventType.rightMouseDown.rawValue)
        
        // .listenOnly гарантирует, что события ВСЕГДА проходят к системе; блокирующий
        // tap нужен только custom-комбинации, чтобы её символ не попадал в текст.
        let blocking = cachedHotKeyMode.needsBlockingTap
        let tapOptions: CGEventTapOptions = blocking ? .defaultTap : .listenOnly
        
        guard let eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: tapOptions,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { _, type, event, refcon in
                // КРИТИЧНО: всегда пропускаем событие при любой ошибке.
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotKeyManager>.fromOpaque(refcon).takeUnretainedValue()
                
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = manager.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }
                
                let shouldBlock = manager.handleTapEvent(event, type: type)
                if shouldBlock && manager.cachedHotKeyMode.needsBlockingTap {
                    return nil
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            Logger.hotkeys.error("❌ Failed to create event tap")
            return
        }
        
        self.eventTap = eventTap
        self.tapIsBlocking = blocking
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let rl = eventRunLoop {
            CFRunLoopAddSource(rl, runLoopSource, .commonModes)
            CFRunLoopWakeUp(rl)
        } else {
            Logger.hotkeys.error("❌ Event run loop is nil - falling back to main run loop")
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: eventTap, enable: true)
        
        Logger.hotkeys.info("✅ Event tap created for mode: \(self.cachedHotKeyMode.rawValue), options: \(blocking ? "defaultTap" : "listenOnly")")
    }

    /// Лениво создаёт выделенный поток с собственным run loop для event tap.
    /// Блокирует вызывающий (main) поток через семафор до публикации CFRunLoop.
    private func ensureEventThread() {
        guard eventThread == nil else { return }

        let readySemaphore = DispatchSemaphore(value: 0)
        let thread = Thread { [weak self] in
            let rl = CFRunLoopGetCurrent()
            self?.eventRunLoop = rl
            readySemaphore.signal()
            // Пустой run loop без source мгновенно выходит, поэтому крутим с таймаутом.
            while !Thread.current.isCancelled {
                CFRunLoopRunInMode(.defaultMode, 0.5, false)
            }
        }
        thread.qualityOfService = .userInteractive
        thread.name = "com.layoutswitcher.eventtap"
        thread.start()

        readySemaphore.wait()
        eventThread = thread
    }
    
    /// Выполняет блок на потоке event tap — там, где живёт состояние распознавания.
    /// До создания потока конкурентного доступа нет, блок выполняется сразу.
    private func performOnEventThread(_ block: @escaping @Sendable () -> Void) {
        guard let rl = eventRunLoop else {
            block()
            return
        }
        CFRunLoopPerformBlock(rl, CFRunLoopMode.commonModes.rawValue, block)
        CFRunLoopWakeUp(rl)
    }
    
    /// Сброс отслеживания слова из MainActor-контекста (после конвертации).
    private func resetWordTrackingFromMainActor() {
        performOnEventThread { [weak self] in
            self?.tracker.reset()
        }
    }
    
    // MARK: - Tap thread: event handling
    
    /// Точка входа из callback'а. Возвращает true, если событие нужно проглотить.
    nonisolated func handleTapEvent(_ event: CGEvent, type: CGEventType) -> Bool {
        // События, сгенерированные самим приложением (⌘C, ⌘V, Shift+←), не считаем.
        if event.getIntegerValueField(.eventSourceUserData) == SelfEventMarker.value {
            return false
        }
        
        lastSnapshot = tracker.snapshot
        feedTyping(event, type: type)
        
        guard type == .keyDown || type == .flagsChanged else { return false }
        
        switch cachedHotKeyMode {
        case .customHotkey:
            return handleCustomHotkey(event, type: type)
        case .doubleShift:
            return handleDoubleModifier(event, type: type, targetFlag: .maskShift, keyCodes: [KeyCode.leftShift, KeyCode.rightShift])
        case .doubleAlt:
            return handleDoubleModifier(event, type: type, targetFlag: .maskAlternate, keyCodes: [KeyCode.leftAlt, KeyCode.rightAlt])
        case .singleAlt:
            return handleSingleAlt(event, type: type)
        case .ctrlShift:
            return handleCombo(event, type: type, required: [.maskControl, .maskShift], forbidden: [.maskCommand, .maskAlternate], name: "Ctrl+Shift")
        case .fnShift:
            return handleCombo(event, type: type, required: [.maskSecondaryFn, .maskShift], forbidden: [.maskCommand, .maskAlternate, .maskControl], name: "Fn+Shift")
        }
    }
    
    nonisolated private func triggerConversion(afterDelay delay: UInt64 = 0) {
        Task { @MainActor in
            if delay > 0 { try? await Task.sleep(nanoseconds: delay) }
            await self.convertLayout()
        }
    }
    
    nonisolated private func handleCustomHotkey(_ event: CGEvent, type: CGEventType) -> Bool {
        guard type == .keyDown else { return false }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let expected = CGEventFlags(rawValue: UInt64(cachedModifierFlags))
        guard HotkeyMatcher.matches(keyCode: keyCode, flags: event.flags,
                                    expectedKeyCode: cachedKeyCode, expectedFlags: expected) else {
            return false
        }
        Logger.hotkeys.info("Custom hotkey triggered")
        triggerConversion()
        return true
    }
    
    nonisolated private func handleDoubleModifier(
        _ event: CGEvent, type: CGEventType, targetFlag: CGEventFlags, keyCodes: [UInt16]
    ) -> Bool {
        // Обычная клавиша между двумя нажатиями модификатора — это набор текста
        // с Shift/Alt, а не двойное нажатие.
        if type == .keyDown {
            doubleTap.cancel()
            return false
        }
        guard type == .flagsChanged else { return false }
        
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        guard keyCodes.contains(keyCode) else { return false }
        
        let flags = event.flags
        var otherModifiers: CGEventFlags = HotkeyMatcher.relevantModifiers
        otherModifiers.remove(targetFlag)
        if !flags.intersection(otherModifiers).isEmpty {
            doubleTap.cancel()
            return false
        }
        
        guard flags.contains(targetFlag) else { return false }  // отпускание не считаем
        if doubleTap.press(at: Date.timeIntervalSinceReferenceDate) {
            Logger.hotkeys.info("Double press detected!")
            triggerConversion(afterDelay: Timing.doubleShiftDelay)
        }
        return false
    }
    
    nonisolated private func handleCombo(_ event: CGEvent, type: CGEventType,
                                         required: CGEventFlags, forbidden: CGEventFlags, name: String) -> Bool {
        guard type == .flagsChanged else { return false }
        let flags = event.flags
        guard flags.contains(required), flags.intersection(forbidden).isEmpty else { return false }
        
        let now = Date.timeIntervalSinceReferenceDate
        guard now - lastComboTriggerTime > comboDebounceInterval else { return false }
        lastComboTriggerTime = now
        
        Logger.hotkeys.info("✅ \(name) detected!")
        triggerConversion()
        return false
    }
    
    /// Одиночный тап Alt: срабатывает при отпускании, если Alt был нажат один,
    /// без других модификаторов и обычных клавиш, и удержание было коротким.
    nonisolated private func handleSingleAlt(_ event: CGEvent, type: CGEventType) -> Bool {
        if type == .keyDown {
            altPressedAlone = false
            return false
        }
        guard type == .flagsChanged else { return false }
        
        let flags = event.flags
        let altDown = flags.contains(.maskAlternate)
        let hasOthers = !flags.intersection([.maskCommand, .maskControl, .maskShift]).isEmpty
        
        if altDown {
            altPressedAlone = !hasOthers
            altPressTime = Date.timeIntervalSinceReferenceDate
        } else if altPressedAlone {
            altPressedAlone = false
            let now = Date.timeIntervalSinceReferenceDate
            if now - altPressTime < singleAltMaxHold {
                guard now - lastComboTriggerTime > comboDebounceInterval else { return false }
                lastComboTriggerTime = now
                Logger.hotkeys.info("✅ Single Alt tap detected!")
                triggerConversion()
            }
        }
        return false
    }
    
    // MARK: - Tap thread: word tracking
    
    /// Переводит CGEvent в событие WordTracker и отдаёт завершённые слова детектору.
    nonisolated private func feedTyping(_ event: CGEvent, type: CGEventType) {
        let trackerEvent: WordTracker.Event
        switch type {
        case .leftMouseDown, .rightMouseDown:
            trackerEvent = .cursorMove
        case .keyDown:
            let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags
            if keyCode == KeyCode.space {
                trackerEvent = .space
            } else if keyCode == KeyCode.return || keyCode == KeyCode.tab {
                trackerEvent = .newline
            } else if keyCode == KeyCode.delete {
                trackerEvent = .backspace
            } else if KeyCode.navigation.contains(keyCode) {
                trackerEvent = .cursorMove
            } else if !flags.intersection([.maskCommand, .maskControl, .maskAlternate]).isEmpty {
                trackerEvent = .command
            } else {
                // Символ, реально набранный в текущей раскладке.
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                event.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &length, unicodeString: &chars)
                guard length > 0, let ch = String(utf16CodeUnits: chars, count: length).first else { return }
                trackerEvent = WordTracker.isWordCharacter(ch) ? .character(ch) : .punctuation
            }
        default:
            return
        }
        
        if let word = tracker.feed(trackerEvent) {
            guard cachedAutoSwitchMode != .off, word.count >= cachedMinWordLength else { return }
            Task { @MainActor in await self.analyzeWord(word) }
        }
    }
    
    // MARK: - Auto-switch
    
    /// Анализирует завершённое слово на MainActor: проверяет исключения и детектор.
    private func analyzeWord(_ word: String) async {
        if IsSecureEventInputEnabled() {
            Logger.conversion.debug("Auto-switch skipped: secure input active")
            return
        }
        if let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
           settings.configuration.excludedAppBundleIDs.contains(bundleID) {
            Logger.conversion.debug("Auto-switch skipped: excluded app \(bundleID)")
            return
        }
        if AXTextAccess.isSecureFieldFocused() {
            Logger.conversion.debug("Auto-switch skipped: secure text field focused")
            return
        }
        
        let cfg = settings.configuration
        guard let detected = detection.detect(word: word, configuration: cfg) else { return }
        Logger.conversion.info("⚠️ Wrong layout suspected: '\(word)' → '\(detected.converted)'")
        
        switch cfg.autoSwitchMode {
        case .warnSound:
            SoundManager.shared.playSound(named: cfg.wrongLayoutSoundName, volume: cfg.soundVolume)
        case .autoSwitch:
            await performAutoCorrection(word: word, converted: detected.converted, targetLayoutID: detected.targetLayoutID)
        case .off:
            break
        }
    }
    
    /// Авто-исправление: слово только что завершено границей, курсор стоит после
    /// «слово<граница>». Сначала Accessibility (прямое редактирование поля), иначе —
    /// ⌘C/⌘V с выделением через Shift+←.
    private func performAutoCorrection(word: String, converted: String, targetLayoutID: String) async {
        guard !isConverting else {
            Logger.conversion.debug("Auto-correction skipped: conversion in progress")
            return
        }
        isConverting = true
        defer { isConverting = false }
        
        let cfg = settings.configuration
        
        if cfg.useAccessibilityReplacement, let target = AXTextAccess.focusedTextTarget(), !target.isSecure,
           target.selection.length == 0,
           let range = AXTextAccess.lastWordRange(in: target.value, before: target.selection.location),
           target.value.substring(with: range) == word {
            let caret = target.selection.location + (converted as NSString).length - range.length
            if AXTextAccess.replace(range: range, with: converted, in: target, caretAt: caret) {
                finishAutoCorrection(word: word, converted: converted, targetLayoutID: targetLayoutID, cfg: cfg)
                return
            }
            Logger.conversion.debug("Auto-correction: AX replacement unavailable — clipboard path")
        }
        
        let pasteboard = NSPasteboard.general
        let clipboardState = ClipboardState(pasteboard: pasteboard)
        let boundary = 1  // граница, на которой слово было завершено
        
        do {
            try await moveCursor(boundary, left: true)
            try await selectBack(word.count)
            
            pasteboard.clearContents()
            pasteboard.setString(converted, forType: .string)
            try await Task.sleep(nanoseconds: Timing.pasteDelay)
            try await simulateKeyPress(key: KeyCode.v, modifiers: .maskCommand)
            try await moveCursor(boundary, left: false)
            
            try await Task.sleep(nanoseconds: Timing.restoreDelay)
            clipboardState.restore(to: pasteboard)
            
            finishAutoCorrection(word: word, converted: converted, targetLayoutID: targetLayoutID, cfg: cfg)
        } catch {
            Logger.conversion.error("Auto-correction failed: \(error)")
            clipboardState.restore(to: pasteboard)
        }
    }
    
    private func finishAutoCorrection(word: String, converted: String, targetLayoutID: String, cfg: HotKeyConfiguration) {
        LayoutManager.switchTo(layoutID: targetLayoutID)
        resetWordTrackingFromMainActor()
        SoundManager.shared.playSound(named: cfg.wrongLayoutSoundName, volume: cfg.soundVolume)
        Logger.conversion.info("✅ Auto-corrected: '\(word)' → '\(converted)'")
    }
    
    // MARK: - Conversion
    
    /// Результат конвертации текста: новый текст и раскладка, в которую переключиться.
    private struct Converted {
        let text: String
        /// nil — направление неизвестно, переключаемся на противоположную из пары.
        let targetLayoutID: String?
    }
    
    /// Динамический маппинг по реальным раскладкам с запасной таблицей ru/en.
    private func convertText(_ text: String, cfg: HotKeyConfiguration) -> Converted? {
        if let dynamic = DynamicKeyMapping.convert(text, layout1ID: cfg.layout1ID, layout2ID: cfg.layout2ID) {
            return Converted(text: dynamic.text, targetLayoutID: dynamic.targetLayoutID)
        }
        let fallback = LayoutConverter.convert(text)
        guard fallback != text else { return nil }
        return Converted(text: fallback, targetLayoutID: nil)
    }
    
    private func switchLayout(after converted: Converted, cfg: HotKeyConfiguration) {
        if let id = converted.targetLayoutID {
            LayoutManager.switchTo(layoutID: id)
        } else {
            LayoutManager.switchToOpposite(layout1ID: cfg.layout1ID, layout2ID: cfg.layout2ID)
        }
    }
    
    func convertLayout() async {
        guard !isConverting else {
            Logger.conversion.debug("Conversion already in progress - ignoring re-entrant trigger")
            return
        }
        isConverting = true
        defer { isConverting = false }

        let startTime = Date()
        Logger.conversion.info("Starting layout conversion...")
        
        guard AXIsProcessTrusted() else {
            await fail(.accessibilityPermissionDenied)
            return
        }
        if IsSecureEventInputEnabled() {
            await fail(.secureField)
            return
        }
        
        let cfg = settings.configuration
        let snapshot = lastSnapshot
        
        if cfg.useAccessibilityReplacement {
            switch convertViaAccessibility(cfg: cfg) {
            case .done:
                metrics.recordSuccess(duration: Date().timeIntervalSince(startTime), viaAccessibility: true)
                await playSuccessSound()
                return
            case .failed(let error):
                await fail(error)
                return
            case .unavailable:
                break
            }
        }
        
        await convertViaClipboard(cfg: cfg, snapshot: snapshot, startTime: startTime)
    }
    
    private enum AXOutcome {
        case done
        case failed(LayoutError)
        case unavailable
    }
    
    /// Путь через Accessibility: читаем выделение (или последнее слово перед
    /// курсором) прямо из поля и заменяем его на месте.
    private func convertViaAccessibility(cfg: HotKeyConfiguration) -> AXOutcome {
        guard let target = AXTextAccess.focusedTextTarget() else { return .unavailable }
        if target.isSecure { return .failed(.secureField) }
        
        let range: NSRange
        if target.selection.length > 0 {
            range = target.selection
        } else if let wordRange = AXTextAccess.lastWordRange(in: target.value, before: target.selection.location) {
            range = wordRange
        } else {
            return .unavailable
        }
        
        let text = target.value.substring(with: range)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .unavailable }
        guard let converted = convertText(text, cfg: cfg) else {
            Logger.conversion.warning("Text unchanged after conversion")
            return .failed(.conversionFailed("unchanged"))
        }
        
        let newLength = (converted.text as NSString).length
        let caret = target.selection.length > 0
            ? range.location + newLength
            : target.selection.location + newLength - range.length
        
        guard AXTextAccess.replace(range: range, with: converted.text, in: target, caretAt: caret) else {
            return .unavailable
        }
        Logger.conversion.info("AX: '\(text.prefix(50))' → '\(converted.text.prefix(50))'")
        switchLayout(after: converted, cfg: cfg)
        resetWordTrackingFromMainActor()
        return .done
    }
    
    /// Классический путь: ⌘C выделения (или выделение последнего слова по
    /// счётчикам клавиш через Shift+←), конвертация, ⌘V, восстановление буфера.
    private func convertViaClipboard(cfg: HotKeyConfiguration, snapshot: WordTracker.Snapshot, startTime: Date) async {
        let pasteboard = NSPasteboard.general
        let clipboardState = ClipboardState(pasteboard: pasteboard)
        
        do {
            // 1. Сначала пробуем уже выделенный пользователем текст.
            try await simulateKeyPress(key: KeyCode.c, modifiers: .maskCommand)
            var copiedText = await waitForCopiedText(initialChangeCount: clipboardState.changeCount, pasteboard: pasteboard)
            
            // Сколько позиций вернуть курсор вправо после вставки (для слова перед границей).
            var restoreCursorRight = 0
            
            // 2. Выделения нет — выделяем последнее набранное слово по счётчикам клавиш.
            if copiedText?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true {
                if snapshot.wordLength > 0 {
                    try await selectBack(snapshot.wordLength)
                } else if snapshot.wordBeforeBoundaryLength > 0 && snapshot.boundaryCount > 0 {
                    try await moveCursor(snapshot.boundaryCount, left: true)
                    try await selectBack(snapshot.wordBeforeBoundaryLength)
                    restoreCursorRight = snapshot.boundaryCount
                } else {
                    Logger.conversion.warning("Nothing selected and no tracked word - aborting")
                    clipboardState.restore(to: pasteboard)
                    await fail(.noTextSelected)
                    return
                }
                let beforeCount = pasteboard.changeCount
                try await simulateKeyPress(key: KeyCode.c, modifiers: .maskCommand)
                copiedText = await waitForCopiedText(initialChangeCount: beforeCount, pasteboard: pasteboard)
            }
            
            guard let text = copiedText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                Logger.conversion.warning("Failed to copy text - restoring clipboard")
                clipboardState.restore(to: pasteboard)
                await fail(.clipboardOperationFailed)
                return
            }
            
            Logger.conversion.info("Source text (\(text.count) chars): '\(text.prefix(50))'")
            
            // 3. Конвертация.
            guard let converted = convertText(text, cfg: cfg) else {
                Logger.conversion.warning("Text unchanged after conversion")
                clipboardState.restore(to: pasteboard)
                await fail(.conversionFailed("unchanged"))
                return
            }
            Logger.conversion.info("Converted (\(converted.text.count) chars): '\(converted.text.prefix(50))'")
            
            // 4. Вставляем результат вместо выделения.
            pasteboard.clearContents()
            pasteboard.setString(converted.text, forType: .string)
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
            switchLayout(after: converted, cfg: cfg)
            resetWordTrackingFromMainActor()
            
            metrics.recordSuccess(duration: Date().timeIntervalSince(startTime), viaAccessibility: false)
            await playSuccessSound()
        } catch {
            Logger.conversion.error("Conversion failed: \(error)")
            clipboardState.restore(to: pasteboard)
            await fail(.clipboardOperationFailed)
        }
    }
    
    private func fail(_ error: LayoutError) async {
        Logger.conversion.warning("Conversion failed: \(error.localizedDescription)")
        metrics.recordFailure()
        await playErrorSound()
    }
    
    /// Ожидает изменения буфера обмена после Cmd+C, опрашивая `changeCount`.
    private func waitForCopiedText(initialChangeCount: Int, pasteboard: NSPasteboard) async -> String? {
        var waited: UInt64 = 0
        while waited < Timing.clipboardPollTimeout {
            if pasteboard.changeCount > initialChangeCount {
                return pasteboard.string(forType: .string)
            }
            try? await Task.sleep(nanoseconds: Timing.clipboardPollInterval)
            waited += Timing.clipboardPollInterval
        }
        guard pasteboard.changeCount > initialChangeCount else { return nil }
        return pasteboard.string(forType: .string)
    }
    
    // MARK: - Synthetic keys
    
    /// Источник событий, помеченный нашим маркером, чтобы event tap игнорировал
    /// сгенерированные нами нажатия (Cmd+C, Cmd+V, Shift+←).
    private func makeMarkedEventSource() -> CGEventSource? {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.userData = SelfEventMarker.value
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
        keyDown.setIntegerValueField(.eventSourceUserData, value: SelfEventMarker.value)
        keyUp.setIntegerValueField(.eventSourceUserData, value: SelfEventMarker.value)
        
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
    
    // MARK: - Sounds
    
    private func playSuccessSound() async {
        guard settings.configuration.soundEnabled else { return }
        SoundManager.shared.playSound(named: settings.configuration.successSoundName,
                                      volume: settings.configuration.soundVolume)
    }
    
    private func playErrorSound() async {
        guard settings.configuration.soundEnabled else { return }
        SoundManager.shared.playSound(named: settings.configuration.errorSoundName,
                                      volume: settings.configuration.soundVolume)
    }
}
