//
//  HotkeyRecognizers.swift
//  LayoutSwitcher
//
//  Чистая логика распознавания горячих клавиш (без CGEvent и акторов), чтобы её
//  можно было тестировать: точное совпадение модификаторов и детектор двойного
//  нажатия модификатора.
//

import Foundation
import CoreGraphics

enum HotkeyMatcher {
    /// Модификаторы, которые участвуют в сравнении (без Caps Lock, Fn, NumPad и т.п.).
    static let relevantModifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
    
    /// Точное совпадение: те же клавиша и ровно тот же набор модификаторов.
    /// Раньше проверялось `flags.contains(expected)`, и ⌘⇧L срабатывал также на ⌃⌘⇧L и ⌥⌘⇧L.
    static func matches(keyCode: UInt16, flags: CGEventFlags,
                        expectedKeyCode: UInt16, expectedFlags: CGEventFlags) -> Bool {
        guard keyCode == expectedKeyCode else { return false }
        return flags.intersection(relevantModifiers) == expectedFlags.intersection(relevantModifiers)
    }
}

/// Детектор двойного нажатия одного модификатора (⇧⇧, ⌥⌥).
/// Любое нажатие обычной клавиши между двумя нажатиями отменяет серию: иначе
/// «Hello World», набранное быстро с двумя Shift, запускало конвертацию.
struct DoubleTapDetector: Equatable {
    var minInterval: TimeInterval
    var maxInterval: TimeInterval
    private var lastPressTime: TimeInterval = 0
    private var pressCount = 0
    
    init(minInterval: TimeInterval, maxInterval: TimeInterval) {
        self.minInterval = minInterval
        self.maxInterval = maxInterval
    }
    
    /// Нажатие модификатора в момент `time`. true — зафиксировано двойное нажатие.
    mutating func press(at time: TimeInterval) -> Bool {
        let sinceLast = lastPressTime > 0 ? time - lastPressTime : Double.infinity
        if sinceLast > maxInterval {
            pressCount = 1
            lastPressTime = time
            return false
        }
        if sinceLast < minInterval {
            // Дребезг — игнорируем, серию не трогаем.
            return false
        }
        pressCount += 1
        if pressCount >= 2 {
            cancel()
            return true
        }
        lastPressTime = time
        return false
    }
    
    /// Сброс серии (другая клавиша нажата, другие модификаторы и т.п.).
    mutating func cancel() {
        pressCount = 0
        lastPressTime = 0
    }
}
