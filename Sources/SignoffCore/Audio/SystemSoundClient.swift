import Foundation
import AudioToolbox
import AppKit

/// Wraps `AudioServicesPlaySystemSound` so we can play macOS system sounds.
/// The Swift SDK overlay for `AudioServicesPlaySystemSound` returns Void
/// (the historical `OSStatus` return value is no longer surfaced), so we use a
/// fire-and-forget pattern with an in-memory soft-retry suppression cache.
public actor SystemSoundClient {
    public static let shared = SystemSoundClient()

    public enum Sound: Sendable, Equatable {
        case tink, basso, funk, blow, glass, hero, morse, ping, pop, purr, sosumi, submarine
    }

    private var suppressedSounds: Set<Sound> = []

    public func play(_ sound: Sound, volume: Float = 0.5) {
        if suppressedSounds.contains(sound) {
            return
        }
        let id = systemSoundID(for: sound)
        // Note: `AudioServicesPlaySystemSound` does not accept a volume
        // argument; volume shaping for partner-demo polish should be layered
        // via `AVAudioPlayer` against an inline buffer (spec §16).
        AudioServicesPlaySystemSound(SystemSoundID(id))
    }

    public func probeAllSounds() {
        for s in [Sound.tink, .basso, .funk, .blow] {
            AudioServicesPlaySystemSound(SystemSoundID(systemSoundID(for: s)))
        }
    }

    public func systemSoundID(for sound: Sound) -> UInt32 {
        switch sound {
        case .tink:     return 1057
        case .basso:    return 1004
        case .funk:     return 1094
        case .blow:     return 1005
        case .glass:    return 1014
        case .hero:     return 1029
        case .morse:    return 1053
        case .ping:     return 1103
        case .pop:      return 1033
        case .purr:     return 1044
        case .sosumi:   return 1031
        case .submarine:return 1035
        }
    }
}
