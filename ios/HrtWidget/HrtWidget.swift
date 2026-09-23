import SwiftUI
import WidgetKit

private let widgetKind = "HrtWidget"
private let appGroupID = "group.com.deliacheminot.mona"

fileprivate struct NextIntakeSnapshot {
    let dueDay: Date
    let dueAt: Date?
    let intervalMinutes: Int

    init?(defaults: UserDefaults) {
        guard let dateString = defaults.string(forKey: "next_intake_date"),
              let intervalString = defaults.string(forKey: "next_intake_interval_minutes"),
              let intervalMinutes = Int(intervalString), intervalMinutes > 0
        else {
            return nil
        }
        let parts = dateString.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              let parsedDay = Calendar.current.date(
                from: DateComponents(year: year, month: month, day: day)
              ),
              Calendar.current.component(.year, from: parsedDay) == year,
              Calendar.current.component(.month, from: parsedDay) == month,
              Calendar.current.component(.day, from: parsedDay) == day
        else {
            return nil
        }

        self.dueDay = Calendar.current.startOfDay(for: parsedDay)
        self.intervalMinutes = intervalMinutes
        if let rawInstant = defaults.string(forKey: "next_intake_due_at_ms"),
           let milliseconds = Int64(rawInstant) {
            self.dueAt = Date(timeIntervalSince1970: Double(milliseconds) / 1000)
        } else {
            self.dueAt = nil
        }
    }

    private init(dueDay: Date, dueAt: Date?, intervalMinutes: Int) {
        self.dueDay = dueDay
        self.dueAt = dueAt
        self.intervalMinutes = intervalMinutes
    }

    static var sample: NextIntakeSnapshot {
        let today = Calendar.current.startOfDay(for: Date())
        let dueDay = Calendar.current.date(byAdding: .day, value: 5, to: today) ?? today
        return NextIntakeSnapshot(dueDay: dueDay, dueAt: nil, intervalMinutes: 7 * 24 * 60)
    }

    func countdown(at now: Date) -> NextIntakeCountdown {
        if let dueAt {
            let seconds = dueAt.timeIntervalSince(now)
            let minutes = seconds >= 0
                ? Int(ceil(seconds / 60))
                : -Int(ceil(-seconds / 60))
            return NextIntakeCountdown(
                remainingMinutes: minutes,
                intervalMinutes: intervalMinutes,
                dateOnly: false
            )
        }

        let calendar = Calendar.current
        var logicalToday = calendar.startOfDay(for: now)
        let time = calendar.dateComponents([.hour, .minute], from: now)
        if (time.hour ?? 0) * 60 + (time.minute ?? 0) < 240 {
            logicalToday = calendar.date(byAdding: .day, value: -1, to: logicalToday)
                ?? logicalToday
        }
        let days = calendar.dateComponents([.day], from: logicalToday, to: dueDay).day ?? 0
        return NextIntakeCountdown(
            remainingMinutes: days * 24 * 60,
            intervalMinutes: intervalMinutes,
            dateOnly: true
        )
    }
}

private struct NextIntakeCountdown {
    let remainingMinutes: Int
    let intervalMinutes: Int
    let dateOnly: Bool

    var display: (value: Int, unit: Unit) {
        let minutes = abs(remainingMinutes)
        if minutes < 60 {
            return (minutes, .minutes)
        }
        if minutes < 24 * 60 {
            return (minutes / 60, .hours)
        }
        // Preview-only approximation; real month durations need calendar dates.
        if minutes >= 30 * 24 * 60 {
            return (minutes / (30 * 24 * 60), .months)
        }
        if minutes >= 7 * 24 * 60 {
            return (minutes / (7 * 24 * 60), .weeks)
        }
        return (minutes / (24 * 60), .days)
    }

    var rectangularText: String {
        if remainingMinutes == 0 {
            return dateOnly ? "Today" : "Now"
        }
        let duration = shortDuration
        return remainingMinutes < 0 ? "\(duration) ago" : "in \(duration)"
    }

    var accessibilityLabel: String {
        if remainingMinutes == 0 {
            return dateOnly ? "Intake due today" : "Intake due now"
        }
        let duration = spokenDuration
        return remainingMinutes < 0
            ? "Intake overdue by \(duration)"
            : "Next intake in \(duration)"
    }

    private var shortDuration: String {
        let minutes = abs(remainingMinutes)
        if minutes < 60 {
            return "\(minutes) min"
        }
        if minutes < 24 * 60 {
            let hours = minutes / 60
            let extraMinutes = minutes % 60
            return extraMinutes == 0 ? "\(hours)h" : "\(hours)h \(extraMinutes)m"
        }
        return "\(display.value) \(display.unit.label(for: display.value))"
    }

