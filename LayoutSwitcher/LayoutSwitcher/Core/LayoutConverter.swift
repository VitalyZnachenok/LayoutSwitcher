//
//  LayoutConverter.swift
//  LayoutSwitcher
//
//  Запасная статическая таблица русский ↔ английский (QWERTY/ЙЦУКЕН).
//  Основной путь — DynamicKeyMapping по реальным раскладкам системы; таблица
//  используется, когда динамический маппинг недоступен.
//

import Foundation
import os.log

struct LayoutConverter {
    static let rusToEng: [Character: Character] = [
        "й": "q", "ц": "w", "у": "e", "к": "r", "е": "t", "н": "y", "г": "u", "ш": "i", "щ": "o", "з": "p", "х": "[", "ъ": "]",
        "ф": "a", "ы": "s", "в": "d", "а": "f", "п": "g", "р": "h", "о": "j", "л": "k", "д": "l", "ж": ";", "э": "'",
        "я": "z", "ч": "x", "с": "c", "м": "v", "и": "b", "т": "n", "ь": "m", "б": ",", "ю": ".", ".": "/",
        "Й": "Q", "Ц": "W", "У": "E", "К": "R", "Е": "T", "Н": "Y", "Г": "U", "Ш": "I", "Щ": "O", "З": "P", "Х": "{", "Ъ": "}",
        "Ф": "A", "Ы": "S", "В": "D", "А": "F", "П": "G", "Р": "H", "О": "J", "Л": "K", "Д": "L", "Ж": ":", "Э": "\"",
        "Я": "Z", "Ч": "X", "С": "C", "М": "V", "И": "B", "Т": "N", "Ь": "M", "Б": "<", "Ю": ">", ",": "?",
        "ё": "`", "Ё": "~", "№": "#", " ": " "
    ]
    
    static let engToRus: [Character: Character] = {
        // Строим обратный словарь поэлементно, чтобы дубликаты значений
        // не приводили к краху (Dictionary(uniqueKeysWithValues:) бросает fatalError).
        var result: [Character: Character] = [:]
        result.reserveCapacity(rusToEng.count)
        for (rus, eng) in rusToEng {
            result[eng] = rus
        }
        return result
    }()
    
    private static let russianCharSet: Set<Character> = Set(rusToEng.keys)
    private static let englishCharSet: Set<Character> = Set(engToRus.keys)
    
    /// Конвертация с автоопределением направления по содержимому.
    static func convert(_ text: String) -> String {
        let isRussian = detectRussian(text)
        Logger.conversion.debug("Static table: converting from \(isRussian ? "Russian" : "English")")
        return convert(text, currentLayoutIsRussian: isRussian)
    }
    
    /// Конвертация с явно заданным направлением (без автодетекции).
    static func convert(_ text: String, currentLayoutIsRussian: Bool) -> String {
        let mapping = currentLayoutIsRussian ? rusToEng : engToRus
        return String(text.map { mapping[$0] ?? $0 })
    }
    
    /// true, если в тексте больше символов русской раскладки, чем английской.
    static func detectRussian(_ text: String) -> Bool {
        var rusCount = 0
        var engCount = 0
        for char in text.lowercased() {
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
