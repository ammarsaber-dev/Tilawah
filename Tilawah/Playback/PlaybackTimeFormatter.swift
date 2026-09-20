//
//  PlaybackTimeFormatter.swift
//  Tilawah
//
//  Media timestamps use Latin digits by convention (as in Arabic YouTube /
//  system players) even though counts elsewhere use Arabic-Indic digits.
//

import Foundation

public enum PlaybackTimeFormatter {
    /// `61` → `"1:01"`, `3661` → `"1:01:01"`. NaN/negative → `"0:00"`.
    public static func string(from interval: TimeInterval) -> String {
        guard interval.isFinite, interval > 0 else { return "0:00" }
        let total = Int(interval)
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
