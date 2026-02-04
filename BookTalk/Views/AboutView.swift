import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var spotlightService = SpotlightService.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // App header
                    appHeader

                    // How to use sections
                    howToSection

                    // Spotlight indexing section
                    spotlightSection

                    // Credits
                    creditsSection
                }
                .padding()
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var appHeader: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed.fill")
                .font(.system(size: 60))
                .foregroundColor(.blue)

            Text("BookTalk")
                .font(.largeTitle.bold())

            Text("Your Reading Companion")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }

    private var howToSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("How to Use")
                .font(.title2.bold())

            // Library
            featureCard(
                icon: "books.vertical",
                title: "Library",
                description: "Add books to your library by tapping the + button. You can enter details manually or scan a book's ISBN barcode to automatically fetch the title, author, and cover image."
            )

            // Recording annotations
            featureCard(
                icon: "mic.fill",
                title: "Voice Annotations",
                description: "Open a book and hold the microphone button to record voice notes about what you're reading. Your recordings are automatically transcribed for easy searching later."
            )

            // PTT
            featureCard(
                icon: "antenna.radiowaves.left.and.right",
                title: "Push to Talk",
                description: "Enable Push to Talk for hands-free recording. Join a PTT channel for a book, then use the system PTT button (in Dynamic Island or Control Center) to record annotations even when the app is in the background."
            )

            // Images
            featureCard(
                icon: "photo",
                title: "Image Annotations",
                description: "Capture photos of interesting passages, diagrams, or anything worth remembering. Add optional captions to provide context."
            )

            // Feed
            featureCard(
                icon: "text.bubble",
                title: "Feed",
                description: "Browse all your annotations across all books in the Feed tab. Pull down to shuffle for a random walk through your reading notes. Tap 'Go to' to jump directly to any annotation in its book."
            )

            // Search
            featureCard(
                icon: "magnifyingglass",
                title: "Search",
                description: "Find any annotation instantly by searching through transcriptions and captions. Full-text search helps you rediscover insights from your reading."
            )

            // Tips
            tipsSection
        }
    }

    private func featureCard(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.blue)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var tipsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Tips", systemImage: "lightbulb.fill")
                .font(.headline)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 6) {
                tipRow("Long-press a book cover to archive it")
                tipRow("Tap the shuffle button in Feed for random discoveries")
                tipRow("PTT recordings work even when your phone is locked")
                tipRow("Edit transcriptions by tapping the menu on any annotation")
            }
            .padding()
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func tipRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .foregroundColor(.orange)
            Text(text)
                .font(.subheadline)
        }
    }

    private var spotlightSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Spotlight Search")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 12) {
                Text("Your annotations are indexed for Spotlight search, so you can find them from your home screen.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                // Status
                HStack {
                    Text("Last indexed:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    if spotlightService.isIndexing {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Indexing...")
                            .font(.subheadline)
                    } else {
                        Text("\(spotlightService.lastIndexedCount) annotations")
                            .font(.subheadline.bold())
                    }
                }

                // Error if any
                if let error = spotlightService.lastIndexError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                // Reindex button
                Button {
                    Task {
                        await spotlightService.reindexAllAnnotations()
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Reindex All Annotations")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(spotlightService.isIndexing)
            }
            .padding()
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var creditsSection: some View {
        VStack(spacing: 12) {
            Divider()
                .padding(.vertical)

            Text("Built by Bram Adams")
                .font(.headline)

            Link(destination: URL(string: "https://www.bramadams.dev/")!) {
                HStack {
                    Text("bramadams.dev")
                    Image(systemName: "arrow.up.right.square")
                }
                .font(.subheadline)
            }

            Link(destination: URL(string: "https://www.bramadams.dev/booktalk-privacy-policy/")!) {
                HStack {
                    Text("Privacy Policy")
                    Image(systemName: "arrow.up.right.square")
                }
                .font(.subheadline)
            }

            Text("Version 1.0")
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical)
    }
}

#Preview {
    AboutView()
}
