// XeonLLM - run LLMs locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import XeonLLM

/// A bundle without the identity keys of make-app.sh is plain XeonLLM, so its data, logs,
/// Keychain entries and updates stay where they always were.
final class AppIdentityTests: XCTestCase {
    func testABundleWithoutIdentityKeysIsXeonLLM() {
        XCTAssertEqual(AppInfo.name, "XeonLLM")
        XCTAssertEqual(AppInfo.identifier, "dev.xeonllm.app")
        XCTAssertEqual(AppInfo.dataFolder, "XeonLLM")
        XCTAssertEqual(AppInfo.productVersion, AppInfo.version)
        XCTAssertTrue(AppInfo.updatesEnabled)
        XCTAssertFalse(AppInfo.isNoAVX2)
        XCTAssertFalse(AppInfo.isRebranded)
        XCTAssertEqual(AppInfo.branded("Welcome to XeonLLM"), "Welcome to XeonLLM")
        XCTAssertEqual(AppSupport.directory.lastPathComponent, "XeonLLM")
    }

    /// make-app.sh writes the identity under these names, and the app reads exactly these.
    func testTheIdentityIsReadUnderTheXeonKeys() {
        let identity = AppInfo.Identity(values: ["XEONNoAVX2": true,
                                                 "XEONProductName": "TestLLM",
                                                 "XEONIdentifier": "dev.testllm.app",
                                                 "XEONDataFolder": "TestLLM",
                                                 "XEONProductVersion": "1.2.3",
                                                 "XEONUpdatesDisabled": true])
        XCTAssertTrue(identity.noAVX2)
        XCTAssertEqual(identity.name, "TestLLM")
        XCTAssertEqual(identity.identifier, "dev.testllm.app")
        XCTAssertEqual(identity.dataFolder, "TestLLM")
        XCTAssertEqual(identity.productVersion, "1.2.3")
        XCTAssertTrue(identity.updatesDisabled)
    }

    /// No aliases: a bundle still carrying the old key names is a plain XeonLLM build.
    func testTheOldKeyNamesAreIgnored() {
        let identity = AppInfo.Identity(values: ["TOSHNoAVX2": true,
                                                 "TOSHProductName": "OldLLM",
                                                 "TOSHIdentifier": "dev.oldllm.app",
                                                 "TOSHDataFolder": "OldLLM",
                                                 "TOSHProductVersion": "0.0.1",
                                                 "TOSHUpdatesDisabled": true])
        XCTAssertFalse(identity.noAVX2)
        XCTAssertNil(identity.name)
        XCTAssertNil(identity.identifier)
        XCTAssertNil(identity.dataFolder)
        XCTAssertNil(identity.productVersion)
        XCTAssertFalse(identity.updatesDisabled)
        XCTAssertEqual(identity.name ?? "XeonLLM", "XeonLLM")
        XCTAssertEqual(identity.identifier ?? "dev.xeonllm.app", "dev.xeonllm.app")
    }
}