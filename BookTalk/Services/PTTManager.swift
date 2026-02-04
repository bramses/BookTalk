import Foundation
#if !targetEnvironment(simulator)
import PushToTalk
#endif
import AVFoundation
import UIKit
import os.log

extension Notification.Name {
    static let pttRecordingCompleted = Notification.Name("pttRecordingCompleted")
}

private let pttLogger = Logger(subsystem: "dev.bramadams.BookTalk", category: "PTT")

@MainActor
class PTTManager: NSObject, ObservableObject {
    static let shared = PTTManager()

    @Published var isJoined = false
    @Published var isTransmitting = false
    @Published var isAudioSessionActive = false
    @Published var channelStatus: String = "Not joined"
    @Published var currentBookId: String?
    @Published var currentBookTitle: String?

    #if !targetEnvironment(simulator)
    private var channelManager: PTChannelManager?
    private var activeChannelUUID: UUID?
    private var pendingBook: Book?
    #endif

    // Audio recording for PTT
    private var audioRecorder: AVAudioRecorder?
    private var currentRecordingURL: URL?
    private var recordingStartTime: Date?

    // UserDefaults keys for persistence
    private let bookIdKey = "PTTCurrentBookId"
    private let bookTitleKey = "PTTCurrentBookTitle"

    var onAudioSessionActivated: (() -> Void)?
    var onAudioSessionDeactivated: (() -> Void)?
    var onRecordingComplete: ((Annotation) -> Void)?

    override init() {
        super.init()
        #if targetEnvironment(simulator)
        channelStatus = "PTT unavailable on Simulator"
        #else
        // Restore book info from UserDefaults
        currentBookId = UserDefaults.standard.string(forKey: bookIdKey)
        currentBookTitle = UserDefaults.standard.string(forKey: bookTitleKey)
        if currentBookId != nil {
            print("PTT: Restored book context - \(currentBookTitle ?? "unknown")")
        }
        #endif
    }

    func initialize() async {
        #if targetEnvironment(simulator)
        channelStatus = "PTT unavailable on Simulator"
        #else
        do {
            channelManager = try await PTChannelManager.channelManager(delegate: self, restorationDelegate: self)
            channelStatus = "Ready"
        } catch {
            channelStatus = "PTT unavailable"
            print("Failed to create channel manager: \(error)")
        }
        #endif
    }

    func joinChannel(forBook book: Book) {
        #if targetEnvironment(simulator)
        channelStatus = "PTT unavailable on Simulator"
        #else
        guard let channelManager = channelManager else {
            channelStatus = "PTT not ready"
            return
        }

        // Leave current channel if any
        if isJoined, let currentUUID = activeChannelUUID {
            print("PTT: Leaving current channel before joining new one")
            pendingBook = book
            channelManager.leaveChannel(channelUUID: currentUUID)
            // The didLeaveChannel delegate will handle joining the pending book
        } else {
            Task {
                await joinChannelInternal(book: book)
            }
        }
        #endif
    }

    func forceLeaveChannel() {
        #if targetEnvironment(simulator)
        channelStatus = "PTT unavailable on Simulator"
        #else
        guard let channelManager = channelManager, let channelUUID = activeChannelUUID else {
            channelStatus = "Not in channel"
            return
        }

        pendingBook = nil // Don't rejoin anything
        channelManager.leaveChannel(channelUUID: channelUUID)
        channelStatus = "Leaving..."

        // Clear persisted book info
        UserDefaults.standard.removeObject(forKey: bookIdKey)
        UserDefaults.standard.removeObject(forKey: bookTitleKey)
        #endif
    }

