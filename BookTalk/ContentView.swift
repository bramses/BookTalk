import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @StateObject private var pttManager = PTTManager.shared
    @EnvironmentObject var spotlightNavigation: SpotlightNavigationState
    @State private var spotlightBook: Book?
    @State private var spotlightAnnotationId: String?
    @State private var showSpotlightBook = false

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                LibraryView()
                    .tabItem {
                        Label("Library", systemImage: "books.vertical")
                    }
                    .tag(0)

                FeedView()
                    .tabItem {
                        Label("Feed", systemImage: "text.bubble")
                    }
                    .tag(1)

                SearchView()
                    .tabItem {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                    .tag(2)
            }

            // Floating PTT indicator
            if pttManager.isJoined {
                VStack {
                    Spacer()
                    PTTIndicatorView(pttManager: pttManager)
                        .padding(.bottom, 60) // Above tab bar
                }
            }
        }
        .task {
            await pttManager.initialize()
        }
        .onChange(of: spotlightNavigation.pendingAnnotationId) { annotationId in
            guard let annotationId = annotationId else { return }
            handleSpotlightNavigation(annotationId: annotationId)
            spotlightNavigation.pendingAnnotationId = nil
        }
        .fullScreenCover(isPresented: $showSpotlightBook) {
            if let book = spotlightBook {
                NavigationStack {
                    BookDetailView(book: book, scrollToAnnotationId: spotlightAnnotationId)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") {
                                    showSpotlightBook = false
                                    spotlightBook = nil
                                    spotlightAnnotationId = nil
                                }
                            }
                        }
                }
            }
        }
    }

    private func handleSpotlightNavigation(annotationId: String) {
        // Find the annotation and its book
        do {
            if let annotation = try Annotation.find(id: annotationId),
               let book = try Book.find(id: annotation.bookId) {
                spotlightBook = book
                spotlightAnnotationId = annotationId
                showSpotlightBook = true
            }
        } catch {
            print("Failed to navigate to Spotlight result: \(error)")
        }
    }
}

struct PTTIndicatorView: View {
    @ObservedObject var pttManager: PTTManager
    @State private var showingConfirmation = false

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator
            Circle()
                .fill(pttManager.isTransmitting ? Color.red : Color.green)
                .frame(width: 10, height: 10)

            // Book name
            VStack(alignment: .leading, spacing: 2) {
                Text("PTT Active")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(pttManager.currentBookTitle ?? "Unknown")
                    .font(.caption.bold())
                    .lineLimit(1)
            }

            Spacer()

            // Leave button
            Button {
                showingConfirmation = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
            .accessibilityLabel("Leave PTT channel")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Push to Talk active for \(pttManager.currentBookTitle ?? "book"). \(pttManager.isTransmitting ? "Currently recording" : "Ready")")
        .background(
            RoundedRectangle(cornerRadius: 25)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        )
        .padding(.horizontal, 20)
        .confirmationDialog(
            "Leave PTT Channel?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave Channel", role: .destructive) {
                pttManager.forceLeaveChannel()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll stop receiving PTT for \"\(pttManager.currentBookTitle ?? "this book")\"")
        }
    }
}

#Preview {
    ContentView()
}
