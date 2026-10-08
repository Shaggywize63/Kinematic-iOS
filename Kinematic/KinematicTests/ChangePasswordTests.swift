//
//  ChangePasswordTests.swift
//  KinematicTests
//
//  The client-side rules behind Settings → Change password (and the forced first-login screen):
//  what must be filled in before "Update password" is enabled, and the server's 10-character minimum
//  (the app used to say 6). The server stays the authority for the other password rules — common
//  passwords, repeated characters, keyboard sequences — and its message is shown as-is.
//

import XCTest
@testable import Kinematic

@MainActor
final class ChangePasswordTests: XCTestCase {

    private let good = "river-Stone-42"   // 14 chars, nothing the app itself would refuse

    // MARK: - a complete, valid change

    func testAValidChangeHasNoProblem() {
        XCTAssertNil(PasswordPolicy.passwordProblem(current: "old-password-1", new: good, confirm: good))
    }

    // MARK: - current password

    func testCurrentPasswordIsRequired() {
        XCTAssertEqual(PasswordPolicy.passwordProblem(current: "", new: good, confirm: good),
                       "Enter your current password.")
    }

    func testCurrentIsReportedBeforeAnythingElse() {
        // Everything is wrong, but the first field on screen is the one named.
        XCTAssertEqual(PasswordPolicy.passwordProblem(current: "", new: "", confirm: "x"),
                       "Enter your current password.")
    }

    // MARK: - length (server minimum is 10, not 6)

    func testNineCharactersIsTooShortAndTenIsEnough() {
        XCTAssertEqual(PasswordPolicy.newPasswordProblem("abcdefghi"), PasswordPolicy.tooShortMessage)
        XCTAssertNil(PasswordPolicy.newPasswordProblem("abcdefghij"))
    }

    func testSixCharactersIsNoLongerEnough() {
        XCTAssertEqual(PasswordPolicy.newPasswordProblem("abc123"), PasswordPolicy.tooShortMessage)
        XCTAssertEqual(PasswordPolicy.passwordProblem(current: "old-password-1", new: "abc123", confirm: "abc123"),
                       PasswordPolicy.tooShortMessage)
    }

    func testAnEmptyNewPasswordIsTooShort() {
        XCTAssertEqual(PasswordPolicy.newPasswordProblem(""), PasswordPolicy.tooShortMessage)
    }

    func testTheLongestAcceptedPasswordIs200Characters() {
        XCTAssertNil(PasswordPolicy.newPasswordProblem(String(repeating: "a", count: 200)))
        XCTAssertEqual(PasswordPolicy.newPasswordProblem(String(repeating: "a", count: 201)),
                       PasswordPolicy.tooLongMessage)
    }

    func testLengthIsCountedLikeTheServerDoes() {
        // JavaScript's `string.length` counts UTF-16 code units: five emoji are 10 of them.
        let emoji = "😀😃😄😁😆"
        XCTAssertEqual(emoji.count, 5)
        XCTAssertNil(PasswordPolicy.newPasswordProblem(emoji))
    }

    func testTheShownTextAgreesWithTheMinimum() {
        XCTAssertEqual(PasswordPolicy.minLength, 10)
        XCTAssertTrue(PasswordPolicy.tooShortMessage.contains("\(PasswordPolicy.minLength)"))
        XCTAssertTrue(PasswordPolicy.placeholder.contains("\(PasswordPolicy.minLength)"))
        XCTAssertTrue(PasswordPolicy.hint.contains("\(PasswordPolicy.minLength)"))
        XCTAssertTrue(PasswordPolicy.tooLongMessage.contains("\(PasswordPolicy.maxLength)"))
        XCTAssertFalse(PasswordPolicy.hint.contains("6 characters"))
    }

    func testLengthIsReportedBeforeTheMismatch() {
        XCTAssertEqual(PasswordPolicy.passwordProblem(current: "old-password-1", new: "short", confirm: "different"),
                       PasswordPolicy.tooShortMessage)
    }

    // MARK: - new must differ from current

    func testNewPasswordMustDifferFromTheCurrentOne() {
        XCTAssertEqual(PasswordPolicy.passwordProblem(current: good, new: good, confirm: good),
                       "Your new password must be different from the current one.")
    }

    func testDifferingOnlyByCaseIsADifferentPassword() {
        XCTAssertNil(PasswordPolicy.passwordProblem(current: "River-Stone-42", new: "river-Stone-42", confirm: "river-Stone-42"))
    }

    // MARK: - confirmation

    func testConfirmationMustMatch() {
        XCTAssertEqual(PasswordPolicy.passwordProblem(current: "old-password-1", new: good, confirm: good + "x"),
                       "Passwords do not match.")
    }

    func testAnEmptyConfirmationDoesNotMatch() {
        XCTAssertEqual(PasswordPolicy.passwordProblem(current: "old-password-1", new: good, confirm: ""),
                       "Passwords do not match.")
    }

    func testPasswordsAreNeverTrimmed() {
        // A trailing space is part of the password, so it must be confirmed exactly.
        XCTAssertEqual(PasswordPolicy.passwordProblem(current: "old-password-1", new: good + " ", confirm: good),
                       "Passwords do not match.")
        XCTAssertNil(PasswordPolicy.passwordProblem(current: "old-password-1", new: good + " ", confirm: good + " "))
    }
}
