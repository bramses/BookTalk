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
    @State private var activeVideoId: String?

    private let pageSize = 20

    struct AnnotationWithBook: Identifiable {
        var annotation: Annotation  // Changed from let to var
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
                        .frame(maxWidth: .infinity)
                } else if annotations.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 16) {
                        ForEach(annotations) { item in
                            FeedAnnotationRow(
                                annotation: item.annotation,
                                book: item.book,
                                audioPlayer: audioPlayer,
                                activeVideoId: $activeVideoId,
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
                            HStack {
                                ProgressView()
                                    .padding()
                            }
                            .frame(maxWidth: .infinity)
                        }

                        if !hasMoreContent && !annotations.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.green)
                                Text("You're all caught up!")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 24)
                            .frame(maxWidth: .infinity)
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
            .onReceive(NotificationCenter.default.publisher(for: .pttRecordingCompleted)) { _ in
                Task { await loadAnnotations() }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pttTranscriptionCompleted)) { notification in
                // Update the specific annotation with transcription
                if let annotation = notification.object as? Annotation,
                   let index = annotations.firstIndex(where: { $0.annotation.id == annotation.id }) {
                    var updated = annotations[index]
                    updated.annotation = annotation
                    annotations[index] = updated
                }
            }
            .task {
                if annotations.isEmpty {
                    await loadAnnotations()
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: "text.bubble")
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(.purple)
                    .symbolRenderingMode(.hierarchical)
            }
            
            VStack(spacing: 8) {
                Text("No Annotations Yet")
                    .font(.title2.weight(.semibold))
                Text("Your annotations from all books\nwill appear here")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 40)
            
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
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
    @Binding var activeVideoId: String?
    var onGoToBook: (() -> Void)? = nil

    @State private var coverImage: UIImage?
    @State private var annotationImage: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Book info header
            if let book = book {
                HStack(spacing: 10) {
                    if let coverImage {
                        Image(uiImage: coverImage)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 36, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.blue.opacity(0.15))
                            .frame(width: 36, height: 52)
                            .overlay {
                                Image(systemName: "book.closed.fill")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                                    .symbolRenderingMode(.hierarchical)
                            }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(book.title)
                            .font(.subheadline.weight(.semibold))
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
                .padding(.bottom, 4)
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
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.3), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.03), radius: 2, y: 1)
        .onAppear { loadImagesIfNeeded() }
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
            if let annotationImage {
                Image(uiImage: annotationImage)
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
                if activeVideoId == annotation.id {
                    VideoThumbnailPlayer(url: videoURL)
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Button {
                        activeVideoId = annotation.id
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.08))
                                .frame(height: 200)
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 48))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                    .buttonStyle(.plain)
                }
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

    private func loadImagesIfNeeded() {
        if coverImage == nil, let coverURL = book?.coverImageURL {
            FeedImageLoader.shared.loadImage(path: coverURL.path) { image in
                coverImage = image
            }
        }

        if annotationImage == nil, let imageURL = annotation.imageURL {
            FeedImageLoader.shared.loadImage(path: imageURL.path) { image in
                annotationImage = image
            }
        }
    }
}
