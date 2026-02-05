import SwiftUI
import PhotosUI
import AVKit

struct BookDetailView: View {
    @State var book: Book
    var scrollToAnnotationId: String? = nil
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var audioPlayer = AudioPlayer()
    @StateObject private var transcriptionService = TranscriptionService()
    @ObservedObject private var pttManager = PTTManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var annotations: [Annotation] = []
    @State private var showingImagePicker = false
    @State private var showingMediaLibraryPicker = false
    @State private var showingMediaSourceSheet = false
    @State private var capturedImage: UIImage?
    @State private var mediaPickerResult: MediaPickerResult?
    @State private var showingCaptionSheet = false
    @State private var pendingImagePath: String?
    @State private var pendingVideoPath: String?
    @State private var pendingMediaIsVideo = false
    @State private var showingEditBook = false
    @State private var showingTextNoteSheet = false
    @State private var transcribingAnnotationId: String?
    @State private var hasScrolledToAnnotation = false
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        mainContent
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            transcriptionBanner
            annotationsList
            Divider()
            recordingControlsView
        }
        .navigationTitle(book.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .onAppear { loadAnnotations() }
        .sheet(isPresented: $showingImagePicker) { ImagePicker(image: $capturedImage) }
        .sheet(isPresented: $showingMediaLibraryPicker) { MediaLibraryPicker(result: $mediaPickerResult) }
        .sheet(isPresented: $showingCaptionSheet) { captionSheet }
        .sheet(isPresented: $showingEditBook) { EditBookSheet(book: $book) }
        .sheet(isPresented: $showingTextNoteSheet) { textNoteSheet }
        .confirmationDialog("Add Photo or Video", isPresented: $showingMediaSourceSheet) { mediaSourceButtons }
        .onChange(of: capturedImage) { handleCapturedImage($0) }
        .onChange(of: mediaPickerResult) { handleMediaResult($0) }
        .onChange(of: scenePhase) { handleScenePhase($0) }
        .onReceive(NotificationCenter.default.publisher(for: .pttRecordingCompleted)) { handlePTTNotification($0) }
        .onReceive(NotificationCenter.default.publisher(for: .pttTranscriptionCompleted)) { handlePTTTranscriptionNotification($0) }
        .alert("Error", isPresented: $showingError) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "An error occurred") }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { showingEditBook = true } label: { Label("Edit Book", systemImage: "pencil") }
                Button { 
                    PTTManager.shared.joinChannel(for: book)
                } label: { 
                    Label("Enable Lock Screen Recording", systemImage: "lock.open.iphone") 
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
    }

    @ViewBuilder
    private var transcriptionBanner: some View {
        if transcribingAnnotationId != nil {
            HStack {
                ProgressView().scaleEffect(0.8)
                Text("Transcribing audio...").font(.subheadline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
        }
    }

    private var annotationsList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if annotations.isEmpty {
                        emptyStateView
                    } else {
                        ForEach(annotations) { annotation in
                            annotationRow(for: annotation)
                        }
                    }
                }
                .padding()
            }
            .onChange(of: annotations.count) { _ in performScrollIfNeeded(proxy: proxy) }
            .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { performScrollIfNeeded(proxy: proxy) } }
        }
    }

    private var recordingControlsView: some View {
        RecordingControls(
            book: book,
            audioRecorder: audioRecorder,
            transcriptionService: transcriptionService,
            onRecordingComplete: { annotations.insert($0, at: 0) },
            onTranscriptionStarted: { transcribingAnnotationId = $0 },
            onTranscriptionComplete: { id, text in
                transcribingAnnotationId = nil
                if let idx = annotations.firstIndex(where: { $0.id == id }) { annotations[idx].transcription = text }
            },
            onImageCapture: { showingMediaSourceSheet = true },
            onTextNote: { showingTextNoteSheet = true }
        )
    }

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.bubble").font(.system(size: 40)).foregroundColor(.secondary)
            Text("No annotations yet").font(.headline).foregroundColor(.secondary)
            Text("Use the controls below to add audio or image annotations").font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 60)
    }

    private var captionSheet: some View {
        MediaCaptionInputSheet(imagePath: pendingImagePath, videoPath: pendingVideoPath, isVideo: pendingMediaIsVideo, bookId: book.id) { annotation in
            annotations.insert(annotation, at: 0)
            pendingImagePath = nil; pendingVideoPath = nil; pendingMediaIsVideo = false
        }
    }

    private var textNoteSheet: some View {
        TextNoteInputSheet(bookId: book.id) { annotations.insert($0, at: 0) }
    }

    @ViewBuilder
    private var mediaSourceButtons: some View {
        Button("Take Photo") { showingImagePicker = true }
        Button("Choose from Library") { showingMediaLibraryPicker = true }
        Button("Cancel", role: .cancel) {}
    }

    private func annotationRow(for annotation: Annotation) -> some View {
        AnnotationRow(
            annotation: annotation,
            audioPlayer: audioPlayer,
            isHighlighted: annotation.id == scrollToAnnotationId,
            onDelete: { deleteAnnotation(annotation) },
            onUpdate: { updateAnnotation(annotation, text: $0, pageNumber: $1) },
            onRetranscribe: annotation.type == .audio ? { retranscribeAnnotation(annotation) } : nil
        ).id(annotation.id)
    }

    private func performScrollIfNeeded(proxy: ScrollViewProxy) {
        guard let targetId = scrollToAnnotationId, !hasScrolledToAnnotation, annotations.contains(where: { $0.id == targetId }) else { return }
        hasScrolledToAnnotation = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { withAnimation { proxy.scrollTo(targetId, anchor: .center) } }
    }

    private func handleCapturedImage(_ newImage: UIImage?) {
        if let image = newImage { saveImage(image) }
    }

    private func handleMediaResult(_ result: MediaPickerResult?) {
        if let result = result { handleMediaPickerResult(result); mediaPickerResult = nil }
    }

    private func handleScenePhase(_ newPhase: ScenePhase) {
        if newPhase == .active { loadAnnotations() }
    }

    private func handlePTTNotification(_ notification: Notification) {
        if let annotation = notification.object as? Annotation, annotation.bookId == book.id {
            // Add new annotation if not already present
            if !annotations.contains(where: { $0.id == annotation.id }) {
                annotations.insert(annotation, at: 0)
            }
        }
    }
    
    private func handlePTTTranscriptionNotification(_ notification: Notification) {
        if let annotation = notification.object as? Annotation, annotation.bookId == book.id {
            // Update the annotation in the list with the transcribed version
            if let index = annotations.firstIndex(where: { $0.id == annotation.id }) {
                annotations[index] = annotation
            }
        }
    }

    private func loadAnnotations() {
        do { annotations = try Annotation.forBook(book.id) }
        catch { errorMessage = "Failed to load annotations."; showingError = true }
    }

    private func deleteAnnotation(_ annotation: Annotation) {
        do { try annotation.delete(); annotations.removeAll { $0.id == annotation.id } }
        catch { errorMessage = "Failed to delete annotation."; showingError = true }
    }

    private func updateAnnotation(_ annotation: Annotation, text: String?, pageNumber: String?) {
        var mutable = annotation
        do { try mutable.update(text: text, pageNumber: pageNumber); if let idx = annotations.firstIndex(where: { $0.id == annotation.id }) { annotations[idx] = mutable } }
        catch { errorMessage = "Failed to update annotation."; showingError = true }
    }

    private func retranscribeAnnotation(_ annotation: Annotation) {
        guard let audioURL = annotation.audioURL else { return }
        let annotationId = annotation.id
        transcribingAnnotationId = annotationId

        Task {
            if let transcription = await transcriptionService.transcribe(audioURL: audioURL) {
                var mutable = annotation
                do {
                    try mutable.updateTranscription(transcription)
                    await MainActor.run {
                        if let idx = annotations.firstIndex(where: { $0.id == annotationId }) {
                            annotations[idx].transcription = transcription
                        }
                        transcribingAnnotationId = nil
                    }
                } catch {
                    await MainActor.run {
                        errorMessage = "Failed to save transcription."
                        showingError = true
                        transcribingAnnotationId = nil
                    }
                }
            } else {
                await MainActor.run {
                    errorMessage = "Transcription failed. Please try again."
                    showingError = true
                    transcribingAnnotationId = nil
                }
            }
        }
    }

    private func saveImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { errorMessage = "Failed to process image."; showingError = true; return }
        let filename = "\(book.id)_\(UUID().uuidString).jpg"
        let url = DatabaseManager.imagesDirectory.appendingPathComponent(filename)
        do { try data.write(to: url); pendingImagePath = filename; pendingMediaIsVideo = false; capturedImage = nil; showingCaptionSheet = true }
        catch { errorMessage = "Failed to save image."; showingError = true }
    }

    private func handleMediaPickerResult(_ result: MediaPickerResult) {
        if let videoURL = result.videoURL {
            let filename = "\(book.id)_\(UUID().uuidString).\(videoURL.pathExtension)"
            let destURL = DatabaseManager.videosDirectory.appendingPathComponent(filename)
            do { try FileManager.default.copyItem(at: videoURL, to: destURL); try? FileManager.default.removeItem(at: videoURL); pendingVideoPath = filename; pendingMediaIsVideo = true; showingCaptionSheet = true }
            catch { errorMessage = "Failed to save video."; showingError = true }
        } else if let image = result.image { saveImage(image) }
    }
}

