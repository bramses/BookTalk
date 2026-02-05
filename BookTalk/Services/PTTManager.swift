import Foundation
import AVFoundation
import os.log

extension Notification.Name {
    static let pttRecordingCompleted = Notification.Name("pttRecordingCompleted")
    static let pttTranscriptionCompleted = Notification.Name("pttTranscriptionCompleted")
}

private let pttLogger = Logger(subsystem: "dev.bramadams.BookTalk", category: "PTT")

/// PTT-Style Recording Manager (local recording only, no push-to-talk communication)
/// This provides a walkie-talkie style UI for local audio recording
@MainActor
class PTTManager: NSObject, ObservableObject {
    static let shared = PTTManager()

    @Published var isRecording = false
    @Published var currentBookId: String?
    @Published var currentBookTitle: String?

    // Audio recording
    private var audioRecorder: AVAudioRecorder?
    private var currentRecordingURL: URL?
    private var recordingStartTime: Date?

    var onRecordingComplete: ((Annotation) -> Void)?

    override init() {
        super.init()
        pttLogger.info("PTT-Style Recording Manager initialized")
    }

    func setBook(_ book: Book) {
        currentBookId = book.id
        currentBookTitle = book.title
        pttLogger.info("Set active book: \(book.title)")
    }
    
    func startRecording() {
        guard !isRecording else {
            pttLogger.warning("Already recording")
            return
        }
        
        guard let bookId = currentBookId else {
            pttLogger.error("No book set for recording")
            return
        }
        
        startInternalRecording()
    }
    
    func stopRecording() {
        guard isRecording else {
            pttLogger.warning("Not currently recording")
            return
        }
        
        stopInternalRecording()
    }

    
    // MARK: - Internal Recording

    private func startInternalRecording() {
        guard let bookId = currentBookId else {
            pttLogger.error("No book ID for recording")
            return
        }

        // Ensure audio directory exists
        let audioDir = DatabaseManager.audioDirectory
        if !FileManager.default.fileExists(atPath: audioDir.path) {
            do {
                try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
            } catch {
                pttLogger.error("Failed to create audio directory: \(error.localizedDescription)")
                return
            }
        }

        let filename = "\(bookId)_\(UUID().uuidString).m4a"
        let url = audioDir.appendingPathComponent(filename)
        
        pttLogger.info("Starting recording to: \(filename)")

        // Configure audio session
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            pttLogger.error("Failed to configure audio session: \(error.localizedDescription)")
            return
        }

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true

            if audioRecorder?.record() == true {
                currentRecordingURL = url
                recordingStartTime = Date()
                isRecording = true
                pttLogger.info("✅ Recording started successfully")
            } else {
                pttLogger.error("Failed to start recording")
            }
        } catch {
            pttLogger.error("Failed to create recorder: \(error.localizedDescription)")
        }
    }

    private func stopInternalRecording() {
        guard let recorder = audioRecorder,
              let url = currentRecordingURL,
              let bookId = currentBookId,
              let startTime = recordingStartTime else {
            pttLogger.warning("No recording to stop")
            return
        }

        recorder.stop()
        isRecording = false
        
        let duration = Date().timeIntervalSince(startTime)
        pttLogger.info("Stopped recording, duration: \(duration)s")

        // Only save if we have meaningful audio (> 0.5 seconds)
        if duration > 0.5 {
            let filename = url.lastPathComponent

            var annotation = Annotation(
                bookId: bookId,
                type: .audio,
                audioPath: filename,
                duration: duration
            )

            do {
                try annotation.save()
                pttLogger.info("Saved annotation: \(annotation.id)")
                onRecordingComplete?(annotation)

                // Post notification for UI updates
                NotificationCenter.default.post(name: .pttRecordingCompleted, object: annotation)

                // Start transcription in background
                Task.detached {
                    await self.transcribeRecording(annotation: annotation, audioURL: url)
                }
            } catch {
                pttLogger.error("Failed to save annotation: \(error.localizedDescription)")
            }
        } else {
            pttLogger.info("Recording too short, deleting")
            try? FileManager.default.removeItem(at: url)
        }

        audioRecorder = nil
        currentRecordingURL = nil
        recordingStartTime = nil
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)
    }

    private func transcribeRecording(annotation: Annotation, audioURL: URL) async {
        let transcriptionService = await TranscriptionService()

        if let transcription = await transcriptionService.transcribe(audioURL: audioURL) {
            var mutableAnnotation = annotation
            do {
                try mutableAnnotation.updateTranscription(transcription)
                pttLogger.info("Transcription saved for \(annotation.id)")
                
                // Post notification on main actor to update UI
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .pttTranscriptionCompleted,
                        object: mutableAnnotation
                    )
                }
            } catch {
                pttLogger.error("Failed to save transcription: \(error.localizedDescription)")
            }
        } else {
            pttLogger.warning("Transcription failed for \(annotation.id)")
        }
    }
}


