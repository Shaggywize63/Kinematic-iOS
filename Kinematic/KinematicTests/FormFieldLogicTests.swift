//
//  FormFieldLogicTests.swift
//  KinematicTests
//
//  The form-builder question rules shared by the two form screens (route-plan and ad-hoc): which control each builder
//  type gets, how a date / time / date-and-time / multi-select / location answer is stored and shown, the rating's
//  size, and what blocks a submit (hidden questions, section headers, unticked required checkboxes, phone, e-mail,
//  number). Mirrors the Android FormFieldLogicTest.
//

import XCTest
@testable import Kinematic

@MainActor
final class FormFieldLogicTests: XCTestCase {

    private let a = FormOption(label: "Option A", value: "opt_a")
    private let b = FormOption(label: "Option B", value: "opt_b")

    private func field(
        id: String = "f1",
        type: String = "short_text",
        label: String = "Label",
        required: Bool = false,
        options: [FormOption]? = nil,
        keyboard: String? = nil,
        dependsOnId: String? = nil,
        dependsOnValue: String? = nil,
        stars: Double? = nil
    ) -> FormField {
        FormField(id: id, label: label, fieldKey: id, fieldType: type, isRequired: required, options: options,
                  dependsOnId: dependsOnId, dependsOnValue: dependsOnValue, keyboardType: keyboard, validationMax: stars)
    }

    private func problem(_ fields: [FormField], _ answers: [String: String] = [:]) -> FormFieldLogic.Problem? {
        FormFieldLogic.firstProblem(fields: fields, responses: answers)
    }

    // MARK: - which control

    func testEveryBuilderTypeGetsItsControl() {
        let expected: [(String, FormFieldLogic.Kind)] = [
            ("short_text", .text), ("text", .text), ("textarea", .longText), ("long_text", .longText),
            ("number", .number), ("email", .email), ("phone", .phone),
            ("radio", .radio), ("dropdown", .dropdown), ("select", .dropdown),
            ("yes_no", .yesNo), ("rating", .rating),
            ("date", .date), ("time", .time), ("datetime", .dateTime),
            ("image", .photo), ("photo", .photo), ("file", .file), ("signature", .signature),
            ("location", .location), ("gps", .location),
            ("section_header", .section), ("section", .section),
            ("consent", .checkbox), ("multi_select", .multiSelect),
        ]
        for (type, kind) in expected {
            XCTAssertEqual(FormFieldLogic.kindOf(fieldType: type, hasOptions: false), kind, type)
        }
    }

    func testACheckboxWithOptionsIsAMultiSelectWithoutOptionsOneBox() {
        XCTAssertEqual(FormFieldLogic.kindOf(fieldType: "checkbox", hasOptions: true), .multiSelect)
        XCTAssertEqual(FormFieldLogic.kindOf(fieldType: "checkbox", hasOptions: false), .checkbox)
        XCTAssertEqual(FormFieldLogic.kindOf(field(type: "checkbox", options: [a, b])), .multiSelect)
        XCTAssertEqual(FormFieldLogic.kindOf(field(type: "checkbox", options: [])), .checkbox)
        XCTAssertEqual(FormFieldLogic.kindOf(field(type: "checkbox", options: nil)), .checkbox)
        // a consent is always the single box, whatever it carries
        XCTAssertEqual(FormFieldLogic.kindOf(field(type: "consent", options: [a])), .checkbox)
    }

    func testTheTypeIsReadCaseInsensitivelyAndAnUnknownOneIsAPlainTextBox() {
        XCTAssertEqual(FormFieldLogic.kindOf(fieldType: " Time ", hasOptions: false), .time)
        XCTAssertEqual(FormFieldLogic.kindOf(fieldType: "DATETIME", hasOptions: false), .dateTime)
        XCTAssertEqual(FormFieldLogic.kindOf(fieldType: "hologram", hasOptions: false), .other)
        XCTAssertEqual(FormFieldLogic.kindOf(fieldType: "", hasOptions: false), .other)
        XCTAssertEqual(FormFieldLogic.kindOf(fieldType: nil, hasOptions: false), .other)
    }

    // MARK: - visibility

