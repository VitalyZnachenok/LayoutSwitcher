//
//  Detectors.swift
//  LayoutSwitcher
//
//  Детекция ввода в неправильной раскладке: словарный движок (NSSpellChecker),
//  статистический движок (триграммные модели из Resources/ngram-<lang>.bin) и
//  сервис, который выбирает движок, строит конверсию по реальной паре раскладок
//  и работает для любых языков, а не только для русского и английского.
//

import AppKit
import os.log

// MARK: - N-gram language model

/// Символьная триграммная модель: оценивает «правдоподобие» слова как текста на
/// данном языке. Таблица квантованных −log₂ p(c | a b) собрана скриптом
/// scripts/ngram/build_ngram.py из частотных словарей (см. scripts/ngram/README.md).
final class NGramLanguageModel {
    /// Оценка для слова с символом вне алфавита модели: это точно не слово данного языка.
    static let unknownScore: Double = -16.0
    private static let quant: Double = 8.0
    
    let language: String
    private let index: [Character: Int]   // символ → индекс 1…N (0 — граница слова)
    private let n: Int                     // размер алфавита + 1
    private let table: [UInt8]
    
    private static var cache: [String: NGramLanguageModel] = [:]
    private static let cacheLock = NSLock()
    
    /// Модель языка из ресурсов приложения (с кэшем) или nil, если файла нет.
    static func load(language: String, bundle: Bundle = .main) -> NGramLanguageModel? {
        cacheLock.lock(); defer { cacheLock.unlock() }
        if let cached = cache[language] { return cached }
        guard let url = bundle.url(forResource: "ngram-\(language)", withExtension: "bin"),
              let data = try? Data(contentsOf: url),
              let model = NGramLanguageModel(language: language, data: data) else {
            return nil
        }
        cache[language] = model
        return model
    }
    
    static func isAvailable(language: String, bundle: Bundle = .main) -> Bool {
        load(language: language, bundle: bundle) != nil
    }
    
    /// Формат: "NGM1", uint16 N, N × uint32 code point, (N+1)^3 байт таблицы.
    init?(language: String, data: Data) {
        guard data.count > 6, data[0] == 0x4E, data[1] == 0x47, data[2] == 0x4D, data[3] == 0x31 else { return nil }
        let count = Int(data[4]) | (Int(data[5]) << 8)
        var index: [Character: Int] = [:]
        var offset = 6
        guard data.count >= offset + count * 4 else { return nil }
        for i in 0..<count {
            let cp = UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8)
                   | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
            offset += 4
            guard let scalar = Unicode.Scalar(cp) else { return nil }
            index[Character(scalar)] = i + 1
        }
        let n = count + 1
        guard data.count == offset + n * n * n else { return nil }
        self.language = language
        self.index = index
        self.n = n
        self.table = [UInt8](data[offset...])
    }
    
    /// Средний log₂-вероятности перехода на символ (чем выше — тем «нормальнее»
    /// слово для этого языка). Символ вне алфавита даёт `unknownScore`.
    func score(_ word: String) -> Double {
        var seq: [Int] = [0, 0]
        seq.reserveCapacity(word.count + 3)
        for ch in word.lowercased() {
            guard let i = index[ch] else { return Self.unknownScore }
            seq.append(i)
        }
        seq.append(0)
        guard seq.count > 2 else { return Self.unknownScore }
        var total = 0.0
        for i in 2..<seq.count {
            let q = table[(seq[i - 2] * n + seq[i - 1]) * n + seq[i]]
            total -= Double(q) / Self.quant
        }
        return total / Double(seq.count - 2)
    }
}

// MARK: - N-gram detector

/// Сравнивает правдоподобие слова «как набрано» (в модели языка текущей раскладки)
/// с правдоподобием его конверсии (в модели языка другой раскладки).
final class NGramLayoutDetector {
    /// Минимальный перевес (log₂ на переход). Подобран на отложенной выборке
    /// частотных словарей: ~0.1 % ложных срабатываний при ~97 % распознавания.
    static let threshold: Double = 2.0
    
    private let bundle: Bundle
    
    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }
    
    func hasModels(_ typedLanguage: String, _ otherLanguage: String) -> Bool {
        NGramLanguageModel.isAvailable(language: typedLanguage, bundle: bundle)
            && NGramLanguageModel.isAvailable(language: otherLanguage, bundle: bundle)
    }
    
    /// nil — нет модели для одного из языков; иначе true, если конверсия
    /// существенно правдоподобнее набранного варианта.
    func isWrongLayout(word: String, converted: String, typedLanguage: String, otherLanguage: String) -> Bool? {
        guard let typedModel = NGramLanguageModel.load(language: typedLanguage, bundle: bundle),
              let otherModel = NGramLanguageModel.load(language: otherLanguage, bundle: bundle) else {
            return nil
        }
        let typedScore = typedModel.score(word)
        let convertedScore = otherModel.score(converted)
        return convertedScore - typedScore > Self.threshold
    }
    
    func warmUp(languages: [String]) {
        for language in languages {
            _ = NGramLanguageModel.load(language: language, bundle: bundle)?.score("warmup")
        }
    }
}

