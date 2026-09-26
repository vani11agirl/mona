import SwiftUI
import WidgetKit

private let widgetKind = "HrtWidget"
// Sideload test builds must use the App Group granted by their signing profile.
private let appGroupID = Bundle.main.object(forInfoDictionaryKey: "MonaWidgetAppGroup") as? String
    ?? "group.com.deliacheminot.mona"

private func sharedWidgetData() -> [String: Any] {
    guard let defaults = UserDefaults(suiteName: appGroupID) else { return [:] }
    // Read one published value, never a mixture of fields from two app syncs.
    // Retain pre-upgrade data until the app publishes its first snapshot.
    guard let encoded = defaults.string(forKey: "widget_snapshot_v1") else {
        return defaults.dictionaryRepresentation()
    }
    guard let bytes = encoded.data(using: .utf8),
          let data = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any]
    else { return [:] }
    return data
}

private func widgetInstant(_ value: Any?) -> Date? {
    guard let raw = value as? String, let milliseconds = Double(raw),
          milliseconds.isFinite else { return nil }
    return Date(timeIntervalSince1970: milliseconds / 1000)
}

private func intakeData(at date: Date, in data: [String: Any]) -> (values: [String: Any], expired: Bool) {
    guard let timeline = data["intake_timeline"] as? [[String: Any]] else {
        return (data, false)
    }
    guard let end = widgetInstant(data["intake_timeline_end_ms"]),
          let current = timeline.last(where: {
              guard let start = widgetInstant($0["from_ms"]) else { return false }
              return start <= date
          }) else {
        return ([:], true)
    }
    if date >= end, let next = NextIntakeSnapshot(data: current),
       next.countdown(at: date).remainingMinutes <= 0 {
        // "Today" totals have expired. A known intake still in the future can
        // keep counting down (e.g. a monthly schedule), but must not reuse an
        // old day's count once it becomes due.
        return ([:], true)
    }
    return (current, false)
}

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

    init?(data: [String: Any]) {
        guard let dateString = data["next_intake_date"] as? String,
              let intervalString = data["next_intake_interval_minutes"] as? String,
              let intervalMinutes = Int(intervalString), intervalMinutes > 0
        else {
            return nil
        }
        guard let parsedDay = widgetDay(dateString) else {
            return nil
        }

        self.dueDay = Calendar.current.startOfDay(for: parsedDay)
        self.intervalMinutes = intervalMinutes
        self.dueAt = widgetInstant(data["next_intake_due_at_ms"])
    }

    func countdown(at now: Date) -> NextIntakeCountdown {
        if let dueAt {
            let seconds = dueAt.timeIntervalSince(now)
            let minutes = seconds >= 0
                ? Int(ceil(seconds / 60))
                : -Int(ceil(-seconds / 60))
            return NextIntakeCountdown(
                remainingMinutes: minutes,
                remainingMonths: Calendar.current.dateComponents([.month], from: now, to: dueAt).month ?? 0,
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
            remainingMonths: calendar.dateComponents([.month], from: logicalToday, to: dueDay).month ?? 0,
            intervalMinutes: intervalMinutes
        )
    }
}

private struct NextIntakeCountdown {
    let remainingMinutes: Int
    let remainingMonths: Int
    let intervalMinutes: Int

    var display: (value: Int, unit: Unit) {
        let minutes = abs(remainingMinutes)
        if minutes < 60 {
            return (minutes, .minutes)
        }
        if minutes < 24 * 60 {
            return (minutes / 60, .hours)
        }
        // Use completed calendar months, not a fixed 30-day approximation.
        if remainingMonths > 0 {
            return (remainingMonths, .months)
        }
        // Keep whole-day precision until the month range.
        return (minutes / (24 * 60), .days)
    }

    func rectangularText(copy: WidgetCopy, pendingTodayCount: Int) -> String {
        if remainingMinutes <= 0 {
            return copy.countToday(max(0, pendingTodayCount))
        }
        if remainingMinutes >= 24 * 60 {
            return copy.relative(display.unit.components(value: display.value), abbreviated: false)
        }
        return copy.future(shortDuration(copy: copy))
    }