    func testAQuestionDependingOnAnotherIsShownOnlyForTheExpectedAnswerIgnoringCase() {
        let child = field(id: "c", dependsOnId: "p", dependsOnValue: "Yes")
        XCTAssertTrue(FormFieldLogic.isVisible(child, responses: ["p": "yes"]))
        XCTAssertTrue(FormFieldLogic.isVisible(child, responses: ["p": "YES"]))
        XCTAssertFalse(FormFieldLogic.isVisible(child, responses: ["p": "No"]))
        XCTAssertFalse(FormFieldLogic.isVisible(child, responses: [:]))
        XCTAssertTrue(FormFieldLogic.isVisible(field(), responses: [:]))
        XCTAssertTrue(FormFieldLogic.isVisible(field(dependsOnId: ""), responses: [:]))
        // pinned: a dependency with no expected value is met by an unanswered parent
        XCTAssertTrue(FormFieldLogic.isVisible(field(dependsOnId: "p", dependsOnValue: nil), responses: [:]))
    }

    // MARK: - required

    func testARequiredTextAnswerMustHoldSomethingOtherThanBlanks() {
        let f = field(label: "Name", required: true)
        XCTAssertEqual(problem([f]), FormFieldLogic.Problem(kind: .missing, label: "Name"))
        XCTAssertEqual(problem([f], ["f1": "   "])?.kind, .missing)
        XCTAssertNil(problem([f], ["f1": "Asha"]))
        // not required: blank is fine
        XCTAssertNil(problem([field()]))
    }

    func testARequiredCheckboxMustBeTickedTheStoredFalseIsNotAnAnswer() {
        let f = field(type: "checkbox", label: "I agree", required: true)
        XCTAssertEqual(problem([f])?.kind, .missing)
        XCTAssertEqual(problem([f], ["f1": "false"])?.kind, .missing)
        XCTAssertNil(problem([f], ["f1": "true"]))
        // a checkbox that is not required may stay unticked
        XCTAssertNil(problem([field(type: "checkbox")], ["f1": "false"]))
        // a required consent too
        XCTAssertEqual(problem([field(type: "consent", required: true)], ["f1": "false"])?.kind, .missing)
        // the consent switch writes true / false, and also reads yes / 1
        XCTAssertNil(problem([field(type: "consent", required: true)], ["f1": "true"]))
        XCTAssertNil(problem([field(type: "consent", required: true)], ["f1": "yes"]))
    }

    func testARequiredMultiSelectNeedsAtLeastOneOptionChosen() {
        let f = field(type: "checkbox", required: true, options: [a, b])
        XCTAssertEqual(problem([f])?.kind, .missing)
        XCTAssertEqual(problem([f], ["f1": ""])?.kind, .missing)
        XCTAssertNil(problem([f], ["f1": "opt_a,opt_b"]))
    }

    func testRequiredRatingDateTimeDatetimeAndLocationNeedAValue() {
        for type in ["rating", "date", "time", "datetime", "location"] {
            let f = field(type: type, required: true)
            XCTAssertEqual(problem([f])?.kind, .missing, type)
            XCTAssertNil(problem([f], ["f1": "x"]), type)
        }
    }

    func testAPhotoCountsAsAnsweredWhileItsPictureIsHeldOutsideTheAnswers() {
        let f = field(type: "photo", required: true)
        XCTAssertEqual(FormFieldLogic.firstProblem(fields: [f], responses: ["f1": ""], hasAsset: { _ in false })?.kind, .missing)
        XCTAssertNil(FormFieldLogic.firstProblem(fields: [f], responses: ["f1": ""], hasAsset: { id in id == "f1" }))
        XCTAssertTrue(FormFieldLogic.isMissing(f, value: "", hasAsset: false))
        XCTAssertFalse(FormFieldLogic.isMissing(f, value: "", hasAsset: true))
    }

    func testASectionHeaderIsNeverRequired() {
        XCTAssertNil(problem([field(type: "section_header", required: true)]))
        XCTAssertNil(problem([field(type: "section", required: true)]))
        XCTAssertFalse(FormFieldLogic.isMissing(field(type: "section_header", required: true), value: nil))
    }

