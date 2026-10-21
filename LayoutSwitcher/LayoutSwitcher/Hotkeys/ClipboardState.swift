//
//  ClipboardState.swift
//  LayoutSwitcher
//
//  Снимок буфера обмена со всеми типами данных (текст, RTF, картинки, файлы)
//  и его восстановление после конвертации через ⌘C/⌘V.
//

import AppKit
import os.log

struct ClipboardState {
    let changeCount: Int
    private let items: [[NSPasteboard.PasteboardType: Data]]
    private let fallbackString: String?
    
    /// Данные крупнее этого объёма (на тип) не копируем — только строковое представление.
    static let maxItemBytes = 16 * 1024 * 1024
    
    init(pasteboard: NSPasteboard) {
        changeCount = pasteboard.changeCount
        fallbackString = pasteboard.string(forType: .string)
        var snapshot: [[NSPasteboard.PasteboardType: Data]] = []
        for item in pasteboard.pasteboardItems ?? [] {
            var entry: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                guard let data = item.data(forType: type), data.count <= Self.maxItemBytes else { continue }
                entry[type] = data
            }
            if !entry.isEmpty { snapshot.append(entry) }
        }
        items = snapshot
    }
    
    /// Восстанавливает содержимое буфера обмена.
    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            let restored = items.map { entry -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in entry { item.setData(data, forType: type) }
                return item
            }
            if pasteboard.writeObjects(restored) {
                Logger.conversion.debug("Restored clipboard (\(items.count) item(s))")
                return
            }
        }
        if let string = fallbackString {
            pasteboard.setString(string, forType: .string)
            Logger.conversion.debug("Restored clipboard content (string)")
        } else {
            Logger.conversion.debug("Cleared clipboard (was empty)")
        }
    }
}