    func accessibilityLabel(copy: WidgetCopy, pendingTodayCount: Int) -> String {
        if remainingMinutes <= 0 {
            return "\(copy.intakesDue), \(copy.countToday(max(0, pendingTodayCount)))"
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

    init?(data: [String: Any]) {
        guard let raw = data["hrt_first_date"] as? String,
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
    let showsIntakes: Bool
    let hasHrtData: Bool
    fileprivate let nextIntake: NextIntakeSnapshot?
    let pendingTodayCount: Int
    let intakeTimelineExpired: Bool
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
        entry(at: Date(), data: sharedWidgetData())
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (HrtWidgetEntry) -> Void
    ) {
        let now = Date()
        completion(entry(at: now, data: sharedWidgetData()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<HrtWidgetEntry>) -> Void
    ) {
        let now = Date()
        let data = sharedWidgetData()
        let entries = timelineDates(from: now, data: data).map {
            entry(at: $0, data: data)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func timelineDates(from now: Date, data: [String: Any]) -> [Date] {
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

        if let timeline = data["intake_timeline"] as? [[String: Any]] {
            for state in timeline {
                if let change = widgetInstant(state["from_ms"]), change > now, change <= horizon {
                    dates.insert(change)
                }
                if let due = widgetInstant(state["next_intake_due_at_ms"]), due > now, due <= horizon {
                    dates.insert(due)
                }
            }
        }
        if let end = widgetInstant(data["intake_timeline_end_ms"]), end > now, end <= horizon {
            dates.insert(end)
        }

        // Each segment uses its own selected intake, including after 04:00.
        // Include exact schedule transitions independently of countdown steps.
        let boundaries = dates.union([horizon]).sorted()
        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            let state = intakeData(at: start, in: data)
            guard let dueAt = NextIntakeSnapshot(data: state.values)?.dueAt, dueAt > start else { continue }
            var cursor = start
            while cursor < min(end, dueAt) {
                let distance = abs(dueAt.timeIntervalSince(cursor))
                let step: TimeInterval = distance < 60 * 60 ? 5 * 60
                    : distance < 24 * 60 * 60 ? 15 * 60 : 6 * 60 * 60
                cursor = cursor.addingTimeInterval(step)
                if cursor < min(end, dueAt) { dates.insert(cursor) }
            }
        }
        return dates.sorted()
    }

    private func entry(at date: Date, data: [String: Any]) -> HrtWidgetEntry {
        let state = intakeData(at: date, in: data)
        let localeIdentifier = data["app_locale"] as? String ?? Locale.current.identifier
        let copy = WidgetCopy(localeIdentifier: localeIdentifier)
        let duration = HrtDurationSnapshot(data: data)?.duration(at: date)

        return HrtWidgetEntry(
            date: date,
            durationValue: duration?.value ?? 0,
            durationUnit: duration?.unit ?? .days,
            showsIntakes: duration != nil,
            hasHrtData: duration != nil,
            nextIntake: NextIntakeSnapshot(data: state.values),
            pendingTodayCount: max(0, Int(state.values["next_intake_today_count"] as? String ?? "") ?? 0),
            intakeTimelineExpired: state.expired,
            localeIdentifier: localeIdentifier,
            homeTitle: data["widget_home_title"] as? String ?? copy.homeTitle,
            homeIntakeText: data["widget_home_intakes"] as? String
                ?? "",
            homeEmptyText: data["widget_home_empty"] as? String ?? copy.homeEmpty
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
            default:
                if #available(iOSApplicationExtension 16.0, *) {
                    accessoryWidget
                } else {
                    smallWidget
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
                        Text(entry.intakeTimelineExpired ? "" : entry.copy.noPlan.uppercased(with: entry.copy.locale))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(emptyIntakeText)
            }
        } else if family == .accessoryRectangular {
            VStack(alignment: .leading, spacing: 2) {
                Text(accessoryTitle)
                    .font(.caption2.weight(.semibold))
                Text(countdown?.rectangularText(
                    copy: entry.copy,
                    pendingTodayCount: entry.pendingTodayCount
                ) ?? emptyIntakeText)
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
                ?? emptyIntakeText)
        } else {
            EmptyView()
        }
    }

    private var emptyIntakeText: String {
        entry.intakeTimelineExpired ? "—" : entry.copy.noSchedule
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
            if family == .systemSmall {
                containerBackground(Color(.systemBackground), for: .widget)
            } else {
                containerBackground(Color.clear, for: .widget)
            }
        } else {
            if family == .systemSmall {
                background(Color(.systemBackground))
            } else {
                self
            }
        }
    }
}

struct HrtWidget: Widget {
    private var pickerCopy: WidgetCopy {
        let savedLocale = sharedWidgetData()["app_locale"] as? String
        return WidgetCopy(localeIdentifier: savedLocale ?? Locale.current.identifier)
    }

    private var supportedFamilies: [WidgetFamily] {
        var families: [WidgetFamily] = [
            .systemSmall,
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
