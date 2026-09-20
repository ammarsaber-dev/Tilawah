//
//  FixtureCatalogService.swift
//  TilawahTests
//
//  In-memory fake of `QuranCatalogService` backed by the JSON fixtures in
//  `TilawahTests/Fixtures`. Deterministic, no network — used by unit tests
//  and (in later phases) SwiftUI previews.
//

@testable import Tilawah
import Foundation

struct FixtureCatalogService: QuranCatalogService {
    let reciters: [Reciter]
    let suwar: [Surah]
    let riwayat: [Riwayah]

    init(reciters: [Reciter] = [], suwar: [Surah] = [], riwayat: [Riwayah] = []) {
        self.reciters = reciters
        self.suwar = suwar
        self.riwayat = riwayat
    }

    /// Loads the bundled JSON fixtures from the test target's resources.
    static func loadedFromFixtures() throws -> FixtureCatalogService {
        let bundle = Bundle(for: FixtureBundleMarker.self)
        func data(_ name: String) throws -> Data {
            guard let url = bundle.url(forResource: name, withExtension: "json") else {
                throw CatalogError.decodingFailed("Missing fixture: \(name).json")
            }
            return try Data(contentsOf: url)
        }
        let decoder = JSONDecoder()
        let reciters = try decoder.decode(RecitersResponse.self, from: data("reciters")).reciters
        let suwar = try decoder.decode(SuwarResponse.self, from: data("suwar")).suwar
        let riwayat = try decoder.decode(RiwayatResponse.self, from: data("riwayat")).riwayat
        return FixtureCatalogService(reciters: reciters, suwar: suwar, riwayat: riwayat)
    }

    func fetchReciters(language: String = "ar") async throws -> [Reciter] { reciters }

    func fetchReciter(id: Int, language: String = "ar") async throws -> Reciter {
        guard let reciter = reciters.first(where: { $0.id == id }) else {
            throw CatalogError.decodingFailed("Reciter \(id) not found in fixtures.")
        }
        return reciter
    }

    func fetchSuwar(language: String = "ar") async throws -> [Surah] { suwar }
    func fetchRiwayat(language: String = "ar") async throws -> [Riwayah] { riwayat }
}

private final class FixtureBundleMarker: NSObject {}
