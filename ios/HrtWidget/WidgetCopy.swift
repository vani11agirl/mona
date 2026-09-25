import Foundation

// Copy is generated from Mona's i18next sources and bundled as JSON so timeline
// updates can localize themselves while the Flutter app is closed.
struct WidgetCopy {
    let locale: Locale
    private let words: [String: String]

    init(localeIdentifier: String) {
        locale = Locale(identifier: localeIdentifier)
        let normalized = localeIdentifier.replacingOccurrences(of: "_", with: "-")
        let language = normalized.split(separator: "-").first.map(String.init) ?? "en"
        words = Self.translations[normalized] ?? Self.translations[language] ?? [:]
    }

    private func text(_ key: String) -> String {
        words[key] ?? Self.translations["en"]?[key] ?? key
    }

    var nextIntake: String { text("iosWidgetNextIntake") }
    var intakesDue: String { text("iosWidgetIntakesDue") }
    var noPlan: String { text("iosWidgetNoPlan") }
    var noSchedule: String { text("iosWidgetNoSchedule") }
    var homeTitle: String { text("HrtCounter") }
    var homeEmpty: String { text("neverTakenYet") }
    var pickerDescription: String { text("HrtCounterDescription") }

    func future(_ duration: String) -> String {
        text("iosWidgetFuture").replacingOccurrences(of: "{{duration}}", with: duration)
    }

    func countToday(_ count: Int) -> String {
        text("iosWidgetCountToday").replacingOccurrences(of: "{{count}}", with: String(count))
    }

    func duration(_ components: DateComponents, units: NSCalendar.Unit, abbreviated: Bool) -> String {
        formattedDuration(components, units: units, style: abbreviated ? .abbreviated : .full)
    }

    private func formattedDuration(
        _ components: DateComponents,
        units: NSCalendar.Unit,
        style: DateComponentsFormatter.UnitsStyle
    ) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.allowedUnits = units
        formatter.unitsStyle = style
        return formatter.string(from: components) ?? ""
    }

    func relative(_ components: DateComponents, abbreviated: Bool) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = abbreviated ? .abbreviated : .full
        return formatter.localizedString(from: components)
    }

    func circularUnit(_ components: DateComponents, units: NSCalendar.Unit) -> String {
        let pattern = "[\\p{N}\\s]+"
        let fullUnit = formattedDuration(components, units: units, style: .full)
            .replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .uppercased(with: locale)
        if !fullUnit.isEmpty && fullUnit.count <= 5 { return fullUnit }

        let shortUnit = formattedDuration(components, units: units, style: .short)
            .replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .uppercased(with: locale)
        if !shortUnit.isEmpty && shortUnit.count <= 5 { return shortUnit }

        let compactUnit = formattedDuration(components, units: units, style: .abbreviated)
            .replacingOccurrences(of: pattern, with: "", options: .regularExpression)
            .uppercased(with: locale)
        return compactUnit.isEmpty ? "—" : compactUnit
    }

    private static let translations: [String: [String: String]] = {
        guard let url = Bundle.main.url(forResource: "WidgetTranslations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let translations = try? JSONDecoder().decode([String: [String: String]].self, from: data)
        else { return [:] }
        return translations
    }()
}