    func testAQuestionHiddenByItsDependencyNeverBlocksTheSubmit() {
        let parent = field(id: "p", type: "yes_no")
        let child = field(id: "c", label: "Why", required: true, dependsOnId: "p", dependsOnValue: "Yes")
        XCTAssertNil(problem([parent, child], ["p": "No"]))
        XCTAssertNil(problem([parent, child]))
        // shown again -> required again
        XCTAssertEqual(problem([parent, child], ["p": "Yes"]), FormFieldLogic.Problem(kind: .missing, label: "Why"))
        XCTAssertNil(problem([parent, child], ["p": "Yes", "c": "Because"]))
        // a hidden bad phone does not block either
        let badPhone = field(id: "ph", type: "phone", dependsOnId: "p", dependsOnValue: "Yes")
        XCTAssertNil(problem([parent, badPhone], ["p": "No", "ph": "123"]))
    }

    // MARK: - phone, e-mail, number

    func testAPhoneAnswerNeedsTenDigits() {
        let f = field(type: "phone", label: "Mobile")
        XCTAssertEqual(problem([f], ["f1": "98765"]), FormFieldLogic.Problem(kind: .phone, label: "Mobile"))
        XCTAssertNil(problem([f], ["f1": "9876543210"]))
        XCTAssertNil(problem([f]))   // blank is the required check's business
        // by keyboard too
        XCTAssertEqual(problem([field(keyboard: "phone")], ["f1": "12"])?.kind, .phone)
        XCTAssertFalse(FormFieldLogic.isInvalidPhone("98765-43210"))   // ten digits, punctuation ignored
        XCTAssertTrue(FormFieldLogic.isInvalidPhone("+91 98765 43210"))
        XCTAssertFalse(FormFieldLogic.isInvalidPhone(""))
    }

    func testAnEmailIsCheckedForTheEmailTypeAndForTheEmailKeyboard() {
        let byType = field(type: "email", label: "Mail")
        let byKeyboard = field(type: "short_text", label: "Mail 2", keyboard: "email")
        XCTAssertEqual(problem([byType], ["f1": "not-an-email"]), FormFieldLogic.Problem(kind: .email, label: "Mail"))
        XCTAssertEqual(problem([byKeyboard], ["f1": "nope"])?.kind, .email)
        XCTAssertNil(problem([byType], ["f1": "asha@example.com"]))
        XCTAssertNil(problem([byType]))   // blank is fine unless required
        // the matcher can be injected
        XCTAssertEqual(FormFieldLogic.firstProblem(fields: [byType], responses: ["f1": "x@y"], isEmail: { _ in false })?.kind, .email)
        XCTAssertNil(FormFieldLogic.firstProblem(fields: [byType], responses: ["f1": "x@y"], isEmail: { _ in true }))
    }

    func testTheEmailMatcherAcceptsOrdinaryAddressesAndRejectsBrokenOnes() {
        for ok in ["a@b.co", "first.last+tag@sub.example.com", "o'brien@example.org", "x_y@e-x.in"] {
            XCTAssertTrue(FormFieldLogic.looksLikeEmail(ok), ok)
        }
        for bad in ["", "plain", "a@b", "@b.com", "a@.com", "a b@c.com", "a@b..com", "a@-b.com", "a@b.c om"] {
            XCTAssertFalse(FormFieldLogic.looksLikeEmail(bad), bad)
        }
    }

    func testANumberAnswerMustBeANumber() {
        let f = field(type: "number", label: "Qty")
        XCTAssertEqual(problem([f], ["f1": "12abc"]), FormFieldLogic.Problem(kind: .number, label: "Qty"))
        XCTAssertNil(problem([f], ["f1": "42"]))
        XCTAssertNil(problem([f], ["f1": "-3.5"]))
        XCTAssertNil(problem([f], ["f1": " "]))   // blank is the required check's business
        XCTAssertNil(problem([f]))
        for ok in ["12", "-3.5", "+7", ".5", "5.", " 42 ", "0"] { XCTAssertTrue(FormFieldLogic.isNumeric(ok), ok) }
        for bad in ["", " ", "abc", "1e5", "1,000", "--1", "NaN", "Infinity", "12abc", "1.2.3", "0x10", "."] {
            XCTAssertFalse(FormFieldLogic.isNumeric(bad), bad)
        }
        // only the number TYPE is checked; a text box with a number keyboard stays text
        XCTAssertNil(problem([field(keyboard: "number")], ["f1": "abc"]))
    }

