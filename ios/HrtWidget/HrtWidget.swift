import SwiftUI
import WidgetKit

private let widgetKind = "HrtWidget"

#if WIDGET_PREVIEW
private let previewAppGroup = Bundle.main.object(
    forInfoDictionaryKey: "PreviewAppGroup"
) as? String
#endif

private enum HrtWidgetColors {
    // Keeps Mona's Android widget palette, expressed through native iOS shapes
    // and semantic foreground colors.
    static let accent = Color(red: 103.0 / 255.0, green: 80.0 / 255.0, blue: 164.0 / 255.0)
}

fileprivate enum HrtDurationUnit: String {
    case days
    case weeks
    case months
    case years

    func label(for value: Int) -> String {
        guard value == 1 else { return rawValue }
        return String(rawValue.dropLast())
    }

    var compactLabel: String {
        switch self {
        case .days: return "d"
        case .weeks: return "w"
        case .months: return "mo"
        case .years: return "y"
        }
    }
}

struct HrtWidgetEntry: TimelineEntry {
    let date: Date
    let durationValue: Int
    fileprivate let durationUnit: HrtDurationUnit
    let intakeCount: Int
    let showsIntakes: Bool
    let recentIntakeCounts: [Int]

    fileprivate var durationText: String {
        "\(durationValue) \(durationUnit.label(for: durationValue))"
    }

    fileprivate var intakeText: String {
        "\(intakeCount) \(intakeCount == 1 ? "intake" : "intakes") logged"
    }

    fileprivate static let sample = HrtWidgetEntry(
        date: Date(),
        durationValue: 8,
        durationUnit: .months,
        intakeCount: 16,
        showsIntakes: true,
        recentIntakeCounts: [0, 1, 0, 2, 1, 0, 3]
    )
}

