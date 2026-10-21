//
//  WordTracker.swift
//  LayoutSwitcher
//
//  Чистый автомат отслеживания набираемого слова по нажатиям клавиш. Не зависит
//  от CGEvent, поэтому тестируется напрямую. Используется для конвертации
//  последнего слова без выделения (запасной путь без Accessibility) и для
//  передачи завершённых слов детектору неправильной раскладки.
//

import Foundation

struct WordTracker: Equatable {
    /// Событие ввода, уже очищенное от деталей CGEvent.
    enum Event: Equatable {
        case character(Character)   // печатный символ в текущей раскладке
        case space
        case newline                // Enter / Tab
        case backspace
        case cursorMove             // стрелки, Home/End, Escape, Forward Delete, клик мышью
        case command                // комбинация с ⌘/⌃/⌥ — не набор текста
        case punctuation            // прочий печатный символ (граница слова)
    }
    
    /// Снимок счётчиков для конвертации последнего слова.
    struct Snapshot: Equatable {
        /// Длина слова прямо перед курсором (0, если курсор после границы).
        var wordLength = 0
        /// Длина слова перед границей (пробелами), если курсор стоит после них.
        var wordBeforeBoundaryLength = 0
        /// Сколько пробелов между этим словом и курсором.
        var boundaryCount = 0
    }
    
    private(set) var snapshot = Snapshot()
    /// Символы текущего слова (ограничены `maxBufferLength`).
    private(set) var typingBuffer: String = ""
    
    let maxBufferLength: Int
    
    init(maxBufferLength: Int = 64) {
        self.maxBufferLength = maxBufferLength
    }
    
    /// Полный сброс (курсор переместился, слово неизвестно).
    mutating func reset() {
        snapshot = Snapshot()
        typingBuffer = ""
    }
    
    /// Обрабатывает событие. Возвращает завершённое слово, если событие закрыло его
    /// границей (пробел, пунктуация, перевод строки), иначе nil.
    @discardableResult
    mutating func feed(_ event: Event) -> String? {
        switch event {
        case .character(let ch):
            snapshot.wordLength += 1
            snapshot.wordBeforeBoundaryLength = 0
            snapshot.boundaryCount = 0
            typingBuffer.append(ch)
            if typingBuffer.count > maxBufferLength {
                typingBuffer.removeFirst(typingBuffer.count - maxBufferLength)
            }
            return nil
            
        case .space:
            // Пробел — мягкая граница: запоминаем длину слова перед ним.
            if snapshot.wordLength > 0 {
                snapshot.wordBeforeBoundaryLength = snapshot.wordLength
                snapshot.boundaryCount = 1
            } else if snapshot.wordBeforeBoundaryLength > 0 {
                snapshot.boundaryCount += 1
            }
            snapshot.wordLength = 0
            return finishWord()
            
        case .punctuation:
            snapshot.wordLength = 0
            snapshot.wordBeforeBoundaryLength = 0
            snapshot.boundaryCount = 0
            return finishWord()
            
        case .newline:
            let word = finishWord()
            reset()
            return word
            
        case .backspace:
            if snapshot.wordLength > 0 {
                snapshot.wordLength -= 1
                if !typingBuffer.isEmpty { typingBuffer.removeLast() }
            } else {
                reset()
            }
            return nil
            
        case .cursorMove, .command:
            reset()
            return nil
        }
    }
    
    private mutating func finishWord() -> String? {
        let word = typingBuffer
        typingBuffer = ""
        return word.isEmpty ? nil : word
    }
    
    /// Классификация символа для `feed`.
    static func isWordCharacter(_ ch: Character) -> Bool {
        ch.isLetter || ch == "'" || ch == "-"
    }
}
