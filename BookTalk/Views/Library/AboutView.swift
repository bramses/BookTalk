import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // App icon and title
                    VStack(spacing: 12) {
                        Image(systemName: "book.pages.fill")
                            .font(.system(size: 80))
                            .foregroundStyle(
                                LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .symbolRenderingMode(.hierarchical)
                        
                        Text("BookTalk")
                            .font(.largeTitle.bold())
                        
                        Text("Your Audio Book Journal")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    
                    Divider()
                    
                    // How to use section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How to Use")
                            .font(.title2.bold())
                        
                        FeatureRow(
                            icon: "plus",
                            title: "Add Books",
                            description: "Tap the + button to add books to your library. Include a cover image, title, and author."
                        )
                        
                        FeatureRow(
                            icon: "mic.fill",
                            title: "Record Audio Annotations",
                            description: "Tap the microphone to record your thoughts. Your audio will be automatically transcribed."
                        )
                        
                        FeatureRow(
                            icon: "camera.fill",
                            title: "Capture Images & Videos",
                            description: "Take photos or videos of pages, diagrams, or anything related to your reading."
                        )
                        
                        FeatureRow(
                            icon: "note.text",
                            title: "Write Notes",
                            description: "Add text notes for quick thoughts and observations."
                        )
                        
                        FeatureRow(
                            icon: "lock.iphone",
                            title: "Lock Screen Recording",
                            description: "Enable lock screen recording in a book's menu to record audio annotations even when your phone is locked."
                        )
                        
                        FeatureRow(
                            icon: "magnifyingglass",
                            title: "Search Everything",
                            description: "Use the search tab to find any annotation across all your books. Searches include transcriptions and captions."
                        )
                        
                        FeatureRow(
                            icon: "text.bubble",
                            title: "Browse Your Feed",
                            description: "The Feed tab shows a randomized view of all your annotations across all books."
                        )
                        
                        FeatureRow(
                            icon: "archivebox",
                            title: "Archive Books",
                            description: "Swipe on a book or use the context menu to archive it. Access archived books from the library menu."
                        )
                    }
                    
                    Divider()
                    
                    // Tips section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Tips")
                            .font(.title2.bold())
                        
                        TipRow(
                            icon: "number",
                            tip: "Add page numbers to annotations to easily reference where you were in the book."
                        )
                        
                        TipRow(
                            icon: "link",
                            tip: "URLs in transcriptions and captions are automatically clickable."
                        )
                        
                        TipRow(
                            icon: "waveform.badge.mic",
                            tip: "Tap 'Retranscribe' in an audio annotation's menu if you want to regenerate the transcription."
                        )
                        
                        TipRow(
                            icon: "arrow.right.circle.fill",
                            tip: "Tap 'Go to' in the Feed or Search to jump directly to a book with that annotation highlighted."
                        )
                    }
                    
                    Divider()
                    
                    // Privacy section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Privacy")
                            .font(.title2.bold())
                        
                        Text("BookTalk stores all your data locally on your device. Your annotations, recordings, and notes never leave your phone unless you choose to share them.")
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                    
                    // Version info
                    VStack(spacing: 4) {
                        Text("Version 1.0")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("© 2026")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)
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
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
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
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

struct TipRow: View {
    let icon: String
    let tip: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(.green)
                .frame(width: 24)
            
            Text(tip)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
