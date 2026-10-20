import AppKit
import Carbon.HIToolbox

/// Registers ⌃⌥⌘B system-wide with Carbon's hot key API, which — unlike a
/// global NSEvent monitor — does not require Accessibility permission.
final class HotkeyManager {
    static let shared = HotkeyManager()

    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {}

    func start() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, _ in
                DispatchQueue.main.async { HotkeyManager.shared.onTrigger?() }
                return noErr
            },
            1, &spec, nil, &handlerRef
        )
        RegisterEventHotKey(
            UInt32(kVK_ANSI_B), UInt32(controlKey | optionKey | cmdKey),
            EventHotKeyID(signature: 0x42414241, id: 1), // 'BABA'
            GetEventDispatcherTarget(), 0, &hotKeyRef
        )
    }
}
