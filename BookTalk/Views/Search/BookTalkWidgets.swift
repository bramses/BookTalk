import WidgetKit
import SwiftUI

struct BookTalkWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder var body: some Widget {
        #if swift(>=6.0)
        if #available(iOS 18.0, *) {
            RecordingControl()
        } else {
            PlaceholderWidget()
        }
        #else
        PlaceholderWidget()
        #endif
    }
}
struct PlaceholderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(
            kind: "dev.bramadams.BookTalk.Placeholder",
            provider: PlaceholderProvider()
        ) { _ in
            Text("BookTalk")
                .padding()
        }
        .configurationDisplayName("BookTalk")
        .description("Open BookTalk to record annotations.")
    }
}

struct PlaceholderEntry: TimelineEntry {
    let date: Date
}

struct PlaceholderProvider: TimelineProvider {
    func placeholder(in context: Context) -> PlaceholderEntry {
        PlaceholderEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (PlaceholderEntry) -> Void) {
        completion(PlaceholderEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PlaceholderEntry>) -> Void) {
        let entry = PlaceholderEntry(date: Date())
        completion(Timeline(entries: [entry], policy: .never))
    }
}

