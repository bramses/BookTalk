import AppIntents
import SwiftUI
import WidgetKit

/// App Intent for toggling audio recording from Control Center
struct ToggleRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Recording"
    static var description = IntentDescription("Start or stop recording an audio annotation")
    
    static var openAppWhenRun: Bool = false // Runs in background
    
    func perform() async throws -> some IntentResult {
        await MainActor.run {
            RecordingManager.shared.toggleRecording()
        }
        
        return .result()
    }
}

#if swift(>=6.0)
/// Control widget configuration
@available(iOS 18.0, *)
struct RecordingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "dev.bramadams.BookTalk.RecordingControl",
            provider: RecordingStateProvider()
        ) { isRecording in
            ControlWidgetToggle(
                "Record Annotation",
                isOn: isRecording,
                action: ToggleRecordingIntent()
            ) { isOn in
                Label {
                    if let bookTitle = RecordingManager.shared.currentBookTitle {
                        Text(bookTitle)
                    } else {
                        Text("Record")
                    }
                } icon: {
                    Image(systemName: isOn ? "stop.circle.fill" : "mic.circle.fill")
                }
            }
        }
        .displayName("Record Annotation")
        .description("Record audio annotations for your current book")
    }
}

struct RecordingStateProvider: ControlValueProvider {
    var previewValue: Bool {
        false
    }

    func currentValue() async throws -> Bool {
        await MainActor.run {
            RecordingManager.shared.isRecording
        }
    }
}
#endif
