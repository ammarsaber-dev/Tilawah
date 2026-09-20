//
//  CatalogModels.swift
//  Tilawah
//
//  Domain model for the catalog layer (Phase 1: Foundation + Catalog).
//  Mirrors MP3Quran v3 payloads with tolerant decoding; provider details
//  stay behind the `QuranCatalogService` adapter (see AGENTS.md §5–§6).
//
//  Identity rule (AGENTS.md §5.3):
//  `AudioAsset.id` is stable and persisted:
//  `mp3quran:v3:reciter:{reciterID}:mushaf:{mushafID}:surah:{surahID}`.
//  Audio URLs are derived, never identity. Persist `relativeStoragePath`,
//  never absolute sandbox paths.
//

import Foundation

// MARK: - Reciter

/// A reciter (قارئ) as exposed by `GET /reciters?language=ar`.
public struct Reciter: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let letter: String?
    public let date: String?
    public let moshaf: [Mushaf]

    public init(id: Int, name: String, letter: String? = nil, date: String? = nil, moshaf: [Mushaf] = []) {
        self.id = id
        self.name = name
        self.letter = letter
        self.date = date
        self.moshaf = moshaf
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, letter, date, moshaf
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // `id` is sometimes encoded as a string by the provider; tolerate both.
        if let intID = try? container.decode(Int.self, forKey: .id) {
            id = intID
        } else if let stringID = try? container.decode(String.self, forKey: .id),
                  let parsed = Int(stringID.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            id = parsed
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: container,
                debugDescription: "Reciter.id must be an integer or numeric string."
            )
        }
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        letter = try? container.decode(String.self, forKey: .letter)
        date = try? container.decode(String.self, forKey: .date)
        moshaf = (try? container.decode([Mushaf].self, forKey: .moshaf)) ?? []
    }
}

// MARK: - Mushaf (recording collection)

/// One recording collection for a reciter (e.g. مرتل, مجود).
/// Verified payload: `{ id, name, rewaya_id?, server, surah_total, moshaf_type, surah_list }`.
public struct Mushaf: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let rewayaID: Int?
    public let server: String
    public let surahTotal: Int?
    public let moshafType: Int?
    /// Raw comma-separated list, e.g. `"1,2,3,…,114"`. Parse via `availableSurahIDs`.
    public let surahListRaw: String

    public init(
        id: Int, name: String, rewayaID: Int? = nil, server: String,
        surahTotal: Int? = nil, moshafType: Int? = nil, surahListRaw: String
    ) {
        self.id = id
        self.name = name
        self.rewayaID = rewayaID
        self.server = server
        self.surahTotal = surahTotal
        self.moshafType = moshafType
        self.surahListRaw = surahListRaw
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, server
        case rewayaID = "rewaya_id"
        case surahTotal = "surah_total"
        case moshafType = "moshaf_type"
        case surahListRaw = "surah_list"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intID = try? container.decode(Int.self, forKey: .id) {
            id = intID
        } else if let stringID = try? container.decode(String.self, forKey: .id),
                  let parsed = Int(stringID.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            id = parsed
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: container,
                debugDescription: "Mushaf.id must be an integer or numeric string."
            )
        }
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        // rewaya_id may be Int or numeric String; absent means unknown.
        if let intRewaya = try? container.decode(Int.self, forKey: .rewayaID) {
            rewayaID = intRewaya
        } else if let stringRewaya = try? container.decode(String.self, forKey: .rewayaID) {
            rewayaID = Int(stringRewaya.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            rewayaID = nil
        }
        server = (try? container.decode(String.self, forKey: .server)) ?? ""
        // surah_total is advisory only; tolerate Int or numeric String.
        if let intTotal = try? container.decode(Int.self, forKey: .surahTotal) {
            surahTotal = intTotal
        } else if let stringTotal = try? container.decode(String.self, forKey: .surahTotal) {
            surahTotal = Int(stringTotal.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            surahTotal = nil
        }
        if let intType = try? container.decode(Int.self, forKey: .moshafType) {
            moshafType = intType
        } else if let stringType = try? container.decode(String.self, forKey: .moshafType) {
            moshafType = Int(stringType.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            moshafType = nil
        }
        // surah_list is documented as a comma-separated string; tolerate
        // an already-split array or a single number just in case.
        if let raw = try? container.decode(String.self, forKey: .surahListRaw) {
            surahListRaw = raw
        } else if let array = try? container.decode([Int].self, forKey: .surahListRaw) {
            surahListRaw = array.map(String.init).joined(separator: ",")
        } else if let single = try? container.decode(Int.self, forKey: .surahListRaw) {
            surahListRaw = String(single)
        } else {
            surahListRaw = ""
        }
    }

    /// Parsed, validated surah IDs from `surahListRaw`.
    /// Defensive: ignores whitespace, trailing commas, empty and non-numeric
    /// tokens; dedupes and sorts. Trusts the parsed list over `surahTotal`.
    public var availableSurahIDs: [Int] {
        SurahListParser.parse(surahListRaw)
    }
}

// MARK: - Riwayah

/// A narration/riwayah (e.g. 1 = حفص عن عاصم) from `GET /riwayat?language=ar`.
public struct Riwayah: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case id, name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let intID = try? container.decode(Int.self, forKey: .id) {
            id = intID
        } else if let stringID = try? container.decode(String.self, forKey: .id),
                  let parsed = Int(stringID.trimmingCharacters(in: .whitespacesAndNewlines))
        {
            id = parsed
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .id, in: container,
                debugDescription: "Riwayah.id must be an integer or numeric string."
            )
        }
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
    }
}

