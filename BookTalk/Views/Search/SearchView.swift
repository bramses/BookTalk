import SwiftUI

struct SearchView: View {
    @State private var searchText = ""
    @State private var results: [Annotation.SearchResult] = []
    @State private var isSearching = false
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var navigationPath = NavigationPath()

    struct BookNavigation: Hashable {
        let book: Book
        let annotationId: String
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            VStack {
                if searchText.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("Search Annotations")
                            .font(.title2.bold())
                        Text("Search through transcriptions and captions")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else if isSearching {
                    ProgressView("Searching...")
                        .frame(maxHeight: .infinity)
                } else if results.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 60))
                            .foregroundColor(.secondary)
                        Text("No Results")
                            .font(.title2.bold())
                        Text("Try a different search term")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    List {
                        ForEach(results, id: \.annotation.id) { result in
                            SearchResultRow(
                                result: result,
                                searchTerm: searchText,
                                audioPlayer: audioPlayer,
                                onGoToBook: result.book != nil ? {
                                    navigationPath.append(BookNavigation(book: result.book!, annotationId: result.annotation.id))
                                } : nil
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Search")
            .navigationDestination(for: BookNavigation.self) { nav in
                BookDetailView(book: nav.book, scrollToAnnotationId: nav.annotationId)
            }
            .searchable(text: $searchText, prompt: "Search transcriptions & captions")
            .onChange(of: searchText) { newValue in
                performSearch(query: newValue)
            }
        }
    }

    private func performSearch(query: String) {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            results = []
            return
        }

        isSearching = true

        // Debounce search
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000) // 300ms

            guard !Task.isCancelled else { return }

            do {
                let searchResults = try Annotation.search(query: query)
                await MainActor.run {
                    results = searchResults
                    isSearching = false
                }
            } catch {
                print("Search failed: \(error)")
                await MainActor.run {
                    results = []
                    isSearching = false
                }
            }
        }
    }
}

struct SearchResultRow: View {
    let result: Annotation.SearchResult
    let searchTerm: String
    @ObservedObject var audioPlayer: AudioPlayer
    var onGoToBook: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Book info
            if let book = result.book {
                HStack {
                    Image(systemName: "book.fill")
                        .foregroundColor(.blue)
                    Text(book.title)
                        .font(.subheadline.bold())
                    Spacer()
                }
            }

            // Annotation type indicator
            HStack {
                Image(systemName: iconForType)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(result.annotation.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Highlighted text
            HighlightedText(
                text: result.matchedText,
                highlights: result.highlightRanges
            )
            .font(.body)
            .lineLimit(4)

            // Action buttons
            HStack {
                if result.annotation.type == .audio,
                   let audioURL = result.annotation.audioURL {
                    Button {
                        audioPlayer.togglePlayPause(url: audioURL, annotationId: result.annotation.id)
                    } label: {
                        HStack {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            Text(isPlaying ? "Pause" : "Play")
                            Text("(\(result.annotation.formattedDuration))")
                                .foregroundColor(.secondary)
                        }
                        .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }

                if let onGoToBook = onGoToBook {
                    Button {
                        onGoToBook()
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
        .padding(.vertical, 4)
    }

    private var iconForType: String {
        switch result.annotation.type {
        case .audio: return "waveform"
        case .image: return "photo"
        case .video: return "video"
        case .text: return "text.quote"
        }
    }

    private var isPlaying: Bool {
        audioPlayer.isPlaying && audioPlayer.currentAnnotationId == result.annotation.id
    }
}

struct HighlightedText: View {
    let text: String
    let highlights: [Range<String.Index>]

    var body: some View {
        if highlights.isEmpty {
            Text(text)
        } else {
            highlightedAttributedString
        }
    }

    private var highlightedAttributedString: Text {
        var result = Text("")
        var currentIndex = text.startIndex

        for range in highlights.sorted(by: { $0.lowerBound < $1.lowerBound }) {
            // Add text before highlight
            if currentIndex < range.lowerBound {
                result = result + Text(text[currentIndex..<range.lowerBound])
            }

            // Add highlighted text
            result = result + Text(text[range])
                .bold()
                .foregroundColor(.blue)

            currentIndex = range.upperBound
        }

        // Add remaining text
        if currentIndex < text.endIndex {
            result = result + Text(text[currentIndex..<text.endIndex])
        }

        return result
    }
}