// MARK: - Spell-checker detector

/// Словарный детектор: слово некорректно в языке текущей раскладки, а его
/// конверсия — корректное слово в языке другой раскладки.
@MainActor
final class WrongLayoutDetector {
    private let checker = NSSpellChecker.shared
    private var resolved: [String: String?] = [:]
    
    /// nil — для одного из языков нет словаря; иначе результат проверки.
    func isWrongLayout(word: String, converted: String, typedLanguage: String, otherLanguage: String) -> Bool? {
        guard word.allSatisfy({ $0.isLetter }) else { return false }
        guard let typedLang = resolve(typedLanguage), let otherLang = resolve(otherLanguage) else { return nil }
        guard isMisspelled(word, language: typedLang) else { return false }
        return !isMisspelled(converted, language: otherLang)
    }
    
    func warmUp(languages: [String]) {
        for language in languages {
            if let lang = resolve(language) { _ = isMisspelled("warmup", language: lang) }
        }
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
    
    /// "ru" → "ru_RU" и т.п. по списку доступных словарей (с кэшем).
    private func resolve(_ code: String) -> String? {
        if let cached = resolved[code] { return cached }
        let available = checker.availableLanguages
        let lower = code.lowercased()
        let result = available.first { $0.lowercased() == lower }
            ?? available.first { $0.lowercased().hasPrefix(lower) }
        resolved[code] = result
        return result
    }
}

// MARK: - Detection service

/// Собирает всё вместе: текущая сторона пары раскладок, конверсия слова по
/// реальным раскладкам (с запасной таблицей ru/en), выбор движка.
@MainActor
final class LayoutDetectionService {
    struct Detection {
        let converted: String
        /// Раскладка, в которой слово должно было быть набрано.
        let targetLayoutID: String
    }
    
    private let spell = WrongLayoutDetector()
    private let ngram: NGramLayoutDetector
    
    init(bundle: Bundle = .main) {
        ngram = NGramLayoutDetector(bundle: bundle)
    }
    
    func warmUp(configuration cfg: HotKeyConfiguration) {
        let (id1, id2) = LayoutManager.resolvePair(layout1ID: cfg.layout1ID, layout2ID: cfg.layout2ID)
        let languages = [id1, id2].compactMap { LayoutManager.primaryLanguage(ofLayoutID: $0) }
        ngram.warmUp(languages: languages)
        spell.warmUp(languages: languages)
    }
    
    /// Возвращает конверсию, если слово похоже на набранное в неправильной раскладке.
    func detect(word: String, configuration cfg: HotKeyConfiguration) -> Detection? {
        guard word.count >= cfg.minWordLength else { return nil }
        guard let side = LayoutManager.currentSide(layout1ID: cfg.layout1ID, layout2ID: cfg.layout2ID) else {
            Logger.conversion.debug("Detection skipped: current layout is not in the pair")
            return nil
        }
        
        let typedLanguage = LayoutManager.primaryLanguage(ofLayoutID: side.current)
        let otherLanguage = LayoutManager.primaryLanguage(ofLayoutID: side.other)
        
        var converted = DynamicKeyMapping.convert(word, from: side.current, to: side.other)
        if converted == nil, let typedLanguage, ["ru", "en"].contains(typedLanguage) {
            converted = LayoutConverter.convert(word, currentLayoutIsRussian: typedLanguage == "ru")
        }
        guard let converted, converted != word else { return nil }
        guard let typedLanguage, let otherLanguage, typedLanguage != otherLanguage else { return nil }
        
        let hit: Bool
        switch cfg.detectionEngine {
        case .ngram:
            if let result = ngram.isWrongLayout(word: word, converted: converted,
                                                typedLanguage: typedLanguage, otherLanguage: otherLanguage) {
                hit = result
            } else {
                // Нет модели для языка — словарь как запасной вариант.
                hit = spell.isWrongLayout(word: word, converted: converted,
                                          typedLanguage: typedLanguage, otherLanguage: otherLanguage) ?? false
            }
        case .spellChecker:
            hit = spell.isWrongLayout(word: word, converted: converted,
                                      typedLanguage: typedLanguage, otherLanguage: otherLanguage) ?? false
        }
        return hit ? Detection(converted: converted, targetLayoutID: side.other) : nil
    }
}
