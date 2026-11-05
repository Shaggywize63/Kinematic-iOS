//
//  SparkRayLeadActivityTests.swift
//  KinematicTests
//
//  Pure logic behind the Spark & Ray lead / activity round: the effective-client gate precedence, the
//  industry colour palette, the picked-address -> coordinates mapping, the activity-type list (server rows,
//  fallback, scheduling, custom types), the activity photo rules and the `activity_upcoming` notification route.
//

import XCTest
import Foundation
@testable import Kinematic

final class SparkRayLeadActivityTests: XCTestCase {

    private let sparkId = "c0218852-0a19-4dd0-b9fa-72f9e32ed0d8"
    private let otherId = "a1f67468-526e-4734-be3a-2cb132cc2804"

    // MARK: - effective client / gate precedence

    func testPickerSelectionWinsOverTheUsersOwnClient() {
        XCTAssertEqual(CRMClientScope.effectiveClientId(selected: otherId, userClientId: sparkId), otherId)
    }

    func testClientAdminWithNoPickerFallsBackToTheirOwnClient() {
        XCTAssertEqual(CRMClientScope.effectiveClientId(selected: nil, userClientId: sparkId), sparkId)
        XCTAssertEqual(CRMClientScope.effectiveClientId(selected: "  ", userClientId: sparkId), sparkId)
    }

    func testNothingSelectedAndNoUserClientIsNil() {
        XCTAssertNil(CRMClientScope.effectiveClientId(selected: nil, userClientId: nil))
        XCTAssertNil(CRMClientScope.effectiveClientId(selected: "", userClientId: " "))
    }

    func testSparkGateOpensForAClientAdminAndFollowsThePicker() {
        // A client admin pinned to Spark by their login (no picker): the gate is open.
        XCTAssertTrue(SparkJourney.isSpark(clientId: CRMClientScope.effectiveClientId(selected: nil, userClientId: sparkId)))
        // An org admin picking Spark in the header picker: open, even though their own client is another one.
        XCTAssertTrue(SparkJourney.isSpark(clientId: CRMClientScope.effectiveClientId(selected: sparkId, userClientId: otherId)))
        // An org admin whose picker is on another client stays closed even if their own login is Spark.
        XCTAssertFalse(SparkJourney.isSpark(clientId: CRMClientScope.effectiveClientId(selected: otherId, userClientId: sparkId)))
        // Everyone else stays closed.
        XCTAssertFalse(SparkJourney.isSpark(clientId: CRMClientScope.effectiveClientId(selected: nil, userClientId: otherId)))
        XCTAssertFalse(SparkJourney.isSpark(clientId: CRMClientScope.effectiveClientId(selected: nil, userClientId: nil)))
    }

    func testSparkGateIsCaseInsensitive() {
        XCTAssertTrue(SparkJourney.isSpark(clientId: CRMClientScope.effectiveClientId(selected: nil, userClientId: sparkId.uppercased())))
    }

    // MARK: - industry palette

    func testPaletteHasTheSevenColours() {
        XCTAssertEqual(SparkIndustries.color(for: "Manufacturing"), "#2563EB")
        XCTAssertEqual(SparkIndustries.color(for: "Automotive"), "#DC2626")
        XCTAssertEqual(SparkIndustries.color(for: "Pharma & Healthcare"), "#16A34A")
        XCTAssertEqual(SparkIndustries.color(for: "Food & Beverage"), "#F59E0B")
        XCTAssertEqual(SparkIndustries.color(for: "Construction & Infrastructure"), "#7C3AED")
        XCTAssertEqual(SparkIndustries.color(for: "Power & Energy"), "#0891B2")
        XCTAssertEqual(SparkIndustries.color(for: "Other"), "#6B7280")
    }

    func testPaletteMatchIsCaseAndWhitespaceInsensitive() {
        XCTAssertEqual(SparkIndustries.color(for: "  automotive "), "#DC2626")
        XCTAssertEqual(SparkIndustries.color(for: "POWER & ENERGY"), "#0891B2")
    }

    func testUnknownOrBlankIndustryIsGrey() {
        XCTAssertEqual(SparkIndustries.color(for: nil), "#6B7280")
        XCTAssertEqual(SparkIndustries.color(for: ""), "#6B7280")
        XCTAssertEqual(SparkIndustries.color(for: "Textiles"), "#6B7280")
    }

    func testEveryOptionHasItsOwnColourExceptOtherIsGrey() {
        let colours = SparkIndustries.options.map { SparkIndustries.color(for: $0) }
        XCTAssertEqual(Set(colours).count, SparkIndustries.options.count)
        XCTAssertEqual(SparkIndustries.color(for: SparkIndustries.options.last), SparkIndustries.otherHex)
    }

