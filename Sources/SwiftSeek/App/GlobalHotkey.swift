import AppKit
import Carbon.HIToolbox

/// Minimal Carbon RegisterEventHotKey wrapper.
///
/// Why Carbon instead of `NSEvent.addGlobalMonitorForEvents`:
///   `addGlobalMonitorForEvents` needs the "Accessibility" permission the
///   user has to grant in System Settings. `RegisterEventHotKey` has been
///   shipping since 10.3 and needs no extra permission, which matches our
///   "launch and go" UX goal for v1.
final class GlobalHotkey {
    /// Default activation hotkey: ⌥ + Space (Spotlight-style).
    static let defaultKeyCode: UInt32 = 49           // kVK_Space
    static let defaultModifiers: UInt32 = UInt32(optionKey)

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var onPressed: (() -> Void)?
    private let idValue: UInt32 = 0x53_53_4B_31      // 'SSK1'
    private let signature: OSType = 0x53_53_65_4B    // 'SSeK'

    var isRegistered: Bool { hotKeyRef != nil }

    @discardableResult
    func register(keyCode: UInt32 = GlobalHotkey.defaultKeyCode,
                  modifiers: UInt32 = GlobalHotkey.defaultModifiers,
                  onPressed: @escaping () -> Void) -> Bool {
        unregister()
        self.onPressed = onPressed

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )
        let rawSelf = Unmanaged.passUnretained(self).toOpaque()
        let installStatus = InstallEventHandler(
            GetEventDispatcherTarget(),
            { (_, eventRef, userData) -> OSStatus in
                guard let eventRef, let userData else { return noErr }
                var hkID = EventHotKeyID()
                let got = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hkID
                )
                guard got == noErr else { return noErr }
                let hk = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
                if hkID.id == hk.idValue {
                    DispatchQueue.main.async { hk.onPressed?() }
                }
                return noErr
            },
            1,
            &eventType,
            rawSelf,
            &handlerRef
        )
        guard installStatus == noErr else {
            NSLog("SwiftSeek: InstallEventHandler failed: \(installStatus)")
            self.onPressed = nil
            return false
        }

        let hkID = EventHotKeyID(signature: signature, id: idValue)
        var ref: EventHotKeyRef?
        let regStatus = RegisterEventHotKey(
            keyCode,
            modifiers,
            hkID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        guard regStatus == noErr, let ref else {
            NSLog("SwiftSeek: RegisterEventHotKey failed: \(regStatus)")
            if let h = handlerRef { RemoveEventHandler(h); handlerRef = nil }
            self.onPressed = nil
            _ = hkID    // silence unused
            return false
        }
        self.hotKeyRef = ref
        return true
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let h = handlerRef {
            RemoveEventHandler(h)
            handlerRef = nil
        }
        onPressed = nil
    }

    deinit {
        unregister()
    }
}