    func testProblemsComeInTheOrderTheScreensUse() {
        let missing = field(id: "m", label: "Missing", required: true)
        let phone = field(id: "p", type: "phone", label: "Phone")
        let mail = field(id: "e", type: "email", label: "Mail")
        let num = field(id: "n", type: "number", label: "Num")
        let all = [num, mail, phone, missing]
        XCTAssertEqual(problem(all, ["p": "1", "e": "x", "n": "z"])?.kind, .missing)
        XCTAssertEqual(problem(all, ["m": "ok", "p": "1", "e": "x", "n": "z"])?.kind, .phone)
        XCTAssertEqual(problem(all, ["m": "ok", "p": "9876543210", "e": "x", "n": "z"])?.kind, .email)
        XCTAssertEqual(problem(all, ["m": "ok", "p": "9876543210", "e": "a@b.com", "n": "z"])?.kind, .number)
        XCTAssertNil(problem(all, ["m": "ok", "p": "9876543210", "e": "a@b.com", "n": "5"]))
        // the FIRST offending question in form order is the one named
        let two = [field(id: "x", label: "First", required: true), field(id: "y", label: "Second", required: true)]
        XCTAssertEqual(problem(two)?.label, "First")
    }

    // MARK: - the banner above the submit button

    func testTheBannerNamesEveryMissingQuestionFirst() {
        let one = [field(id: "x", label: "First", required: true)]
        XCTAssertEqual(FormFieldLogic.banner(fields: one, responses: [:]),
                       FormFieldLogic.Banner(title: "Fill these required field first", detail: "First"))
        let two = [field(id: "x", label: "First", required: true), field(id: "y", label: "Second", required: true)]
        XCTAssertEqual(FormFieldLogic.banner(fields: two, responses: [:]),
                       FormFieldLogic.Banner(title: "Fill these required fields first", detail: "First • Second"))
        XCTAssertNil(FormFieldLogic.banner(fields: two, responses: ["x": "a", "y": "b"]))
    }

    func testTheBannerNamesBadPhonesMailsAndNumbersOnceNothingIsMissing() {
        let phone = field(id: "p", type: "phone", label: "Mobile")
        let mail = field(id: "e", type: "email", label: "Mail")
        let num = field(id: "n", type: "number", label: "Qty")
        XCTAssertEqual(FormFieldLogic.banner(fields: [phone], responses: ["p": "123"]),
                       FormFieldLogic.Banner(title: "Enter a 10-digit mobile number", detail: "Mobile"))
        XCTAssertEqual(FormFieldLogic.banner(fields: [mail], responses: ["e": "x"]),
                       FormFieldLogic.Banner(title: "Enter a valid email address", detail: "Mail"))
        XCTAssertEqual(FormFieldLogic.banner(fields: [num], responses: ["n": "x"]),
                       FormFieldLogic.Banner(title: "Enter a valid number", detail: "Qty"))
        // the banner and firstProblem agree on what blocks
        XCTAssertNil(FormFieldLogic.banner(fields: [phone, mail, num], responses: ["p": "9876543210", "e": "a@b.com", "n": "4"]))
    }

    func testCompletionCountsOnlyRequiredQuestionsThatAreOnScreen() {
        XCTAssertEqual(FormFieldLogic.completion(fields: [field()], responses: [:]), 0.5)   // nothing required
        let two = [field(id: "x", required: true), field(id: "y", required: true)]
        XCTAssertEqual(FormFieldLogic.completion(fields: two, responses: ["x": "a"]), 0.5)
        XCTAssertEqual(FormFieldLogic.completion(fields: two, responses: ["x": "a", "y": "b"]), 1.0)
        XCTAssertEqual(FormFieldLogic.completion(fields: two, responses: [:]), 0.0)
        // a hidden required question is not counted
        let hidden = [field(id: "p", type: "yes_no"), field(id: "c", required: true, dependsOnId: "p", dependsOnValue: "Yes")]
        XCTAssertEqual(FormFieldLogic.completion(fields: hidden, responses: ["p": "No"]), 0.5)
    }

