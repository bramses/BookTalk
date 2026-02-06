//
//  BookTalkWidgetsControl.swift
//  BookTalkWidgets
//
//  Created by Bram Adams on 2/5/26.
//

#if swift(>=6.0)
import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct BookTalkWidgetsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.bram.booktalk.BookTalkWidgetsControl",
            provider: Provider()
        ) { value in
            ControlWidgetToggle(
                "Start Timer",
                isOn: value,
                action: StartTimerIntent()
            ) { isRunning in
                Label(isRunning ? "On" : "Off", systemImage: "timer")
            }
        }
        .displayName("Timer")
        .description("An example control that runs a timer.")
    }
}

@available(iOS 18.0, *)
extension BookTalkWidgetsControl {
    struct Provider: ControlValueProvider {
        var previewValue: Bool {
            false
        }

        func currentValue() async throws -> Bool {
            let isRunning = true
            return isRunning
        }
    }
}

@available(iOS 18.0, *)
struct StartTimerIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Start a timer"

    @Parameter(title: "Timer is running")
    var value: Bool

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
#endif
