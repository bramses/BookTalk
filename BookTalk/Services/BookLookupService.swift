import Foundation

struct BookMetadata {
    let title: String
    let author: String?
    let coverURL: URL?
    let isbn: String
}

class BookLookupService {
    static let shared = BookLookupService()

    private init() {}

    func lookup(isbn: String) async -> BookMetadata? {
        // Clean ISBN (remove hyphens)
        let cleanISBN = isbn.replacingOccurrences(of: "-", with: "")

        // Try Open Library API
        guard let url = URL(string: "https://openlibrary.org/isbn/\(cleanISBN).json") else {
            return nil
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                print("Book not found for ISBN: \(cleanISBN)")
                return nil
            }

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

            guard let title = json?["title"] as? String else {
                return nil
            }

            // Get author (might need another API call)
            var authorName: String?
            if let authors = json?["authors"] as? [[String: Any]],
               let authorKey = authors.first?["key"] as? String {
                authorName = await fetchAuthorName(key: authorKey)
            }

            // Get cover URL
            var coverURL: URL?
            if let covers = json?["covers"] as? [Int], let coverId = covers.first {
                coverURL = URL(string: "https://covers.openlibrary.org/b/id/\(coverId)-L.jpg")
            }

            return BookMetadata(
                title: title,
                author: authorName,
                coverURL: coverURL,
                isbn: cleanISBN
            )
        } catch {
            print("Error looking up ISBN: \(error)")
            return nil
        }
    }

    private func fetchAuthorName(key: String) async -> String? {
        guard let url = URL(string: "https://openlibrary.org\(key).json") else {
            return nil
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            return json?["name"] as? String
        } catch {
            return nil
        }
    }

    func downloadCover(from url: URL) async -> String? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)

            let filename = "\(UUID().uuidString).jpg"
            let fileURL = DatabaseManager.coversDirectory.appendingPathComponent(filename)

            try data.write(to: fileURL)
            return filename
        } catch {
            print("Error downloading cover: \(error)")
            return nil
        }
    }
}
