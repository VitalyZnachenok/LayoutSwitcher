//
//  DynamicKeyMapping.swift
//  LayoutSwitcher
//
//  Динамический маппинг символов между двумя раскладками через UCKeyTranslate.
//  В отличие от жёстко зашитой таблицы, строит соответствие из реальных раскладок
//  системы по их 'uchr'-данным, поэтому работает для произвольных пар (не только RU/EN).
//

import Foundation
import Carbon.HIToolbox

@MainActor
enum DynamicKeyMapping {
    /// Кэш построенных карт: ключ "fromID→toID".
    private static var cache: [String: [Character: Character]] = [:]
    
    static func invalidateCache() { cache.removeAll() }
    
    /// Виртуальные коды печатных клавиш основного блока (буквы/цифры/пунктуация).
    private static let printableKeycodes: [UInt16] = Array(0...50)
    
    /// Результат конвертации: преобразованный текст и ID раскладки, в которую он
    /// относится (для переключения клавиатуры на правильную раскладку).
    struct Result {
        let text: String
        let targetLayoutID: String
        /// Сколько символов изменилось.
        let changed: Int
    }
    
    /// Конвертирует текст между раскладками пары. Направление определяется по
    /// СОДЕРЖИМОМУ текста: выбирается та сторона, которая меняет больше символов,
    /// поэтому работает, даже если клавиатура уже переключена на другую раскладку,
    /// и не сбивается на смешанном тексте вроде «ghbdtn привет».
    /// Возвращает nil, если ни одно направление не меняет текст (вызывающий — фолбэк).
    static func convert(_ text: String, layout1ID: String, layout2ID: String) -> Result? {
        let (id1, id2) = LayoutManager.resolvePair(layout1ID: layout1ID, layout2ID: layout2ID)
        guard !id1.isEmpty, !id2.isEmpty,
              let source1 = LayoutManager.source(for: id1),
              let source2 = LayoutManager.source(for: id2) else {
            return nil
        }
        
        let map12 = buildMap(from: source1, fromID: id1, to: source2, toID: id2)
        let map21 = buildMap(from: source2, fromID: id2, to: source1, toID: id1)
        
        let r12 = apply(map12, to: text)
        let r21 = apply(map21, to: text)
        guard r12.changed > 0 || r21.changed > 0 else { return nil }
        if r12.changed >= r21.changed {
            return Result(text: r12.text, targetLayoutID: id2, changed: r12.changed)
        }
        return Result(text: r21.text, targetLayoutID: id1, changed: r21.changed)
    }
    
    /// Конвертация в заданном направлении: текст набран в раскладке `fromID`,
    /// нужно получить то, что получилось бы в `toID`. nil, если раскладки не найдены.
    static func convert(_ text: String, from fromID: String, to toID: String) -> String? {
        guard let from = LayoutManager.source(for: fromID),
              let to = LayoutManager.source(for: toID) else { return nil }
        return apply(buildMap(from: from, fromID: fromID, to: to, toID: toID), to: text).text
    }
    
    private static func apply(_ map: [Character: Character], to text: String) -> (text: String, changed: Int) {
        var changed = 0
        var out = String()
        out.reserveCapacity(text.count)
        for ch in text {
            if let mapped = map[ch] {
                out.append(mapped)
                changed += 1
            } else {
                out.append(ch)
            }
        }
        return (out, changed)
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
