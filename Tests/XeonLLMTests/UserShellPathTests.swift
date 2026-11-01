// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import XeonLLM

final class UserShellPathTests: XCTestCase {
    private var home: URL!

    override func setUp() {
        super.setUp()
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("xeonllm-home-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: home)
        super.tearDown()
    }

    private func makeDirectory(_ relative: String) {
        try? FileManager.default.createDirectory(at: home.appendingPathComponent(relative, isDirectory: true),
                                                 withIntermediateDirectories: true)
    }

    func testMergesTheLoginShellPathAndFixedExtras() {
        makeDirectory(".local/bin")
        makeDirectory(".cargo/bin")
        makeDirectory(".nvm/versions/node/v18.0.0/bin")
        makeDirectory(".nvm/versions/node/v20.1.0/bin")

        let loader = UserShellPath.Loader(environment: ["SHELL": "/bin/zsh"], run: { _, _, _ in
            "__XEONLLM_PATH__/from/shell:/usr/bin__XEONLLM_END__\n"
        })
        let parts = loader.merged("/base/bin:/usr/bin", home: home.path)
            .split(separator: ":").map(String.init)

        XCTAssertEqual(parts.first, "/from/shell")
        // A directory both paths already list is not repeated.
        XCTAssertEqual(parts.filter { $0 == "/usr/bin" }.count, 1)
        XCTAssertTrue(parts.contains("/base/bin"))
        XCTAssertTrue(parts.contains("/opt/homebrew/bin"))
        XCTAssertTrue(parts.contains("/usr/local/bin"))
        XCTAssertTrue(parts.contains(home.appendingPathComponent(".local/bin").path))
        XCTAssertTrue(parts.contains(home.appendingPathComponent(".cargo/bin").path))
        // Only the newest nvm node is added.
        XCTAssertTrue(parts.contains(home.appendingPathComponent(".nvm/versions/node/v20.1.0/bin").path))
        XCTAssertFalse(parts.contains(home.appendingPathComponent(".nvm/versions/node/v18.0.0/bin").path))
    }

    func testFallsBackSilentlyWhenTheShellFails() {
        let loader = UserShellPath.Loader(environment: ["SHELL": "/bin/zsh"], run: { _, _, _ in nil })
        XCTAssertNil(loader.loginPath())

        let parts = loader.merged("/base/bin", home: home.path).split(separator: ":").map(String.init)
        XCTAssertTrue(parts.contains("/base/bin"))
        XCTAssertTrue(parts.contains("/opt/homebrew/bin"))
        XCTAssertTrue(parts.contains("/usr/local/bin"))
    }

    func testReadsTheLoginShellOnlyOnce() {
        var calls = 0
        let loader = UserShellPath.Loader(environment: [:], run: { _, _, _ in
            calls += 1
            return "__XEONLLM_PATH__/a:/b__XEONLLM_END__"
        })
        _ = loader.loginPath()
        _ = loader.loginPath()
        XCTAssertEqual(calls, 1)
    }
}