    #if !targetEnvironment(simulator)
    private func joinChannelInternal(book: Book) async {
        guard let channelManager = channelManager else { return }

        // Generate consistent UUID for this book
        let channelUUID = uuidForBook(book.id)

        // Create channel image
        let channelImage = createChannelImage(for: book)

        let descriptor = PTChannelDescriptor(name: book.title, image: channelImage)

        activeChannelUUID = channelUUID
        currentBookId = book.id
        currentBookTitle = book.title

        // Persist book info for channel restoration
        UserDefaults.standard.set(book.id, forKey: bookIdKey)
        UserDefaults.standard.set(book.title, forKey: bookTitleKey)

        print("PTT: Requesting to join channel for '\(book.title)'")
        channelManager.requestJoinChannel(channelUUID: channelUUID, descriptor: descriptor)
        channelStatus = "Joining \(book.title)..."
    }
    #endif

    #if !targetEnvironment(simulator)
    private func createChannelImage(for book: Book) -> UIImage {
        // Try to use book cover, otherwise use default
        if let coverURL = book.coverImageURL,
           let coverImage = UIImage(contentsOfFile: coverURL.path) {
            // Create a properly sized square image for PTT
            return createSquareImage(from: coverImage, size: 60)
        } else {
            // Create a default book icon image
            let config = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
            return UIImage(systemName: "book.fill", withConfiguration: config) ?? UIImage()
        }
    }

    private func createSquareImage(from image: UIImage, size: CGFloat) -> UIImage {
        let targetSize = CGSize(width: size, height: size)

        UIGraphicsBeginImageContextWithOptions(targetSize, false, 0)
        defer { UIGraphicsEndImageContext() }

        // Fill with a background color
        UIColor.systemBlue.setFill()
        UIRectFill(CGRect(origin: .zero, size: targetSize))

        // Calculate aspect-fit rect
        let imageAspect = image.size.width / image.size.height
        var drawRect = CGRect(origin: .zero, size: targetSize)

        if imageAspect > 1 {
            // Wider than tall
            let height = size / imageAspect
            drawRect = CGRect(x: 0, y: (size - height) / 2, width: size, height: height)
        } else {
            // Taller than wide
            let width = size * imageAspect
            drawRect = CGRect(x: (size - width) / 2, y: 0, width: width, height: size)
        }

        image.draw(in: drawRect)

        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }
    #endif

    func leaveChannel() {
        #if targetEnvironment(simulator)
        // No-op on simulator
        #else
        guard let channelManager = channelManager, let channelUUID = activeChannelUUID else { return }

        channelManager.leaveChannel(channelUUID: channelUUID)
        channelStatus = "Leaving..."
        #endif
    }

    func startTransmitting() {
        #if targetEnvironment(simulator)
        // No-op on simulator
        #else
        guard let channelManager = channelManager, let channelUUID = activeChannelUUID, isJoined else {
            channelStatus = "Not in channel"
            return
        }

        channelManager.requestBeginTransmitting(channelUUID: channelUUID)
        #endif
    }

    func stopTransmitting() {
        #if targetEnvironment(simulator)
        // No-op on simulator
        #else
        guard let channelManager = channelManager, let channelUUID = activeChannelUUID else { return }

        channelManager.stopTransmitting(channelUUID: channelUUID)
        #endif
    }

    #if !targetEnvironment(simulator)
    // MARK: - Internal Recording

    private func startInternalRecording() {
        guard let bookId = currentBookId else {
            print("PTT: No book ID for recording")
            return
        }

        // Ensure audio directory exists
        let audioDir = DatabaseManager.audioDirectory
        if !FileManager.default.fileExists(atPath: audioDir.path) {
            try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        }

        let filename = "\(bookId)_\(UUID().uuidString).m4a"
        let url = audioDir.appendingPathComponent(filename)
        print("PTT: Recording URL: \(url.path)")

        // Configure audio session for recording if not already configured by PTT
        let session = AVAudioSession.sharedInstance()
        print("PTT: Current audio session - category: \(session.category.rawValue), mode: \(session.mode.rawValue)")

        // Try to configure audio session if needed
        if session.category != .playAndRecord {
            do {
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
                try session.setActive(true)
                print("PTT: Configured audio session for recording")
            } catch {
                print("PTT: Could not configure audio session: \(error)")
            }
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

            let prepared = audioRecorder?.prepareToRecord() ?? false
            print("PTT: prepareToRecord() returned: \(prepared)")

            if audioRecorder?.record() == true {
                currentRecordingURL = url
                recordingStartTime = Date()
                print("PTT: Started recording to \(filename)")
            } else {
                print("PTT: Failed to start recording - record() returned false")
                print("PTT: Audio session category: \(session.category.rawValue)")
                print("PTT: Audio session mode: \(session.mode.rawValue)")
                print("PTT: Record permission: \(session.recordPermission.rawValue)")
                print("PTT: Is other audio playing: \(session.isOtherAudioPlaying)")
            }
        } catch {
            print("PTT: Failed to create recorder: \(error)")
        }
    }

