// XeonLLM - run LLMs locally (fork of ToshLLM) on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import XCTest
@testable import XeonLLM

/// The toolbar, About and docs all read AppInfo.donateOptions, so a change there is a
/// change everywhere. The maintainer's channels are exactly these two.
final class DonateOptionsTests: XCTestCase {
    func testTheDonateOptionsAreExactlySponsorsAndPayPal() {
        let urls = AppInfo.donateOptions.map(\.url)
        XCTAssertEqual(urls, ["https://github.com/sponsors/SamerKharboush",
                              "https://paypal.me/Samerelnady"])
        XCTAssertEqual(AppInfo.donateOptions.map(\.label), ["GitHub Sponsors", "PayPal"])
    }

    func testEveryDonateOptionIsAUsableHTTPSURL() {
        for option in AppInfo.donateOptions {
            let url = URL(string: option.url)
            XCTAssertNotNil(url, option.url)
            XCTAssertEqual(url?.scheme, "https")
            XCTAssertNotNil(url?.host)
        }
    }
}