struct HrtWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HrtWidgetEntry {
        .sample
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (HrtWidgetEntry) -> Void
    ) {
        completion(currentEntry)
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<HrtWidgetEntry>) -> Void
    ) {
        completion(Timeline(entries: [currentEntry], policy: .never))
    }

    private var currentEntry: HrtWidgetEntry {
        #if WIDGET_PREVIEW
        guard let previewAppGroup,
              let defaults = UserDefaults(suiteName: previewAppGroup)
        else {
            return .sample
        }

        let storedValue = defaults.integer(forKey: "preview_duration_value")
        let storedUnit = defaults.string(forKey: "preview_duration_unit")
        let storedIntakes = defaults.integer(forKey: "preview_intake_count")
        let storedRecentCounts = defaults.string(
            forKey: "preview_recent_intake_counts"
        )
        let recentCounts = storedRecentCounts?
            .split(separator: ",")
            .map { max(0, Int($0) ?? 0) }
        let normalizedRecentCounts = recentCounts?.count == 7
            ? recentCounts ?? []
            : HrtWidgetEntry.sample.recentIntakeCounts

        return HrtWidgetEntry(
            date: Date(),
            durationValue: storedValue > 0 ? storedValue : HrtWidgetEntry.sample.durationValue,
            durationUnit: HrtDurationUnit(rawValue: storedUnit ?? "") ?? .months,
            intakeCount: defaults.object(forKey: "preview_intake_count") == nil
                ? HrtWidgetEntry.sample.intakeCount
                : max(0, storedIntakes),
            showsIntakes: defaults.object(forKey: "preview_show_intakes") == nil
                ? true
                : defaults.bool(forKey: "preview_show_intakes"),
            recentIntakeCounts: normalizedRecentCounts
        )
        #else
        return .sample
        #endif
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
            Label("Time on HRT", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundColor(HrtWidgetColors.accent)

            Spacer(minLength: 8)

            Text(entry.durationText)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.52)

            if entry.showsIntakes {
                Text(entry.intakeText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 4)
            }
        }
        .monaContentMargins()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var mediumWidget: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("HRT summary", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundColor(HrtWidgetColors.accent)

            Spacer(minLength: 12)

            HStack(alignment: .bottom, spacing: 28) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.durationText)
                        .font(.title2.weight(.bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text("Time on HRT")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if entry.showsIntakes {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.intakeCount)")
                            .font(.title2.weight(.bold))
                            .foregroundColor(.primary)

                        Text(entry.intakeCount == 1 ? "Intake logged" : "Intakes logged")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .monaContentMargins()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var largeWidget: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("HRT summary", systemImage: "calendar")
                .font(.caption.weight(.semibold))
                .foregroundColor(HrtWidgetColors.accent)

            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.durationText)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("Time on HRT")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if entry.showsIntakes {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.intakeCount)")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Text(entry.intakeCount == 1 ? "Intake logged" : "Intakes logged")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 14)

            Divider()
                .padding(.vertical, 13)

            HStack(alignment: .firstTextBaseline) {
                Text("Recent intakes")
                    .font(.headline)
                Spacer(minLength: 8)
                Text("Last 7 days")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            recentActivityGraph
                .padding(.top, 8)
        }
        .monaContentMargins()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var recentActivityGraph: some View {
        GeometryReader { geometry in
            let maximum = max(entry.recentIntakeCounts.max() ?? 0, 1)

            HStack(alignment: .bottom, spacing: 7) {
                ForEach(entry.recentIntakeCounts.indices, id: \.self) { index in
                    let count = entry.recentIntakeCounts[index]

                    VStack(spacing: 4) {
                        Spacer(minLength: 0)

                        if count > 0 {
                            Text("\(count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Rectangle()
                            .fill(
                                count == 0
                                    ? HrtWidgetColors.accent.opacity(0.16)
                                    : HrtWidgetColors.accent
                            )
                            .frame(
                                height: count == 0
                                    ? 2
                                    : max(
                                        8,
                                        (geometry.size.height - 30)
                                            * CGFloat(count)
                                            / CGFloat(maximum)
                                    )
                            )

                        Text(dayLabel(for: index))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(recentActivityAccessibilityLabel)
    }

    private func dayLabel(for index: Int) -> String {
        let daysAgo = 6 - index
        guard let date = Calendar.current.date(
            byAdding: .day,
            value: -daysAgo,
            to: entry.date
        ) else {
            return ""
        }

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEEE")
        return formatter.string(from: date)
    }

    private var recentActivityAccessibilityLabel: String {
        let values = entry.recentIntakeCounts.indices.map { index in
            let count = entry.recentIntakeCounts[index]
            return "\(dayLabel(for: index)), \(count) \(count == 1 ? "intake" : "intakes")"
        }
        return "Recent intake activity. \(values.joined(separator: ", "))."
    }

    private var accessibilitySummary: String {
        var summary = "On HRT for \(entry.durationText)."
        if entry.showsIntakes {
            summary += " \(entry.intakeText)."
        }
        return summary
    }

    @available(iOSApplicationExtension 16.0, *)
    @ViewBuilder
    private var accessoryWidget: some View {
        if family == .accessoryCircular {
            VStack(spacing: 0) {
                Image(systemName: "calendar")
                    .font(.caption2)
                Text("\(entry.durationValue)\(entry.durationUnit.compactLabel)")
                    .font(.system(.body, design: .rounded).weight(.bold))
                    .minimumScaleFactor(0.65)
            }
            .widgetAccentable()
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(entry.durationText) on HRT")
        } else if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 2) {
                Label("On HRT", systemImage: "calendar")
                    .font(.headline)
                    .widgetAccentable()
                Text(entry.showsIntakes
                    ? "\(entry.durationText) • \(entry.intakeCount) intakes"
                    : entry.durationText)
                    .font(.caption)
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilitySummary)
        } else {
            Label(
                entry.showsIntakes
                    ? "\(entry.durationText) on HRT • \(entry.intakeCount) intakes"
                    : "\(entry.durationText) on HRT",
                systemImage: "cross.case.fill"
            )
            .accessibilityLabel(accessibilitySummary)
        }
    }
}

private extension View {
    @ViewBuilder
    func monaContentMargins() -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self
        } else {
            padding(16)
        }
    }

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
        return [
            .systemSmall,
            // Re-enable other sizes as their designs are reviewed.
            // .systemMedium,
            // .systemLarge,
            // .accessoryInline,
            // .accessoryCircular,
            // .accessoryRectangular,
        ]
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: widgetKind, provider: HrtWidgetProvider()) { entry in
            HrtWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Time on HRT")
        .description("See your HRT duration and logged intakes at a glance.")
        .supportedFamilies(supportedFamilies)
    }
}

@main
struct HrtWidgetBundle: WidgetBundle {
    var body: some Widget {
        HrtWidget()
    }
}
