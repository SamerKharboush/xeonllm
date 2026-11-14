// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// App text, English only.
///
/// The interface ships one language. `Localizer` stays as an `ObservableObject`
/// because the views take it as an environment object and several of them hand
/// it to helper views and functions; it has no state and no lookup to do.
///
/// A language code left in `UserDefaults` by an earlier build is simply never
/// read, so it cannot break a launch.
final class Localizer: ObservableObject {
    init() {}
}