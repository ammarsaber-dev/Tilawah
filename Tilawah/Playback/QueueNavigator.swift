//
//  QueueNavigator.swift
//  Tilawah
//
//  Pure queue-advance logic (unit-tested). The controller owns side effects;
//  everything about "what plays next" lives here with no AVFoundation.
//

import Foundation

/// Repeat behavior for the queue.
public enum RepeatMode: String, Codable, CaseIterable, Sendable {
    case off
    case all
    case one

    /// Cycles off → all → one → off (player button behavior).
    public func next() -> RepeatMode {
        switch self {
        case .off: .all
        case .all: .one
        case .one: .off
        }
    }

    public var label: String {
        switch self {
        case .off: "بدون تكرار"
        case .all: "تكرار القائمة"
        case .one: "تكرار السورة"
        }
    }
}

public enum PreviousAction: Equatable, Sendable {
    /// Restart the current track (position was past the threshold).
    case restart
    /// Move to the item at this index.
    case moveTo(Int)
    /// Nothing to do (empty queue).
    case none
}

public enum QueueNavigator {
    /// Index to advance to when the current item ends, or nil to stop.
    /// - `one` never advances (the controller re-seeks instead).
    public static func nextIndex(current: Int, count: Int, repeat repeatMode: RepeatMode) -> Int? {
        guard count > 0, current >= 0, current < count else { return nil }
        switch repeatMode {
        case .one:
            return current
        case .all:
            return (current + 1) % count
        case .off:
            let next = current + 1
            return next < count ? next : nil
        }
    }

    /// Previous-button behavior: restart when past `threshold` seconds,
    /// else step back (wrapping only under repeat-all).
    public static func previous(
        current: Int, count: Int, position: Double,
        threshold: Double = 5, repeat repeatMode: RepeatMode
    ) -> PreviousAction {
        guard count > 0, current >= 0, current < count else { return .none }
        if position > threshold {
            return .restart
        }
        if current > 0 {
            return .moveTo(current - 1)
        }
        // At the head: wrap only when repeating the queue.
        if repeatMode == .all, count > 1 {
            return .moveTo(count - 1)
        }
        return .restart
    }
}
