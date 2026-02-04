import Foundation
import GRDB
import CoreSpotlight

enum AnnotationType: String, Codable {
    case audio
    case image
    case video
    case text
}

struct Annotation: Identifiable, Codable {
    var id: String
    var bookId: String
    var type: AnnotationType
    var audioPath: String?
    var imagePath: String?
    var videoPath: String?
    var caption: String?
    var transcription: String?
    var duration: Double?
    var pageNumber: String?
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        bookId: String,
        type: AnnotationType,
        audioPath: String? = nil,
        imagePath: String? = nil,
        videoPath: String? = nil,
        caption: String? = nil,
        transcription: String? = nil,
        duration: Double? = nil,
        pageNumber: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookId = bookId
        self.type = type
        self.audioPath = audioPath
        self.imagePath = imagePath
        self.videoPath = videoPath
        self.caption = caption
        self.transcription = transcription
        self.duration = duration
        self.pageNumber = pageNumber
        self.createdAt = createdAt
    }

    var audioURL: URL? {
        guard let path = audioPath else { return nil }
        return DatabaseManager.audioDirectory.appendingPathComponent(path)
    }

    var videoURL: URL? {
        guard let path = videoPath else { return nil }
        return DatabaseManager.videosDirectory.appendingPathComponent(path)
    }

    var imageURL: URL? {
        guard let path = imagePath else { return nil }
        return DatabaseManager.imagesDirectory.appendingPathComponent(path)
    }

    var formattedDuration: String {
        guard let duration = duration else { return "" }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}

// MARK: - GRDB Record
extension Annotation: FetchableRecord, PersistableRecord {
    static var databaseTableName: String { "annotations" }

    enum Columns {
        static let id = Column(CodingKeys.id)
        static let bookId = Column(CodingKeys.bookId)
        static let type = Column(CodingKeys.type)
        static let caption = Column(CodingKeys.caption)
        static let transcription = Column(CodingKeys.transcription)
        static let pageNumber = Column(CodingKeys.pageNumber)
        static let createdAt = Column(CodingKeys.createdAt)
    }
}

