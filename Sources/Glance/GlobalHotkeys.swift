import Carbon.HIToolbox

/// Registered global hotkeys (`RegisterEventHotKey`). Unlike the event tap, these
/// keep working while Secure Event Input is on (e.g. a password field is focused),
/// because macOS delivers only the exact combos we register; no other keystrokes
/// are ever visible to us. Callbacks arrive on the main thread.
final class GlobalHotkeys {
    private static let signature: OSType = 0x474C_4E43 // 'GLNC'

    var onPress: ((UInt32) -> Void)?
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var hotkey = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                           EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &hotkey)
            guard status == noErr, hotkey.signature == GlobalHotkeys.signature else {
                return OSStatus(eventNotHandledErr)
            }
            Unmanaged<GlobalHotkeys>.fromOpaque(userData).takeUnretainedValue().onPress?(hotkey.id)
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(id: UInt32, keyCode: Int, modifiers: Int) {
        guard refs[id] == nil else { return }
        var ref: EventHotKeyRef?
        let hotkeyID = EventHotKeyID(signature: Self.signature, id: id)
        if RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotkeyID,
                               GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
            refs[id] = ref
        } else {
            NSLog("Glance: failed to register hotkey \(id)")
        }
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
    }
}
