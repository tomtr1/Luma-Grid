import Foundation

/// Raw byte storage for the save file. Abstracted so tests can use memory instead of disk.
public protocol ProgressDataStorage: AnyObject {
    func read() throws -> Data?
    func write(_ data: Data) throws
    /// Moves an unreadable save aside (kept for support/debugging) so a fresh one can be written.
    func quarantineCorruptData()
}

public enum ProgressLoadIssue: Equatable, Sendable {
    case none
    case noSaveFound
    case corruptDataReset
    case migrated(fromVersion: Int)
    case newerSchema(version: Int)
}

/// Encodes, decodes, and migrates `PlayerProgress`.
public enum ProgressCodec {
    public static func encode(_ progress: PlayerProgress) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var copy = progress
        copy.schemaVersion = PlayerProgress.currentSchemaVersion
        copy.daily.trim()
        return try encoder.encode(copy)
    }

    /// Never throws: unreadable data yields fresh defaults plus an issue describing what happened.
    public static func decode(_ data: Data) -> (PlayerProgress, ProgressLoadIssue) {
        guard
            let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return (PlayerProgress(), .corruptDataReset)
        }
        let version = raw["schemaVersion"] as? Int ?? 0
        let migrated = migrate(raw, fromVersion: version)
        guard
            let migratedData = try? JSONSerialization.data(withJSONObject: migrated),
            var progress = try? JSONDecoder().decode(PlayerProgress.self, from: migratedData)
        else {
            return (PlayerProgress(), .corruptDataReset)
        }
        let issue: ProgressLoadIssue
        if version < PlayerProgress.currentSchemaVersion {
            issue = .migrated(fromVersion: version)
        } else if version > PlayerProgress.currentSchemaVersion {
            // Written by a newer app version (e.g. after a downgrade). Known fields are kept;
            // unknown ones are ignored.
            issue = .newerSchema(version: version)
        } else {
            issue = .none
        }
        progress.schemaVersion = PlayerProgress.currentSchemaVersion
        return (progress, issue)
    }

    /// Step-wise migrations on the raw JSON dictionary. Add a case per schema bump.
    static func migrate(_ raw: [String: Any], fromVersion version: Int) -> [String: Any] {
        var json = raw
        if version < 1 {
            // Version 0: unversioned pre-release prototype saves used `highScore` and a flat
            // `soundOn` flag. Map them onto the v1 layout.
            if json["bestScore"] == nil, let highScore = json["highScore"] as? Int {
                json["bestScore"] = highScore
            }
            if json["settings"] == nil, let soundOn = json["soundOn"] as? Bool {
                json["settings"] = ["soundEnabled": soundOn]
            }
            json.removeValue(forKey: "highScore")
            json.removeValue(forKey: "soundOn")
        }
        json["schemaVersion"] = PlayerProgress.currentSchemaVersion
        return json
    }
}

/// Loads and saves progress through a storage backend.
public final class ProgressRepository {
    private let storage: ProgressDataStorage

    public init(storage: ProgressDataStorage) {
        self.storage = storage
    }

    public func load() -> (PlayerProgress, ProgressLoadIssue) {
        let data: Data?
        do {
            data = try storage.read()
        } catch {
            storage.quarantineCorruptData()
            return (PlayerProgress(), .corruptDataReset)
        }
        guard let data else { return (PlayerProgress(), .noSaveFound) }
        let (progress, issue) = ProgressCodec.decode(data)
        if issue == .corruptDataReset { storage.quarantineCorruptData() }
        return (progress, issue)
    }

    public func save(_ progress: PlayerProgress) throws {
        try storage.write(try ProgressCodec.encode(progress))
    }
}

/// Stores the save file in Application Support, written atomically so an interrupted write
/// can never leave a half-written file behind.
public final class FileProgressStorage: ProgressDataStorage {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public static func defaultLocation(fileManager: FileManager = .default) throws -> FileProgressStorage {
        let directory = try fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("LumaGrid", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return FileProgressStorage(fileURL: directory.appendingPathComponent("progress.json"))
    }

    public func read() throws -> Data? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try Data(contentsOf: fileURL)
    }

    public func write(_ data: Data) throws {
        try data.write(to: fileURL, options: [.atomic])
    }

    public func quarantineCorruptData() {
        let backup = fileURL.deletingPathExtension().appendingPathExtension("corrupt.json")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: fileURL, to: backup)
    }
}

/// In-memory storage for tests, previews, and UI-test launches.
public final class InMemoryProgressStorage: ProgressDataStorage {
    public var data: Data?
    public private(set) var quarantineCount = 0
    public var failWrites = false

    public init(data: Data? = nil) {
        self.data = data
    }

    public func read() throws -> Data? { data }

    public func write(_ data: Data) throws {
        if failWrites { throw CocoaError(.fileWriteUnknown) }
        self.data = data
    }

    public func quarantineCorruptData() {
        quarantineCount += 1
        data = nil
    }
}