// MARK: - Edit Book Sheet

struct EditBookSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var book: Book
    @State private var title: String = ""
    @State private var author: String = ""
    @State private var coverImage: UIImage?
    @State private var showingImagePicker = false
    @State private var selectedPhotoItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                coverSection
                detailsSection
            }
            .navigationTitle("Edit Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { saveChanges() }.disabled(title.isEmpty) }
            }
            .photosPicker(isPresented: $showingImagePicker, selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { newValue in
                Task { if let data = try? await newValue?.loadTransferable(type: Data.self), let image = UIImage(data: data) { await MainActor.run { coverImage = image } } }
            }
            .onAppear { title = book.title; author = book.author ?? ""; if let url = book.coverImageURL, let img = UIImage(contentsOfFile: url.path) { coverImage = img } }
        }
    }

    private var coverSection: some View {
        Section {
            HStack { Spacer(); coverImageView.onTapGesture { showingImagePicker = true }; Spacer() }
            .listRowBackground(Color.clear)
        }
    }

    @ViewBuilder
    private var coverImageView: some View {
        if let image = coverImage {
            Image(uiImage: image).resizable().aspectRatio(2/3, contentMode: .fill).frame(width: 120, height: 180).clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottomTrailing) { Image(systemName: "pencil.circle.fill").font(.title2).foregroundColor(.blue).background(Circle().fill(.white)).offset(x: 8, y: 8) }
        } else {
            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2)).frame(width: 120, height: 180)
                .overlay { VStack { Image(systemName: "photo").font(.largeTitle).foregroundColor(.gray); Text("Add Cover").font(.caption).foregroundColor(.gray) } }
        }
    }

    private var detailsSection: some View {
        Section("Book Details") { TextField("Title", text: $title); TextField("Author", text: $author) }
    }

    private func saveChanges() {
        var updated = book
        updated.title = title
        updated.author = author.isEmpty ? nil : author
        if let img = coverImage, let data = img.jpegData(compressionQuality: 0.8) {
            if let old = book.coverImageURL { try? FileManager.default.removeItem(at: old) }
            let filename = "\(book.id)_cover.jpg"
            let url = DatabaseManager.coversDirectory.appendingPathComponent(filename)
            try? data.write(to: url)
            updated.coverImagePath = filename
        }
        do { book = try updated.save(); dismiss() } catch { print("Failed to save: \(error)") }
    }
}

