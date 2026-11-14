// XeonLLM - run LLMs locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import XeonLLM

/// v0.1 ships with online benchmark sharing off: the XeonLLM site is a static
/// GitHub Pages site with no benchmark API. These tests prove every public
/// BenchmarkSharing entry point refuses the call before a URL is built or a
/// connection is opened, using a URLProtocol stub that records every request.
@MainActor
final class BenchmarkSharingOfflineTests: XCTestCase {
    private final class CountingProtocol: URLProtocol, @unchecked Sendable {
        static let lock = NSLock()
        nonisolated(unsafe) static var requests: [URL] = []

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lock.lock(); Self.requests.append(request.url!); Self.lock.unlock()
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
        }

        override func stopLoading() {}

        static func reset() { lock.lock(); requests = []; lock.unlock() }
        static var count: Int { lock.lock(); defer { lock.unlock() }; return requests.count }
    }

    private func stubbedSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CountingProtocol.self]
        return URLSession(configuration: config)
    }

    override func setUp() {
        super.setUp()
        CountingProtocol.reset()
        BenchmarkSharing.sessionProvider = { .shared }
    }

    override func tearDown() {
        BenchmarkSharing.sessionProvider = { .shared }
        CountingProtocol.reset()
        super.tearDown()
    }

    func testSharingIsOffInThisVersion() {
        XCTAssertFalse(BenchmarkSharing.onlineSharingEnabled)
        XCTAssertFalse(BenchmarkSharing.shareUIAvailable,
                       "no share UI may be shown while sharing is off")
    }

    func testPrepareShareThrowsWithoutRequest() async {
        BenchmarkSharing.sessionProvider = stubbedSession
        let model = LocalModel(url: URL(fileURLWithPath: "/nonexistent/model.gguf"),
                               name: "model.gguf", sizeBytes: 1)
        do {
            _ = try await BenchmarkSharing.shared.prepareShare(
                model: model, settings: .fromDefaults(), contributorAlias: nil)
            XCTFail("prepareShare must throw when sharing is off")
        } catch let error as BenchmarkSharing.ShareError {
            guard case .disabled = error else { return XCTFail("wrong error: \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
        XCTAssertEqual(CountingProtocol.count, 0)
    }

    func testSubmitPreparedThrowsWithoutRequest() async {
        BenchmarkSharing.sessionProvider = stubbedSession
        let prepared = BenchmarkSharing.Prepared(
            payload: Data("{}" .utf8), installationId: "iid", keyFingerprint: "fp", pp: 1, tg: 2)
        do {
            _ = try await BenchmarkSharing.shared.submitPrepared(prepared)
            XCTFail("submitPrepared must throw when sharing is off")
        } catch let error as BenchmarkSharing.ShareError {
            guard case .disabled = error else { return XCTFail("wrong error: \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
        XCTAssertEqual(CountingProtocol.count, 0)
    }

    func testFetchHistoryThrowsWithoutRequest() async {
        BenchmarkSharing.sessionProvider = stubbedSession
        do {
            _ = try await BenchmarkSharing.shared.fetchHistory()
            XCTFail("fetchHistory must throw when sharing is off")
        } catch let error as BenchmarkSharing.ShareError {
            guard case .disabled = error else { return XCTFail("wrong error: \(error)") }
        } catch {
            XCTFail("wrong error type: \(error)")
        }
        XCTAssertEqual(CountingProtocol.count, 0)
    }

    func testResetIdentityIsANoOpWithoutRequest() {
        BenchmarkSharing.sessionProvider = stubbedSession
        BenchmarkSharing.shared.resetIdentity()
        XCTAssertEqual(CountingProtocol.count, 0)
    }
}