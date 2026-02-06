//
//  BookTalkWidgetsLiveActivity.swift
//  BookTalkWidgets
//
//  Created by Bram Adams on 2/5/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct BookTalkWidgetsAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct BookTalkWidgetsLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BookTalkWidgetsAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension BookTalkWidgetsAttributes {
    fileprivate static var preview: BookTalkWidgetsAttributes {
        BookTalkWidgetsAttributes(name: "World")
    }
}

extension BookTalkWidgetsAttributes.ContentState {
    fileprivate static var smiley: BookTalkWidgetsAttributes.ContentState {
        BookTalkWidgetsAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: BookTalkWidgetsAttributes.ContentState {
         BookTalkWidgetsAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: BookTalkWidgetsAttributes.preview) {
   BookTalkWidgetsLiveActivity()
} contentStates: {
    BookTalkWidgetsAttributes.ContentState.smiley
    BookTalkWidgetsAttributes.ContentState.starEyes
}
