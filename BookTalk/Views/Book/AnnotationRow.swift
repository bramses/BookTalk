import SwiftUI
import AVKit

struct AnnotationRow: View {
    let annotation: Annotation
    @ObservedObject var audioPlayer: AudioPlayer
    var isHighlighted: Bool = false
    var onDelete: () -> Void
    var onUpdate: (String?, String?) -> Void
    var onRetranscribe: (() -> Void)? = nil

    @State private var showingEditCaption = false
    @State private var showingFullScreenImage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with date, type, and page number
            HStack {
                Image(systemName: iconForType)
                    .foregroundColor(.blue)
                Text(annotation.formattedDate)
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let page = annotation.pageNumber, !page.isEmpty {
                    Text("p. \(page)")
                        .font(.caption.bold())
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                }
                Spacer()
                Menu {
                    Button {
                        showingEditCaption = true
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    if annotation.type == .audio, let onRetranscribe = onRetranscribe {
                        Button {
                            onRetranscribe()
                        } label: {
                            Label("Retranscribe", systemImage: "waveform.badge.mic")
                        }
                    }
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }

            // Content based on type
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
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHighlighted ? Color.blue : Color.clear, lineWidth: 2)
        )
        .shadow(color: isHighlighted ? .blue.opacity(0.3) : .black.opacity(0.05), radius: isHighlighted ? 6 : 2, y: 1)
        .sheet(isPresented: $showingEditCaption) {
            EditCaptionSheet(
                caption: annotation.caption ?? annotation.transcription ?? "",
                pageNumber: annotation.pageNumber ?? "",
                onSave: { newCaption, newPageNumber in
                    let page = newPageNumber.isEmpty ? nil : newPageNumber
                    onUpdate(newCaption, page)
                }
            )
        }
        .fullScreenCover(isPresented: $showingFullScreenImage) {
            if let imageURL = annotation.imageURL,
               let uiImage = UIImage(contentsOfFile: imageURL.path) {
                ZoomableImageView(image: uiImage)
            }
        }
    }

    private var iconForType: String {
        switch annotation.type {
        case .audio: return "waveform"
        case .image: return "photo"
        case .video: return "video"
        case .text: return "text.quote"
        }
    }

    @ViewBuilder
    private var audioContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Playback controls
            if let audioURL = annotation.audioURL {
                HStack {
                    Button {
                        audioPlayer.togglePlayPause(url: audioURL, annotationId: annotation.id)
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.blue)
                    }

                    VStack(alignment: .leading) {
                        // Progress bar
                        if isPlaying || audioPlayer.currentAnnotationId == annotation.id {
                            ProgressView(value: audioPlayer.currentTime, total: max(audioPlayer.duration, 0.1))
                                .tint(.blue)
                        }
                        Text(annotation.formattedDuration)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
            }

            // Transcription
            if let transcription = annotation.transcription, !transcription.isEmpty {
                LinkedText(transcription)
                    .font(.body)
                    .foregroundColor(.primary)
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
                    .onTapGesture {
                        showingFullScreenImage = true
                    }
            }

            if let caption = annotation.caption, !caption.isEmpty {
                LinkedText(caption)
                    .font(.body)
                    .foregroundColor(.primary)
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

            if let caption = annotation.caption, !caption.isEmpty {
                LinkedText(caption)
                    .font(.body)
                    .foregroundColor(.primary)
            }
        }
    }

    @ViewBuilder
    private var textContent: some View {
        if let caption = annotation.caption {
            LinkedText(caption)
                .font(.body)
                .foregroundColor(.primary)
        }
    }

    private var isPlaying: Bool {
        audioPlayer.isPlaying && audioPlayer.currentAnnotationId == annotation.id
    }
}

