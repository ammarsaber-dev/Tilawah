//
//  SleepTimer.swift
//  Tilawah
//
//  Sleep timer (Phase 6, AGENTS.md §6 Playback: allowed secondary addition).
//  Pure option model + deadline math live here (testable without AVPlayer);
//  `PlaybackController` owns the firing task and the end-of-surah hook.
//

import Foundation

/// Sleep-timer choice. Minutes-based options pause playback at the deadline;
/// `.endOfSurah` pauses when the current item finishes instead of advancing.
public enum SleepTimerOption: Equatable, Sendable, Hashable {
    case off
    case minutes(Int)
    case endOfSurah

    public static let minuteChoices = [5, 10, 15, 30, 60]

    public var label: String {
        switch self {
        case .off: return "إيقاف المؤقت"
        case let .minutes(value): return "بعد \(value) دقيقة"
        case .endOfSurah: return "بعد نهاية السورة"
        }
    }

    /// Deadline for minutes-based options, nil for off/end-of-surah.
    public func deadline(from now: Date = Date()) -> Date? {
        if case let .minutes(value) = self {
            return now.addingTimeInterval(TimeInterval(value * 60))
        }
        return nil
    }
}

/// Pure remaining-time math (testable without timers).
public enum SleepTimerMath {
    public static func remaining(until: Date?, now: Date = Date()) -> Double? {
        guard let until else { return nil }
        return max(0, until.timeIntervalSince(now))
    }

    public static func remainingLabel(_ remaining: Double?) -> String? {
        guard let remaining else { return nil }
        let total = Int(remaining.rounded(.up))
        let minutes = total / 60
        let seconds = total % 60
        if minutes > 0 {
            return "\(minutes) د \(String(format: "%02d", seconds)) ث"
        }
        return "\(seconds) ث"
    }
}