    private func stopInternalRecording() {
        guard let recorder = audioRecorder,
              let url = currentRecordingURL,
              let bookId = currentBookId,
              let startTime = recordingStartTime else {
            print("PTT: No recording to stop")
            return
        }

        recorder.stop()
        let duration = Date().timeIntervalSince(startTime)
        print("PTT: Stopped recording, duration: \(duration)")

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
                print("PTT: Saved annotation \(annotation.id)")
                onRecordingComplete?(annotation)

                // Post notification for UI updates
                NotificationCenter.default.post(name: .pttRecordingCompleted, object: annotation)

                // Start transcription in background
                let annotationCopy = annotation
                let audioURL = url
                Task.detached {
                    await self.transcribeRecording(annotation: annotationCopy, audioURL: audioURL)
                }
            } catch {
                print("PTT: Failed to save annotation: \(error)")
            }
        } else {
            print("PTT: Recording too short, deleting")
            try? FileManager.default.removeItem(at: url)
        }

        audioRecorder = nil
        currentRecordingURL = nil
        recordingStartTime = nil
    }

    private func transcribeRecording(annotation: Annotation, audioURL: URL) async {
        let transcriptionService = await TranscriptionService()

        if let transcription = await transcriptionService.transcribe(audioURL: audioURL) {
            var mutableAnnotation = annotation
            do {
                try mutableAnnotation.updateTranscription(transcription)
                print("PTT: Transcription saved for \(annotation.id)")
            } catch {
                print("PTT: Failed to save transcription: \(error)")
            }
        }
    }
    #endif

    #if !targetEnvironment(simulator)
    // MARK: - Helpers

    private func uuidForBook(_ bookId: String) -> UUID {
        // Create a deterministic UUID from the book ID using a hash
        let data = bookId.data(using: .utf8)!
        var bytes = [UInt8](repeating: 0, count: 16)

        // Simple hash distribution
        var hash: UInt64 = 5381
        for byte in data {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }

        // Fill bytes from hash
        for i in 0..<8 {
            bytes[i] = UInt8((hash >> (i * 8)) & 0xFF)
        }

        // Use another hash for remaining bytes
        hash = hash &* 31 &+ 17
        for i in 8..<16 {
            bytes[i] = UInt8((hash >> ((i - 8) * 8)) & 0xFF)
        }

        // Set version and variant bits for UUID
        bytes[6] = (bytes[6] & 0x0F) | 0x40  // Version 4
        bytes[8] = (bytes[8] & 0x3F) | 0x80  // Variant 1

        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3],
                          bytes[4], bytes[5], bytes[6], bytes[7],
                          bytes[8], bytes[9], bytes[10], bytes[11],
                          bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    #endif
}