    // MARK: - rating

    func testARatingHasTheBuildersMaxFiveWhenItSaysNothing() {
        XCTAssertEqual(FormFieldLogic.ratingMax(nil), 5)
        XCTAssertEqual(FormFieldLogic.ratingMax(7), 7)
        XCTAssertEqual(FormFieldLogic.ratingMax(3), 3)
        XCTAssertEqual(FormFieldLogic.ratingMax(4.9), 4)
        XCTAssertEqual(FormFieldLogic.ratingMax(.nan), 5)
        XCTAssertEqual(FormFieldLogic.ratingMax(.infinity), 5)
    }

    func testTheRatingMaxIsKeptBetweenOneAndTen() {
        XCTAssertEqual(FormFieldLogic.ratingMax(0), 1)
        XCTAssertEqual(FormFieldLogic.ratingMax(-4), 1)
        XCTAssertEqual(FormFieldLogic.ratingMax(1), 1)
        XCTAssertEqual(FormFieldLogic.ratingMax(10), 10)
        XCTAssertEqual(FormFieldLogic.ratingMax(11), 10)
        XCTAssertEqual(FormFieldLogic.ratingMax(250), 10)
        XCTAssertEqual(FormFieldLogic.ratingMax(1e30), 10)
    }

    // MARK: - options

    func testADropdownShowsTheOptionsLabelAndKeepsStoringItsValue() {
        let opts = [a, b]
        XCTAssertEqual(FormFieldLogic.optionLabel(opts, value: "opt_b"), "Option B")
        XCTAssertEqual(FormFieldLogic.optionLabel(opts, value: ""), "")
        // an answer that matches no option shows as stored
        XCTAssertEqual(FormFieldLogic.optionLabel(opts, value: "legacy"), "legacy")
        XCTAssertEqual(FormFieldLogic.optionLabel(nil, value: "opt_a"), "opt_a")
        XCTAssertEqual(FormFieldLogic.optionLabel([FormOption(label: "  ", value: "x")], value: "x"), "x")
    }

    func testMultiSelectAnswersAreCommaJoinedOptionValuesInTheOrderChosen() {
        XCTAssertEqual(FormFieldLogic.selectedValues(""), [])
        XCTAssertEqual(FormFieldLogic.selectedValues("a,b,,a"), ["a", "b"])
        XCTAssertEqual(FormFieldLogic.toggleSelected("", optionValue: "opt_a", checked: true), "opt_a")
        XCTAssertEqual(FormFieldLogic.toggleSelected("opt_a", optionValue: "opt_b", checked: true), "opt_a,opt_b")
        XCTAssertEqual(FormFieldLogic.toggleSelected("opt_b", optionValue: "opt_a", checked: true), "opt_b,opt_a")
        XCTAssertEqual(FormFieldLogic.toggleSelected("opt_a,opt_b", optionValue: "opt_a", checked: false), "opt_b")
        XCTAssertEqual(FormFieldLogic.toggleSelected("opt_b", optionValue: "opt_b", checked: false), "")
        // ticking what is ticked, or unticking what is not, changes nothing
        XCTAssertEqual(FormFieldLogic.toggleSelected("opt_a", optionValue: "opt_a", checked: true), "opt_a")
        XCTAssertEqual(FormFieldLogic.toggleSelected("opt_a", optionValue: "opt_z", checked: false), "opt_a")
    }

    // MARK: - date, time, datetime

    func testADateIsStoredAsYyyyMmDd() {
        let d = FormDay(year: 2026, month: 10, day: 11)
        XCTAssertEqual(FormFieldLogic.formatDate(d), "2026-10-11")
        XCTAssertEqual(FormFieldLogic.formatDate(FormDay(year: 2026, month: 1, day: 5)), "2026-01-05")
        XCTAssertEqual(FormFieldLogic.parseDate("2026-10-11"), d)
        XCTAssertEqual(FormFieldLogic.parseDate("2026-10-11T08:00:00Z"), d)
        XCTAssertEqual(FormFieldLogic.parseDate(" 2026-10-11 "), d)
        for bad in [nil, "", "11/10/2026", "2026-13-40", "abcdefghij", "2026-10", "2026-02-30"] {
            XCTAssertNil(FormFieldLogic.parseDate(bad), bad ?? "nil")
        }
        XCTAssertEqual(FormFieldLogic.parseDate("2028-02-29"), FormDay(year: 2028, month: 2, day: 29))   // a leap day
        XCTAssertEqual(FormFieldLogic.friendlyDate(d), "11 Oct 2026")
    }

