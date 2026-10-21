//
//  SettingsManager.swift
//  LayoutSwitcher
//
//  Хранение, валидация и автосохранение конфигурации.
//

import Foundation
import Combine
import os.log

@MainActor
final class SettingsManager: ObservableObject {
    @Published var configuration = HotKeyConfiguration() {
        didSet { validateConfiguration() }
    }
    
    private let userDefaults = UserDefaults.standard
    private let configKey = "hotkey_configuration"
    private var cancellables = Set<AnyCancellable>()
    
    @Published private(set) var configurationErrors: [String] = []
    
    var isConfigurationValid: Bool {
        configurationErrors.isEmpty
    }
    
    init() {
        loadConfiguration()
        setupAutoSave()
    }
    
    private func validateConfiguration() {
        var errors: [String] = []
        
        switch configuration.hotKeyMode {
        case .doubleShift, .doubleAlt:
            if configuration.minDoubleShiftInterval <= 0 {
                errors.append(L(.valMinIntervalGt0))
            }
            if configuration.maxDoubleShiftInterval <= configuration.minDoubleShiftInterval {
                errors.append(L(.valMaxGtMin))
            }
            if configuration.maxDoubleShiftInterval > 5.0 {
                errors.append(L(.valMaxTooBig))
            }
        case .ctrlShift, .fnShift, .singleAlt:
            break // Нет дополнительных проверок
        case .customHotkey:
            if configuration.keyCharacter.isEmpty {
                errors.append(L(.valKeyEmpty))
            }
            if configuration.modifierFlags == 0 {
                errors.append(L(.valNeedModifier))
            }
        }
        
        if configuration.autoSwitchMode != .off && configuration.minWordLength < 2 {
            errors.append(L(.valMinWordLength))
        }

        if !configuration.layout1ID.isEmpty,
           !configuration.layout2ID.isEmpty,
           configuration.layout1ID == configuration.layout2ID {
            errors.append(L(.valLayoutsSame))
        }

        configurationErrors = errors
        
        if !errors.isEmpty {
            Logger.ui.warning("Configuration validation errors: \(errors.joined(separator: ", "))")
        }
    }
    
    private func setupAutoSave() {
        $configuration
            .debounce(for: .seconds(0.5), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] config in
                self?.saveConfiguration(config)
            }
            .store(in: &cancellables)
    }
    
    private func loadConfiguration() {
        guard let data = userDefaults.data(forKey: configKey),
              let config = try? JSONDecoder().decode(HotKeyConfiguration.self, from: data) else {
            Logger.ui.info("Loading default configuration")
            return
        }
        configuration = config
        Logger.ui.info("Loaded configuration: \(config.displayString)")
    }
    
    private func saveConfiguration(_ config: HotKeyConfiguration) {
        guard let data = try? JSONEncoder().encode(config) else { return }
        userDefaults.set(data, forKey: configKey)
        NotificationCenter.default.post(
            name: .hotKeyConfigurationChanged,
            object: nil,
            userInfo: ["configuration": config]
        )
        Logger.ui.info("Saved configuration: \(config.displayString)")
    }
}
