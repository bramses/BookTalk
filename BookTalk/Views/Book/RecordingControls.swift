import SwiftUI

struct RecordingControls: View {
    let book: Book
    @ObservedObject var audioRecorder: AudioRecorder
    @ObservedObject var transcriptionService: TranscriptionService
    var onRecordingComplete: (Annotation) -> Void
    var onTranscriptionStarted: ((String) -> Void)?
    var onTranscriptionComplete: ((String, String) -> Void)?
    var onImageCapture: () -> Void
    var onTextNote: () -> Void

    @State private var currentRecordingFilename: String?

    var body: some View {
        VStack(spacing: 12) {
            // Recording duration
            if audioRecorder.isRecording {
                HStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 8, height: 8)
                    Text(formatDuration(audioRecorder.currentDuration))
                        .font(.headline.monospacedDigit())
                        .foregroundColor(.red)
                }
            }

            // Controls - Note and Photo balanced around mic
            HStack {
                // Text note button - left side
                Button {
                    onTextNote()
                } label: {
                    VStack {
                        Image(systemName: "note.text")
                            .font(.system(size: 24))
                        Text("Note")
                            .font(.caption)
                    }
                    .foregroundColor(.green)
                    .frame(maxWidth: .infinity)
                }
                .disabled(audioRecorder.isRecording)
                .accessibilityLabel("Add text note")

                // Record button - center
                Button {
                    if audioRecorder.isRecording {
                        stopRecording()
                    } else {
                        startRecording()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(audioRecorder.isRecording ? Color.red : Color.blue)
                            .frame(width: 72, height: 72)

                        if audioRecorder.isRecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white)
                                .frame(width: 24, height: 24)
                        } else {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                        }
                    }
                }
                .accessibilityLabel(audioRecorder.isRecording ? "Stop recording" : "Start recording")
                .accessibilityHint(audioRecorder.isRecording ? "Double tap to stop" : "Double tap to record audio annotation")

                // Image/Video capture button - right side
                Button {
                    onImageCapture()
                } label: {
                    VStack {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 24))
                        Text("Media")
                            .font(.caption)
                    }
                    .foregroundColor(.blue)
                    .frame(maxWidth: .infinity)
                }
                .disabled(audioRecorder.isRecording)
                .accessibilityLabel("Add photo or video")
            }
            .padding(.horizontal, 24)
        }
        .padding()
        .background(Color(.systemGroupedBackground))
    }

    private func startRecording() {
        currentRecordingFilename = audioRecorder.startRecording(forBook: book.id)
    }

    private func stopRecording() {
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

        // Save annotation first
        do {
            try annotation.save()
            onRecordingComplete(annotation)
        } catch {
            print("Failed to save annotation: \(error)")
            return
        }

        // Start transcription in background
        let annotationId = annotation.id
        onTranscriptionStarted?(annotationId)

        Task {
            if let transcription = await transcriptionService.transcribe(audioURL: audioURL) {
                do {
                    try annotation.updateTranscription(transcription)
                    await MainActor.run {
                        onTranscriptionComplete?(annotationId, transcription)
                    }
                } catch {
                    print("Failed to save transcription: \(error)")
                    await MainActor.run {
                        onTranscriptionComplete?(annotationId, "")
                    }
                }
            } else {
                await MainActor.run {
                    onTranscriptionComplete?(annotationId, "")
                }
            }
        }

        currentRecordingFilename = nil
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}