    func testATimeIsStoredAsHhMmAndShownOnATwelveHourClock() {
        XCTAssertEqual(FormFieldLogic.formatTime(hour: 7, minute: 5), "07:05")
        XCTAssertEqual(FormFieldLogic.formatTime(hour: 16, minute: 30), "16:30")
        XCTAssertEqual(FormFieldLogic.formatTime(hour: 0, minute: 0), "00:00")
        XCTAssertEqual(FormFieldLogic.friendlyTime(hour: 0, minute: 0), "12:00 AM")
        XCTAssertEqual(FormFieldLogic.friendlyTime(hour: 0, minute: 15), "12:15 AM")
        XCTAssertEqual(FormFieldLogic.friendlyTime(hour: 9, minute: 5), "9:05 AM")
        XCTAssertEqual(FormFieldLogic.friendlyTime(hour: 11, minute: 59), "11:59 AM")
        XCTAssertEqual(FormFieldLogic.friendlyTime(hour: 12, minute: 0), "12:00 PM")
        XCTAssertEqual(FormFieldLogic.friendlyTime(hour: 12, minute: 30), "12:30 PM")
        XCTAssertEqual(FormFieldLogic.friendlyTime(hour: 16, minute: 30), "4:30 PM")
        XCTAssertEqual(FormFieldLogic.friendlyTime(hour: 23, minute: 59), "11:59 PM")
    }

    func testAStoredTimeIsReadBackAndShownFriendly() {
        XCTAssertEqual(FormFieldLogic.parseTime("16:30"), FormClock(hour: 16, minute: 30))
        XCTAssertEqual(FormFieldLogic.parseTime("7:05"), FormClock(hour: 7, minute: 5))
        XCTAssertEqual(FormFieldLogic.parseTime("07:05:00"), FormClock(hour: 7, minute: 5))
        XCTAssertEqual(FormFieldLogic.parseTime(" 23:59 "), FormClock(hour: 23, minute: 59))
        for bad in [nil, "", "24:00", "12:60", "abc", "1630", "16:3", "-1:30", "16:30pm"] {
            XCTAssertNil(FormFieldLogic.parseTime(bad), bad ?? "nil")
        }
        XCTAssertEqual(FormFieldLogic.timeDisplay("16:30"), "4:30 PM")
        XCTAssertEqual(FormFieldLogic.timeDisplay(nil), "")
        XCTAssertEqual(FormFieldLogic.timeDisplay("  "), "")
        // a value that cannot be read is shown as stored, never hidden
        XCTAssertEqual(FormFieldLogic.timeDisplay("around noon"), "around noon")
        // what the picker stores is what is read back
        XCTAssertEqual(FormFieldLogic.parseTime(FormFieldLogic.formatTime(hour: 9, minute: 5)), FormClock(hour: 9, minute: 5))
    }

    func testADateAndTimeIsStoredAsYyyyMmDdTHhMmAndShownInPlainWords() {
        let d = FormDay(year: 2026, month: 10, day: 11)
        XCTAssertEqual(FormFieldLogic.formatDateTime(d, hour: 16, minute: 30), "2026-10-11T16:30")
        XCTAssertEqual(FormFieldLogic.formatDateTime(FormDay(year: 2026, month: 1, day: 5), hour: 9, minute: 5), "2026-01-05T09:05")
        XCTAssertEqual(FormFieldLogic.friendlyDateTime(d, hour: 16, minute: 30), "11 Oct 2026, 4:30 PM")
        XCTAssertEqual(FormFieldLogic.friendlyDateTime(FormDay(year: 2026, month: 1, day: 5), hour: 0, minute: 5), "5 Jan 2026, 12:05 AM")
        XCTAssertEqual(FormFieldLogic.dateTimeDisplay("2026-10-11T16:30"), "11 Oct 2026, 4:30 PM")
        XCTAssertEqual(FormFieldLogic.dateTimeDisplay(""), "")
        XCTAssertEqual(FormFieldLogic.dateTimeDisplay(nil), "")
        XCTAssertEqual(FormFieldLogic.dateTimeDisplay("someday"), "someday")
    }

