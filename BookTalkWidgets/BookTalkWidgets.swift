//
//  BookTalkWidgets.swift
//  BookTalkWidgets
//
//  Created by Bram Adams on 2/5/26.
//

import SwiftUI
import WidgetKit

struct BookTalkEntry: TimelineEntry {
    let date: Date
    let title: String
    let subtitle: String
}

struct BookTalkProvider: TimelineProvider {
    func placeholder(in context: Context) -> BookTalkEntry {
        BookTalkEntry(
            date: Date(),
            title: "Record a note",
            subtitle: "Capture a thought while it’s fresh"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (BookTalkEntry) -> Void) {
        completion(
            BookTalkEntry(
                date: Date(),
                title: "Record a note",
                subtitle: "Capture a thought while it’s fresh"
            )
        )
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BookTalkEntry>) -> Void) {
        let entry = BookTalkEntry(
            date: Date(),
            title: "Record a note",
            subtitle: "Capture a thought while it’s fresh"
        )
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct BookTalkWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: BookTalkEntry

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
                .widgetURL(URL(string: "booktalk://record"))
        case .systemMedium:
            mediumView
                .widgetURL(URL(string: "booktalk://record"))
        case .systemLarge:
            largeView
                .widgetURL(URL(string: "booktalk://record"))
        case .accessoryCircular:
            accessoryCircularView
                .widgetURL(URL(string: "booktalk://record"))
        case .accessoryRectangular:
            accessoryRectangularView
                .widgetURL(URL(string: "booktalk://record"))
        case .accessoryInline:
            accessoryInlineView
                .widgetURL(URL(string: "booktalk://record"))
        default:
            smallView
                .widgetURL(URL(string: "booktalk://record"))
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Text(entry.title)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(entry.subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var mediumView: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                header
                Text(entry.title)
                    .font(.title3)
                    .foregroundStyle(.primary)
                Text(entry.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            VStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.title2)
                Text("Tap to\nrecord")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var largeView: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Text("Today’s listening")
                .font(.headline)
                .foregroundStyle(.primary)
            Text("Use BookTalk to capture moments, quotes, or reactions as you read.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Divider()
            HStack(spacing: 12) {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.title)
                        .font(.body)
                    Text(entry.subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var accessoryCircularView: some View {
        ZStack {
            Circle()
                .strokeBorder(.secondary, lineWidth: 2)
            Image(systemName: "mic.fill")
        }
    }

    private var accessoryRectangularView: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("BookTalk")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Record note")
                .font(.caption)
        }
    }

    private var accessoryInlineView: some View {
        Text("BookTalk · Record note")
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "book.closed.fill")
            Text("BookTalk")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

struct BookTalkWidget: Widget {
    let kind: String = "BookTalkWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BookTalkProvider()) { entry in
            if #available(iOS 17.0, *) {
                BookTalkWidgetView(entry: entry)
                    .containerBackground(.fill.tertiary, for: .widget)
            } else {
                BookTalkWidgetView(entry: entry)
                    .padding()
                    .background()
            }
        }
        .configurationDisplayName("BookTalk")
        .description("Record quick audio annotations for your books.")
        .supportedFamilies([
            .systemSmall,
            .systemMedium,
            .systemLarge,
            .accessoryCircular,
            .accessoryRectangular,
            .accessoryInline
        ])
    }
}

#Preview(as: .systemSmall) {
    BookTalkWidget()
} timeline: {
    BookTalkEntry(
        date: .now,
        title: "Record a note",
        subtitle: "Capture a thought while it’s fresh"
    )
}