// MARK: - Surah

/// A surah entry from `GET /suwar?language=ar`.
public struct Surah: Codable, Sendable, Identifiable, Hashable {
    public let id: Int
    public let name: String
    public let startPage: Int?
    public let endPage: Int?
    public let makkia: Int?
    public let type: Int?

    public init(
        id: Int, name: String, startPage: Int? = nil, endPage: Int? = nil,
        makkia: Int? = nil, type: Int? = nil
    ) {
        self.id = id
        self.name = name
        self.startPage = startPage
        self.endPage = endPage
        self.makkia = makkia
        self.type = type
    }

    private enum CodingKeys: String, CodingKey {
        case id, name
        case startPage = "start_page"
        case endPage = "end_page"
        case makkia, type
    }
}

// MARK: - AudioAsset

/// A playable full-surah recording. Identity is the stable
/// `mp3quran:v3:reciter:{reciter}:mushaf:{mushaf}:surah:{surah}` string;
/// the stream URL is derived and never used as identity.
public struct AudioAsset: Sendable, Identifiable, Hashable {
    /// Stable persisted identifier (see file header).
    public let id: String
    public let reciterID: Int
    public let mushafID: Int
    public let surahID: Int
    public let reciterName: String
    public let mushafName: String
    public let surahName: String?
    /// Remote stream URL derived from the mushaf `server` + padded surah number.
    public let streamURL: URL
    /// Path relative to the `Application Support/Audio` root, e.g.
    /// `1/1/001.mp3`-style `<reciterID>/<mushafID>/<surahID>.mp3`.
    /// Never persist absolute sandbox paths.
    public let relativeStoragePath: String

    public init(
        reciterID: Int, mushafID: Int, surahID: Int,
        reciterName: String, mushafName: String, surahName: String? = nil,
        streamURL: URL
    ) {
        self.reciterID = reciterID
        self.mushafID = mushafID
        self.surahID = surahID
        self.reciterName = reciterName
        self.mushafName = mushafName
        self.surahName = surahName
        self.streamURL = streamURL
        self.id = AudioAsset.makeID(reciterID: reciterID, mushafID: mushafID, surahID: surahID)
        self.relativeStoragePath = AudioAsset.makeRelativeStoragePath(
            reciterID: reciterID, mushafID: mushafID, surahID: surahID
        )
    }

    public static func makeID(reciterID: Int, mushafID: Int, surahID: Int) -> String {
        "mp3quran:v3:reciter:\(reciterID):mushaf:\(mushafID):surah:\(surahID)"
    }

    public static func makeRelativeStoragePath(reciterID: Int, mushafID: Int, surahID: Int) -> String {
        "\(reciterID)/\(mushafID)/\(String(format: "%03d", surahID)).mp3"
    }
}

// MARK: - surah_list parsing

/// Defensive parser for the provider's comma-separated `surah_list` string.
public enum SurahListParser {
    /// Parses `"1, 2,,114,"` → `[1, 2, 114]`.
    /// - Ignores whitespace, empty segments, and non-numeric tokens.
    /// - Keeps only 1…114, dedupes, sorts ascending.
    public static func parse(_ raw: String?) -> [Int] {
        guard let raw, !raw.isEmpty else { return [] }
        var seen = Set<Int>()
        var result: [Int] = []
        result.reserveCapacity(114)
        for token in raw.split(separator: ",") {
            let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let value = Int(trimmed), (1 ... 114).contains(value) else {
                continue
            }
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result.sorted()
    }
}

// MARK: - API envelopes

struct RecitersResponse: Codable {
    var reciters: [Reciter]
}

struct SuwarResponse: Codable {
    var suwar: [Surah]
}

struct RiwayatResponse: Codable {
    var riwayat: [Riwayah]
}