    private var spokenDuration: String {
        let minutes = abs(remainingMinutes)
        if minutes < 60 {
            return "\(minutes) \(Unit.minutes.label(for: minutes))"
        }
        if minutes < 24 * 60 {
            let hours = minutes / 60
            let extraMinutes = minutes % 60
            let hourText = "\(hours) \(Unit.hours.label(for: hours))"
            return extraMinutes == 0
                ? hourText
                : "\(hourText) and \(extraMinutes) \(Unit.minutes.label(for: extraMinutes))"
        }
        return "\(display.value) \(display.unit.label(for: display.value))"
    }

    enum Unit: String {
        case minutes
        case hours
        case days
        case weeks
        case months

        func label(for value: Int) -> String {
            value == 1 ? String(rawValue.dropLast()) : rawValue
        }

        func circularLabel(for value: Int) -> String {
            switch self {
            case .minutes: return "MIN"
            case .hours: return value == 1 ? "HR" : "HRS"
            case .days: return value == 1 ? "DAY" : "DAYS"
            case .weeks: return value == 1 ? "WK" : "WKS"
            case .months: return "MO."
            }
        }

        var shortSuffix: String {
            switch self {
            case .minutes: return "m"
            case .hours: return "h"
            case .days: return "d"
            case .weeks: return "w"
            case .months: return "mo"
            }
        }
    }
}

#if WIDGET_PREVIEW
private let previewAppGroup = Bundle.main.object(
    forInfoDictionaryKey: "PreviewAppGroup"
) as? String
#endif

private enum HrtWidgetColors {
    // Keeps Mona's Android widget palette, expressed through native iOS shapes
    // and semantic foreground colors.
    static let accent = Color(red: 103.0 / 255.0, green: 80.0 / 255.0, blue: 164.0 / 255.0)
    static let darkAccent = Color(red: 195.0 / 255.0, green: 172.0 / 255.0, blue: 237.0 / 255.0)
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
    fileprivate let nextIntake: NextIntakeSnapshot?

    fileprivate var durationText: String {
        "\(durationValue) \(durationUnit.label(for: durationValue))"
    }

    fileprivate var intakeText: String {
        "\(intakeCount.formatted()) \(intakeCount == 1 ? "intake" : "intakes") logged"
    }

    fileprivate static let sample = HrtWidgetEntry(
        date: Date(),
        durationValue: 8,
        durationUnit: .months,
        intakeCount: 16,
        showsIntakes: true,
        recentIntakeCounts: [0, 1, 0, 2, 1, 0, 3],
        nextIntake: .sample
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
        let now = Date()
        completion(entry(at: now, nextIntake: sharedNextIntake))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<HrtWidgetEntry>) -> Void
    ) {
        let now = Date()
        let nextIntake = sharedNextIntake
        let entries = timelineDates(from: now, for: nextIntake).map {
            entry(at: $0, nextIntake: nextIntake)
        }
        completion(Timeline(entries: entries, policy: nextIntake == nil ? .never : .atEnd))
    }

    private var sharedNextIntake: NextIntakeSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }
        return NextIntakeSnapshot(defaults: defaults)
    }

    private func timelineDates(from now: Date, for nextIntake: NextIntakeSnapshot?) -> [Date] {
        guard let nextIntake else { return [now] }
        var dates = [now]
        if let dueAt = nextIntake.dueAt {
            let horizon = now.addingTimeInterval(7 * 24 * 60 * 60)
            var cursor = now
            while cursor < horizon {
                let distance = abs(dueAt.timeIntervalSince(cursor))
                let step: TimeInterval = distance < 60 * 60 ? 5 * 60
                    : distance < 24 * 60 * 60 ? 15 * 60 : 6 * 60 * 60
                cursor = cursor.addingTimeInterval(step)
                dates.append(cursor)
            }
        } else {
            let calendar = Calendar.current
            guard var boundary = calendar.nextDate(
                after: now,
                matching: DateComponents(hour: 4, minute: 0, second: 0),
                matchingPolicy: .nextTime
            ) else { return dates }
            for _ in 0..<7 {
                dates.append(boundary)
                boundary = calendar.date(byAdding: .day, value: 1, to: boundary) ?? boundary
            }
        }
        return dates
    }

    private func sampleEntry(at date: Date, nextIntake: NextIntakeSnapshot?) -> HrtWidgetEntry {
        HrtWidgetEntry(
            date: date,
            durationValue: HrtWidgetEntry.sample.durationValue,
            durationUnit: HrtWidgetEntry.sample.durationUnit,
            intakeCount: HrtWidgetEntry.sample.intakeCount,
            showsIntakes: HrtWidgetEntry.sample.showsIntakes,
            recentIntakeCounts: HrtWidgetEntry.sample.recentIntakeCounts,
            nextIntake: nextIntake
        )
    }

    private func entry(at date: Date, nextIntake: NextIntakeSnapshot?) -> HrtWidgetEntry {
        #if WIDGET_PREVIEW
        guard let previewAppGroup,
              let defaults = UserDefaults(suiteName: previewAppGroup)
        else {
            return sampleEntry(at: date, nextIntake: nextIntake)
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
            date: date,
            durationValue: storedValue > 0 ? storedValue : HrtWidgetEntry.sample.durationValue,
            durationUnit: HrtDurationUnit(rawValue: storedUnit ?? "") ?? .months,
            intakeCount: defaults.object(forKey: "preview_intake_count") == nil
                ? HrtWidgetEntry.sample.intakeCount
                : max(0, storedIntakes),
            showsIntakes: defaults.object(forKey: "preview_show_intakes") == nil
                ? true
                : defaults.bool(forKey: "preview_show_intakes"),
            recentIntakeCounts: normalizedRecentCounts,
            nextIntake: nextIntake
        )
        #else
        return sampleEntry(at: date, nextIntake: nextIntake)
        #endif
    }
}

