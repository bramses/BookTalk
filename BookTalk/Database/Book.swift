import Foundation
import GRDB

struct Book: Identifiable, Codable, Hashable {
    var id: String
    var title: String
    var author: String?
    var coverImagePath: String?
    var isbn: String?
    var archived: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        author: String? = nil,
        coverImagePath: String? = nil,
        isbn: String? = nil,
        archived: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.coverImagePath = coverImagePath
        self.isbn = isbn
        self.archived = archived
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var coverImageURL: URL? {
        guard let path = coverImagePath else { return nil }
        return DatabaseManager.coversDirectory.appendingPathComponent(path)
    }
}

// MARK: - GRDB Record
extension Book: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "books" }
}

// MARK: - Database Operations
extension Book {
    static func all(archived: Bool = false) throws -> [Book] {
        try DatabaseManager.shared.dbQueue.read { db in
            try Book
                .filter(Column("archived") == archived)
                .order(Column("updatedAt").desc)
                .fetchAll(db)
        }
    }

    static func find(id: String) throws -> Book? {
        try DatabaseManager.shared.dbQueue.read { db in
            try Book.fetchOne(db, key: id)
        }
    }

    @discardableResult
    func save() throws -> Book {
        var book = self
        book.updatedAt = Date()
        try DatabaseManager.shared.dbQueue.write { db in
            try book.save(db)
        }
        return book
    }

    func delete() throws {
        try DatabaseManager.shared.dbQueue.write { db in
            _ = try Book.deleteOne(db, key: id)
        }

        // Delete cover image if exists
        if let url = coverImageURL {
            try? FileManager.default.removeItem(at: url)
        }
    }

    mutating func toggleArchived() throws {
        archived.toggle()
        updatedAt = Date()
        try DatabaseManager.shared.dbQueue.write { db in
            try self.save(db)
        }
    }

    func annotationCount() throws -> Int {
        try DatabaseManager.shared.dbQueue.read { db in
            try Annotation
                .filter(Column("bookId") == id)
                .fetchCount(db)
        }
    }
}
