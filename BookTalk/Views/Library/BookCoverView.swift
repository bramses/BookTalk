import SwiftUI
import Foundation

struct BookCoverView: View {
    let book: Book
    @State private var annotationCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Cover Image
            ZStack {
                if let coverURL = book.coverImageURL,
                   let uiImage = UIImage(contentsOfFile: coverURL.path) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(2/3, contentMode: .fill)
                } else {
                    // Placeholder cover
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.6), .purple.opacity(0.6)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .aspectRatio(2/3, contentMode: .fill)
                        .overlay {
                            VStack {
                                Image(systemName: "book.closed.fill")
                                    .font(.system(size: 40))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                        }
                }
            }
            .frame(height: 200)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .shadow(radius: 4)

            // Title and Author
            VStack(alignment: .leading, spacing: 2) {
                Text(book.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)
                    .foregroundColor(.primary)

                if let author = book.author {
                    Text(author)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if annotationCount > 0 {
                    Text("\(annotationCount) annotation\(annotationCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.blue)
                }
            }
        }
        .onAppear {
            loadAnnotationCount()
        }
    }

    private func loadAnnotationCount() {
        do {
            annotationCount = try book.annotationCount()
        } catch {
            annotationCount = 0
        }
    }
}