struct HrtWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme

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
                .foregroundColor(
                    colorScheme == .dark ? HrtWidgetColors.darkAccent : HrtWidgetColors.accent
                )

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

    private var countdown: NextIntakeCountdown? {
        entry.nextIntake?.countdown(at: entry.date)
    }

    private var accessoryTitle: String {
        guard let countdown else { return "NEXT INTAKE" }
        return countdown.remainingMinutes <= 0 ? "INTAKE DUE" : "NEXT INTAKE"
    }

    @available(iOSApplicationExtension 16.0, *)
    @ViewBuilder
    private var accessoryWidget: some View {
        if family == .accessoryCircular {
            if let countdown {
                Gauge(
                    value: Double(max(0, min(countdown.remainingMinutes, countdown.intervalMinutes))),
                    in: 0...Double(countdown.intervalMinutes)
                ) {
                    Text("Next intake")
                } currentValueLabel: {
                    VStack(spacing: -3) {
                        if countdown.remainingMinutes == 0 {
                            Text("DUE")
                                .font(.system(size: 17, weight: .semibold, design: .rounded))
                        } else {
                            Text(countdown.remainingMinutes < 0
                                ? "\(countdown.display.value)\(countdown.display.unit.shortSuffix)"
                                : "\(countdown.display.value)")
                                .font(.system(size: 25, weight: .medium, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        Text(countdown.remainingMinutes < 0 ? "LATE"
                            : countdown.remainingMinutes == 0
                                ? (countdown.dateOnly ? "TODAY" : "NOW")
                                : countdown.display.unit.circularLabel(for: countdown.display.value))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(countdown.accessibilityLabel)
            } else {
                Gauge(value: 0, in: 0...1) {
                    Text("Next intake")
                } currentValueLabel: {
                    VStack(spacing: -3) {
                        Text("—")
                            .font(.system(size: 25, weight: .medium, design: .rounded))
                        Text("NO PLAN")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("No scheduled intake")
            }
        } else if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 2) {
                Text(accessoryTitle)
                    .font(.caption2.weight(.semibold))
                Text(countdown?.rectangularText ?? "No schedule")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, 8)
            .widgetAccentable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(countdown?.accessibilityLabel ?? "No scheduled intake")
        } else {
            EmptyView()
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
            if family == .systemSmall || family == .systemMedium || family == .systemLarge {
                background(Color(.systemBackground))
            } else {
                self
            }
        }
    }
}

struct HrtWidget: Widget {
    private var supportedFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [
            .systemSmall,
            // Re-enable other sizes as their designs are reviewed.
            // .systemMedium,
            // .systemLarge,
            // .accessoryInline,
        ]
        if #available(iOSApplicationExtension 16.0, *) {
            families += [.accessoryCircular, .accessoryRectangular]
        }
        return families
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: widgetKind, provider: HrtWidgetProvider()) { entry in
            HrtWidgetEntryView(entry: entry)
                .widgetURL(URL(string: "mona-widget://home?homeWidget=true"))
        }
        .configurationDisplayName("Mona")
        .description("See your HRT duration or your next intake at a glance.")
        .supportedFamilies(supportedFamilies)
    }
}

@main
struct HrtWidgetBundle: WidgetBundle {
    var body: some Widget {
        HrtWidget()
    }
}