    func testHexParsesToUnitRGB() {
        let c = SparkIndustries.rgb(hex: "#2563EB")
        XCTAssertEqual(c.r, 0x25 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(c.g, 0x63 / 255.0, accuracy: 0.0001)
        XCTAssertEqual(c.b, 0xEB / 255.0, accuracy: 0.0001)
        // Malformed falls back to the grey rather than crashing.
        let bad = SparkIndustries.rgb(hex: "nope")
        XCTAssertEqual(bad.r, 0x6B / 255.0, accuracy: 0.01)
    }

    func testSubIndustryFieldKey() {
        XCTAssertEqual(SparkIndustries.subIndustryFieldKey, "industry_category")
        XCTAssertEqual(SparkIndustries.subIndustryLabel, "Sub-industry")
    }

    // MARK: - address -> coordinates

    private func detail(_ json: String) throws -> CRMPlaceDetail {
        try JSONDecoder().decode(CRMPlaceDetail.self, from: Data(json.utf8))
    }

    func testPickedPlaceMapsToItsCoordinates() throws {
        let d = try detail(#"{"address_line1":"Plot 4, MIDC","city":"Pune","state":"Maharashtra","postal_code":"411019","latitude":18.6298,"longitude":73.8001}"#)
        XCTAssertEqual(LeadAddressCoordinates.coordinate(from: d), LeadCoordinate(latitude: 18.6298, longitude: 73.8001))
    }

    func testPlaceWithoutUsableCoordinatesMapsToNil() throws {
        XCTAssertNil(LeadAddressCoordinates.coordinate(from: try detail(#"{"address_line1":"x"}"#)))
        XCTAssertNil(LeadAddressCoordinates.coordinate(from: try detail(#"{"latitude":0,"longitude":0}"#)))
        XCTAssertNil(LeadAddressCoordinates.coordinate(from: try detail(#"{"latitude":123.0,"longitude":73.8}"#)))
        XCTAssertNil(LeadAddressCoordinates.coordinate(from: try detail(#"{"latitude":18.6}"#)))
    }

    func testPickedAddressOverridesTheDeviceFixForSparkOnly() {
        let picked = LeadCoordinate(latitude: 18.6298, longitude: 73.8001)
        XCTAssertEqual(LeadAddressCoordinates.pickedOverride(isSpark: true, picked: picked), picked)
        XCTAssertNil(LeadAddressCoordinates.pickedOverride(isSpark: false, picked: picked))
        XCTAssertNil(LeadAddressCoordinates.pickedOverride(isSpark: true, picked: nil))
    }

    func testDeviceFixMayApplyUnlessSparkPickedAnAddress() {
        let picked = LeadCoordinate(latitude: 18.6, longitude: 73.8)
        XCTAssertFalse(LeadAddressCoordinates.deviceFixMayApply(isSpark: true, picked: picked))
        XCTAssertTrue(LeadAddressCoordinates.deviceFixMayApply(isSpark: true, picked: nil))   // no picked address: old behaviour
        XCTAssertTrue(LeadAddressCoordinates.deviceFixMayApply(isSpark: false, picked: picked))
    }

    func testFormFieldsUseSixDecimals() {
        let f = LeadAddressCoordinates.formFields(LeadCoordinate(latitude: 18.6298, longitude: 73.8001))
        XCTAssertEqual(f.latitude, "18.629800")
        XCTAssertEqual(f.longitude, "73.800100")
    }

    func testB2bAddressBlockShowsForSparkOrWhenTheClientEnabledIt() {
        XCTAssertTrue(LeadAddressCoordinates.b2bAddressShown(addressOnB2b: false, isSpark: true))
        XCTAssertTrue(LeadAddressCoordinates.b2bAddressShown(addressOnB2b: true, isSpark: false))
        XCTAssertFalse(LeadAddressCoordinates.b2bAddressShown(addressOnB2b: false, isSpark: false))
    }

    // MARK: - activity types

    private func types(_ json: String) throws -> [ActivityTypeDef] {
        try JSONDecoder().decode([ActivityTypeDef].self, from: Data(json.utf8))
    }

    private let serverJSON = """
    [
      {"id":"builtin:call","slug":"call","name":"Call","icon":"📞","color":null,"position":-1,"is_active":true,"is_system":true},
      {"id":"builtin:meeting","slug":"meeting","name":"Meeting","icon":"📅","color":null,"position":-1,"is_active":true,"is_system":true},
      {"id":"builtin:task","slug":"task","name":"Task","icon":"✅","color":null,"position":-1,"is_active":true,"is_system":true},
      {"id":"builtin:note","slug":"note","name":"Note","icon":"📝","color":null,"position":-1,"is_active":true,"is_system":true},
      {"id":"builtin:email","slug":"email","name":"Email","icon":"✉️","color":null,"position":-1,"is_active":true,"is_system":true},
      {"id":"builtin:sms","slug":"sms","name":"SMS","icon":"💬","color":null,"position":-1,"is_active":true,"is_system":true},
      {"id":"builtin:whatsapp","slug":"whatsapp","name":"WhatsApp","icon":"","color":null,"position":-1,"is_active":true,"is_system":true},
      {"id":"11111111-1111-1111-1111-111111111111","slug":"industry_visit","name":"Industry Visit","icon":"🏭","color":"#0891B2","position":2,"is_active":true,"is_system":false},
      {"id":"22222222-2222-2222-2222-222222222222","slug":"demo","name":"Demo","icon":null,"color":null,"position":1,"is_active":true,"is_system":false},
      {"id":"33333333-3333-3333-3333-333333333333","slug":"retired","name":"Retired","icon":null,"color":null,"position":0,"is_active":false,"is_system":false}
    ]
    """

    func testServerRowsDecode() throws {
        let all = try types(serverJSON)
        XCTAssertEqual(all.count, 10)
        XCTAssertEqual(all[0].id, "builtin:call")
        XCTAssertEqual(all[7].slug, "industry_visit")
        XCTAssertEqual(all[7].name, "Industry Visit")
        XCTAssertEqual(all[7].position, 2)
        XCTAssertEqual(all[7].isSystem, false)
    }

    func testDecodeToleratesMissingFields() throws {
        let all = try types(#"[{"slug":"site_visit"}]"#)
        XCTAssertEqual(all.first?.slug, "site_visit")
        XCTAssertEqual(all.first?.name, "Site Visit")
        XCTAssertEqual(all.first?.id, "builtin:site_visit")
    }

    func testSanitizeDropsInactiveAndFallsBackWhenEmpty() throws {
        let kept = ActivityTypes.sanitize(server: try types(serverJSON))
        XCTAssertFalse(kept.contains { $0.slug == "retired" })
        XCTAssertEqual(ActivityTypes.sanitize(server: nil), ActivityTypes.fallback)
        XCTAssertEqual(ActivityTypes.sanitize(server: []), ActivityTypes.fallback)
    }

    func testOfferedKeepsTheClassicFiveInOrderThenCustomTypesByPosition() throws {
        let offered = ActivityTypes.offered(ActivityTypes.sanitize(server: try types(serverJSON)))
        XCTAssertEqual(offered.map(\.slug), ["meeting", "call", "email", "note", "task", "demo", "industry_visit"])
    }

    func testFallbackOffersTheClassicFiveOnly() {
        XCTAssertEqual(ActivityTypes.offered(ActivityTypes.fallback).map(\.slug), ["meeting", "call", "email", "note", "task"])
        XCTAssertEqual(ActivityTypes.composerTypes(ActivityTypes.fallback, scheduled: false).map(\.slug),
                       ["meeting", "call", "email", "note", "task"])
    }

    func testSchedulingDropsNoteAndPutsTaskFirstButKeepsCustomTypes() throws {
        let all = ActivityTypes.sanitize(server: try types(serverJSON))
        XCTAssertEqual(ActivityTypes.composerTypes(all, scheduled: true).map(\.slug),
                       ["task", "meeting", "call", "email", "demo", "industry_visit"])
        XCTAssertEqual(ActivityTypes.composerTypes(ActivityTypes.fallback, scheduled: true).map(\.slug),
                       ["task", "meeting", "call", "email"])
    }

    func testComposerKeepsTheCurrentTypeEvenWhenNotOffered() throws {
        let all = ActivityTypes.sanitize(server: try types(serverJSON))
        let withSms = ActivityTypes.composerTypes(all, scheduled: false, ensuring: "sms")
        XCTAssertEqual(withSms.last?.slug, "sms")
        let unknown = ActivityTypes.composerTypes(all, scheduled: false, ensuring: "old_type")
        XCTAssertEqual(unknown.last?.slug, "old_type")
        XCTAssertEqual(unknown.last?.name, "Old Type")
        // Already offered: not duplicated.
        XCTAssertEqual(ActivityTypes.composerTypes(all, scheduled: false, ensuring: "call").filter { $0.slug == "call" }.count, 1)
    }

    func testFilterSlugsIncludeCustomTypesAndTheActiveFilter() throws {
        let all = ActivityTypes.sanitize(server: try types(serverJSON))
        XCTAssertTrue(ActivityTypes.filterSlugs(all).contains("industry_visit"))
        XCTAssertEqual(ActivityTypes.filterSlugs(all, ensuring: "sms").last, "sms")
        XCTAssertEqual(ActivityTypes.filterSlugs(all, ensuring: "all"), ActivityTypes.filterSlugs(all))
    }

    func testNameLookup() throws {
        let all = ActivityTypes.sanitize(server: try types(serverJSON))
        XCTAssertEqual(ActivityTypes.name(for: "industry_visit", in: all), "Industry Visit")
        XCTAssertEqual(ActivityTypes.name(for: "INDUSTRY_VISIT", in: all), "Industry Visit")
        XCTAssertEqual(ActivityTypes.name(for: "unknown_kind", in: all), "Unknown Kind")
        XCTAssertEqual(ActivityTypes.name(for: nil, in: all), "Activity")
        XCTAssertEqual(ActivityTypes.name(for: "sms", in: []), "SMS")
    }

    func testIconsAndColours() throws {
        let all = ActivityTypes.sanitize(server: try types(serverJSON))
        XCTAssertEqual(ActivityTypes.symbol(for: "call"), "phone.fill")
        XCTAssertEqual(ActivityTypes.symbol(for: "industry_visit"), "mappin.and.ellipse")
        XCTAssertEqual(ActivityTypes.symbol(for: "demo"), "tag.fill")
        // A custom type uses its own emoji; a built-in uses its SF Symbol instead.
        XCTAssertEqual(ActivityTypes.emoji(for: ActivityTypes.def(for: "industry_visit", in: all)), "🏭")
        XCTAssertNil(ActivityTypes.emoji(for: ActivityTypes.def(for: "call", in: all)))
        XCTAssertNil(ActivityTypes.emoji(for: ActivityTypes.def(for: "demo", in: all)))
        let c = ActivityTypes.rgb(hex: ActivityTypes.def(for: "industry_visit", in: all)?.color)
        XCTAssertEqual(c?.r ?? -1, 0x08 / 255.0, accuracy: 0.0001)
        XCTAssertNil(ActivityTypes.rgb(hex: nil))
        XCTAssertNil(ActivityTypes.rgb(hex: "teal"))
    }

    // MARK: - activity photo rules

    func testUploadedUrlIsUsed() {
        XCTAssertEqual(ActivityPhotoRules.outcome(uploadedUrl: "https://x/y.jpg", online: true), .uploaded("https://x/y.jpg"))
        XCTAssertEqual(ActivityPhotoRules.outcome(uploadedUrl: "https://x/y.jpg", online: false), .uploaded("https://x/y.jpg"))
    }

    func testFailedUploadIsSurfacedOnlineAndKeptOnDeviceOffline() {
        XCTAssertEqual(ActivityPhotoRules.outcome(uploadedUrl: nil, online: true), .failed)
        XCTAssertEqual(ActivityPhotoRules.outcome(uploadedUrl: " ", online: true), .failed)
        XCTAssertEqual(ActivityPhotoRules.outcome(uploadedUrl: nil, online: false), .keepOnDevice)
    }

    func testSaveWaitsForTheUploadAndNeverDropsAPickedPhoto() {
        XCTAssertTrue(ActivityPhotoRules.canSave(hasPickedPhoto: false, imageUrl: nil, uploading: false))
        XCTAssertFalse(ActivityPhotoRules.canSave(hasPickedPhoto: true, imageUrl: "https://x/y.jpg", uploading: true))
        XCTAssertFalse(ActivityPhotoRules.canSave(hasPickedPhoto: true, imageUrl: nil, uploading: false))
        XCTAssertTrue(ActivityPhotoRules.canSave(hasPickedPhoto: true, imageUrl: "https://x/y.jpg", uploading: false))
    }

    // MARK: - notifications

    func testUpcomingActivityOpensItsLeadOrDealElseTheActivitiesList() {
        let withLead = ["kind": "activity_upcoming", "activity_id": "A1", "lead_id": "L1", "offset_days": "3"]
        XCTAssertEqual(NotificationRoute.resolve(withLead), .lead("L1"))
        XCTAssertEqual(NotificationRoute.resolve(["kind": "activity_upcoming", "activity_id": "A1", "deal_id": "D1"]), .deal("D1"))
        // An account-only activity has no id-based screen: the Activities list.
        XCTAssertEqual(NotificationRoute.resolve(["kind": "activity_upcoming", "activity_id": "A1", "account_id": "AC1"]), .activities)
        XCTAssertEqual(NotificationRoute.forPush(["kind": "activity_upcoming", "activity_id": "A1", "notification_id": "N1"]), .activities)
    }
}