    func testAStoredDateAndTimeIsReadBackInTheShapesItMayComeIn() {
        let want = FormDateTimeParts(date: FormDay(year: 2026, month: 10, day: 11), hour: 16, minute: 30)
        for shape in ["2026-10-11T16:30", "2026-10-11T16:30:00", "2026-10-11 16:30", "2026-10-11T16:30:00.123Z",
                      "2026-10-11T16:30:00+05:30", " 2026-10-11T16:30 "] {
            XCTAssertEqual(FormFieldLogic.parseDateTime(shape), want, shape)
        }
        for bad in [nil, "", "2026-10-11", "16:30", "2026-13-40T10:00", "2026-10-11T25:00", "2026-10-11T10:61", "x"] {
            XCTAssertNil(FormFieldLogic.parseDateTime(bad), bad ?? "nil")
        }
        // round trip
        let stored = FormFieldLogic.formatDateTime(want.date, hour: want.hour, minute: want.minute)
        XCTAssertEqual(FormFieldLogic.parseDateTime(stored), want)
        XCTAssertTrue(FormFieldLogic.dateTimeHasZone("2026-10-11T16:30:00Z"))
        XCTAssertFalse(FormFieldLogic.dateTimeHasZone("2026-10-11T16:30"))
    }

    func testThePickersMomentIsTheDayAndTimeOnTheRepsClock() throws {
        let ist = try XCTUnwrap(TimeZone(identifier: "Asia/Kolkata"))
        let utc = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let day = FormDay(year: 2026, month: 10, day: 11)
        let moment = try XCTUnwrap(FormFieldLogic.moment(day: day, hour: 16, minute: 30, timeZone: ist))
        // 16:30 in India is 11:00 UTC
        XCTAssertEqual(moment.timeIntervalSince1970, 1_791_716_400)
        XCTAssertEqual(FormFieldLogic.parts(of: moment, timeZone: ist), FormDateTimeParts(date: day, hour: 16, minute: 30))
        XCTAssertEqual(FormFieldLogic.parts(of: moment, timeZone: utc), FormDateTimeParts(date: day, hour: 11, minute: 0))
        // the date at noon stays on its day in any zone the phone may be in
        let noon = try XCTUnwrap(FormFieldLogic.moment(day: day, hour: 12, minute: 0, timeZone: ist))
        XCTAssertEqual(FormFieldLogic.parts(of: noon, timeZone: ist)?.date, day)
    }

    // MARK: - location

    func testACapturedPositionIsStoredAsLatLngWithSixDecimals() {
        XCTAssertEqual(FormFieldLogic.formatLatLng(lat: 12.9715987, lng: 77.5945627), "12.971599,77.594563")
        XCTAssertEqual(FormFieldLogic.formatLatLng(lat: -33.8688, lng: 151.2093), "-33.868800,151.209300")
        XCTAssertEqual(FormFieldLogic.formatLatLng(lat: 0, lng: 0), "0.000000,0.000000")
        XCTAssertEqual(FormFieldLogic.formatLatLng(lat: 90, lng: 180), "90.000000,180.000000")
        // a position that cannot be real is never stored
        XCTAssertNil(FormFieldLogic.formatLatLng(lat: 91, lng: 10))
        XCTAssertNil(FormFieldLogic.formatLatLng(lat: 10, lng: -181))
        XCTAssertNil(FormFieldLogic.formatLatLng(lat: .nan, lng: 10))
        XCTAssertNil(FormFieldLogic.formatLatLng(lat: 10, lng: .infinity))
    }

    func testAStoredPositionIsShownWithASpaceAfterTheComma() {
        XCTAssertEqual(FormFieldLogic.locationDisplay("12.971599,77.594563"), "12.971599, 77.594563")
        XCTAssertEqual(FormFieldLogic.locationDisplay(" 12.97 , 77.59 "), "12.97, 77.59")
        XCTAssertEqual(FormFieldLogic.locationDisplay(nil), "")
        XCTAssertEqual(FormFieldLogic.locationDisplay(""), "")
        XCTAssertEqual(FormFieldLogic.locationDisplay("Main Street"), "Main Street")
        XCTAssertEqual(FormFieldLogic.locationDisplay("1,2,3"), "1,2,3")
    }

