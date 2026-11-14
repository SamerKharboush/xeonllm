// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import SwiftUI

struct BenchmarkShareReviewSheet: View {
    @EnvironmentObject private var loc: Localizer
    @State private var showTechnicalDetails = false
    @State private var showBenchmarkLog = false
    @State private var copiedJSON = false

    let review: BenchmarkShareReview
    let onCancel: () -> Void
    let onSubmit: () -> Void

    init(prepared: BenchmarkSharing.Prepared, onCancel: @escaping () -> Void, onSubmit: @escaping () -> Void) {
        review = BenchmarkShareReview(payload: prepared.payload, keyFingerprint: prepared.keyFingerprint)
        self.onCancel = onCancel
        self.onSubmit = onSubmit
    }

    private let columns = [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)]

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    privacySummary
                    resultSummary
                    systemSummary
                    artifactSummary
                    identitySummary
                    technicalDetails
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .background(WorkspaceStyle.canvas)
        .frame(minWidth: 680, idealWidth: 760, maxWidth: 880,
               minHeight: 620, idealHeight: 720, maxHeight: 860)
    }

    private var header: some View {
        HStack(spacing: 14) {
            SectionGlyph(systemName: "checkmark.shield")
            VStack(alignment: .leading, spacing: 3) {
                Text(AppInfo.branded("Review before signing"))
                    .font(.title3)
                    .bold()
                Text(AppInfo.branded("Nothing has been uploaded yet."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(ByteCountFormatter.string(fromByteCount: Int64(review.payloadByteCount), countStyle: .file))
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
                .help(AppInfo.branded("Exact size of the JSON that will be signed"))
        }
        .padding(20)
    }

    private var privacySummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(AppInfo.branded("Only this benchmark will be sent"),
                  systemImage: "lock.shield.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text(AppInfo.branded("XeonLLM does not include chats, prompts, account names, or local paths. Model files are not uploaded either: only their name, size, and SHA-256 are included."))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 18) {
                Label(AppInfo.branded("No chat content"), systemImage: "checkmark.circle")
                Label(AppInfo.branded("No local paths"), systemImage: "checkmark.circle")
                Label(AppInfo.branded("Private key stays in Keychain"), systemImage: "checkmark.circle")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).stroke(.green.opacity(0.22)) }
    }

    private var resultSummary: some View {
        BenchmarkReviewSection(AppInfo.branded("Measured result"), systemImage: "gauge.with.dots.needle.67percent") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(review.modelName).font(.title3).bold()
                    Spacer()
                    Text("\(review.quantization) · \(review.family)")
                        .font(.callout.monospaced())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    BenchmarkReviewMetric(label: AppInfo.branded("Prompt processing"),
                                          value: String(format: "%.1f t/s", review.promptMedian),
                                          detail: runValues(review.promptRuns))
                    BenchmarkReviewMetric(label: AppInfo.branded("Generation"),
                                          value: String(format: "%.1f t/s", review.generationMedian),
                                          detail: runValues(review.generationRuns))
                }
                Text(AppInfo.branded("Median of \(review.repetitions) independent runs · pp\(review.promptTokens) / tg\(review.generatedTokens)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var systemSummary: some View {
        BenchmarkReviewSection(AppInfo.branded("Machine and configuration"), systemImage: "desktopcomputer") {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                BenchmarkReviewField(label: "GPU", value: review.gpu)
                BenchmarkReviewField(label: "CPU", value: review.cpu)
                BenchmarkReviewField(label: AppInfo.branded("Memory"), value: review.memory)
                BenchmarkReviewField(label: AppInfo.branded("System"), value: "\(review.machine) · \(review.operatingSystem)")
                BenchmarkReviewField(label: AppInfo.branded("Backend / Flash Attention"), value: "\(review.backend) · \(review.flashAttention)")
                BenchmarkReviewField(label: AppInfo.branded("GPU layers / CPU experts"), value: "\(review.gpuLayers) / \(review.cpuMoeExperts)")
                BenchmarkReviewField(label: AppInfo.branded("KV cache"), value: review.cacheTypes)
                BenchmarkReviewField(label: AppInfo.branded("App / context"), value: "\(review.appVersion) · \(review.contextDepth)")
            }
        }
    }

    private var artifactSummary: some View {
        BenchmarkReviewSection(AppInfo.branded("Model identity"), systemImage: "shippingbox") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(review.artifacts) { artifact in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(artifact.name).font(.callout).bold().lineLimit(1)
                            Spacer()
                            Text(artifact.formattedSize).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(artifact.sha256)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                            .help(artifact.sha256)
                    }
                    if artifact.id != review.artifacts.last?.id { Divider() }
                }
            }
        }
    }

    private var identitySummary: some View {
        BenchmarkReviewSection(AppInfo.branded("Signature and public identity"), systemImage: "signature") {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppInfo.branded("The private key remains in this Mac's Keychain. This public fingerprint groups your submissions and verifies that they were not modified."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(review.keyFingerprint)
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(review.keyFingerprint)
                if !review.contributor.isEmpty {
                    BenchmarkReviewField(label: AppInfo.branded("Public alias"), value: review.contributor)
                }
            }
        }
    }

    private var technicalDetails: some View {
        BenchmarkReviewSection(AppInfo.branded("Technical evidence"), systemImage: "curlybraces") {
            DisclosureGroup(isExpanded: $showTechnicalDetails) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(AppInfo.branded("The JSON is formatted here for readability. Signing uses the exact original bytes; the complete log is shown separately."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button(copiedJSON ? AppInfo.branded("JSON copied") : AppInfo.branded("Copy exact JSON"),
                           systemImage: copiedJSON ? "checkmark" : "doc.on.doc",
                           action: copyExactJSON)
                        .buttonStyle(.borderless)
                    ScrollView([.horizontal, .vertical]) {
                        Text(review.formattedJSON)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    }
                    .frame(minHeight: 180, maxHeight: 280)
                .background(WorkspaceStyle.inset, in: RoundedRectangle(cornerRadius: 8))
                    DisclosureGroup(isExpanded: $showBenchmarkLog) {
                        ScrollView([.horizontal, .vertical]) {
                            Text(review.rawOutput)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        }
                        .frame(height: 220)
                        .background(WorkspaceStyle.inset, in: RoundedRectangle(cornerRadius: 8))
                    } label: {
                        Text(AppInfo.branded("Complete benchmark log"))
                    }
                }
                .padding(.top, 10)
            } label: {
                Text(AppInfo.branded("Show JSON and log"))
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Label(AppInfo.branded("Only after confirmation will this content be signed and sent."),
                  systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(AppInfo.branded("Cancel"), role: .cancel, action: onCancel)
                .glassButton()
            Button(AppInfo.branded("Sign and send benchmark"),
                   systemImage: "paperplane.fill", action: onSubmit)
                .glassButton(prominent: true)
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func runValues(_ values: [Double]) -> String {
        values.map { String(format: "%.1f", $0) }.joined(separator: " · ")
    }

    private func copyExactJSON() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(review.exactJSON, forType: .string)
        copiedJSON = true
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copiedJSON = false
        }
    }
}
