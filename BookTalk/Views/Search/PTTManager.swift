import Foundation
#if canImport(PushToTalk)
import PushToTalk
#endif
import AVFoundation
import UIKit
import os.log

extension Notification.Name {
    static let pttRecordingCompleted = Notification.Name("pttRecordingCompleted")
    static let pttTranscriptionCompleted = Notification.Name("pttTranscriptionCompleted")
}

private let pttLogger = Logger(subsystem: "dev.bramadams.BookTalk", category: "PTT")

/// PTTManager provides lock screen / Dynamic Island recording access via PushToTalk framework
/// NOTE: PushToTalk does NOT provide audio data - we record locally with AVAudioRecorder
/// PTT only provides the UI/UX for activating recording from lock screen
@MainActor
class PTTManager: NSObject, ObservableObject {
    static let shared = PTTManager()

    @Published var isTransmitting = false
    @Published var isJoined = false
    @Published var currentBookId: String?
    @Published var currentBookTitle: String?

    #if canImport(PushToTalk)
    private var channelManager: PTChannelManager?
    private var activeChannelUUID: UUID?
    #endif

    // Local audio recording (PTT framework doesn't provide audio!)
    private var audioRecorder: AVAudioRecorder?
    private var currentRecordingURL: URL?
    private var recordingStartTime: Date?

    // UserDefaults keys for persistence
    private let bookIdKey = "PTTCurrentBookId"
    private let bookTitleKey = "PTTCurrentBookTitle"

    var onRecordingComplete: ((Annotation) -> Void)?

    override init() {
        super.init()
        #if canImport(PushToTalk)
        // Restore book context from UserDefaults for channel restoration
        currentBookId = UserDefaults.standard.string(forKey: bookIdKey)
        currentBookTitle = UserDefaults.standard.string(forKey: bookTitleKey)
        if currentBookId != nil {
            pttLogger.info("Restored book context: \(self.currentBookTitle ?? "unknown")")
        }
        #endif
    }

    func initialize() async {
        // Configure audio session for recording at initialization
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            print("✅ Audio session configured for recording at initialization")
        } catch {
            print("❌ Failed to configure audio session: \(error.localizedDescription)")
        }
        
