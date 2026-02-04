import Foundation
import Speech
import AVFoundation

@MainActor
class TranscriptionService: ObservableObject {
    @Published var isTranscribing = false
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))

    init() {
        checkAuthorization()
    }

    func checkAuthorization() {
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }

    func requestAuthorization() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    self.authorizationStatus = status
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }

    func transcribe(audioURL: URL) async -> String? {
        if authorizationStatus != .authorized {
            let authorized = await requestAuthorization()
            if !authorized { return nil }
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("Transcription: Speech recognizer not available")
            return nil
        }

        isTranscribing = true
        defer { Task { @MainActor in self.isTranscribing = false } }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true  // Get partial results to accumulate

        // Prefer on-device but don't require it (server can handle longer audio)
        if #available(iOS 13, *) {
            request.requiresOnDeviceRecognition = false
        }

        // Add task options for better accuracy
        if #available(iOS 16, *) {
            request.addsPunctuation = true
        }

        return await withCheckedContinuation { continuation in
            var finalTranscription: String?
            var hasResumed = false

            let task = recognizer.recognitionTask(with: request) { result, error in
                if let result = result {
                    // Always keep the latest transcription (it's cumulative)
                    finalTranscription = result.bestTranscription.formattedString

                    if result.isFinal {
                        if !hasResumed {
                            hasResumed = true
                            continuation.resume(returning: finalTranscription)
                        }
                    }
                }

                if let error = error {
                    print("Transcription error: \(error.localizedDescription)")
                    // Return whatever we have so far, even if there was an error
                    if !hasResumed {
                        hasResumed = true
                        continuation.resume(returning: finalTranscription)
                    }
                }
            }

            // Safety timeout - if nothing happens in 60 seconds, return what we have
            Task {
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                if !hasResumed {
                    hasResumed = true
                    task.cancel()
                    continuation.resume(returning: finalTranscription)
                }
            }
        }
    }
}
