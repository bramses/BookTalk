import SwiftUI

struct PTTSessionView: View {
    let book: Book
    @ObservedObject var pttManager = PTTManager.shared
    var onRecordingComplete: (Annotation) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var audioRecorder = AudioRecorder()
    @StateObject private var transcriptionService = TranscriptionService()
    @State private var currentRecordingFilename: String?
    @State private var recordings: [RecordingInfo] = []

    struct RecordingInfo: Identifiable {
        let id: String
        let annotation: Annotation
        var isTranscribing: Bool = false
        var transcription: String?
    }

    private var isRecording: Bool {
        pttManager.isTransmitting || audioRecorder.isRecording
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Book cover header
                bookCoverHeader

                // Status
                statusSection

                // Recent recordings in this session
                if !recordings.isEmpty {
                    recordingsList
                }

                Spacer()

                // Recording controls
                recordingControls
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Recording Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        // Don't leave channel on dismiss - user can stay in PTT mode
                        // and leave via the global floating indicator
                        dismiss()
                    }
                }
            }
            .onAppear {
                setupPTTCallbacks()
            }
        }
    }

    private var bookCoverHeader: some View {
        VStack(spacing: 16) {
            if let coverURL = book.coverImageURL,
               let uiImage = UIImage(contentsOfFile: coverURL.path) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .shadow(radius: 8)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 133, height: 200)
                    .overlay {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.blue)
                    }
                    .shadow(radius: 8)
            }

            VStack(spacing: 4) {
                Text(book.title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                if let author = book.author {
                    Text(author)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
    }

    private var statusSection: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            Text(pttManager.isJoined ? pttManager.channelStatus : "Ready")
                .font(.subheadline)
            Spacer()
            if isRecording {
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text(formatDuration(audioRecorder.currentDuration))
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private var statusColor: Color {
        if isRecording {
            return .red
        } else if pttManager.isJoined {
            return .green
        } else {
            return .orange
        }
    }

    private var recordingsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session Recordings (\(recordings.count))")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top)

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(recordings) { recording in
                        HStack {
                            Image(systemName: "waveform")
                                .foregroundColor(.blue)
                            VStack(alignment: .leading) {
                                Text(recording.annotation.formattedDate)
                                    .font(.subheadline)
                                if recording.isTranscribing {
                                    HStack(spacing: 4) {
                                        ProgressView()
                                            .scaleEffect(0.6)
                                        Text("Transcribing...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                } else if let transcription = recording.transcription, !transcription.isEmpty {
                                    Text(transcription)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            Text(recording.annotation.formattedDuration)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.horizontal)
            }
            .frame(maxHeight: 200)
        }
    }

    private var recordingControls: some View {
        VStack(spacing: 20) {
            if !pttManager.isJoined {
                // Join channel button
                Button {
                    pttManager.joinChannel(forBook: book)
                } label: {
                    HStack {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                        Text("Join PTT Channel")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(.horizontal)

                Text("— or —")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Text(pttManager.isJoined ? "Hold to Talk (PTT Active)" : "Hold to Record")
                .font(.subheadline)
                .foregroundColor(.secondary)

            // Large record button
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red : (pttManager.isJoined ? Color.orange : Color.blue))
                    .frame(width: 120, height: 120)
                    .shadow(color: isRecording ? .red.opacity(0.5) : (pttManager.isJoined ? .orange.opacity(0.5) : .blue.opacity(0.5)), radius: 10)

                Image(systemName: pttManager.isJoined ? "antenna.radiowaves.left.and.right" : "mic.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.white)
            }
            .scaleEffect(isRecording ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isRecording)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isRecording {
                            startRecording()
                        }
                    }
                    .onEnded { _ in
                        if isRecording {
                            stopRecording()
                        }
                    }
            )

            Text("Release to stop and transcribe")
                .font(.caption)
                .foregroundColor(.secondary)

            if pttManager.isJoined {
                Button {
                    pttManager.leaveChannel()
                } label: {
                    Text("Leave Channel")
                        .font(.subheadline)
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
        .padding(.bottom, 20)
        .background(Color(.systemBackground))
    }

    private func setupPTTCallbacks() {
        pttManager.onAudioSessionActivated = {
            // PTT audio session activated - ready to record
        }
        pttManager.onAudioSessionDeactivated = {
            // PTT audio session deactivated
        }
    }

    private func startRecording() {
        if pttManager.isJoined {
            pttManager.startTransmitting()
        }
        currentRecordingFilename = audioRecorder.startRecording(forBook: book.id)
    }

    private func stopRecording() {
        if pttManager.isJoined {
            pttManager.stopTransmitting()
        }

        guard let result = audioRecorder.stopRecording(),
              let filename = currentRecordingFilename else {
            return
        }

        let audioURL = DatabaseManager.audioDirectory.appendingPathComponent(filename)

        // Create annotation
        var annotation = Annotation(
            bookId: book.id,
            type: .audio,
            audioPath: filename,
            duration: result.duration
        )

        // Save annotation
        do {
            try annotation.save()
            onRecordingComplete(annotation)

            // Add to local recordings list
            let annotationId = annotation.id
            let recordingInfo = RecordingInfo(
                id: annotationId,
                annotation: annotation,
                isTranscribing: true,
                transcription: nil
            )
            recordings.insert(recordingInfo, at: 0)

            // Start transcription
            Task {
                if let transcription = await transcriptionService.transcribe(audioURL: audioURL) {
                    do {
                        try annotation.updateTranscription(transcription)
                        await MainActor.run {
                            if let index = recordings.firstIndex(where: { $0.id == annotationId }) {
                                recordings[index] = RecordingInfo(
                                    id: annotationId,
                                    annotation: annotation,
                                    isTranscribing: false,
                                    transcription: transcription
                                )
                            }
                        }
                    } catch {
                        print("Failed to save transcription: \(error)")
                        await MainActor.run {
                            markTranscriptionComplete(annotationId)
                        }
                    }
                } else {
                    await MainActor.run {
                        markTranscriptionComplete(annotationId)
                    }
                }
            }
        } catch {
            print("Failed to save annotation: \(error)")
        }

        currentRecordingFilename = nil
    }

    private func markTranscriptionComplete(_ annotationId: String) {
        if let index = recordings.firstIndex(where: { $0.id == annotationId }) {
            let updated = recordings[index]
            recordings[index] = RecordingInfo(
                id: updated.id,
                annotation: updated.annotation,
                isTranscribing: false,
                transcription: updated.transcription
            )
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
