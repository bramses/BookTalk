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
    @State private var pulseAnimation = false

    var body: some View {
        HStack(spacing: 14) {
            // Status indicator with pulse animation
            ZStack {
                if pttManager.isTransmitting {
                    Circle()
                        .fill(Color.red.opacity(0.3))
                        .frame(width: 20, height: 20)
                        .scaleEffect(pulseAnimation ? 1.3 : 1.0)
                        .opacity(pulseAnimation ? 0 : 1)
                }
                Circle()
                    .fill(pttManager.isTransmitting ? Color.red : Color.green)
                    .frame(width: 10, height: 10)
            }

            // Book name
            VStack(alignment: .leading, spacing: 3) {
                Text("PTT Active")
                    .font(.caption2.weight(.medium))
                    .foregroundColor(.secondary)
                Text(pttManager.currentBookTitle ?? "Unknown")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            // Leave button
            Button {
                showingConfirmation = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(Color(.tertiaryLabel))
                    .symbolRenderingMode(.hierarchical)
            }
            .accessibilityLabel("Leave PTT channel")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Push to Talk active for \(pttManager.currentBookTitle ?? "book"). \(pttManager.isTransmitting ? "Currently recording" : "Ready")")
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        )
        .padding(.horizontal, 20)
        .transition(.scale.combined(with: .opacity))
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: pttManager.isJoined)
        .onChange(of: pttManager.isTransmitting) { isTransmitting in
            if isTransmitting {
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: false)) {
                    pulseAnimation = true
                }
            } else {
                pulseAnimation = false
            }
        }
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
