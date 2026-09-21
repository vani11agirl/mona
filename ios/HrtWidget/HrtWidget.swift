import SwiftUI
import WidgetKit

private let widgetKind = "HrtWidget"

struct HrtWidgetEntry: TimelineEntry {
    let date: Date
}

struct HrtWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HrtWidgetEntry {
        HrtWidgetEntry(date: Date())
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (HrtWidgetEntry) -> Void
    ) {
        completion(HrtWidgetEntry(date: Date()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<HrtWidgetEntry>) -> Void
    ) {
        completion(Timeline(entries: [HrtWidgetEntry(date: Date())], policy: .never))
    }
}

struct HrtWidgetEntryView: View {
    let entry: HrtWidgetEntry

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.90, green: 0.83, blue: 1.00))

                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 23, weight: .medium))
                    .foregroundColor(Color(red: 0.24, green: 0.08, blue: 0.43))
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text("On HRT for 8 months")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("16 intakes logged")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .monaWidgetBackground()
    }
}

private extension View {
    @ViewBuilder
    func monaWidgetBackground() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(Color(.systemBackground), for: .widget)
        } else {
            background(Color(.systemBackground))
        }
    }
}

struct HrtWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: widgetKind, provider: HrtWidgetProvider()) { entry in
            HrtWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Time on HRT")
        .description("See how long you’ve been on HRT and your total intakes.")
        .supportedFamilies([.systemMedium])
    }
}

@main
struct HrtWidgetBundle: WidgetBundle {
    var body: some Widget {
        HrtWidget()
    }
}
