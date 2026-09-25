import SwiftUI
import WidgetKit

private let widgetKind = "HrtWidget"
private let appGroupID = "group.com.deliacheminot.mona"

private func widgetDay(_ raw: String, calendar: Calendar = .current) -> Date? {
    let parts = raw.split(separator: "-")
    guard parts.count == 3,
          let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
          let parsed = calendar.date(from: DateComponents(year: year, month: month, day: day)),
          calendar.component(.year, from: parsed) == year,
          calendar.component(.month, from: parsed) == month,
          calendar.component(.day, from: parsed) == day
    else { return nil }
    return calendar.startOfDay(for: parsed)
}

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
        guard let parsedDay = widgetDay(dateString) else {
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

    func countdown(at now: Date) -> NextIntakeCountdown {
        if let dueAt {
            let seconds = dueAt.timeIntervalSince(now)
            let minutes = seconds >= 0
                ? Int(ceil(seconds / 60))
                : -Int(ceil(-seconds / 60))
            return NextIntakeCountdown(
                remainingMinutes: minutes,
                intervalMinutes: intervalMinutes
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
            intervalMinutes: intervalMinutes
        )
    }
}

private struct NextIntakeCountdown {
    let remainingMinutes: Int
    let intervalMinutes: Int

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
        // Keep whole-day precision until the month range.
        return (minutes / (24 * 60), .days)
    }

    func rectangularText(copy: WidgetCopy, pendingTodayCount: Int) -> String {
        if remainingMinutes <= 0 {
            return copy.countToday(max(1, pendingTodayCount))
        }
        if remainingMinutes >= 24 * 60 {
            return copy.relative(display.unit.components(value: display.value), abbreviated: false)
        }
        return copy.future(shortDuration(copy: copy))
    }

    func accessibilityLabel(copy: WidgetCopy, pendingTodayCount: Int) -> String {
        if remainingMinutes <= 0 {
            return "\(copy.intakesDue), \(copy.countToday(max(1, pendingTodayCount)))"
        }
        let time = remainingMinutes >= 24 * 60
            ? copy.relative(display.unit.components(value: display.value), abbreviated: false)
            : copy.future(spokenDuration(copy: copy))
        return "\(copy.nextIntake), \(time)"
    }

    private func shortDuration(copy: WidgetCopy) -> String {
        let minutes = abs(remainingMinutes)
        if minutes < 60 {
            return copy.duration(DateComponents(minute: minutes), units: .minute, abbreviated: true)
        }
        return copy.duration(
            DateComponents(hour: minutes / 60, minute: minutes % 60),
            units: [.hour, .minute], abbreviated: true
        )
    }

    private func spokenDuration(copy: WidgetCopy) -> String {
        let minutes = abs(remainingMinutes)
        if minutes < 60 {
            return copy.duration(DateComponents(minute: minutes), units: .minute, abbreviated: false)
        }
        return copy.duration(
            DateComponents(hour: minutes / 60, minute: minutes % 60),
            units: [.hour, .minute], abbreviated: false
        )
    }

    enum Unit: String {
        case minutes
        case hours
        case days
        case months

        func components(value: Int) -> DateComponents {
            switch self {
            case .minutes: return DateComponents(minute: value)
            case .hours: return DateComponents(hour: value)
            case .days: return DateComponents(day: value)
            case .months: return DateComponents(month: value)
            }
        }

        var calendarUnit: NSCalendar.Unit {
            switch self {
            case .minutes: return .minute
            case .hours: return .hour
            case .days: return .day
            case .months: return .month
            }
        }

    }
}

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

    func components(value: Int) -> (DateComponents, NSCalendar.Unit) {
        switch self {
        case .days: return (DateComponents(day: value), .day)
        case .weeks: return (DateComponents(weekOfMonth: value), .weekOfMonth)
        case .months: return (DateComponents(month: value), .month)
        case .years: return (DateComponents(year: value), .year)
        }
    }

    func label(for value: Int) -> String {
        guard value == 1 else { return rawValue }
        return String(rawValue.dropLast())
    }

}

private struct HrtDurationSnapshot {
    let firstDay: Date

    init?(defaults: UserDefaults) {
        guard let raw = defaults.string(forKey: "hrt_first_date"),
              let day = widgetDay(raw)
        else { return nil }
        firstDay = day
    }

