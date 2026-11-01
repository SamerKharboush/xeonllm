// XeonLLM - run LLMs locally on Intel Macs with AMD GPUs (fork of ToshLLM)
// Copyright (C) 2026 Engelbert Delgado <engeldlgado@gmail.com>
// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation
import Security

/// One-time migration from ToshLLM (dev.engel.toshllm) to XeonLLM (dev.xeonllm.app).
/// Copies settings, data folders and keychain items once; never deletes the old data.
enum IdentityMigration {
    /// The bundle identifier ToshLLM used.
    static let oldIdentifier = "dev.engel.toshllm"
    
    /// The data folder name ToshLLM used.
    static let oldDataFolder = "ToshLLM"
    
    /// Marker key in UserDefaults indicating migration has been performed.
    static let markerKey = "migratedFromToshLLM"

    /// Second marker: beta.5 copied the folder only when XeonLLM's did not exist yet,
    /// so users it migrated still need the per-item merge once.
    static let folderMarkerKey = "migratedFromToshLLMFolderV2"
    
    /// Run the one-time migration from ToshLLM to the current identity.
    ///
    /// - Parameters:
    ///   - defaults: UserDefaults instance to write the marker to (defaults to .standard).
    ///   - oldDomain: Optional preset value for UserDefaults(suiteName: oldIdentifier). If nil, read now.
    ///   - supportDir: Application Support base directory.
    ///   - newDataFolder: Target data folder name (from AppInfo.dataFolder).
    ///   - keychain: Whether to migrate keychain items (set false for tests).
    static func run(defaults: UserDefaults = .standard,
                    oldDomain: [String: Any]? = UserDefaults.standard.persistentDomain(forName: oldIdentifier),
                    supportDir: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!,
                    newDataFolder: String = AppInfo.dataFolder,
                    keychain: Bool = true) {
        
        // Still using the old identifier, or another product built from this tree.
        guard AppInfo.identifier != oldIdentifier else { return }
        guard !AppInfo.isRebranded else { return }

        let fm = FileManager.default
        let oldPath = supportDir.appendingPathComponent(oldDataFolder, isDirectory: true)
        let newPath = supportDir.appendingPathComponent(newDataFolder, isDirectory: true)

        // === Settings and keychain ===
        if !defaults.bool(forKey: markerKey) {
            if let oldDomain = oldDomain {
                var copiedCount = 0
                for (key, value) in oldDomain where
                    !key.hasPrefix("NS") &&
                    !key.hasPrefix("Apple") &&
                    defaults.object(forKey: key) == nil {
                    defaults.set(value, forKey: key)
                    copiedCount += 1
                }
                if copiedCount > 0 {
                    AppLog.app.info("Migrated \(copiedCount) UserDefaults entries from \(oldIdentifier)")
                }
            }

            if keychain {
                copyKeychainItems(oldService: oldIdentifier, newService: AppInfo.identifier)
            }

            defaults.set(true, forKey: markerKey)
        }

        // === Data folder: per-item merge, even when XeonLLM's folder exists ===
        if !defaults.bool(forKey: folderMarkerKey), fm.fileExists(atPath: oldPath.path) {
            do {
                try mergeFolder(from: oldPath, into: newPath, fm: fm)
                defaults.set(true, forKey: folderMarkerKey)
                AppLog.app.info("Merged data folder \(oldDataFolder) → \(newDataFolder)")
            } catch {
                AppLog.app.error("Could not merge data folder: \(error.localizedDescription)")
            }
        }
    }

    /// Copies what the new folder lacks and recurses into directories. A file that is
    /// already there is never overwritten; conversations and projects are merged by id.
    private static func mergeFolder(from old: URL, into new: URL, fm: FileManager) throws {
        try fm.createDirectory(at: new, withIntermediateDirectories: true)
        let items = try fm.contentsOfDirectory(at: old, includingPropertiesForKeys: [.isDirectoryKey])
        for item in items {
            let destination = new.appendingPathComponent(item.lastPathComponent)
            var destinationIsDirectory: ObjCBool = false
            let exists = fm.fileExists(atPath: destination.path, isDirectory: &destinationIsDirectory)

            if item.lastPathComponent == "conversations.json" || item.lastPathComponent == "projects.json" {
                if !exists {
                    try fm.copyItem(at: item, to: destination)
                } else if !destinationIsDirectory.boolValue {
                    try mergeJSON(from: item, into: destination)
                }
                continue
            }

            if !exists {
                try fm.copyItem(at: item, to: destination)
                continue
            }

            var oldIsDirectory: ObjCBool = false
            _ = fm.fileExists(atPath: item.path, isDirectory: &oldIsDirectory)
            if oldIsDirectory.boolValue && destinationIsDirectory.boolValue {
                try mergeFolder(from: item, into: destination, fm: fm)
            }
            // Both are files (or types differ): the new copy wins, leave it untouched.
        }
    }

    /// Union of both arrays by the entry's `id`. The new copy wins on a conflict.
    private static func mergeJSON(from old: URL, into new: URL) throws {
        let oldData = try Data(contentsOf: old)
        let newData = try Data(contentsOf: new)
        guard let oldEntries = try? JSONSerialization.jsonObject(with: oldData) as? [[String: Any]],
              let newEntries = try? JSONSerialization.jsonObject(with: newData) as? [[String: Any]] else {
            return   // unknown shape: keep the new file as it is
        }

        var seen = Set(newEntries.compactMap(idKey))
        var merged = newEntries
        for entry in oldEntries {
            if let id = idKey(entry) {
                guard seen.insert(id).inserted else { continue }
            }
            merged.append(entry)
        }
        guard merged.count != newEntries.count else { return }

        let data = try JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
        try data.write(to: new, options: .atomic)
    }

    private static func idKey(_ entry: [String: Any]) -> String? {
        if let value = entry["id"] as? String { return value }
        if let value = entry["id"] as? NSNumber { return value.stringValue }
        return nil
    }
    
    static func copyKeychainItems(oldService: String, newService: String) {
        // the file keychain rejects kSecMatchLimitAll with kSecReturnData, so list the accounts first
        for account in keychainAccounts(service: oldService) where keychainData(service: newService, account: account) == nil {
            guard let data = keychainData(service: oldService, account: account) else { continue }
            let item: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: newService,
                kSecAttrAccount as String: account,
                kSecValueData as String: data,
            ]
            if SecItemAdd(item as CFDictionary, nil) == errSecSuccess {
                AppLog.app.info("Copied keychain item for account '\(account)'")
            }
        }
    }

    private static func keychainAccounts(service: String) -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    private static func keychainData(service: String, account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }
}
