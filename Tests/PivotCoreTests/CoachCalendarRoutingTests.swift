import XCTest
@testable import PivotCore

final class CoachCalendarRoutingTests: XCTestCase {
    private let choices = [
        CoachCalendarRouting.Choice(id: "email-personal-qa", title: "Personale QA <3", sourceID: "email-source-qa"),
        CoachCalendarRouting.Choice(id: "email-work-qa", title: "Lavoro QA", sourceID: "email-source-qa"),
        CoachCalendarRouting.Choice(id: "cloud-personal-qa", title: "Personale QA ❤️", sourceID: "cloud-source-qa")
    ]
    private func suggest(_ title: String = "Nuovo impegno", hint: String? = nil, settings: Settings) -> CoachCalendarRouting.Suggestion {
        CoachCalendarRouting.suggest(title: title, hint: hint, choices: choices, settings: settings)
    }
    func testAccountPreferenceDoesNotFallBackToCloudOrLastUnrelatedCalendar() {
        var settings = Settings(); settings.preferredNewEventSourceID = "email-source-qa"
        settings.preferredNewEventCalendarID = "cloud-personal-qa"
        XCTAssertNil(suggest(settings: settings).calendarID)
        XCTAssertNil(suggest(hint: "Personale QA ❤️", settings: settings).calendarID)
        XCTAssertEqual(suggest(hint: "Personale QA <3", settings: settings).calendarID, "email-personal-qa")
    }
    func testConfirmedTopicMatchesAcrossDifferentActivitiesAndAccents() {
        var settings = Settings(); settings.preferredNewEventSourceID = "email-source-qa"
        settings.calendarTopicRoutes = ["persona esempio": "email-personal-qa"]
        for title in ["Uscita con Persona Esempio", "Visita a Città QA con Pérsona Esempio", "Cena e Persona Esempio"] {
            XCTAssertEqual(suggest(title, settings: settings).calendarID, "email-personal-qa")
            XCTAssertEqual(suggest(title, settings: settings).reason, .rememberedTopic)
        }
        XCTAssertEqual(suggest(hint: "Persona Esempio", settings: settings).calendarID, "email-personal-qa")
    }
    func testTopicUsesCompleteWordsNotPersonSubstrings() {
        var settings = Settings(); settings.calendarTopicRoutes = ["lia": "email-personal-qa"]
        XCTAssertNil(suggest("Cena con Giulia", settings: settings).calendarID)
        XCTAssertEqual(suggest("Cena con Lia", settings: settings).calendarID, "email-personal-qa")
    }
    func testTwoDifferentMatchingDestinationsNeedAChoice() {
        var settings = Settings(); settings.calendarTopicRoutes = ["persona esempio": "email-personal-qa", "lavoro": "email-work-qa"]
        XCTAssertEqual(suggest("Lavoro con Persona Esempio", settings: settings).reason, .ambiguous)
        XCTAssertNil(suggest("Lavoro con Persona Esempio", settings: settings).calendarID)
    }
    func testExplicitAvailableCalendarTakesPriorityOverTopic() {
        var settings = Settings(); settings.calendarTopicRoutes = ["persona esempio": "email-personal-qa"]
        XCTAssertEqual(suggest("Persona Esempio", hint: "Lavoro QA", settings: settings).calendarID, "email-work-qa")
    }
    func testMissingAccountOrRemovedTopicNeverChoosesAnotherAccount() {
        var settings = Settings(); settings.preferredNewEventSourceID = "removed-source-qa"
        XCTAssertEqual(suggest(settings: settings).reason, .missingAccount)
        settings.preferredNewEventSourceID = "email-source-qa"
        settings.calendarTopicRoutes = ["persona esempio": "cloud-personal-qa"]
        XCTAssertEqual(suggest("Persona Esempio", settings: settings).reason, .missingDestination)
        settings.calendarTopicRoutes = ["persona esempio": "deleted-calendar-qa"]
        XCTAssertNil(suggest("Persona Esempio", settings: settings).calendarID)
    }
    func testUnknownHintCannotSilentlyUseLegacyDefault() {
        var settings = Settings(); settings.preferredNewEventCalendarID = "email-work-qa"
        XCTAssertEqual(suggest(settings: settings).calendarID, "email-work-qa")
        XCTAssertEqual(suggest(hint: "Unknown QA", settings: settings).reason, .unknownHint)
        settings.calendarCreationAliases = ["former name": "email-personal-qa"]
        XCTAssertEqual(suggest(hint: "Former name", settings: settings).calendarID, "email-personal-qa")
        settings.calendarCreationAliases = ["former name": "deleted-qa"]
        XCTAssertEqual(suggest(hint: "Former name", settings: settings).reason, .missingDestination)
    }
    func testDuplicateCalendarNamesAreResolvedOnlyWithinConfirmedAccount() {
        let duplicate = choices + [.init(id: "cloud-duplicate-qa", title: "Personale QA <3", sourceID: "cloud-source-qa")]
        var settings = Settings()
        XCTAssertNil(CoachCalendarRouting.suggest(title: "QA", hint: "Personale QA <3", choices: duplicate, settings: settings).calendarID)
        settings.preferredNewEventSourceID = "email-source-qa"
        XCTAssertEqual(CoachCalendarRouting.suggest(title: "QA", hint: "Personale QA <3", choices: duplicate, settings: settings).calendarID, "email-personal-qa")
    }
    func testConfirmedPreferenceUpdatesAreAtomicAndCanCorrectAnAssociation() throws {
        var settings = Settings()
        try CoachCalendarRouting.remember(topic: " Pérsona Esempio ", calendarID: "email-personal-qa", rememberAccount: true, choices: choices, settings: &settings)
        XCTAssertEqual(settings.preferredNewEventSourceID, "email-source-qa")
        XCTAssertEqual(settings.calendarTopicRoutes?["persona esempio"], "email-personal-qa")
        let before = settings
        XCTAssertThrowsError(try CoachCalendarRouting.remember(topic: "", calendarID: "cloud-personal-qa", rememberAccount: true, choices: choices, settings: &settings))
        XCTAssertEqual(settings, before)
        XCTAssertThrowsError(try CoachCalendarRouting.remember(topic: "QA", calendarID: "deleted-qa", rememberAccount: true, choices: choices, settings: &settings))
        try CoachCalendarRouting.remember(topic: "Persona Esempio", calendarID: "email-work-qa", rememberAccount: false, choices: choices, settings: &settings)
        XCTAssertEqual(settings.calendarTopicRoutes?.count, 1)
        XCTAssertEqual(settings.calendarTopicRoutes?["persona esempio"], "email-work-qa")
    }
    func testPreferencesRoundTripButDoNotEnterNetworkContext() throws {
        var data = AppData()
        try CoachCalendarRouting.remember(topic: "Persona Esempio", calendarID: "email-personal-qa", rememberAccount: true, choices: choices, settings: &data.settings)
        let restored = try BackupCodec.decode(BackupCodec.encodeCompact(data))
        XCTAssertEqual(restored.settings.calendarTopicRoutes, data.settings.calendarTopicRoutes)
        XCTAssertEqual(restored.settings.preferredNewEventSourceID, "email-source-qa")
        let snapshot = try CoachV8Snapshot.make(message: "Organizza la giornata", events: [], data: data, now: Date(), purpose: "conversation")
        let sent = String(decoding: snapshot.encodedRequest, as: UTF8.self)
        XCTAssertFalse(sent.contains("email-source-qa")); XCTAssertFalse(sent.contains("email-personal-qa"))
        XCTAssertFalse(sent.contains("persona esempio"))
    }
    func testInvalidRoutingPreferencesAreRejectedByBackup() {
        var data = AppData(); data.settings.calendarTopicRoutes = ["": "qa"]
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encodeCompact(data)))
        data.settings.calendarTopicRoutes = [String(repeating: "a", count: 81): "qa"]
        XCTAssertThrowsError(try BackupCodec.decode(BackupCodec.encodeCompact(data)))
    }
    func testParticipantInOriginalRequestCanRouteAGenericDraftTitle() {
        var settings = Settings(); settings.preferredNewEventSourceID = "email-source-qa"
        settings.calendarTopicRoutes = ["persona esempio": "email-personal-qa"]
        let result = CoachCalendarRouting.suggest(title: "Visita in città", hint: nil, choices: choices, settings: settings,
            context: "Domani vado a trovare Persona Esempio")
        XCTAssertEqual(result.calendarID, "email-personal-qa")
    }
    func testNegatedOrConflictingContextDoesNotGuessACalendar() {
        var settings = Settings(); settings.calendarTopicRoutes = ["persona esempio": "email-personal-qa", "lavoro": "email-work-qa"]
        for context in ["Non vado da Persona Esempio", "Domani Persona Esempio e lavoro"] {
            XCTAssertNil(CoachCalendarRouting.suggest(title: "Visita in città", hint: nil, choices: choices, settings: settings, context: context).calendarID)
        }
    }
    func testSuggestedAssociationDoesNotMixDestinationAndParticipant() {
        XCTAssertEqual(CoachCalendarRouting.suggestedTopic(title: "Città QA con Persona Esempio", hint: nil), "Persona Esempio")
        XCTAssertEqual(CoachCalendarRouting.suggestedTopic(title: "Vai a trovare Persona Esempio domani", hint: nil), "Persona Esempio")
        XCTAssertEqual(CoachCalendarRouting.suggestedTopic(title: "Un impegno generico", hint: nil), "")
    }
}