    // MARK: - decoding what the server sends

    private func decodeField(_ extra: String) throws -> FormField {
        let json = #"{"id":"q1","label":"How was it?","field_key":"how","field_type":"rating","is_required":true,"sort_order":1\#(extra)}"#
        return try JSONDecoder().decode(FormField.self, from: Data(json.utf8))
    }

    func testAQuestionWithoutValidationDecodesAndRatesOutOfFive() throws {
        let f = try decodeField("")
        XCTAssertNil(f.validationMax)
        XCTAssertEqual(FormFieldLogic.ratingMax(f.validationMax), 5)
    }

    func testTheBuildersValidationMaxReachesTheRating() throws {
        XCTAssertEqual(FormFieldLogic.ratingMax(try decodeField(#","validation":{"max":7}"#).validationMax), 7)
        XCTAssertEqual(FormFieldLogic.ratingMax(try decodeField(#","validation":{"max":"3"}"#).validationMax), 3)
        XCTAssertEqual(FormFieldLogic.ratingMax(try decodeField(#","validation":{"max":" 6 "}"#).validationMax), 6)
        XCTAssertEqual(FormFieldLogic.ratingMax(try decodeField(#","validation":{"min":1,"max":10,"step":1}"#).validationMax), 10)
    }

    func testWhateverTheServerPutsInValidationTheQuestionStillDecodes() throws {
        let junk = ["null", "{}", "\"\"", "\"text\"", "[]", "[1,2]", "5", "true", #"{"max":null}"#, #"{"max":{"deep":1}}"#,
                    #"{"max":"abc"}"#, #"{"max":true}"#, #"{"max":[3]}"#]
        for v in junk {
            let f = try decodeField(#","validation":\#(v)"#)
            XCTAssertEqual(f.id, "q1", v)
            XCTAssertEqual(FormFieldLogic.ratingMax(f.validationMax), 5, v)
        }
    }

    func testAQuestionSurvivesATripThroughJsonWithItsValidation() throws {
        let f = try decodeField(#","validation":{"max":6}"#)
        let back = try JSONDecoder().decode(FormField.self, from: JSONEncoder().encode(f))
        XCTAssertEqual(back.validationMax, 6)
        XCTAssertEqual(FormFieldLogic.ratingMax(back.validationMax), 6)
        // a question without it stays without it
        let plain = try JSONDecoder().decode(FormField.self, from: JSONEncoder().encode(try decodeField("")))
        XCTAssertNil(plain.validationMax)
    }

    func testAWholeFormDecodesWithAndWithoutValidationAndKeepsItsOptions() throws {
        let json = """
        {"id":"t1","activity_id":"a1","name":"Visit","description":null,"requires_photo":false,"requires_gps":true,
         "form_fields":[
           {"id":"q1","label":"Rating","field_key":"r","field_type":"rating","is_required":false,"sort_order":1,"validation":{"max":4}},
           {"id":"q2","label":"Flavours","field_key":"f","field_type":"checkbox","is_required":false,"sort_order":2,
            "options":[{"label":"Mango","value":"mango"},{"label":"Lime","value":"lime"}]},
           {"id":"q3","label":"When","field_key":"w","field_type":"datetime","is_required":true,"sort_order":3}
         ]}
        """
        let t = try JSONDecoder().decode(FormTemplate.self, from: Data(json.utf8))
        let fields = try XCTUnwrap(t.fields)
        XCTAssertEqual(fields.count, 3)
        XCTAssertEqual(FormFieldLogic.ratingMax(fields[0].validationMax), 4)
        XCTAssertEqual(FormFieldLogic.kindOf(fields[1]), .multiSelect)
        XCTAssertEqual(FormFieldLogic.optionLabel(fields[1].options, value: "lime"), "Lime")
        XCTAssertEqual(FormFieldLogic.kindOf(fields[2]), .dateTime)
        XCTAssertNil(fields[2].validationMax)
    }
}