#if !targetEnvironment(simulator)
// MARK: - PTChannelManagerDelegate
extension PTTManager: PTChannelManagerDelegate {
    nonisolated func channelManager(_ channelManager: PTChannelManager, didActivate audioSession: AVAudioSession) {
        print("PTT: Audio session ACTIVATED - category: \(audioSession.category.rawValue)")
        Task { @MainActor in
            isAudioSessionActive = true
            onAudioSessionActivated?()
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, didDeactivate audioSession: AVAudioSession) {
        print("PTT: Audio session DEACTIVATED")
        Task { @MainActor in
            isAudioSessionActive = false
            onAudioSessionDeactivated?()
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, didJoinChannel channelUUID: UUID, reason: PTChannelJoinReason) {
        print("PTT: Joined channel \(channelUUID), reason: \(reason)")
        Task { @MainActor in
            activeChannelUUID = channelUUID
            isJoined = true
            if let title = currentBookTitle {
                channelStatus = "Connected: \(title)"
            } else {
                channelStatus = "Connected"
            }
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, didLeaveChannel channelUUID: UUID, reason: PTChannelLeaveReason) {
        print("PTT: Left channel \(channelUUID), reason: \(reason)")
        Task { @MainActor in
            activeChannelUUID = nil
            isJoined = false
            isTransmitting = false
            isAudioSessionActive = false
            channelStatus = "Disconnected"

            // If there's a pending book to join, do it now
            if let book = pendingBook {
                pendingBook = nil
                print("PTT: Joining pending book channel after leave")
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                await joinChannelInternal(book: book)
            } else {
                // Clear book info only if not switching channels
                currentBookId = nil
                currentBookTitle = nil
            }
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, channelUUID: UUID, didBeginTransmittingFrom source: PTChannelTransmitRequestSource) {
        print("PTT: Begin transmitting from source: \(source)")
        Task { @MainActor in
            isTransmitting = true
            channelStatus = "Recording..."

            // Wait for audio session to be activated (up to 1 second)
            var waitAttempts = 0
            while !isAudioSessionActive && waitAttempts < 10 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                waitAttempts += 1
                print("PTT: Waiting for audio session... attempt \(waitAttempts)")
            }

            print("PTT: Audio session active: \(isAudioSessionActive), starting recording")
            startInternalRecording()
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, channelUUID: UUID, didEndTransmittingFrom source: PTChannelTransmitRequestSource) {
        print("PTT: End transmitting from source: \(source)")
        Task { @MainActor in
            isTransmitting = false
            if let title = currentBookTitle {
                channelStatus = "Connected: \(title)"
            } else {
                channelStatus = "Connected"
            }
            stopInternalRecording()
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, receivedEphemeralPushToken pushToken: Data) {
        print("PTT: Received push token")
    }

    nonisolated func incomingPushResult(channelManager: PTChannelManager, channelUUID: UUID, pushPayload: [String : Any]) -> PTPushResult {
        return .leaveChannel
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, failedToJoinChannel channelUUID: UUID, error: Error) {
        print("PTT: Failed to join channel: \(error)")
        Task { @MainActor in
            channelStatus = "Join failed"
            isJoined = false
            activeChannelUUID = nil
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, failedToLeaveChannel channelUUID: UUID, error: Error) {
        print("PTT: Failed to leave channel: \(error)")
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, failedToBeginTransmittingInChannel channelUUID: UUID, error: Error) {
        print("PTT: Failed to begin transmitting: \(error)")
        Task { @MainActor in
            channelStatus = "Record failed"
            isTransmitting = false
        }
    }

    nonisolated func channelManager(_ channelManager: PTChannelManager, failedToStopTransmittingInChannel channelUUID: UUID, error: Error) {
        print("PTT: Failed to stop transmitting: \(error)")
    }
}

// MARK: - PTChannelRestorationDelegate
extension PTTManager: PTChannelRestorationDelegate {
    nonisolated func channelDescriptor(restoredChannelUUID channelUUID: UUID) -> PTChannelDescriptor {
        print("PTT: Restoring channel \(channelUUID)")
        let config = UIImage.SymbolConfiguration(pointSize: 30, weight: .medium)
        let channelImage = UIImage(systemName: "book.fill", withConfiguration: config) ?? UIImage()
        return PTChannelDescriptor(name: "BookTalk", image: channelImage)
    }
}
#endif
