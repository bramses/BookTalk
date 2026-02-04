import SwiftUI
import AVKit

struct FeedView: View {
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var annotations: [AnnotationWithBook] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var hasMoreContent = true
    @State private var currentSeed: UInt64 = 0
    @State private var navigationPath = NavigationPath()

    private let pageSize = 20

    struct AnnotationWithBook: Identifiable {
        let annotation: Annotation
        let book: Book?
        var id: String { annotation.id }
    }

    struct BookNavigation: Hashable {
        let book: Book
        let annotationId: String
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            ScrollView {
                if isLoading {
                    ProgressView()
                        .padding(.top, 100)
                } else if annotations.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(annotations) { item in
                            FeedAnnotationRow(
                                annotation: item.annotation,
                                book: item.book,
                                audioPlayer: audioPlayer,
                                onGoToBook: item.book != nil ? {
                                    navigationPath.append(BookNavigation(book: item.book!, annotationId: item.annotation.id))
                                } : nil
                            )
                            .onAppear {
                                // Load more when reaching near the end
                                if item.id == annotations.last?.id && hasMoreContent && !isLoadingMore {
                                    loadMoreAnnotations()
                                }
                            }
                        }

                        if isLoadingMore {
                            ProgressView()
                                .padding()
                        }

                        if !hasMoreContent && !annotations.isEmpty {
                            Text("You've seen all annotations")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding()
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Feed")
            .navigationDestination(for: BookNavigation.self) { nav in
                BookDetailView(book: nav.book, scrollToAnnotationId: nav.annotationId)
            }
            .refreshable {
                await loadAnnotations()
            }
            .task {
                if annotations.isEmpty {
                    await loadAnnotations()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "text.bubble")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            Text("No Annotations Yet")
                .font(.title2.bold())
            Text("Your annotations from all books will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 100)
    }

    private func loadAnnotations() async {
        isLoading = true
        currentSeed = UInt64.random(in: 0..<UInt64.max)

        do {
            let allAnnotations = try Annotation.randomized(seed: currentSeed, limit: pageSize, offset: 0)
            var results: [AnnotationWithBook] = []

            for annotation in allAnnotations {
                let book = try? Book.find(id: annotation.bookId)
                results.append(AnnotationWithBook(annotation: annotation, book: book))
            }

            await MainActor.run {
                annotations = results
                hasMoreContent = allAnnotations.count == pageSize
                isLoading = false
            }
        } catch {
            #if DEBUG
            print("Failed to load annotations: \(error)")
            #endif
            await MainActor.run {
                isLoading = false
            }
        }
    }

    private func loadMoreAnnotations() {
        guard !isLoadingMore else { return }
        isLoadingMore = true

        Task {
            do {
                let newAnnotations = try Annotation.randomized(
                    seed: currentSeed,
                    limit: pageSize,
                    offset: annotations.count
                )

                var results: [AnnotationWithBook] = []
                for annotation in newAnnotations {
                    let book = try? Book.find(id: annotation.bookId)
                    results.append(AnnotationWithBook(annotation: annotation, book: book))
                }

                await MainActor.run {
                    annotations.append(contentsOf: results)
                    hasMoreContent = newAnnotations.count == pageSize
                    isLoadingMore = false
                }
            } catch {
                #if DEBUG
                print("Failed to load more annotations: \(error)")
                #endif
                await MainActor.run {
                    isLoadingMore = false
                }
            }
        }
    }
}

struct FeedAnnotationRow: View {
    let annotation: Annotation
    let book: Book?
    @ObservedObject var audioPlayer: AudioPlayer
    var onGoToBook: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Book info header
            if let book = book {
                HStack {
                    if let coverURL = book.coverImageURL,
                       let uiImage = UIImage(contentsOfFile: coverURL.path) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 32, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    } else {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.blue.opacity(0.2))
                            .frame(width: 32, height: 48)
                            .overlay {
                                Image(systemName: "book.closed.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                    }

                    VStack(alignment: .leading) {
                        Text(book.title)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        if let author = book.author {
                            Text(author)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                }
            }

            Divider()

            // Annotation content
            switch annotation.type {
            case .audio:
                audioContent
            case .image:
                imageContent
            case .video:
                videoContent
            case .text:
                textContent
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
    }

    @ViewBuilder
    private var audioContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let audioURL = annotation.audioURL {
                HStack {
                    Button {
                        audioPlayer.togglePlayPause(url: audioURL, annotationId: annotation.id)
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.blue)
                    }

                    Text(annotation.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if onGoToBook != nil {
                        Button {
                            onGoToBook?()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right.circle.fill")
                                Text("Go to")
                            }
                            .font(.subheadline)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            if let transcription = annotation.transcription, !transcription.isEmpty {
                Text(transcription)
                    .font(.body)
            }
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let imageURL = annotation.imageURL,
               let uiImage = UIImage(contentsOfFile: imageURL.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxHeight: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                if let caption = annotation.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.body)
                }
                Spacer()
                if onGoToBook != nil {
                    Button {
                        onGoToBook?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Go to")
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var videoContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let videoURL = annotation.videoURL {
                VideoThumbnailPlayer(url: videoURL)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                if let caption = annotation.caption, !caption.isEmpty {
                    Text(caption)
                        .font(.body)
                }
                Spacer()
                if onGoToBook != nil {
                    Button {
                        onGoToBook?()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Go to")
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var textContent: some View {
        HStack {
            if let caption = annotation.caption {
                Text(caption)
                    .font(.body)
            }
            Spacer()
            if onGoToBook != nil {
                Button {
                    onGoToBook?()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right.circle.fill")
                        Text("Go to")
                    }
                    .font(.subheadline)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var isPlaying: Bool {
        audioPlayer.isPlaying && audioPlayer.currentAnnotationId == annotation.id
    }
}
