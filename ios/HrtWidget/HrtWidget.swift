import SwiftUI
import WidgetKit

private let widgetKind = "HrtWidget"

private enum HrtWidgetColors {
    // Matches the Android widget's default Material color scheme while the
    // surrounding layout and typography remain native to WidgetKit.
    static let accent = Color(red: 103.0 / 255.0, green: 80.0 / 255.0, blue: 164.0 / 255.0)
    static let accentSoft = Color(red: 255.0 / 255.0, green: 216.0 / 255.0, blue: 228.0 / 255.0)
    static let accentOnSoft = Color(red: 49.0 / 255.0, green: 17.0 / 255.0, blue: 29.0 / 255.0)
}

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
    @Environment(\.widgetFamily) private var family

    let entry: HrtWidgetEntry

    var body: some View {
        Group {
            switch family {
            case .systemSmall:
                smallWidget
            case .systemLarge:
                largeWidget
            case .systemMedium:
                mediumWidget
            default:
                if #available(iOSApplicationExtension 16.0, *) {
                    accessoryWidget
                } else {
                    mediumWidget
                }
            }
        }
        .monaWidgetBackground(for: family)
    }

    private var smallWidget: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                symbolBadge(size: 30, symbolSize: 14)

                Spacer(minLength: 4)

                Text("HRT")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 4)

            Text("8")
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .foregroundColor(HrtWidgetColors.accent)
                .minimumScaleFactor(0.8)

            Text("months")
                .font(.headline)

            Text("16 intakes logged")
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 3)
        }
        .padding(12)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("On HRT for 8 months. 16 intakes logged.")
    }

    private var mediumWidget: some View {
        HStack(spacing: 12) {
            symbolBadge(size: 48, symbolSize: 24)

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
        .accessibilityElement(children: .combine)
        .accessibilityLabel("On HRT for 8 months. 16 intakes logged.")
    }

    private var largeWidget: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                symbolBadge(size: 40, symbolSize: 19)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Your HRT journey")
                        .font(.headline)
                    Text("Sample overview")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            VStack(alignment: .leading, spacing: 0) {
                Text("8 months")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundColor(HrtWidgetColors.accent)
                Text("on HRT")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("First year")
                    Spacer()
                    Text("67%")
                        .foregroundColor(.secondary)
                }
                .font(.caption.weight(.semibold))

                ProgressView(value: 8, total: 12)
                    .tint(HrtWidgetColors.accent)

                Text("4 months until your one-year milestone")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Divider()

            HStack(spacing: 12) {
                metricCard(value: "16", label: "Intakes", symbol: "checkmark.circle.fill")
                metricCard(value: "Jan 21", label: "Started", symbol: "calendar")
            }
        }
        .padding(18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Your HRT journey. 8 months on HRT. 16 intakes. Started January 21."
        )
    }

    @ViewBuilder
    private func symbolBadge(size: CGFloat, symbolSize: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(HrtWidgetColors.accentSoft)

            Image(systemName: "calendar")
                .font(.system(size: symbolSize, weight: .medium))
                .foregroundColor(HrtWidgetColors.accentOnSoft)
        }
        .frame(width: size, height: size)
    }

    private func metricCard(value: String, label: String, symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(HrtWidgetColors.accent)

            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.headline)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(HrtWidgetColors.accentSoft.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @available(iOSApplicationExtension 16.0, *)
    @ViewBuilder
    private var accessoryWidget: some View {
        if family == .accessoryCircular {
            Gauge(value: 8, in: 0 ... 12) {
                Image(systemName: "cross.case.fill")
            } currentValueLabel: {
                Text("8m")
                    .font(.system(.body, design: .rounded).weight(.bold))
            }
            .gaugeStyle(.accessoryCircular)
            .widgetAccentable()
            .accessibilityLabel("8 months on HRT")
        } else if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 2) {
                Label("On HRT", systemImage: "calendar")
                    .font(.headline)
                    .widgetAccentable()
                Text("8 months • 16 intakes")
                    .font(.caption)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("On HRT for 8 months. 16 intakes logged.")
        } else {
            Label("8 months on HRT • 16 intakes", systemImage: "cross.case.fill")
                .accessibilityLabel("8 months on HRT. 16 intakes logged.")
        }
    }
}

private extension View {
    @ViewBuilder
    func monaWidgetBackground(for family: WidgetFamily) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            if family == .systemSmall || family == .systemMedium || family == .systemLarge {
                containerBackground(Color(.systemBackground), for: .widget)
            } else {
                containerBackground(Color.clear, for: .widget)
            }
        } else {
            background(Color(.systemBackground))
        }
    }
}

struct HrtWidget: Widget {
    private var supportedFamilies: [WidgetFamily] {
        if #available(iOSApplicationExtension 16.0, *) {
            return [
                .systemSmall,
                .systemMedium,
                .systemLarge,
                .accessoryInline,
                .accessoryCircular,
                .accessoryRectangular,
            ]
        } else {
            return [.systemSmall, .systemMedium, .systemLarge]
        }
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: widgetKind, provider: HrtWidgetProvider()) { entry in
            HrtWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Time on HRT")
        .description("See your HRT duration, logged intakes, and milestones.")
        .supportedFamilies(supportedFamilies)
    }
}

@main
struct HrtWidgetBundle: WidgetBundle {
    var body: some Widget {
        HrtWidget()
    }
}
