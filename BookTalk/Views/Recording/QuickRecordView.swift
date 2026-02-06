import SwiftUI

struct QuickRecordView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var transcriptionService = TranscriptionService()
    @State private var selectedBook: Book?
    @State private var showBookPicker = false
    @State private var currentRecordingFilename: String?
    @State private var pendingRecording: PendingRecording?
    @State private var showSavedBanner = false
    @State private var savedBookTitle = ""
    @State private var errorMessage: String?
    @State private var showingError = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                if audioRecorder.isRecording {
                    recordingState
                } else {
                    preRecordState
                }
                Spacer()
                controls
            }
            .padding(24)
            .navigationTitle("Quick Record")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showBookPicker) {
                BookPickerView(selectedBook: $selectedBook) {
                    discardRecordingAndDismiss()
                }
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An error occurred")
            }
            .onChange(of: selectedBook) { _ in
                savePendingRecordingIfNeeded()
            }
            .overlay(alignment: .top) {
                if showSavedBanner {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Saved to \(savedBookTitle)")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial, in: Capsule())
                    .shadow(color: .black.opacity(0.12), radius: 10, y: 6)
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: showSavedBanner)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") {
                if audioRecorder.isRecording {
                    discardRecordingAndDismiss()
                } else {
                    dismiss()
                }
            }
        }
    }

    private var preRecordState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 140, height: 140)
                Image(systemName: "mic.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundColor(.blue)
            }
            Text("Start a quick audio note")
                .font(.title2.weight(.semibold))
            Text("Pick a book while you record, then save or discard.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var recordingState: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                Text(formatDuration(audioRecorder.currentDuration))
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundColor(.red)
            }

            if let selectedBook {
                VStack(spacing: 6) {
                    Text("Saving to")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(selectedBook.title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                }
            } else {
                Text("No book selected yet")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if audioRecorder.isRecording {
                Button {
                    showBookPicker = true
                } label: {
                    Label(selectedBook == nil ? "Choose Book" : "Change Book", systemImage: "book")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    stopRecording()
                } label: {
                    Text("Stop & Save")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button {
                    startRecording()
                } label: {
                    Text("Start Recording")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
        }
    }

    private func startRecording() {
        guard let filename = audioRecorder.startRecording() else {
            errorMessage = "Failed to start recording."
            showingError = true
            return
        }
        currentRecordingFilename = filename
    }

    private func stopRecording() {
        guard let result = audioRecorder.stopRecording() else { return }
        currentRecordingFilename = nil
        pendingRecording = PendingRecording(filename: result.filename, duration: result.duration)

        guard selectedBook != nil else {
            showBookPicker = true
            return
        }

        savePendingRecordingIfNeeded()
    }

    private func discardRecordingAndDismiss() {
        if audioRecorder.isRecording, let result = audioRecorder.stopRecording() {
            discardRecording(filename: result.filename)
        } else if let currentRecordingFilename {
            discardRecording(filename: currentRecordingFilename)
        } else if let pendingRecording {
            discardRecording(filename: pendingRecording.filename)
        }
        pendingRecording = nil
        dismiss()
    }

    private func discardRecording(filename: String) {
        let url = DatabaseManager.audioDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: url)
    }

    private func savePendingRecordingIfNeeded() {
        guard let pending = pendingRecording, let selectedBook else { return }

        let audioURL = DatabaseManager.audioDirectory.appendingPathComponent(pending.filename)
        var annotation = Annotation(
            bookId: selectedBook.id,
            type: .audio,
            audioPath: pending.filename,
            duration: pending.duration
        )

        do {
            try annotation.save()
            pendingRecording = nil
            Task {
                if let transcription = await transcriptionService.transcribe(audioURL: audioURL) {
                    var mutable = annotation
                    try? mutable.updateTranscription(transcription)
                }
            }
            savedBookTitle = selectedBook.title
            withAnimation {
                showSavedBanner = true
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 700_000_000)
                dismiss()
            }
        } catch {
            discardRecording(filename: pending.filename)
            pendingRecording = nil
            errorMessage = "Failed to save recording."
            showingError = true
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

private struct PendingRecording {
    let filename: String
    let duration: TimeInterval
}

private struct BookPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var books: [Book] = []
    @State private var searchText = ""
    @Binding var selectedBook: Book?
    let onCancelRecording: () -> Void

    var body: some View {
        NavigationStack {
            List {
                if filteredBooks.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "book")
                            .font(.system(size: 40, weight: .light))
                            .foregroundColor(.secondary)
                        Text("No books found")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 60)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredBooks) { book in
                        Button {
                            selectedBook = book
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                if let coverURL = book.coverImageURL,
                                   let image = UIImage(contentsOfFile: coverURL.path) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 44, height: 64)
                                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                } else {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(Color.gray.opacity(0.15))
                                        .frame(width: 44, height: 64)
                                        .overlay {
                                            Image(systemName: "book.closed.fill")
                                                .font(.caption)
                                                .foregroundColor(.gray)
                                        }
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(book.title)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                    if let author = book.author {
                                        Text(author)
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                }

                                Spacer()
                                if selectedBook?.id == book.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose Book")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search books")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Discard Recording", role: .destructive) {
                        dismiss()
                        onCancelRecording()
                    }
                }
            }
            .interactiveDismissDisabled(true)
            .onAppear { loadBooks() }
        }
    }

    private var filteredBooks: [Book] {
        guard !searchText.isEmpty else { return books }
        let query = searchText.lowercased()
        return books.filter { $0.title.lowercased().contains(query) || ($0.author?.lowercased().contains(query) ?? false) }
    }

    private func loadBooks() {
        do {
            books = try Book.all(archived: false)
        } catch {
            books = []
        }
    }
}

#Preview {
    QuickRecordView()
}
