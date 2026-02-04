import Foundation
import GRDB

class DatabaseManager {
    static let shared = DatabaseManager()

    private(set) var dbQueue: DatabaseQueue!

    private init() {
        do {
            try setupDatabase()
        } catch {
            fatalError("Database setup failed: \(error)")
        }
    }

    private func setupDatabase() throws {
        let fileManager = FileManager.default
        let appSupportURL = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbURL = appSupportURL.appendingPathComponent("booktalk.sqlite")

        dbQueue = try DatabaseQueue(path: dbURL.path)

        try migrator.migrate(dbQueue)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            // Books table
            try db.create(table: "books") { t in
                t.column("id", .text).primaryKey()
                t.column("title", .text).notNull()
                t.column("author", .text)
                t.column("coverImagePath", .text)
                t.column("isbn", .text)
                t.column("archived", .boolean).notNull().defaults(to: false)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            // Annotations table
            try db.create(table: "annotations") { t in
                t.column("id", .text).primaryKey()
                t.column("bookId", .text).notNull().references("books", onDelete: .cascade)
                t.column("type", .text).notNull()
                t.column("audioPath", .text)
                t.column("imagePath", .text)
                t.column("caption", .text)
                t.column("transcription", .text)
                t.column("duration", .double)
                t.column("createdAt", .datetime).notNull()
            }

            // FTS5 virtual table for full-text search
            try db.execute(sql: """
                CREATE VIRTUAL TABLE annotations_fts USING fts5(
                    id,
                    caption,
                    transcription,
                    content='annotations',
                    content_rowid='rowid'
                )
            """)

            // Triggers to keep FTS in sync
            try db.execute(sql: """
                CREATE TRIGGER annotations_ai AFTER INSERT ON annotations BEGIN
                    INSERT INTO annotations_fts(rowid, id, caption, transcription)
                    VALUES (NEW.rowid, NEW.id, NEW.caption, NEW.transcription);
                END
            """)

            try db.execute(sql: """
                CREATE TRIGGER annotations_ad AFTER DELETE ON annotations BEGIN
                    INSERT INTO annotations_fts(annotations_fts, rowid, id, caption, transcription)
                    VALUES('delete', OLD.rowid, OLD.id, OLD.caption, OLD.transcription);
                END
            """)

            try db.execute(sql: """
                CREATE TRIGGER annotations_au AFTER UPDATE ON annotations BEGIN
                    INSERT INTO annotations_fts(annotations_fts, rowid, id, caption, transcription)
                    VALUES('delete', OLD.rowid, OLD.id, OLD.caption, OLD.transcription);
                    INSERT INTO annotations_fts(rowid, id, caption, transcription)
                    VALUES (NEW.rowid, NEW.id, NEW.caption, NEW.transcription);
                END
            """)
        }

        migrator.registerMigration("v2") { db in
            // Add pageNumber column to annotations
            try db.alter(table: "annotations") { t in
                t.add(column: "pageNumber", .text)
            }
        }

        migrator.registerMigration("v3") { db in
            // Add videoPath column to annotations
            try db.alter(table: "annotations") { t in
                t.add(column: "videoPath", .text)
            }
        }

        return migrator
    }
}

// MARK: - Directory Helpers
extension DatabaseManager {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var audioDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("Audio")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var imagesDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("Images")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var coversDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("Covers")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static var videosDirectory: URL {
        let url = documentsDirectory.appendingPathComponent("Videos")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
