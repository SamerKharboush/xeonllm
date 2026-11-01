// XeonLLM - run LLMs (fork of ToshLLM) locally on Intel Macs with AMD GPUs
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// The PATH a Finder launch must hand to the engine and to MCP servers: the user's
/// login-shell PATH (read once with a timeout) plus the usual install locations.
enum UserShellPath {
    /// Fixed locations a GUI launch does not inherit.
    static let fixedDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]
    /// Home-relative install locations, in search order.
    static let homeDirectories = [".local/bin", ".cargo/bin", ".bun/bin", ".volta/bin", ".deno/bin"]

    private static let startMarker = "__XEONLLM_PATH__"
    private static let endMarker = "__XEONLLM_END__"

    final class Loader {
        let environment: [String: String]
        let timeout: TimeInterval
        let run: (String, [String], TimeInterval) -> String?
        private let lock = NSLock()
        /// `nil` means not read yet; `.some(nil)` means read and failed.
        private var cached: String??

        init(environment: [String: String] = ProcessInfo.processInfo.environment,
             timeout: TimeInterval = 3,
             run: @escaping (String, [String], TimeInterval) -> String? = UserShellPath.runShell) {
            self.environment = environment
            self.timeout = timeout
            self.run = run
        }

        /// The login shell's PATH. Read once; a failure is cached as nil and stays silent.
        func loginPath() -> String? {
            lock.lock()
            defer { lock.unlock() }
            if let cached { return cached }

            let shell = environment["SHELL"].flatMap { $0.isEmpty ? nil : $0 } ?? "/bin/zsh"
            let command = "printf '\(startMarker)%s\(endMarker)' \"$PATH\""
            let output = run(shell, ["-lic", command], timeout)
            let result = output.flatMap(Self.extract)
            cached = .some(result)
            return result
        }

        /// Login PATH first, then `base`, then the fixed and home locations, without duplicates.
        func merged(_ base: String? = nil, home: String = NSHomeDirectory()) -> String {
            var values: [String] = []
            for source in [loginPath(), base] {
                values.append(contentsOf: (source ?? "").split(separator: ":").map(String.init))
            }
            values.append(contentsOf: fixedDirectories)
            for directory in homeDirectories {
                let path = (home as NSString).appendingPathComponent(directory)
                if FileManager.default.fileExists(atPath: path) { values.append(path) }
            }
            if let node = newestNode(home) { values.append(node) }

            var seen = Set<String>()
            return values.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
        }

        private static func extract(_ output: String) -> String? {
            if let start = output.range(of: startMarker),
               let end = output.range(of: endMarker, range: start.upperBound..<output.endIndex) {
                let value = String(output[start.upperBound..<end.lowerBound])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                return value.isEmpty ? nil : value
            }
            // A shell that ignored the markers still prints the PATH last.
            let value = (output.split(whereSeparator: \.isNewline).last.map(String.init) ?? output)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }

        /// The newest node installed through nvm, if any.
        private func newestNode(_ home: String) -> String? {
            let root = (home as NSString).appendingPathComponent(".nvm/versions/node")
            guard let versions = try? FileManager.default.contentsOfDirectory(atPath: root) else { return nil }
            let visible = versions.filter { !$0.hasPrefix(".") }
            guard let newest = visible.max(by: { $0.compare($1, options: .numeric) == .orderedAscending }) else { return nil }
            let bin = ((root as NSString).appendingPathComponent(newest) as NSString)
                .appendingPathComponent("bin")
            return FileManager.default.fileExists(atPath: bin) ? bin : nil
        }
    }

    static let shared = Loader()

    static func loginPath() -> String? { shared.loginPath() }
    static func merged(_ base: String? = nil) -> String { shared.merged(base) }

    /// Runs the shell with a hard deadline. Output after the deadline is discarded.
    static func runShell(_ shell: String, _ arguments: [String], _ timeout: TimeInterval) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }

        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.01)
        }
        guard !process.isRunning else {
            process.terminate()
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return String(decoding: data, as: UTF8.self)
    }
}