struct EditCaptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var caption: String
    @State private var pageNumber: String
    let onSave: (String, String) -> Void

    init(caption: String, pageNumber: String, onSave: @escaping (String, String) -> Void) {
        self._caption = State(initialValue: caption)
        self._pageNumber = State(initialValue: pageNumber)
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Caption or transcription", text: $caption, axis: .vertical)
                        .lineLimit(5...10)
                }

                Section {
                    TextField("Page number (optional)", text: $pageNumber)
                        .keyboardType(.default)
                } header: {
                    Text("Page Reference")
                } footer: {
                    Text("Add a page number to remember where this was in the book")
                }
            }
            .navigationTitle("Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(caption, pageNumber)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Zoomable Image View

struct ZoomableImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    .offset(offset)
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = lastScale * value
                            }
                            .onEnded { _ in
                                lastScale = scale
                                if scale < 1.0 {
                                    withAnimation {
                                        scale = 1.0
                                        lastScale = 1.0
                                        offset = .zero
                                        lastOffset = .zero
                                    }
                                }
                            }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { value in
                                if scale > 1.0 {
                                    offset = CGSize(
                                        width: lastOffset.width + value.translation.width,
                                        height: lastOffset.height + value.translation.height
                                    )
                                }
                            }
                            .onEnded { _ in
                                lastOffset = offset
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation {
                            if scale > 1.0 {
                                scale = 1.0
                                lastScale = 1.0
                                offset = .zero
                                lastOffset = .zero
                            } else {
                                scale = 2.5
                                lastScale = 2.5
                            }
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
            .background(Color.black)
            .ignoresSafeArea()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }
}

// MARK: - Linked Text (Clickable URLs)

struct LinkedText: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(attributedString)
    }

    private var attributedString: AttributedString {
        var attributedString = AttributedString(text)

        // URL regex pattern
        let urlPattern = #"https?://[^\s<>\"\[\]]+"#

        guard let regex = try? NSRegularExpression(pattern: urlPattern, options: []) else {
            return attributedString
        }

        let nsString = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))

        for match in matches {
            guard let range = Range(match.range, in: text),
                  let attributedRange = Range(range, in: attributedString),
                  let url = URL(string: String(text[range])) else {
                continue
            }

            attributedString[attributedRange].link = url
            attributedString[attributedRange].foregroundColor = .blue
            attributedString[attributedRange].underlineStyle = .single
        }

        return attributedString
    }
}

// MARK: - Video Thumbnail Player

struct VideoThumbnailPlayer: View {
    let url: URL
    @State private var player: AVPlayer?
    @State private var showPlayer = false
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            if showPlayer, let player = player {
                VideoPlayer(player: player)
                    .onDisappear {
                        player.pause()
                    }
            } else {
                // Thumbnail view
                thumbnailView

                // Play button overlay
                Button {
                    startPlayback()
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.white)
                        .shadow(radius: 4)
                }
            }
        }
        .onAppear {
            generateThumbnail()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if let thumbnail = thumbnail {
            Image(uiImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Rectangle()
                .fill(Color.black.opacity(0.3))
                .overlay {
                    ProgressView()
                }
        }
    }

    private func startPlayback() {
        // Create player first, then show
        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        showPlayer = true
        newPlayer.play()
    }

    private func generateThumbnail() {
        Task {
            let asset = AVAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 400, height: 400)

            do {
                let cgImage = try await imageGenerator.image(at: .zero).image
                await MainActor.run {
                    self.thumbnail = UIImage(cgImage: cgImage)
                }
            } catch {
                print("Thumbnail generation failed: \(error)")
            }
        }
    }
}

// MARK: - Static Video Thumbnail (for forms/sheets)

struct VideoThumbnail: View {
    let url: URL
    @State private var thumbnail: UIImage?

    var body: some View {
        ZStack {
            if let thumbnail = thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Rectangle()
                    .fill(Color.black.opacity(0.3))
                    .overlay {
                        ProgressView()
                    }
            }

            Image(systemName: "video.fill")
                .font(.title)
                .foregroundColor(.white)
                .padding(8)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
        .onAppear {
            generateThumbnail()
        }
    }

    private func generateThumbnail() {
        Task {
            let asset = AVAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 400, height: 400)

            do {
                let cgImage = try await imageGenerator.image(at: .zero).image
                await MainActor.run {
                    self.thumbnail = UIImage(cgImage: cgImage)
                }
            } catch {
                print("Thumbnail generation failed: \(error)")
            }
        }
    }
}
