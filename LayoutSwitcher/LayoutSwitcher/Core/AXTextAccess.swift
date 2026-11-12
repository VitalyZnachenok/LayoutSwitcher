//
//  AXTextAccess.swift
//  LayoutSwitcher
//
//  Чтение и замена текста в сфокусированном поле через Accessibility API —
//  без буфера обмена и синтетических нажатий. Если приложение не отдаёт текст
//  или не позволяет менять выделение, вызывающий откатывается на ⌘C/⌘V.
//

import AppKit
import ApplicationServices
import os.log

@MainActor
enum AXTextAccess {
    struct Target {
        let element: AXUIElement
        /// Полный текст поля.
        let value: NSString
        /// Выделение в UTF-16 единицах (length 0 — просто курсор).
        let selection: NSRange
        let isSecure: Bool
    }
    
    /// Поля длиннее не читаем целиком — это огромные документы, им хватит буфера обмена.
    static let maxValueLength = 2_000_000
    
    // MARK: Reading
    
    static func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return nil
        }
        return (focused as! AXUIElement)
    }
    
    /// Сфокусировано защищённое текстовое поле (пароль).
    static func isSecureFieldFocused() -> Bool {
        guard let element = focusedElement() else { return false }
        return isSecure(element)
    }
    
    private static func isSecure(_ element: AXUIElement) -> Bool {
        let subrole: String? = attribute(kAXSubroleAttribute, of: element)
        return subrole == (kAXSecureTextFieldSubrole as String)
    }
    
    /// Текст и выделение сфокусированного поля или nil, если поле не текстовое,
    /// не отдаёт значение или не позволяет менять выделение.
    static func focusedTextTarget() -> Target? {
        guard let element = focusedElement() else { return nil }
        let secure = isSecure(element)
        
        guard let selectionValue: AXValue = attribute(kAXSelectedTextRangeAttribute, of: element),
              AXValueGetType(selectionValue) == .cfRange else {
            return nil
        }
        var cfRange = CFRange()
        guard AXValueGetValue(selectionValue, .cfRange, &cfRange) else { return nil }
        
        if let count: Int = attribute(kAXNumberOfCharactersAttribute, of: element), count > maxValueLength {
            Logger.conversion.debug("AX: field too large (\(count) chars) — clipboard path")
            return nil
        }
        guard let value: String = attribute(kAXValueAttribute, of: element) else { return nil }
        let nsValue = value as NSString
        guard nsValue.length <= maxValueLength else { return nil }
        
        // Замена возможна только если оба атрибута доступны на запись.
        guard isSettable(kAXSelectedTextRangeAttribute, of: element),
              isSettable(kAXSelectedTextAttribute, of: element) else {
            return nil
        }
        
        let selection = NSRange(location: cfRange.location, length: cfRange.length)
        guard selection.location >= 0, NSMaxRange(selection) <= nsValue.length else { return nil }
        return Target(element: element, value: nsValue, selection: selection, isSecure: secure)
    }
    
    // MARK: Writing
    
    /// Заменяет `range` на `text` и ставит курсор в `caretAt`. true — содержимое
    /// поля изменилось (независимо от кода возврата AX). false — ничего не
    /// изменилось, можно безопасно откатиться на буфер обмена.
    static func replace(range: NSRange, with text: String, in target: Target, caretAt: Int) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else { return false }
        guard AXUIElementSetAttributeValue(target.element, kAXSelectedTextRangeAttribute as CFString, rangeValue) == .success else {
            Logger.conversion.debug("AX: cannot set selection range")
            return false
        }
        let setStatus = AXUIElementSetAttributeValue(target.element, kAXSelectedTextAttribute as CFString, text as CFTypeRef)
        
        // Кодам возврата верить нельзя в обе стороны: одни приложения отвечают
        // success и ничего не делают, другие (Telegram) возвращают ошибку, но текст
        // заменяют. Поэтому исход определяем по фактическому содержимому поля.
        let original = target.value as String
        var after: String? = attribute(kAXValueAttribute, of: target.element)
        if setStatus != .success {
            Logger.conversion.debug("AX: set selected text returned \(setStatus.rawValue) — verifying field content")
            // Замена могла примениться асинхронно — даём полю немного времени.
            var attempts = 0
            while after == nil || after == original, attempts < 5 {
                Thread.sleep(forTimeInterval: 0.01)
                after = attribute(kAXValueAttribute, of: target.element)
                attempts += 1
            }
        }
        if let after {
            guard after != original else {
                Logger.conversion.debug("AX: value unchanged after replacement — clipboard path")
                return false
            }
            let ns = after as NSString
            let expected = NSRange(location: range.location, length: (text as NSString).length)
            if NSMaxRange(expected) > ns.length || ns.substring(with: expected) != text {
                Logger.conversion.warning("AX: replacement applied, but the field content differs from the expected text")
            }
        } else if setStatus != .success {
            // Ошибка и проверить нечем — считаем, что замены не было.
            Logger.conversion.debug("AX: cannot set selected text (\(setStatus.rawValue))")
            return false
        }
        
        var caret = CFRange(location: caretAt, length: 0)
        if let caretValue = AXValueCreate(.cfRange, &caret) {
            AXUIElementSetAttributeValue(target.element, kAXSelectedTextRangeAttribute as CFString, caretValue)
        }
        return true
    }
    
    // MARK: Word lookup
    
    /// Диапазон последнего слова перед позицией `caret` (UTF-16). Между словом и
    /// курсором допускается до `maxSkip` пробелов/знаков препинания; перевод строки
    /// прерывает поиск. nil, если слова нет.
    nonisolated static func lastWordRange(in value: NSString, before caret: Int, maxSkip: Int = 4) -> NSRange? {
        let s = value as String
        guard caret >= 0, caret <= value.length,
              let caretIndex = String.Index(utf16Offset: caret, in: s) as String.Index? else { return nil }
        
        var end = caretIndex
        var skipped = 0
        while end > s.startIndex {
            let prev = s.index(before: end)
            let ch = s[prev]
            if WordTracker.isWordCharacter(ch) { break }
            if ch.isNewline { return nil }
            skipped += 1
            if skipped > maxSkip { return nil }
            end = prev
        }
        
        var start = end
        while start > s.startIndex {
            let prev = s.index(before: start)
            guard WordTracker.isWordCharacter(s[prev]) else { break }
            start = prev
        }
        guard start < end else { return nil }
        let location = start.utf16Offset(in: s)
        return NSRange(location: location, length: end.utf16Offset(in: s) - location)
    }
    
    // MARK: Helpers
    
    private static func attribute<T>(_ name: String, of element: AXUIElement) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &ref) == .success, let ref else { return nil }
        return ref as? T
    }
    
    private static func isSettable(_ name: String, of element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, name as CFString, &settable) == .success else { return false }
        return settable.boolValue
    }
}
