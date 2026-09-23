import Foundation

// Lock Screen copy lives in the extension because its timeline keeps changing
// while Mona is closed. Home Screen copy already translated by Slang is shared
// separately through the App Group.
struct WidgetCopy {
    let locale: Locale
    private let words: Words

    init(localeIdentifier: String) {
        locale = Locale(identifier: localeIdentifier)
        let normalized = localeIdentifier.replacingOccurrences(of: "_", with: "-")
        let language = normalized.split(separator: "-").first.map(String.init) ?? "en"
        words = Self.translations[normalized] ?? Self.translations[language] ?? Self.english
    }

    var nextIntake: String { words.nextIntake }
    var intakeDue: String { words.intakeDue }
    var due: String { words.due }
    var late: String { words.late }
    var noPlan: String { words.noPlan }
    var noSchedule: String { words.noSchedule }
    var now: String { words.now }

    func future(_ duration: String) -> String {
        words.future.replacingOccurrences(of: "%@", with: duration)
    }

    func past(_ duration: String) -> String {
        words.past.replacingOccurrences(of: "%@", with: duration)
    }

    func duration(_ components: DateComponents, units: NSCalendar.Unit, abbreviated: Bool) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.allowedUnits = units
        formatter.unitsStyle = abbreviated ? .abbreviated : .full
        return formatter.string(from: components) ?? ""
    }

    func relative(_ components: DateComponents, abbreviated: Bool) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = abbreviated ? .abbreviated : .full
        return formatter.localizedString(from: components)
    }

    var today: String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.doesRelativeDateFormatting = true
        return formatter.string(from: Date())
    }

    func circularUnit(_ components: DateComponents, units: NSCalendar.Unit) -> String {
        let formatted = duration(components, units: units, abbreviated: true)
        let unit = formatted.replacingOccurrences(
            of: "[\\p{N}\\s\\u{00a0}]+", with: "", options: .regularExpression
        )
        return unit.isEmpty ? "—" : unit.uppercased(with: locale)
    }

    private struct Words {
        let nextIntake: String
        let intakeDue: String
        let due: String
        let late: String
        let noPlan: String
        let noSchedule: String
        let now: String
        let future: String
        let past: String
    }

    private static let english = Words(
        nextIntake: "Next intake", intakeDue: "Intake due", due: "Due",
        late: "Late", noPlan: "No plan", noSchedule: "No schedule", now: "Now",
        future: "in %@", past: "%@ ago"
    )

    private static let translations: [String: Words] = [
        "de": Words(nextIntake: "Nächste Einnahme", intakeDue: "Einnahme fällig",
            due: "Fällig", late: "Verspätet", noPlan: "Kein Plan",
            noSchedule: "Kein Zeitplan", now: "Jetzt", future: "in %@", past: "vor %@"),
        "es": Words(nextIntake: "Próxima toma", intakeDue: "Toma pendiente",
            due: "Pendiente", late: "Atrasada", noPlan: "Sin plan",
            noSchedule: "Sin horarios", now: "Ahora", future: "en %@", past: "hace %@"),
        "et": Words(nextIntake: "Järgmine annus", intakeDue: "Annuse aeg",
            due: "Aeg", late: "Hilinenud", noPlan: "Plaan puudub",
            noSchedule: "Ajakava puudub", now: "Praegu", future: "%@ pärast", past: "%@ tagasi"),
        "fr": Words(nextIntake: "Prochaine prise", intakeDue: "Prise à faire",
            due: "À prendre", late: "En retard", noPlan: "Aucun plan",
            noSchedule: "Aucun planning", now: "Maintenant", future: "dans %@", past: "il y a %@"),
        "gl": Words(nextIntake: "Próxima toma", intakeDue: "Toma pendente",
            due: "Pendente", late: "Atrasada", noPlan: "Sen plan",
            noSchedule: "Sen horarios", now: "Agora", future: "en %@", past: "hai %@"),
        "is": Words(nextIntake: "Næsta inntaka", intakeDue: "Tími fyrir inntöku",
            due: "Kominn tími", late: "Seint", noPlan: "Engin áætlun",
            noSchedule: "Engin áætlun", now: "Núna", future: "eftir %@", past: "fyrir %@ síðan"),
        "it": Words(nextIntake: "Prossima dose", intakeDue: "Dose da assumere",
            due: "Ora", late: "In ritardo", noPlan: "Nessun piano",
            noSchedule: "Nessun programma", now: "Adesso", future: "tra %@", past: "%@ fa"),
        "ko": Words(nextIntake: "다음 투여", intakeDue: "투여 시간",
            due: "투여", late: "지연", noPlan: "계획 없음",
            noSchedule: "일정 없음", now: "지금", future: "%@ 후", past: "%@ 전"),
        "nl": Words(nextIntake: "Volgende inname", intakeDue: "Inname verwacht",
            due: "Nu", late: "Te laat", noPlan: "Geen plan",
            noSchedule: "Geen schema", now: "Nu", future: "over %@", past: "%@ geleden"),
        "pl": Words(nextIntake: "Następne przyjęcie", intakeDue: "Czas na przyjęcie",
            due: "Teraz", late: "Po terminie", noPlan: "Brak planu",
            noSchedule: "Brak harmonogramu", now: "Teraz", future: "za %@", past: "%@ temu"),
        "pt": Words(nextIntake: "Próxima toma", intakeDue: "Hora da toma",
            due: "Agora", late: "Atrasada", noPlan: "Sem plano",
            noSchedule: "Sem cronograma", now: "Agora", future: "daqui a %@", past: "há %@"),
        "pt-BR": Words(nextIntake: "Próxima dose", intakeDue: "Hora da dose",
            due: "Agora", late: "Atrasada", noPlan: "Sem plano",
            noSchedule: "Sem cronograma", now: "Agora", future: "em %@", past: "há %@"),
        "ru": Words(nextIntake: "Следующий приём", intakeDue: "Пора принять",
            due: "Пора", late: "Просрочено", noPlan: "Нет плана",
            noSchedule: "Нет расписания", now: "Сейчас", future: "через %@", past: "%@ назад"),
        "sk": Words(nextIntake: "Ďalšia dávka", intakeDue: "Čas na dávku",
            due: "Teraz", late: "Mešká", noPlan: "Bez plánu",
            noSchedule: "Žiadny plán", now: "Teraz", future: "o %@", past: "pred %@"),
        "sq": Words(nextIntake: "Marrja e radhës", intakeDue: "Koha e marrjes",
            due: "Tani", late: "Me vonesë", noPlan: "Pa plan",
            noSchedule: "Nuk ka orare", now: "Tani", future: "pas %@", past: "%@ më parë"),
        "sv": Words(nextIntake: "Nästa intag", intakeDue: "Dags för intag",
            due: "Nu", late: "Försenad", noPlan: "Ingen plan",
            noSchedule: "Inga scheman", now: "Nu", future: "om %@", past: "för %@ sedan"),
        "th": Words(nextIntake: "รับยาครั้งถัดไป", intakeDue: "ถึงเวลารับยา",
            due: "ถึงเวลา", late: "เลยกำหนด", noPlan: "ไม่มีแผน",
            noSchedule: "ไม่มีตารางเวลา", now: "ตอนนี้", future: "อีก %@", past: "%@ ที่ผ่านมา"),
        "uk": Words(nextIntake: "Наступний прийом", intakeDue: "Час прийому",
            due: "Час", late: "Прострочено", noPlan: "Немає плану",
            noSchedule: "Розкладу немає", now: "Зараз", future: "через %@", past: "%@ тому"),
        "ur": Words(nextIntake: "اگلی خوراک", intakeDue: "خوراک کا وقت",
            due: "وقت", late: "تاخیر", noPlan: "کوئی منصوبہ نہیں",
            noSchedule: "کوئی شیڈیول نہیں", now: "ابھی", future: "%@ میں", past: "%@ پہلے")
        // Toki Pona currently uses the English fallback rather than invented medical copy.
    ]
}
