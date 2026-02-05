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
    
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let title = Column(CodingKeys.title)
        static let author = Column(CodingKeys.author)
        static let archived = Column(CodingKeys.archived)
        static let createdAt = Column(CodingKeys.createdAt)
        static let updatedAt = Column(CodingKeys.updatedAt)
    }
}

// MARK: - Database Operations
extension Book {
    static func all(archived: Bool = false) throws -> [Book] {
        try DatabaseManager.shared.dbQueue.read { db in
            try Book
                .filter(Column("archived") == archived)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }
    
    static func find(id: String) throws -> Book? {
        try DatabaseManager.shared.dbQueue.read { db in
            try Book.fetchOne(db, key: id)
        }
    }
    
    @discardableResult
    mutating func save() throws -> Book {
        updatedAt = Date()
        try DatabaseManager.shared.dbQueue.write { db in
            try self.save(db)
        }
        // Index in Spotlight
        SpotlightService.shared.indexBook(self)
        return self
    }
    
    func delete() throws {
        // Delete associated annotations
        let annotations = try Annotation.forBook(id)
        for annotation in annotations {
            try annotation.delete()
        }
        
        // Delete cover image
        if let url = coverImageURL {
            try? FileManager.default.removeItem(at: url)
        }
        
        // Remove from Spotlight
        SpotlightService.shared.removeBook(id)
        
        try DatabaseManager.shared.dbQueue.write { db in
            _ = try Book.deleteOne(db, key: id)
        }
    }
    
    mutating func toggleArchived() throws {
        archived.toggle()
        try save()
    }
    
    func annotationCount() throws -> Int {
        try DatabaseManager.shared.dbQueue.read { db in
            try Annotation
                .filter(Annotation.Columns.bookId == id)
                .fetchCount(db)
        }
    }
}
