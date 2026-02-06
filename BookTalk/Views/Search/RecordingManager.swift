import Foundation
import AVFoundation
import os.log

private let recordingLogger = Logger(subsystem: "dev.bramadams.BookTalk", category: "Recording")

/// Simple audio recording manager that works in background
/// Replaces PTTManager with a solution that actually works
@MainActor
class RecordingManager: NSObject, ObservableObject {
    static let shared = RecordingManager()
    
    @Published var isRecording = false
    @Published var currentBookId: String?
    @Published var currentBookTitle: String?
    
    private var audioRecorder: AVAudioRecorder?
    private var currentRecordingURL: URL?
    private var recordingStartTime: Date?
    
    // UserDefaults keys
    private let bookIdKey = "CurrentBookId"
    private let bookTitleKey = "CurrentBookTitle"
    
    override init() {
        super.init()
        restoreCurrentBook()
        configureAudioSession()
    }
    
    /// Configure audio session for background recording
    func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
            recordingLogger.info("✅ Audio session configured for recording")
        } catch {
            recordingLogger.error("❌ Failed to configure audio session: \(error.localizedDescription)")
        }
    }
    
    /// Set the active book for recording
    func setActiveBook(_ book: Book) {
        currentBookId = book.id
        currentBookTitle = book.title
        
        UserDefaults.standard.set(book.id, forKey: bookIdKey)
        UserDefaults.standard.set(book.title, forKey: bookTitleKey)
        
        recordingLogger.info("📚 Set active book: \(book.title)")
    }
    
    /// Restore the current book from UserDefaults
    private func restoreCurrentBook() {
        currentBookId = UserDefaults.standard.string(forKey: bookIdKey)
        currentBookTitle = UserDefaults.standard.string(forKey: bookTitleKey)
        
        if let title = currentBookTitle {
            recordingLogger.info("🔄 Restored active book: \(title)")
        }
    }
    
    /// Toggle recording on/off
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
    
    /// Start recording
    func startRecording() {
        recordingLogger.info("🔴 Starting recording")
        
        guard let bookId = currentBookId else {
            recordingLogger.error("❌ No active book set")
            return
        }
        
        let audioDir = DatabaseManager.audioDirectory
        if !FileManager.default.fileExists(atPath: audioDir.path) {
            try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        }
        
        let filename = "\(bookId)_\(UUID().uuidString).m4a"
        let url = audioDir.appendingPathComponent(filename)
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.prepareToRecord()
            
            if audioRecorder?.record() == true {
                currentRecordingURL = url
                recordingStartTime = Date()
                isRecording = true
                recordingLogger.info("✅ Recording started: \(filename)")
            } else {
                recordingLogger.error("❌ Failed to start recording")
            }
        } catch {
            recordingLogger.error("❌ Error creating recorder: \(error.localizedDescription)")
        }
    }
    
    /// Stop recording and save
    func stopRecording() {
        recordingLogger.info("⏹️ Stopping recording")
        
        guard let recorder = audioRecorder,
              let url = currentRecordingURL,
              let bookId = currentBookId,
              let startTime = recordingStartTime else {
            recordingLogger.warning("⚠️ No active recording to stop")
            return
        }
        
        recorder.stop()
        let duration = Date().timeIntervalSince(startTime)
        
        audioRecorder = nil
        currentRecordingURL = nil
        recordingStartTime = nil
        isRecording = false
        
        recordingLogger.info("⏱️ Recording duration: \(duration)s")
        
        // Only save if > 0.5 seconds
        guard duration > 0.5 else {
            try? FileManager.default.removeItem(at: url)
            recordingLogger.info("🗑️ Recording too short, deleted")
            return
        }
        
        // Save annotation
        var annotation = Annotation(
            bookId: bookId,
            type: .audio,
            audioPath: url.lastPathComponent,
            duration: duration
        )
        
        do {
            try annotation.save()
            recordingLogger.info("💾 Saved annotation: \(annotation.id)")
            
            // Notify app
            NotificationCenter.default.post(
                name: NSNotification.Name("RecordingCompleted"),
                object: annotation
            )
            
            // Transcribe in background
            Task.detached {
                await self.transcribe(annotation: annotation, audioURL: url)
            }
        } catch {
            recordingLogger.error("❌ Failed to save annotation: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    /// Transcribe the recording
    private func transcribe(annotation: Annotation, audioURL: URL) async {
        let transcriptionService = await TranscriptionService()
        
        guard let transcription = await transcriptionService.transcribe(audioURL: audioURL) else {
            recordingLogger.warning("⚠️ Transcription failed")
            return
        }
        
        var mutableAnnotation = annotation
        do {
            try mutableAnnotation.updateTranscription(transcription)
            recordingLogger.info("✅ Transcription saved")
            
            await MainActor.run {
                NotificationCenter.default.post(
                    name: NSNotification.Name("TranscriptionCompleted"),
                    object: mutableAnnotation
                )
            }
        } catch {
            recordingLogger.error("❌ Failed to save transcription: \(error.localizedDescription)")
        }
    }
}
