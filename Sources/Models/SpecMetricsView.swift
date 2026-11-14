// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI

/// Live acceptance of the running server's speculation, broken down by draft
/// position. Hidden entirely while nothing has been drafted.
struct SpecMetricsView: View {
    let port: Int
    @EnvironmentObject private var loc: Localizer
    @State private var metrics: SpecDecodeMetrics?
    @State private var timer: Timer?

    var body: some View {
        Group {
            if let m = metrics, m.ran {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: "chart.bar.xaxis").frame(width: 18).foregroundStyle(.secondary)
                        Text(AppInfo.branded("Draft acceptance")).font(.callout)
                        Spacer(minLength: 8)
                        Text(percent(m.acceptance))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .help(AppInfo.branded("Share of the drafted tokens the big model confirmed, accumulated since the server started. It does not change answer quality, only speed."))

                    if let mean = m.meanAccepted {
                        metricRow(AppInfo.branded("Tokens gained per step"),
                                  String(format: "%.2f", mean),
                                  help: AppInfo.branded("Mean tokens accepted per verification. Below 1 the speculation costs more than it saves."))
                    }

                    ForEach(Array(m.acceptedPerPosition.indices), id: \.self) { i in
                        if let share = m.acceptance(atPosition: i) {
                            positionRow(index: i, share: share)
                        }
                    }
                }
                .help(AppInfo.branded("Each position is one more token of draft depth; when the last one drops a lot, the depth is wasted."))
            }
        }
        .onAppear(perform: start)
        .onDisappear { timer?.invalidate(); timer = nil }
    }

    private func metricRow(_ title: String, _ value: String, help: String) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }
        .help(help)
    }

    private func positionRow(index: Int, share: Double) -> some View {
        HStack(spacing: 8) {
            Text(AppInfo.branded("Position \(index + 1)"))
                .font(.caption).foregroundStyle(.secondary)
                .frame(width: 78, alignment: .leading)
            ProgressView(value: share).controlSize(.small)
            Text(percent(share))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private func percent(_ value: Double?) -> String {
        guard let value else { return "--" }
        return String(format: "%.0f%%", value * 100)
    }

    private func start() {
        refresh()
        timer?.invalidate()
        // the engine now serves /metrics while it decodes, so the readout can follow
        // a generation instead of freezing until it ends
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            Task { @MainActor in refresh() }
        }
    }

    private func refresh() {
        let port = self.port
        Task { @MainActor in
            metrics = await SpecDecodeMetrics.fetch(port: port)
        }
    }
}
