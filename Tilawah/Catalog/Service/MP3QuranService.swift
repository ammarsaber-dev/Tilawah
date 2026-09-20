//
//  MP3QuranService.swift
//  Tilawah
//
//  MP3Quran v3 adapter (PROVISIONAL P2/P5 per AGENTS.md §3: primary provider
//  choice and `server + 3-digit-surah + .mp3` URL rule are provider details
//  isolated here so a server naming change never touches playback).
//
//  Verified 2026-09-20: host must be `https://www.mp3quran.net/api/v3/...`
//  (bare host returns 301). Endpoints: `/reciters`, `/suwar`, `/riwayat`
//  with `?language=ar`.
//
//  Audio rule (verified via HEAD): `server + 001.mp3`, content-type
//  `audio/mpeg`, `accept-ranges: bytes` (streaming/seek/resume capable).
//

import Foundation

/// URL builder for MP3Quran audio assets. The single place that knows the
/// `server + zero-padded-3-digit + .mp3` convention.
public enum MP3QuranURLBuilder: Sendable {
    /// Builds e.g. `https://server6.mp3quran.net/akdr/` + `001.mp3`.
    /// Returns nil for out-of-range IDs or unbuildable servers.
    public static func streamURL(server: String, surahID: Int) -> URL? {
        guard (1 ... 114).contains(surahID) else { return nil }
        let trimmed = server.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let base = URL(string: trimmed) else { return nil }
        let filename = String(format: "%03d.mp3", surahID)
        // Ensure exactly one `/` between server and filename.
        if base.absoluteString.hasSuffix("/") {
            return base.appendingPathComponent(filename)
        }
        return URL(string: base.absoluteString + "/" + filename)
    }
}

/// Live MP3Quran v3 implementation of `QuranCatalogService`.
/// `URLSession` follows redirects by default, satisfying the www-host rule.
public struct MP3QuranService: QuranCatalogService {
    public let baseURL: URL
    public let session: URLSession
    private let decoder: JSONDecoder

    public init(
        baseURL: URL = URL(string: "https://www.mp3quran.net/api/v3")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
        decoder = JSONDecoder()
    }

    // MARK: - QuranCatalogService

    public func fetchReciters(language: String = "ar") async throws -> [Reciter] {
        let response: RecitersResponse = try await get(
            path: "reciters", query: [URLQueryItem(name: "language", value: language)]
        )
        return response.reciters
    }

    public func fetchReciter(id: Int, language: String = "ar") async throws -> Reciter {
        let response: RecitersResponse = try await get(
            path: "reciters",
            query: [
                URLQueryItem(name: "language", value: language),
                URLQueryItem(name: "reciter", value: String(id)),
            ]
        )
        guard let reciter = response.reciters.first else {
            throw CatalogError.decodingFailed("Reciter \(id) not found in response.")
        }
        return reciter
    }

    public func fetchSuwar(language: String = "ar") async throws -> [Surah] {
        let response: SuwarResponse = try await get(
            path: "suwar", query: [URLQueryItem(name: "language", value: language)]
        )
        return response.suwar
    }

    public func fetchRiwayat(language: String = "ar") async throws -> [Riwayah] {
        let response: RiwayatResponse = try await get(
            path: "riwayat", query: [URLQueryItem(name: "language", value: language)]
        )
        return response.riwayat
    }

    // MARK: - Private

    private func get<T: Decodable>(path: String, query: [URLQueryItem]) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = query
        guard let url = components?.url else {
            throw CatalogError.invalidURL(path)
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(from: url)
        } catch let urlError as URLError where urlError.code == .notConnectedToInternet {
            throw CatalogError.offline
        } catch {
            throw CatalogError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw CatalogError.transport("Invalid server response.")
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw CatalogError.httpStatus(http.statusCode)
        }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw CatalogError.decodingFailed(error.localizedDescription)
        }
    }
}