    func duration(at now: Date) -> (value: Int, unit: HrtDurationUnit) {
        let calendar = Calendar.current
        var today = calendar.startOfDay(for: now)
        let time = calendar.dateComponents([.hour, .minute], from: now)
        if (time.hour ?? 0) * 60 + (time.minute ?? 0) < 240 {
            today = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        }

        let days = max(0, calendar.dateComponents([.day], from: firstDay, to: today).day ?? 0)
        if days < 7 { return (max(days, 1), .days) }
        if days < 90 { return (days / 7, .weeks) }

        let first = calendar.dateComponents([.year, .month, .day], from: firstDay)
        let current = calendar.dateComponents([.year, .month, .day], from: today)
        var months = ((current.year ?? 0) - (first.year ?? 0)) * 12
            + (current.month ?? 0) - (first.month ?? 0)
        if (current.day ?? 0) < (first.day ?? 0) { months -= 1 }
        return months < 12 ? (max(months, 1), .months) : (months / 12, .years)
    }
}

struct HrtWidgetEntry: TimelineEntry {
    let date: Date
    let durationValue: Int
    fileprivate let durationUnit: HrtDurationUnit
    let intakeCount: Int
    let showsIntakes: Bool
    let hasHrtData: Bool
    let recentIntakeCounts: [Int]
    fileprivate let nextIntake: NextIntakeSnapshot?
    let pendingTodayCount: Int
    let localeIdentifier: String
    let homeTitle: String
    let homeIntakeText: String
    let homeEmptyText: String

    fileprivate var copy: WidgetCopy { WidgetCopy(localeIdentifier: localeIdentifier) }

    fileprivate var durationText: String {
        guard hasHrtData else { return "—" }
        let (components, units) = durationUnit.components(value: durationValue)
        let localized = copy.duration(components, units: units, abbreviated: false)
        return localized.isEmpty ? "\(durationValue) \(durationUnit.label(for: durationValue))" : localized
    }

    fileprivate var intakeText: String {
        homeIntakeText
    }
}

