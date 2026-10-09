import AVFoundation

/// Pure audio-route rules (no AVAudioSession side effects), so they are unit-testable.
/// Same priority as Android `AudioRoute.resolve`: with the speaker off, Bluetooth wins over a
/// wired headset, which wins over the earpiece; the speaker override beats everything.
enum SyRtcAudioRouting {
    static let bluetoothOutputs: Set<AVAudioSession.Port> = [.bluetoothHFP, .bluetoothA2DP, .bluetoothLE]
    static let wiredOutputs: Set<AVAudioSession.Port> = [.headphones, .headsetMic, .usbAudio]

    /// Route the session is actually playing to.
    static func route(outputs: [AVAudioSession.Port]) -> SyRtcAudioRoute {
        for port in outputs {
            switch port {
            case .builtInSpeaker: return .speaker
            case .builtInReceiver: return .earpiece
            case _ where wiredOutputs.contains(port): return .headset
            case _ where bluetoothOutputs.contains(port): return .bluetooth
            default: continue
            }
        }
        return .unknown
    }

    /// Routes the app can switch to right now. Speaker always; earpiece only on phones;
    /// headset / Bluetooth when such a device is connected (seen as an input or current output).
    static func available(inputs: [AVAudioSession.Port], outputs: [AVAudioSession.Port], hasEarpiece: Bool) -> [SyRtcAudioRoute] {
        let all = inputs + outputs
        var routes: [SyRtcAudioRoute] = [.speaker]
        if hasEarpiece { routes.append(.earpiece) }
        if all.contains(where: { wiredOutputs.contains($0) }) { routes.append(.headset) }
        if all.contains(where: { bluetoothOutputs.contains($0) }) { routes.append(.bluetooth) }
        return routes
    }

    /// Input port to prefer so iOS moves playback to `route` (HFP / headset mic carry the output with them).
    static func preferredInput(for route: SyRtcAudioRoute, inputs: [AVAudioSession.Port]) -> AVAudioSession.Port? {
        let wanted: [AVAudioSession.Port]
        switch route {
        case .bluetooth: wanted = [.bluetoothHFP, .bluetoothLE]
        case .headset: wanted = [.headsetMic, .usbAudio]
        case .earpiece, .speaker: wanted = [.builtInMic]
        case .unknown: return nil
        }
        return wanted.first(where: { inputs.contains($0) })
    }

    /// Playback-device ids for `enumeratePlaybackDevices` / `setPlaybackDevice`.
    static func deviceId(_ route: SyRtcAudioRoute) -> String? {
        switch route {
        case .speaker: return "speaker"
        case .earpiece: return "earpiece"
        case .headset: return "headset"
        case .bluetooth: return "bluetooth"
        case .unknown: return nil
        }
    }

    static func route(deviceId: String) -> SyRtcAudioRoute? {
        switch deviceId {
        case "speaker": return .speaker
        case "earpiece": return .earpiece
        case "headset": return .headset
        case "bluetooth": return .bluetooth
        default: return nil
        }
    }
}

/// Publishes `onAudioRoutingChanged` only when the route really changes (Android dedupes the same way).
final class SyRtcAudioRouteDeduper {
    private(set) var last: SyRtcAudioRoute?
    func shouldPublish(_ route: SyRtcAudioRoute) -> Bool {
        if route == last { return false }
        last = route
        return true
    }
    func reset() { last = nil }
}
