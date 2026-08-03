import Foundation
import OSLog

/// Before opening the SwiftData store for the first time on a v2 install, scan
/// the SQLite file at `~/Library/Application Support/Signoff/store.sqlite` and
/// rewrite any `Bucket.id == "general"` to `"standard"`. Then rename every
/// `SignoffGeneration.bucketId == "general"` likewise.
///
/// This is the legacy v1 → v2 bucket-naming reconciliation step. It MUST run
/// *before* the SwiftData schema migration so foreign-key-style invariants survive.
/// Idempotent.
public enum MigrationPreScan {
    private static let didRunFlagKey = "com.signoff.migrationPreScan.didRun"

    public static func rewriteLegacyIDsIfNeeded() {
        guard UserDefaults.standard.bool(forKey: didRunFlagKey) == false else { return }
        let fm = FileManager.default
        guard let dir = try? fm.url(for: .applicationSupportDirectory,
                                    in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("Signoff", isDirectory: true) else { return }
        let storeURL = dir.appendingPathComponent("store.sqlite")
        guard fm.fileExists(atPath: storeURL.path) else {
            UserDefaults.standard.set(true, forKey: didRunFlagKey)
            return
        }
        // Open SQLite directly and rewrite.
        var db: OpaquePointer?
        if sqlite3_open(storeURL.path, &db) != SQLITE_OK {
            Logger(subsystem: "app.signoff", category: "migration").warning("MigrationPreScan: could not open SQLite for legacy rewrite")
            return
        }
        defer { sqlite3_close(db) }
        exec(db, "UPDATE ZBUCKET SET ZID = 'standard' WHERE ZID = 'general'")
        exec(db, "UPDATE ZBUCKET SET ZNAME = 'Standard' WHERE ZNAME = 'General'")
        exec(db, "UPDATE ZSIGNOFFGENERATION SET ZBUCKETID = 'standard' WHERE ZBUCKETID = 'general'")
        UserDefaults.standard.set(true, forKey: didRunFlagKey)
        Logger(subsystem: "app.signoff", category: "migration").info("MigrationPreScan: legacy rewrite complete")
    }

    private static func exec(_ db: OpaquePointer?, _ sql: String) {
        var err: UnsafeMutablePointer<CChar>?
        let s = sql.withCString { cstr -> Int32 in
            sqlite3_exec(db, cstr, nil, nil, &err)
        }
        if s != SQLITE_OK {
            if let err = err { print("MigrationPreScan exec failed: \(String(cString: err))") }
            sqlite3_free(err)
        }
    }
}

import SQLite3