struct HrtWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HrtWidgetEntry {
        entry(at: Date(), nextIntake: sharedNextIntake)
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
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private var sharedNextIntake: NextIntakeSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return nil }
        return NextIntakeSnapshot(defaults: defaults)
    }

    private func timelineDates(from now: Date, for nextIntake: NextIntakeSnapshot?) -> [Date] {
        let calendar = Calendar.current
        let horizon = calendar.date(byAdding: .day, value: 7, to: now)
            ?? now.addingTimeInterval(7 * 24 * 60 * 60)
        var dates: Set<Date> = [now]

        // Mona's logical day starts at 04:00; refresh HRT duration even if
        // the app has not been opened and no next intake is scheduled.
        if var boundary = calendar.nextDate(
            after: now,
            matching: DateComponents(hour: 4, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) {
            while boundary <= horizon {
                dates.insert(boundary)
                boundary = calendar.date(byAdding: .day, value: 1, to: boundary) ?? horizon.addingTimeInterval(1)
            }
        }

        if let dueAt = nextIntake?.dueAt {
            var cursor = now
            while cursor < horizon {
                let distance = abs(dueAt.timeIntervalSince(cursor))
                let step: TimeInterval = distance < 60 * 60 ? 5 * 60
                    : distance < 24 * 60 * 60 ? 15 * 60 : 6 * 60 * 60
                cursor = cursor.addingTimeInterval(step)
                if cursor <= horizon { dates.insert(cursor) }
            }
        }
        return dates.sorted()
    }

    private func entry(at date: Date, nextIntake: NextIntakeSnapshot?) -> HrtWidgetEntry {
        let defaults = UserDefaults(suiteName: appGroupID)
        let localeIdentifier = defaults?.string(forKey: "app_locale") ?? Locale.current.identifier
        let copy = WidgetCopy(localeIdentifier: localeIdentifier)
        let duration = defaults.flatMap { HrtDurationSnapshot(defaults: $0) }?.duration(at: date)
        let intakeCount = max(0, Int(defaults?.string(forKey: "hrt_intake_count") ?? "") ?? 0)
        let recentCounts = defaults?.string(forKey: "hrt_recent_intake_counts")?
            .split(separator: ",")
            .map { max(0, Int($0) ?? 0) }
        let normalizedRecentCounts = recentCounts?.count == 7
            ? recentCounts ?? []
            : Array(repeating: 0, count: 7)

        return HrtWidgetEntry(
            date: date,
            durationValue: duration?.value ?? 0,
            durationUnit: duration?.unit ?? .days,
            intakeCount: intakeCount,
            showsIntakes: duration != nil,
            hasHrtData: duration != nil,
            recentIntakeCounts: normalizedRecentCounts,
            nextIntake: nextIntake,
            pendingTodayCount: max(0, Int(defaults?.string(forKey: "next_intake_today_count") ?? "") ?? 0),
            localeIdentifier: localeIdentifier,
            homeTitle: defaults?.string(forKey: "widget_home_title") ?? copy.homeTitle,
            homeIntakeText: defaults?.string(forKey: "widget_home_intakes")
                ?? "",
            homeEmptyText: defaults?.string(forKey: "widget_home_empty") ?? copy.homeEmpty
        )
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
            Label(entry.homeTitle, systemImage: "calendar")
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

            if entry.showsIntakes && !entry.intakeText.isEmpty {
                Text(entry.intakeText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 4)
            } else {
                Text(entry.homeEmptyText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

                    Text(entry.homeTitle)
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
                    Text(entry.homeTitle)
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
        guard entry.hasHrtData else { return "\(entry.homeTitle), \(entry.homeEmptyText)." }
        var summary = "\(entry.homeTitle), \(entry.durationText)."
        if entry.showsIntakes && !entry.intakeText.isEmpty {
            summary += " \(entry.intakeText)."
        }
        return summary
    }

    private var countdown: NextIntakeCountdown? {
        entry.nextIntake?.countdown(at: entry.date)
    }

    private var accessoryTitle: String {
        guard let countdown else { return entry.copy.nextIntake.uppercased(with: entry.copy.locale) }
        let title = countdown.remainingMinutes <= 0 ? entry.copy.intakesDue : entry.copy.nextIntake
        return title.uppercased(with: entry.copy.locale)
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
                    Text(entry.copy.nextIntake)
                } currentValueLabel: {
                    VStack(spacing: -3) {
                        if countdown.remainingMinutes <= 0 {
                            Image(systemName: "clock")
                                .font(.system(size: 25, weight: .medium))
                        } else {
                            Text("\(countdown.display.value)")
                                .font(.system(size: 25, weight: .medium, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text(entry.copy.circularUnit(
                                countdown.display.unit.components(value: countdown.display.value),
                                units: countdown.display.unit.calendarUnit
                            ))
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                    }
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(countdown.accessibilityLabel(
                    copy: entry.copy,
                    pendingTodayCount: entry.pendingTodayCount
                ))
            } else {
                Gauge(value: 0, in: 0...1) {
                    Text(entry.copy.nextIntake)
                } currentValueLabel: {
                    VStack(spacing: -3) {
                        Text("—")
                            .font(.system(size: 25, weight: .medium, design: .rounded))
                        Text(entry.copy.noPlan.uppercased(with: entry.copy.locale))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(entry.copy.noSchedule)
            }
        } else if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 2) {
                Text(accessoryTitle)
                    .font(.caption2.weight(.semibold))
                Text(countdown?.rectangularText(
                    copy: entry.copy,
                    pendingTodayCount: entry.pendingTodayCount
                ) ?? entry.copy.noSchedule)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, 8)
            .widgetAccentable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(countdown?.accessibilityLabel(
                copy: entry.copy,
                pendingTodayCount: entry.pendingTodayCount
            )
                ?? entry.copy.noSchedule)
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
    private var pickerCopy: WidgetCopy {
        let savedLocale = UserDefaults(suiteName: appGroupID)?.string(forKey: "app_locale")
        return WidgetCopy(localeIdentifier: savedLocale ?? Locale.current.identifier)
    }

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
        .description(pickerCopy.pickerDescription)
        .supportedFamilies(supportedFamilies)
    }
}

@main
struct HrtWidgetBundle: WidgetBundle {
    var body: some Widget {
        HrtWidget()
    }
}
