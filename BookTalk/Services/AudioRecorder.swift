import Foundation
import AVFoundation

@MainActor
class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var currentDuration: TimeInterval = 0

    private var audioEngine: AVAudioEngine?
    private var tapNode: AVAudioNode?
    private var audioFile: AVAudioFile?
    private var recordingURL: URL?
    private var recordingStartTime: Date?
    private var timer: Timer?
    private var currentFilename: String?
    private var currentBookId: String?

    func startRecording(forBook bookId: String) -> String? {
        startRecordingInternal(bookId: bookId)
    }

    func startRecording() -> String? {
        startRecordingInternal(bookId: nil)
    }

    private func startRecordingInternal(bookId: String?) -> String? {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
            return nil
        }

        let audioDir = DatabaseManager.audioDirectory
        if !FileManager.default.fileExists(atPath: audioDir.path) {
            try? FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)
        }

        let filename = makeFilename(bookId: bookId)
        let url = audioDir.appendingPathComponent(filename)

        let engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)

        let eq = AVAudioUnitEQ(numberOfBands: 2)
        if eq.bands.count >= 2 {
            let highPass = eq.bands[0]
            highPass.filterType = .highPass
            highPass.frequency = 80
            highPass.bandwidth = 0.5
            highPass.gain = 0
            highPass.bypass = false

            let presence = eq.bands[1]
            presence.filterType = .highShelf
            presence.frequency = 4000
            presence.bandwidth = 0.7
            presence.gain = 3
            presence.bypass = false
        }

        engine.attach(eq)
        engine.connect(input, to: eq, format: inputFormat)
        engine.connect(eq, to: engine.mainMixerNode, format: inputFormat)
        engine.mainMixerNode.outputVolume = 0

        do {
            let file = try AVAudioFile(forWriting: url, settings: inputFormat.settings)
            let recordingFile = file
            eq.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { buffer, _ in
                do {
                    try recordingFile.write(from: buffer)
                } catch {
                    print("Failed to write audio buffer: \(error)")
                }
            }

            engine.prepare()
            try engine.start()

            audioEngine = engine
            tapNode = eq
            audioFile = file
            recordingURL = url
            isRecording = true
            recordingStartTime = Date()
            currentFilename = filename
            currentBookId = bookId
            currentDuration = 0
            startTimer()
            return filename
        } catch {
            print("Failed to start recording: \(error)")
        }
        return nil
    }

    private func makeFilename(bookId: String?) -> String {
        if let bookId {
            return "\(bookId)_\(UUID().uuidString).m4a"
        }
        return "quick_\(UUID().uuidString).m4a"
    }

    func stopRecording() -> (filename: String, duration: TimeInterval)? {
        guard isRecording, audioEngine != nil else { return nil }

        tapNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        stopTimer()
        isRecording = false

        let duration = Date().timeIntervalSince(recordingStartTime ?? Date())
        let filename = currentFilename

        currentFilename = nil
        currentBookId = nil
        recordingStartTime = nil
        audioEngine = nil
        tapNode = nil
        audioFile = nil
        recordingURL = nil

        try? AVAudioSession.sharedInstance().setActive(false)

        if let filename = filename {
            return (filename, duration)
        }
        return nil
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.currentDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
