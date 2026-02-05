import Foundation
import CoreSpotlight
import MobileCoreServices
import os.log

class SpotlightService: ObservableObject {
    static let shared = SpotlightService()

    private let domainIdentifier = "dev.bramadams.BookTalk.annotations"
    private let logger = Logger(subsystem: "dev.bramadams.BookTalk", category: "Spotlight")

    @Published var lastIndexedCount: Int = 0
    @Published var lastIndexError: String?
    @Published var isIndexing: Bool = false

    private init() {}

    // MARK: - Index Book

    func indexBook(_ book: Book) {
        logger.info("Indexing book \(book.id): \(book.title)")

        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = book.title
        
        var keywords: [String] = [book.title]
        if let author = book.author {
            attributeSet.contentDescription = "by \(author)"
            keywords.append(author)
        }
        
        attributeSet.keywords = keywords
        
        // Set thumbnail if available
        if let coverURL = book.coverImageURL {
            attributeSet.thumbnailURL = coverURL
        }
        
        // Create searchable item
        let item = CSSearchableItem(
            uniqueIdentifier: "book_\(book.id)",
            domainIdentifier: "dev.bramadams.BookTalk.books",
            attributeSet: attributeSet
        )
        
        // Index the item
        CSSearchableIndex.default().indexSearchableItems([item]) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to index book \(book.id): \(error.localizedDescription)")
            } else {
                self?.logger.info("Successfully indexed book \(book.id)")
            }
        }
    }

    // MARK: - Index Annotation

    func indexAnnotation(_ annotation: Annotation, book: Book?) {
        logger.info("Indexing annotation \(annotation.id) for book: \(book?.title ?? "unknown")")

        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)

        // Set title based on book
        if let book = book {
            attributeSet.title = book.title
            attributeSet.contentDescription = contentDescription(for: annotation)
        } else {
            attributeSet.title = "Book Annotation"
            attributeSet.contentDescription = contentDescription(for: annotation)
        }

        // Set searchable text content
        var keywords: [String] = []

        if let transcription = annotation.transcription {
            attributeSet.textContent = transcription
            keywords.append(contentsOf: transcription.components(separatedBy: .whitespaces).prefix(20))
            logger.debug("Added transcription to index: \(transcription.prefix(50))...")
        }

        if let caption = annotation.caption {
            if attributeSet.textContent == nil {
                attributeSet.textContent = caption
            } else {
                attributeSet.textContent = (attributeSet.textContent ?? "") + " " + caption
            }
            keywords.append(contentsOf: caption.components(separatedBy: .whitespaces).prefix(20))
            logger.debug("Added caption to index: \(caption.prefix(50))...")
        }

        if let book = book {
            keywords.append(book.title)
            if let author = book.author {
                keywords.append(author)
            }
        }

        attributeSet.keywords = keywords

        // Set thumbnail for image/video annotations
        if annotation.type == .image, let imageURL = annotation.imageURL {
            attributeSet.thumbnailURL = imageURL
        }

        // Create searchable item
        let item = CSSearchableItem(
            uniqueIdentifier: annotation.id,
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )

        // Index the item
        CSSearchableIndex.default().indexSearchableItems([item]) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to index annotation \(annotation.id): \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self?.lastIndexError = error.localizedDescription
                }
            } else {
                self?.logger.info("Successfully indexed annotation \(annotation.id)")
            }
        }
    }

    // MARK: - Remove from Index

    func removeBook(_ bookId: String) {
        logger.info("Removing book \(bookId) from Spotlight")
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ["book_\(bookId)"]) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to remove book \(bookId): \(error.localizedDescription)")
            } else {
                self?.logger.info("Successfully removed book \(bookId)")
            }
        }
    }

    func removeAnnotation(_ annotationId: String) {
        logger.info("Removing annotation \(annotationId) from Spotlight")
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: [annotationId]) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to remove annotation \(annotationId): \(error.localizedDescription)")
            } else {
                self?.logger.info("Successfully removed annotation \(annotationId)")
            }
        }
    }

    func removeAllAnnotations() {
        logger.info("Removing all annotations from Spotlight")
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { [weak self] error in
            if let error = error {
                self?.logger.error("Failed to remove all annotations: \(error.localizedDescription)")
            } else {
                self?.logger.info("Successfully removed all annotations")
            }
        }
    }

    // MARK: - Reindex All

    @MainActor
    func reindexAllAnnotations() async {
        logger.info("Starting full reindex of all annotations")
        isIndexing = true
        lastIndexError = nil

        do {
            let annotations = try Annotation.all()
            logger.info("Found \(annotations.count) annotations to index")

            var items: [CSSearchableItem] = []

            for annotation in annotations {
                let book = try? Book.find(id: annotation.bookId)

                let attributeSet = CSSearchableItemAttributeSet(contentType: .text)

                if let book = book {
                    attributeSet.title = book.title
                } else {
                    attributeSet.title = "Book Annotation"
                }

                attributeSet.contentDescription = contentDescription(for: annotation)

                var searchText = ""
                if let transcription = annotation.transcription {
                    searchText += transcription
                }
                if let caption = annotation.caption {
                    if !searchText.isEmpty { searchText += " " }
                    searchText += caption
                }
                attributeSet.textContent = searchText

                if annotation.type == .image, let imageURL = annotation.imageURL {
                    attributeSet.thumbnailURL = imageURL
                }

                let item = CSSearchableItem(
                    uniqueIdentifier: annotation.id,
                    domainIdentifier: domainIdentifier,
                    attributeSet: attributeSet
                )
                items.append(item)
            }

            // Use continuation for async/await
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                CSSearchableIndex.default().indexSearchableItems(items) { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            }

            lastIndexedCount = items.count
            isIndexing = false
            logger.info("Successfully indexed \(items.count) annotations")

        } catch {
            logger.error("Failed to reindex annotations: \(error.localizedDescription)")
            lastIndexError = error.localizedDescription
            isIndexing = false
        }
    }

    // Non-async version for app launch
    func reindexAllAnnotationsBackground() {
        Task { @MainActor in
            await reindexAllAnnotations()
        }
    }

    // MARK: - Helpers

    private func contentDescription(for annotation: Annotation) -> String {
        switch annotation.type {
        case .audio:
            if let transcription = annotation.transcription, !transcription.isEmpty {
                return transcription
            }
            return "Audio recording"
        case .image:
            if let caption = annotation.caption, !caption.isEmpty {
                return caption
            }
            return "Photo annotation"
        case .video:
            if let caption = annotation.caption, !caption.isEmpty {
                return caption
            }
            return "Video annotation"
        case .text:
            return annotation.caption ?? "Text note"
        }
    }
}
