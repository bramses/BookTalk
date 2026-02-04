import Foundation
import AVFoundation

@MainActor
class AudioRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var currentDuration: TimeInterval = 0

    private var audioRecorder: AVAudioRecorder?
    private var recordingStartTime: Date?
    private var timer: Timer?
    private var currentFilename: String?
    private var currentBookId: String?

    func startRecording(forBook bookId: String) -> String? {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
            return nil
        }

        let filename = "\(bookId)_\(UUID().uuidString).m4a"
        let url = DatabaseManager.audioDirectory.appendingPathComponent(filename)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.prepareToRecord()

            if audioRecorder?.record() == true {
                isRecording = true
                recordingStartTime = Date()
                currentFilename = filename
                currentBookId = bookId
                currentDuration = 0
                startTimer()
                return filename
            }
        } catch {
            print("Failed to start recording: \(error)")
        }
        return nil
    }

    func stopRecording() -> (filename: String, duration: TimeInterval)? {
        guard isRecording, let recorder = audioRecorder else { return nil }

        recorder.stop()
        stopTimer()
        isRecording = false

        let duration = Date().timeIntervalSince(recordingStartTime ?? Date())
        let filename = currentFilename

        currentFilename = nil
        currentBookId = nil
        recordingStartTime = nil
        audioRecorder = nil

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

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("Recording finished unsuccessfully")
        }
    }
}
