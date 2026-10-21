//
//  SoundManager.swift
//  LayoutSwitcher
//
//  Системные звуки и их локализованные имена.
//

import AppKit
import os.log

@MainActor
final class SoundManager {
    static let shared = SoundManager()
    private var currentTestSound: NSSound?
    private init() {}
    
    func playSound(named soundName: String, volume: Float) {
        guard let sound = NSSound(named: soundName) else {
            Logger.ui.warning("Sound not found: \(soundName)")
            NSSound.beep()
            return
        }
        sound.volume = volume
        sound.play()
        Logger.ui.debug("Playing sound: \(soundName) at volume \(volume)")
    }
    
    func testSound(_ soundName: String, volume: Float) {
        currentTestSound?.stop()
        currentTestSound = nil
        
        guard let sound = NSSound(named: soundName) else {
            Logger.ui.warning("Test sound not found: \(soundName)")
            NSSound.beep()
            return
        }
        sound.volume = volume
        currentTestSound = sound
        sound.play()
        Logger.ui.debug("Playing test sound: \(soundName) at volume \(volume)")
    }
}

struct SoundConfiguration {
    static let availableSounds: [String] = [
        "Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse",
        "Ping", "Pop", "Purr", "Sosumi", "Submarine", "Tink"
    ]
    
    /// Локализованные имена звуков по языковым кодам. Для английского используются
    /// системные (английские) названия звуков macOS.
    static let soundDisplayNames: [String: [String: String]] = [
        "Basso": ["ru": "Бассо", "en": "Basso"],
        "Blow": ["ru": "Дуновение", "en": "Blow"],
        "Bottle": ["ru": "Бутылка", "en": "Bottle"],
        "Frog": ["ru": "Лягушка", "en": "Frog"],
        "Funk": ["ru": "Фанк", "en": "Funk"],
        "Glass": ["ru": "Стекло", "en": "Glass"],
        "Hero": ["ru": "Герой", "en": "Hero"],
        "Morse": ["ru": "Морзе", "en": "Morse"],
        "Ping": ["ru": "Пинг", "en": "Ping"],
        "Pop": ["ru": "Поп", "en": "Pop"],
        "Purr": ["ru": "Мурлыканье", "en": "Purr"],
        "Sosumi": ["ru": "Сосуми", "en": "Sosumi"],
        "Submarine": ["ru": "Подлодка", "en": "Submarine"],
        "Tink": ["ru": "Тинк", "en": "Tink"]
    ]
    
    static func localizedName(for soundName: String) -> String {
        let code = LocalizationManager.shared.effectiveLanguageCode
        return soundDisplayNames[soundName]?[code] ?? soundName
    }
}
