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
    static let accentSoft = Color(red: 255.0 / 255.0, green: 216.0 / 255.0, blue: 228.0 / 255.0)
    static let accentOnSoft = Color(red: 49.0 / 255.0, green: 17.0 / 255.0, blue: 29.0 / 255.0)
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
        showsIntakes: true
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

        return HrtWidgetEntry(
            date: Date(),
            durationValue: storedValue > 0 ? storedValue : HrtWidgetEntry.sample.durationValue,
            durationUnit: HrtDurationUnit(rawValue: storedUnit ?? "") ?? .months,
            intakeCount: defaults.object(forKey: "preview_intake_count") == nil
                ? HrtWidgetEntry.sample.intakeCount
                : max(0, storedIntakes),
            showsIntakes: defaults.object(forKey: "preview_show_intakes") == nil
                ? true
                : defaults.bool(forKey: "preview_show_intakes")
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
        HStack(spacing: 12) {
            symbolBadge(size: 48, symbolSize: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("On HRT for \(entry.durationText)")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                if entry.showsIntakes {
                    Text(entry.intakeText)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .monaContentMargins()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var largeWidget: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                symbolBadge(size: 38, symbolSize: 18)

                Text("Time on HRT")
                    .font(.headline)

                Spacer(minLength: 0)
            }

            Spacer(minLength: 16)

            Text(entry.durationText)
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            Text("On HRT")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.top, 2)

            Spacer(minLength: 18)

            if entry.showsIntakes {
                Divider()

                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(HrtWidgetColors.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entry.intakeCount)")
                            .font(.title3.weight(.semibold))
                        Text(entry.intakeCount == 1 ? "Intake logged" : "Intakes logged")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
            }
        }
        .monaContentMargins()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
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
