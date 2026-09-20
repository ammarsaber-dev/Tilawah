//
//  CatalogTests.swift
//  TilawahTests
//
//  Phase 1 unit tests (AGENTS.md §9): deterministic fixtures, no network.
//  Covers provider decoding incl. missing optionals, `surah_list` edge
//  cases, stable asset IDs, stream-URL derivation, and the live adapter
//  against a stubbed URLSession.
//

@testable import Tilawah
import Foundation
import Testing

// MARK: - Fixture loading

@Suite("Catalog fixtures")
struct CatalogFixtureTests {
    @Test("reciters fixture decodes with tolerant optionals")
    func recitersFixtureDecodes() throws {
        let service = try FixtureCatalogService.loadedFromFixtures()
        #expect(service.reciters.count == 2)

        let full = try #require(service.reciters.first(where: { $0.id == 1 }))
        #expect(full.name == "أحمد بن علي العجمي")
        #expect(full.moshaf.count == 2)
        #expect(full.moshaf[0].rewayaID == 1)
        // Missing optionals decode as nil, never throw.
        #expect(full.moshaf[1].rewayaID == nil)
        #expect(full.moshaf[1].surahTotal == nil)
        #expect(full.moshaf[1].moshafType == nil)

        // String-encoded IDs are tolerated (reciter 100, mushaf 7).
        let partial = try #require(service.reciters.first(where: { $0.id == 100 }))
        #expect(partial.letter == nil)
        #expect(partial.date == nil)
        let mushaf = try #require(partial.moshaf.first)
        #expect(mushaf.id == 7)
        #expect(mushaf.rewayaID == 1)
        #expect(mushaf.surahTotal == 113)
    }

    @Test("suwar and riwayat fixtures decode")
    func suwarAndRiwayatDecode() throws {
        let service = try FixtureCatalogService.loadedFromFixtures()
        #expect(service.suwar.count == 3)
        let nas = try #require(service.suwar.first(where: { $0.id == 114 }))
        #expect(nas.name == "الناس")
        #expect(nas.startPage == nil)
        #expect(service.riwayat.count == 2)
        #expect(service.riwayat.map(\.id) == [1, 2])
    }
}

// MARK: - surah_list parsing

@Suite("surah_list parsing")
struct SurahListParserTests {
    @Test("parses a normal list")
    func normalList() {
        #expect(SurahListParser.parse("1,2,3,114") == [1, 2, 3, 114])
    }

    @Test("ignores whitespace, empty segments, trailing commas")
    func whitespaceAndTrailingCommas() {
        #expect(SurahListParser.parse("1, 2,,114,") == [1, 2, 114])
        #expect(SurahListParser.parse("  5  ,  7 ") == [5, 7])
    }

    @Test("drops non-numeric and out-of-range tokens, dedupes, sorts")
    func noisyList() {
        #expect(SurahListParser.parse("1,3,5,  ,abc,115,0,-2,114,114") == [1, 3, 5, 114])
    }

    @Test("empty and nil input yield no surahs")
    func emptyInput() {
        #expect(SurahListParser.parse("") == [])
        #expect(SurahListParser.parse(nil) == [])
        #expect(SurahListParser.parse(",,,") == [])
        #expect(SurahListParser.parse("abc, ,") == [])
    }

    @Test("mushaf exposes parsed IDs; surah_total stays advisory")
    func mushafAvailableIDs() throws {
        let service = try FixtureCatalogService.loadedFromFixtures()
        let partial = try #require(service.reciters.first(where: { $0.id == 100 }))
        let mushaf = try #require(partial.moshaf.first)
        // surah_total claims 113 but the parsed list is authoritative.
        #expect(mushaf.availableSurahIDs == [1, 3, 5, 114])
        #expect(!mushaf.availableSurahIDs.contains(2))
    }
}

// MARK: - Asset identity and URLs