// MARK: - Database Operations
extension Annotation {
    static func forBook(_ bookId: String) throws -> [Annotation] {
        try DatabaseManager.shared.dbQueue.read { db in
            try Annotation
                .filter(Column("bookId") == bookId)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    static func all(limit: Int? = nil) throws -> [Annotation] {
        try DatabaseManager.shared.dbQueue.read { db in
            var request = Annotation.order(Column("createdAt").desc)
            if let limit = limit {
                request = request.limit(limit)
            }
            return try request.fetchAll(db)
        }
    }

    static func allPaginated(limit: Int, offset: Int) throws -> [Annotation] {
        try DatabaseManager.shared.dbQueue.read { db in
            try Annotation
                .order(Column("createdAt").desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }

    /// Fetch annotations in a random order using a seed for consistent pagination
    static func randomized(seed: UInt64, limit: Int, offset: Int) throws -> [Annotation] {
        try DatabaseManager.shared.dbQueue.read { db in
            // Use a deterministic random order based on seed and id
            // This allows pagination to work correctly
            let sql = """
                SELECT * FROM annotations
                ORDER BY (CAST(SUBSTR(id, 1, 8) AS INTEGER) + ?) % 1000000
                LIMIT ? OFFSET ?
            """
            return try Annotation.fetchAll(db, sql: sql, arguments: [Int64(seed % 1000000), limit, offset])
        }
    }

    static func find(id: String) throws -> Annotation? {
        try DatabaseManager.shared.dbQueue.read { db in
            try Annotation.fetchOne(db, key: id)
        }
    }

    @discardableResult
    func save() throws -> Annotation {
        try DatabaseManager.shared.dbQueue.write { db in
            try self.save(db)
        }
        // Index in Spotlight
        let book = try? Book.find(id: bookId)
        SpotlightService.shared.indexAnnotation(self, book: book)
        return self
    }

    func delete() throws {
        // Delete associated files
        if let url = audioURL {
            try? FileManager.default.removeItem(at: url)
        }
        if let url = imageURL {
            try? FileManager.default.removeItem(at: url)
        }
        if let url = videoURL {
            try? FileManager.default.removeItem(at: url)
        }

        // Remove from Spotlight
        SpotlightService.shared.removeAnnotation(id)

        try DatabaseManager.shared.dbQueue.write { db in
            _ = try Annotation.deleteOne(db, key: id)
        }
    }

    mutating func updateTranscription(_ text: String) throws {
        transcription = text
        try DatabaseManager.shared.dbQueue.write { db in
            try self.save(db)
        }
        // Update Spotlight index
        let book = try? Book.find(id: bookId)
        SpotlightService.shared.indexAnnotation(self, book: book)
    }

    mutating func updateCaption(_ text: String) throws {
        caption = text
        try DatabaseManager.shared.dbQueue.write { db in
            try self.save(db)
        }
        // Update Spotlight index
        let book = try? Book.find(id: bookId)
        SpotlightService.shared.indexAnnotation(self, book: book)
    }

    mutating func updatePageNumber(_ page: String?) throws {
        pageNumber = page
        try DatabaseManager.shared.dbQueue.write { db in
            try self.save(db)
        }
    }

    mutating func update(text: String?, pageNumber: String?) throws {
        if type == .audio {
            transcription = text
        } else {
            caption = text
        }
        self.pageNumber = pageNumber
        try DatabaseManager.shared.dbQueue.write { db in
            try self.save(db)
        }
        // Update Spotlight index
        let book = try? Book.find(id: bookId)
        SpotlightService.shared.indexAnnotation(self, book: book)
    }
}

// MARK: - Search
extension Annotation {
    struct SearchResult {
        let annotation: Annotation
        let book: Book?
        let matchedText: String
        let highlightRanges: [Range<String.Index>]
    }

    static func search(query: String) throws -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            return []
        }

        let searchTerm = query.trimmingCharacters(in: .whitespaces)

        return try DatabaseManager.shared.dbQueue.read { db in
            // Use FTS5 MATCH query
            let sql = """
                SELECT annotations.*, bm25(annotations_fts) as rank
                FROM annotations
                JOIN annotations_fts ON annotations.rowid = annotations_fts.rowid
                WHERE annotations_fts MATCH ?
                ORDER BY rank
                LIMIT 50
            """

            let annotations = try Annotation.fetchAll(db, sql: sql, arguments: [searchTerm + "*"])

            return try annotations.map { annotation in
                let book = try Book.fetchOne(db, key: annotation.bookId)
                let matchedText = annotation.transcription ?? annotation.caption ?? ""
                let highlightRanges = findHighlightRanges(in: matchedText, for: searchTerm)

                return SearchResult(
                    annotation: annotation,
                    book: book,
                    matchedText: matchedText,
                    highlightRanges: highlightRanges
                )
            }
        }
    }

    private static func findHighlightRanges(in text: String, for query: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var searchRange = text.startIndex..<text.endIndex
        let lowercasedText = text.lowercased()
        let lowercasedQuery = query.lowercased()

        while let range = lowercasedText.range(of: lowercasedQuery, range: searchRange) {
            // Convert to original text range
            let startOffset = lowercasedText.distance(from: lowercasedText.startIndex, to: range.lowerBound)
            let endOffset = lowercasedText.distance(from: lowercasedText.startIndex, to: range.upperBound)

            if let start = text.index(text.startIndex, offsetBy: startOffset, limitedBy: text.endIndex),
               let end = text.index(text.startIndex, offsetBy: endOffset, limitedBy: text.endIndex) {
                ranges.append(start..<end)
            }

            searchRange = range.upperBound..<text.endIndex
        }

        return ranges
    }
}