        #if canImport(PushToTalk)
        do {
            // Request channel manager with both delegates
            channelManager = try await PTChannelManager.channelManager(
                delegate: self,
                restorationDelegate: self
            )
            pttLogger.info("✅ PTT Channel Manager initialized successfully")
            print("⚠️ NOTE: PTT provides UI only - audio recording is handled separately")
        } catch {
            pttLogger.error("❌ Failed to create PTT channel manager: \(error.localizedDescription)")
        }
        #else
        pttLogger.info("⚠️ PushToTalk not available (simulator or unsupported device)")
        #endif
    }

    /// Set the active book for recording
    func setActiveBook(_ book: Book) {
        currentBookId = book.id
        currentBookTitle = book.title
        
        #if canImport(PushToTalk)
        // Persist for channel restoration
        UserDefaults.standard.set(book.id, forKey: bookIdKey)
        UserDefaults.standard.set(book.title, forKey: bookTitleKey)
        #endif
        
        pttLogger.info("Set active book: \(book.title)")
    }

    /// Join a PTT channel for the given book (enables lock screen recording)
    func joinChannel(for book: Book) {
        #if canImport(PushToTalk)
        guard let channelManager = channelManager else {
            pttLogger.warning("⚠️ Channel manager not initialized")
            return
        }

        setActiveBook(book)
        
        let channelUUID = deterministicUUID(for: book.id)
        let image = bookCoverImage(for: book)
        let descriptor = PTChannelDescriptor(name: book.title, image: image)

        activeChannelUUID = channelUUID
        channelManager.requestJoinChannel(channelUUID: channelUUID, descriptor: descriptor)
        pttLogger.info("📡 Requesting to join PTT channel for: \(book.title)")
        #else
        // Simulator fallback - just set the book
        setActiveBook(book)
        pttLogger.info("🔄 Simulator: Join channel called for \(book.title)")
        #endif
    }

    /// Leave the current PTT channel (disables lock screen recording)
    func leaveChannel() {
        #if canImport(PushToTalk)
        guard let channelManager = channelManager, let channelUUID = activeChannelUUID else {
            isJoined = false
            return
        }

        channelManager.leaveChannel(channelUUID: channelUUID)
        pttLogger.info("👋 Leaving PTT channel")
        #else
        isJoined = false
        pttLogger.info("🔄 Simulator: Leave channel called")
        #endif
    }
    
    /// Force leave the current PTT channel (convenience method)
    func forceLeaveChannel() {
        leaveChannel()
        isJoined = false
        #if canImport(PushToTalk)
        activeChannelUUID = nil
        #endif
        pttLogger.info("🚫 Force left PTT channel")
    }

    // MARK: - Recording (happens locally, PTT just triggers it)

    private func startRecording() {
        pttLogger.info("🔴 startRecording() called")
        print("🔴 PTT: startRecording() called")
        
        guard let bookId = currentBookId else {
            pttLogger.error("❌ Cannot record: no active book set")
            print("❌ PTT: Cannot record - no active book set")
            return
        }
        
        print("📚 PTT: Recording for book ID: \(bookId)")

        let audioDir = DatabaseManager.audioDirectory
        if !FileManager.default.fileExists(atPath: audioDir.path) {
            try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        }

        let filename = "\(bookId)_\(UUID().uuidString).m4a"
        let url = audioDir.appendingPathComponent(filename)
        
        print("📁 PTT: Will record to: \(url.path)")

        // Check audio session status
        let audioSession = AVAudioSession.sharedInstance()
        print("🔍 PTT: Audio session category: \(audioSession.category.rawValue)")
        print("🔍 PTT: Audio session mode: \(audioSession.mode.rawValue)")
        
        // Activate audio session if needed
        do {
            if !audioSession.isOtherAudioPlaying {
                try audioSession.setActive(true)
                print("✅ PTT: Activated audio session")
            }
        } catch {
            print("⚠️ PTT: Could not activate audio session: \(error.localizedDescription)")
            // Continue anyway - the session might already be active
        }
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            guard let recorder = audioRecorder else {
                print("❌ PTT: audioRecorder is nil after creation")
                return
            }
            
            recorder.prepareToRecord()
            
            pttLogger.info("🎤 AVAudioRecorder created and prepared")
            print("🎤 PTT: AVAudioRecorder created and prepared")
            print("🔍 PTT: Recorder URL: \(recorder.url)")
            
            let didStart = recorder.record()
            print("🔍 PTT: recorder.record() returned: \(didStart)")
            
            if didStart {
                print("🔍 PTT: Checking recorder.isRecording: \(recorder.isRecording)")
                currentRecordingURL = url
                recordingStartTime = Date()
                pttLogger.info("✅ Recording started successfully: \(filename)")
                print("✅ PTT: Recording started successfully: \(filename)")
            } else {
                pttLogger.error("❌ Failed to start AVAudioRecorder.record()")
                print("❌ PTT: Failed to start AVAudioRecorder.record()")
                audioRecorder = nil
            }
        } catch {
            pttLogger.error("❌ Failed to create AVAudioRecorder: \(error.localizedDescription)")
            print("❌ PTT: Failed to create AVAudioRecorder: \(error.localizedDescription)")
            audioRecorder = nil
        }
    }

    private func stopRecording() {
        pttLogger.info("⏹️ stopRecording() called")
        
        guard let recorder = audioRecorder,
              let url = currentRecordingURL,
              let bookId = currentBookId,
              let startTime = recordingStartTime else {
            pttLogger.warning("⚠️ Stop recording called but no active recording found")
            return
        }

        recorder.stop()
        let duration = Date().timeIntervalSince(startTime)
        pttLogger.info("⏱️ Recording stopped, duration: \(duration)s")

        // Clean up recorder references
        audioRecorder = nil
        currentRecordingURL = nil
        recordingStartTime = nil
        
        // IMPORTANT: DO NOT deactivate the audio session!
        // PTT framework manages the audio session lifecycle.
        // It will call didDeactivate when appropriate.

        // Only save if > 0.5 seconds
        guard duration > 0.5 else {
            try? FileManager.default.removeItem(at: url)
            pttLogger.info("🗑️ Recording too short (\(duration)s), deleted")
            return
        }

        var annotation = Annotation(
            bookId: bookId,
            type: .audio,
            audioPath: url.lastPathComponent,
            duration: duration
        )

        do {
            try annotation.save()
            pttLogger.info("💾 Saved annotation: \(annotation.id)")
            
            onRecordingComplete?(annotation)
            NotificationCenter.default.post(name: .pttRecordingCompleted, object: annotation)

            // Transcribe in background
            Task.detached {
                await self.transcribeRecording(annotation: annotation, audioURL: url)
            }
        } catch {
            pttLogger.error("❌ Failed to save annotation: \(error.localizedDescription)")
            // Clean up the audio file if we couldn't save the annotation
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func transcribeRecording(annotation: Annotation, audioURL: URL) async {
        let transcriptionService = await TranscriptionService()
        
        guard let transcription = await transcriptionService.transcribe(audioURL: audioURL) else {
            pttLogger.warning("Transcription failed for \(annotation.id)")
            return
        }

        var mutableAnnotation = annotation
        do {
            try mutableAnnotation.updateTranscription(transcription)
            pttLogger.info("Transcription saved for \(annotation.id)")
            
            await MainActor.run {
                NotificationCenter.default.post(name: .pttTranscriptionCompleted, object: mutableAnnotation)
            }
        } catch {
            pttLogger.error("Failed to save transcription: \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    #if canImport(PushToTalk)
    private func deterministicUUID(for bookId: String) -> UUID {
        let data = bookId.data(using: .utf8)!
        var bytes = [UInt8](repeating: 0, count: 16)

        var hash: UInt64 = 5381
        for byte in data {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }

        for i in 0..<8 {
            bytes[i] = UInt8((hash >> (i * 8)) & 0xFF)
        }

        hash = hash &* 31 &+ 17
        for i in 8..<16 {
            bytes[i] = UInt8((hash >> ((i - 8) * 8)) & 0xFF)
        }

        bytes[6] = (bytes[6] & 0x0F) | 0x40  // Version 4
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // Variant 1

        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                          bytes[4], bytes[5], bytes[6], bytes[7],
                          bytes[8], bytes[9], bytes[10], bytes[11],
                          bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    private func bookCoverImage(for book: Book) -> UIImage {
        if let coverURL = book.coverImageURL,
           let image = UIImage(contentsOfFile: coverURL.path) {
            return resizeImage(image, to: CGSize(width: 60, height: 60))
        }
        
        let config = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
        return UIImage(systemName: "book.fill", withConfiguration: config) ?? UIImage()
    }

    nonisolated private func resizeImage(_ image: UIImage, to size: CGSize) -> UIImage {
        UIGraphicsBeginImageContextWithOptions(size, false, 0)
        defer { UIGraphicsEndImageContext() }

        let aspect = image.size.width / image.size.height
        var drawRect = CGRect(origin: .zero, size: size)

        if aspect > 1 {
            let height = size.width / aspect
            drawRect = CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
        } else {
            let width = size.height * aspect
            drawRect = CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
        }

        image.draw(in: drawRect)
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
    #endif
}

#if canImport(PushToTalk)
// MARK: - PTChannelManagerDelegate
extension PTTManager: PTChannelManagerDelegate {
    nonisolated func channelManager(_ channelManager: PTChannelManager, didActivate audioSession: AVAudioSession) {
        pttLogger.info("🎤 PTT audio session activated")
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, didDeactivate audioSession: AVAudioSession) {
        pttLogger.info("🔇 PTT audio session deactivated")
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, didJoinChannel channelUUID: UUID, reason: PTChannelJoinReason) {
        pttLogger.info("✅ Joined PTT channel, reason: \(String(describing: reason))")
        Task { @MainActor in
            self.activeChannelUUID = channelUUID
            self.isJoined = true
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, didLeaveChannel channelUUID: UUID, reason: PTChannelLeaveReason) {
        pttLogger.info("👋 Left PTT channel, reason: \(String(describing: reason))")
        Task { @MainActor in
            self.activeChannelUUID = nil
            self.isJoined = false
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, channelUUID: UUID, didBeginTransmittingFrom source: PTChannelTransmitRequestSource) {
        pttLogger.info("🎙️ BEGIN transmitting from source: \(String(describing: source))")
        print("🎙️ PTT: BEGIN transmitting from source: \(String(describing: source))")
        Task { @MainActor in
            print("🎙️ PTT: Calling startRecording on MainActor")
            self.isTransmitting = true
            self.startRecording()
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, channelUUID: UUID, didEndTransmittingFrom source: PTChannelTransmitRequestSource) {
        pttLogger.info("⏹️ END transmitting from source: \(String(describing: source))")
        print("⏹️ PTT: END transmitting from source: \(String(describing: source))")
        Task { @MainActor in
            print("⏹️ PTT: Calling stopRecording on MainActor")
            self.isTransmitting = false
            self.stopRecording()
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, receivedEphemeralPushToken pushToken: Data) {
        pttLogger.debug("📲 Received PTT push token: \(pushToken.count) bytes")
    }

    nonisolated func incomingPushResult(channelManager: PTChannelManager, channelUUID: UUID, pushPayload: [String : Any]) -> PTPushResult {
        pttLogger.info("📨 Incoming push for channel: \(channelUUID)")
        return .leaveChannel
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, failedToJoinChannel channelUUID: UUID, error: Error) {
        pttLogger.error("❌ Failed to join channel: \(error.localizedDescription)")
        Task { @MainActor in
            self.isJoined = false
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, failedToLeaveChannel channelUUID: UUID, error: Error) {
        pttLogger.error("❌ Failed to leave channel: \(error.localizedDescription)")
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, failedToBeginTransmittingInChannel channelUUID: UUID, error: Error) {
        pttLogger.error("❌ Failed to begin transmitting: \(error.localizedDescription)")
        Task { @MainActor in
            self.isTransmitting = false
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, failedToStopTransmittingInChannel channelUUID: UUID, error: Error) {
        pttLogger.error("❌ Failed to stop transmitting: \(error.localizedDescription)")
    }
}

// MARK: - PTChannelRestorationDelegate
extension PTTManager: PTChannelRestorationDelegate {
    nonisolated func channelDescriptor(restoredChannelUUID channelUUID: UUID) -> PTChannelDescriptor {
        pttLogger.info("🔄 Restoring PTT channel: \(channelUUID)")
        
        let restoredBookId = UserDefaults.standard.string(forKey: self.bookIdKey)
        let restoredBookTitle = UserDefaults.standard.string(forKey: self.bookTitleKey)
        
        // Restore state on main actor
        Task { @MainActor in
            if let bookId = restoredBookId {
                self.currentBookId = bookId
                self.currentBookTitle = restoredBookTitle
                self.activeChannelUUID = channelUUID
                pttLogger.info("✅ Restored book context: \(restoredBookTitle ?? "unknown")")
            }
        }
        
        // Create channel descriptor with default image
        // We can't call async database methods from a nonisolated synchronous context
        // so we use the default book icon. The cover image will be updated when the
        // channel state is fully restored on the main actor.
        let config = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
        let image = UIImage(systemName: "book.fill", withConfiguration: config) ?? UIImage()
        
        let title = restoredBookTitle ?? "BookTalk"
        pttLogger.info("📖 Creating channel descriptor for: \(title)")
        
        return PTChannelDescriptor(name: title, image: image)
    }
}
#endif