@Suite("AudioAsset identity and stream URLs")
struct AudioAssetTests {
    @Test("stable asset ID format")
    func stableID() {
        #expect(
            AudioAsset.makeID(reciterID: 1, mushafID: 1, surahID: 1)
                == "mp3quran:v3:reciter:1:mushaf:1:surah:1"
        )
    }

    @Test("different recordings of the same surah never collide")
    func distinctRecordingsDistinctIDs() {
        let a = AudioAsset.makeID(reciterID: 1, mushafID: 1, surahID: 114)
        let b = AudioAsset.makeID(reciterID: 1, mushafID: 2, surahID: 114)
        let c = AudioAsset.makeID(reciterID: 100, mushafID: 7, surahID: 114)
        #expect(a != b)
        #expect(a != c)
        #expect(b != c)
    }

    @Test("stream URL uses zero-padded 3-digit filename")
    func streamURLPadding() {
        #expect(
            MP3QuranURLBuilder.streamURL(server: "https://server6.mp3quran.net/akdr/", surahID: 1)?
                .absoluteString == "https://server6.mp3quran.net/akdr/001.mp3"
        )
        #expect(
            MP3QuranURLBuilder.streamURL(server: "https://server6.mp3quran.net/akdr/", surahID: 114)?
                .absoluteString == "https://server6.mp3quran.net/akdr/114.mp3"
        )
    }

    @Test("stream URL tolerates a missing trailing slash")
    func missingTrailingSlash() {
        #expect(
            MP3QuranURLBuilder.streamURL(server: "https://server.example.net/partial", surahID: 5)?
                .absoluteString == "https://server.example.net/partial/005.mp3"
        )
    }

    @Test("stream URL rejects invalid input")
    func invalidInput() {
        #expect(MP3QuranURLBuilder.streamURL(server: "https://example.net/x/", surahID: 0) == nil)
        #expect(MP3QuranURLBuilder.streamURL(server: "https://example.net/x/", surahID: 115) == nil)
        #expect(MP3QuranURLBuilder.streamURL(server: "", surahID: 1) == nil)
        #expect(MP3QuranURLBuilder.streamURL(server: "  ", surahID: 1) == nil)
    }

    @Test("relative storage path never embeds the sandbox")
    func relativeStoragePath() {
        let path = AudioAsset.makeRelativeStoragePath(reciterID: 1, mushafID: 1, surahID: 1)
        #expect(path == "1/1/001.mp3")
        #expect(!path.hasPrefix("/"))
        #expect(!path.contains("Application Support"))
    }

    @Test("service builds assets from fixture models")
    func serviceBuildsAsset() throws {
        let service = try FixtureCatalogService.loadedFromFixtures()
        let reciter = try #require(service.reciters.first(where: { $0.id == 1 }))
        let mushaf = try #require(reciter.moshaf.first)
        let asset = try #require(
            service.audioAsset(reciter: reciter, mushaf: mushaf, surahID: 2, surahName: "البقرة")
        )
        #expect(asset.id == "mp3quran:v3:reciter:1:mushaf:1:surah:2")
        #expect(asset.streamURL.absoluteString == "https://server6.mp3quran.net/akdr/002.mp3")
        #expect(asset.relativeStoragePath == "1/1/002.mp3")
        #expect(asset.surahName == "البقرة")
    }
}

// MARK: - Live adapter against a stubbed session (no network)

private final class StubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with _: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

@Suite("MP3QuranService with stubbed transport", .serialized)
struct MP3QuranServiceTests {
    private func stubbedService(
        statusCode: Int = 200, body: String
    ) -> MP3QuranService {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: statusCode,
                httpVersion: nil, headerFields: nil
            )!
            return (response, Data(body.utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        return MP3QuranService(session: URLSession(configuration: config))
    }

    private let recitersBody = """
        {"reciters": [
          {"id": 1, "name": "أحمد بن علي العجمي", "letter": "ا",
           "moshaf": [{"id": 1, "name": "المصحف المرتل",
             "server": "https://server6.mp3quran.net/akdr/",
             "surah_list": "1,2,114"}]}
        ]}
        """

    @Test("fetches reciters through the adapter")
    func fetchReciters() async throws {
        let service = stubbedService(body: recitersBody)
        let reciters = try await service.fetchReciters(language: "ar")
        #expect(reciters.count == 1)
        #expect(reciters[0].moshaf[0].availableSurahIDs == [1, 2, 114])
    }

    @Test("requests target the www host with language query")
    func requestShape() async throws {
        var captured: URL?
        StubURLProtocol.handler = { req in
            captured = req.url
            let response = HTTPURLResponse(
                url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil
            )!
            return (response, Data("{\"suwar\": []}".utf8))
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        let service = MP3QuranService(session: URLSession(configuration: config))
        _ = try await service.fetchSuwar(language: "ar")
        let url = try #require(captured)
        #expect(url.host == "www.mp3quran.net")
        #expect(url.path.contains("suwar"))
        #expect(url.query?.contains("language=ar") == true)
    }

    @Test("non-2xx status surfaces as httpStatus")
    func httpError() async throws {
        let service = stubbedService(statusCode: 500, body: "{}")
        await #expect(throws: CatalogError.httpStatus(500)) {
            try await service.fetchReciters(language: "ar")
        }
    }

    @Test("malformed JSON surfaces as decodingFailed")
    func badJSON() async throws {
        let service = stubbedService(body: "not json")
        await #expect(throws: CatalogError.self) {
            try await service.fetchReciters(language: "ar")
        }
    }
}