// MARK: - Media Caption Input Sheet

struct MediaCaptionInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    let imagePath: String?
    let videoPath: String?
    let isVideo: Bool
    let bookId: String
    @State private var caption = ""
    @State private var pageNumber = ""
    var onSave: (Annotation) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section { HStack { Spacer(); mediaPreview; Spacer() } }.listRowBackground(Color.clear)
                Section { TextField("Add a caption (optional)", text: $caption, axis: .vertical).lineLimit(3...6) }
                Section { TextField("Page number (optional)", text: $pageNumber).keyboardType(.default) } header: { Text("Page Reference") } footer: { Text("Add a page number to remember where this was in the book") }
            }
            .navigationTitle("Add Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { cleanupAndDismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { saveAnnotation() } }
            }
        }
    }

    @ViewBuilder
    private var mediaPreview: some View {
        if isVideo, let path = videoPath {
            VideoThumbnail(url: DatabaseManager.videosDirectory.appendingPathComponent(path))
                .frame(height: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if let path = imagePath, let img = UIImage(contentsOfFile: DatabaseManager.imagesDirectory.appendingPathComponent(path).path) {
            Image(uiImage: img).resizable().aspectRatio(contentMode: .fit).frame(maxHeight: 200).clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func cleanupAndDismiss() {
        if isVideo, let p = videoPath { try? FileManager.default.removeItem(at: DatabaseManager.videosDirectory.appendingPathComponent(p)) }
        else if let p = imagePath { try? FileManager.default.removeItem(at: DatabaseManager.imagesDirectory.appendingPathComponent(p)) }
        dismiss()
    }

    private func saveAnnotation() {
        let annotation = isVideo
            ? Annotation(bookId: bookId, type: .video, videoPath: videoPath, caption: caption.isEmpty ? nil : caption, pageNumber: pageNumber.isEmpty ? nil : pageNumber)
            : Annotation(bookId: bookId, type: .image, imagePath: imagePath, caption: caption.isEmpty ? nil : caption, pageNumber: pageNumber.isEmpty ? nil : pageNumber)
        do { try annotation.save(); onSave(annotation); dismiss() } catch { print("Failed to save: \(error)") }
    }
}

// MARK: - Text Note Input Sheet

struct TextNoteInputSheet: View {
    @Environment(\.dismiss) private var dismiss
    let bookId: String
    @State private var noteText = ""
    @State private var pageNumber = ""
    var onSave: (Annotation) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section { TextField("Write your note...", text: $noteText, axis: .vertical).lineLimit(5...15) } header: { Text("Note") } footer: { Text("Add thoughts, quotes, or anything you want to remember") }
                Section { TextField("Page number (optional)", text: $pageNumber).keyboardType(.default) } header: { Text("Page Reference") } footer: { Text("Add a page number to remember where this was in the book") }
            }
            .navigationTitle("Add Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { saveAnnotation() }.disabled(noteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }
        }
    }

    private func saveAnnotation() {
        let trimmed = noteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let annotation = Annotation(bookId: bookId, type: .text, caption: trimmed, pageNumber: pageNumber.isEmpty ? nil : pageNumber)
        do { try annotation.save(); onSave(annotation); dismiss() } catch { print("Failed to save: \(error)") }
    }
}
