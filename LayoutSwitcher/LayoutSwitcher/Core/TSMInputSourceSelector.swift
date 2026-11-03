//
//  TSMInputSourceSelector.swift
//  LayoutSwitcher
//
//  Переключение раскладки «как из системного меню ввода»: просим приложение
//  с фокусом клавиатуры само выбрать источник через его порт Text Services
//  Manager (сообщение ID 7).
//
//  Зачем: при включённой опции «Автоматически переключаться на источник ввода
//  документа» (TextInputGlobalPropertyPerContextInput) у каждого приложения
//  своя раскладка. TISSelectInputSource из фонового процесса меняет только
//  глобальное значение; активное приложение при следующем нажатии клавиши
//  возвращает свою запомненную раскладку, и переключение «не прилипает».
//  Сообщение в TSM-порт меняет раскладку именно у документа активного
//  приложения, поэтому результат сохраняется.
//
//  Символы приватные и разрешаются через dlsym во время выполнения; при любой
//  неудаче возвращается false, и вызывающий откатывается на TISSelectInputSource.
//  Подход заимствован у macism (https://github.com/laishulu/macism).
//

import AppKit
import Carbon.HIToolbox
import os.log

enum TSMInputSourceSelector {
    private typealias KeyFocusFn = @convention(c) (
        UnsafeMutablePointer<ProcessSerialNumber>, UnsafeMutablePointer<DarwinBoolean>
    ) -> Int32
    private typealias PSNToPIDFn = @convention(c) (
        UnsafePointer<ProcessSerialNumber>, UnsafeMutablePointer<pid_t>
    ) -> OSStatus
    private typealias RemotePortFn = @convention(c) (
        CFAllocator?, CFString, pid_t
    ) -> Unmanaged<CFMessagePort>?
    private typealias FlattenFn = @convention(c) (
        TISInputSource, UnsafeMutablePointer<Unmanaged<AnyObject>?>
    ) -> DarwinBoolean
    
    private static let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
    
    private static func symbol<T>(_ name: String, _: T.Type) -> T? {
        dlsym(rtldDefault, name).map { unsafeBitCast($0, to: T.self) }
    }
    
    /// Таймаут отправки/ответа: приложение могло зависнуть, не ждём его вечно.
    private static let requestTimeout: CFTimeInterval = 0.3
    
    /// PID процесса, который получает события клавиатуры. Это не всегда
    /// frontmost-приложение: неактивирующаяся панель тоже может держать фокус.
    private static func keyFocusPID() -> pid_t? {
        guard let keyFocus = symbol("CPSGetKeyFocusProcess", KeyFocusFn.self),
              let psnToPID = symbol("GetProcessPID", PSNToPIDFn.self) else {
            return nil
        }
        var psn = ProcessSerialNumber()
        var ignored: DarwinBoolean = false
        var pid: pid_t = -1
        guard keyFocus(&psn, &ignored) == 0,
              psnToPID(&psn, &pid) == noErr,
              pid > 0 else {
            return nil
        }
        return pid
    }
    
    /// Просит приложение с фокусом ввода выбрать `source`. true — приложение
    /// подтвердило переключение. false — путь недоступен (нет символов, фокус у
    /// нас самих, приложение не ответило или вернуло ошибку).
    static func selectInFocusedApp(_ source: TISInputSource) -> Bool {
        guard let remotePort = symbol("CFMessagePortCreatePerProcessRemote", RemotePortFn.self),
              let flatten = symbol("_CreateFlattenedInputSource", FlattenFn.self),
              let pid = keyFocusPID() else {
            Logger.conversion.debug("TSM: private symbols or key-focus process unavailable")
            return false
        }
        // Синхронный запрос к собственному TSM-порту с главного потока упрётся
        // в таймаут (порт обслуживается этим же run loop).
        guard pid != ProcessInfo.processInfo.processIdentifier else { return false }
        
        var flatRef: Unmanaged<AnyObject>?
        guard flatten(source, &flatRef).boolValue, let flat = flatRef?.takeRetainedValue() else {
            Logger.conversion.debug("TSM: cannot flatten input source")
            return false
        }
        let request = ["tsmInputSourceSelectedInpSrcKey": flat] as CFDictionary
        guard let data = CFPropertyListCreateData(nil, request, .xmlFormat_v1_0, 0, nil)?.takeRetainedValue(),
              let port = remotePort(nil, "com.apple.tsm.portname" as CFString, pid)?.takeRetainedValue() else {
            Logger.conversion.debug("TSM: no TSM port for pid \(pid)")
            return false
        }
        
        var reply: Unmanaged<CFData>?
        let status = CFMessagePortSendRequest(
            port, 7, data, requestTimeout, requestTimeout, CFRunLoopMode.defaultMode.rawValue, &reply
        )
        guard status == kCFMessagePortSuccess else {
            Logger.conversion.debug("TSM: request to pid \(pid) failed (\(status))")
            return false
        }
        if let replyData = reply?.takeRetainedValue(),
           let dict = CFPropertyListCreateWithData(nil, replyData, 0, nil, nil)?.takeRetainedValue() as? [String: Any],
           let error = dict["tsmInputModeReplyToServerErrorKey"] as? Int,
           error != 0 {
            Logger.conversion.debug("TSM: pid \(pid) rejected the switch (\(error))")
            return false
        }
        return true
    }
}
