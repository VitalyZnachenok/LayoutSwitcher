//
//  LayoutManager.swift
//  LayoutSwitcher
//
//  Низкоуровневая работа с раскладками через TIS: получение текущей, списка
//  установленных (с кэшем), переключение по точному ID и переключение на
//  «противоположную» в паре. Пустой ID в паре означает автоопределение
//  (английская/кириллическая).
//

import Foundation
import Carbon.HIToolbox
import os.log

@MainActor
enum LayoutManager {
    /// ID-фрагменты служебных источников, которые не являются настоящими раскладками.
    private static let serviceMarkers = [".SCIM", "Emoji", "Dictation", "CharacterPalette", "PressAndHold"]
    
    /// Кэш установленных раскладок. `TISCreateInputSourceList` перечисляет все
    /// источники ввода системы, а список нужен на каждую конвертацию, каждое слово
    /// автодетекции и каждую перерисовку окна настроек. Сбрасывается по системному
    /// уведомлению о смене набора раскладок.
    private static var cachedLayouts: [TISInputSource]?
    private static var observerInstalled = false
    
    private static func installObserverIfNeeded() {
        guard !observerInstalled else { return }
        observerInstalled = true
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                cachedLayouts = nil
                DynamicKeyMapping.invalidateCache()
                Logger.conversion.info("Keyboard input sources changed — caches invalidated")
            }
        }
    }
    
    /// ID текущей активной раскладки.
    static func currentLayoutID() -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return "" }
        return sourceID(source)
    }
    
    /// Список установленных раскладок (только выбираемые клавиатурные источники).
    static func installedLayouts() -> [TISInputSource] {
        installObserverIfNeeded()
        if let cached = cachedLayouts { return cached }
        guard let sources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        let layouts = sources.filter { source in
            let id = sourceID(source)
            guard !id.isEmpty else { return false }
            return !serviceMarkers.contains { id.contains($0) }
        }
        cachedLayouts = layouts
        return layouts
    }
    
    static func source(for layoutID: String) -> TISInputSource? {
        installedLayouts().first { sourceID($0) == layoutID }
    }
    
    /// Точный ID источника (kTISPropertyInputSourceID).
    nonisolated static func sourceID(_ source: TISInputSource) -> String {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "" }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
    
    /// Человекочитаемое имя раскладки (kTISPropertyLocalizedName).
    nonisolated static func sourceName(_ source: TISInputSource) -> String {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) else { return sourceID(source) }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }
    
    /// Языки раскладки по данным системы (kTISPropertyInputSourceLanguages),
    /// например ["ru"] или ["en"]. Первый — основной.
    nonisolated static func languages(of source: TISInputSource) -> [String] {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else { return [] }
        let array = Unmanaged<CFArray>.fromOpaque(ptr).takeUnretainedValue() as? [String] ?? []
        return array.map { String($0.prefix(2)).lowercased() }
    }
    
    /// Основной язык раскладки по ID ("ru", "en", …) или nil.
    static func primaryLanguage(ofLayoutID layoutID: String) -> String? {
        guard let source = source(for: layoutID) else { return nil }
        return languages(of: source).first
    }
    
    /// Активирует раскладку по точному ID. Возвращает true при успехе.
    @discardableResult
    static func switchTo(layoutID: String) -> Bool {
        guard !layoutID.isEmpty, let source = source(for: layoutID) else {
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
    
    /// Для текущей активной раскладки возвращает (текущая, другая) из пары,
    /// или nil, если активная раскладка не входит в пару.
    static func currentSide(layout1ID: String, layout2ID: String) -> (current: String, other: String)? {
        let (id1, id2) = resolvePair(layout1ID: layout1ID, layout2ID: layout2ID)
        guard !id1.isEmpty, !id2.isEmpty else { return nil }
        let current = currentLayoutID()
        if current == id1 { return (id1, id2) }
        if current == id2 { return (id2, id1) }
        return nil
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
