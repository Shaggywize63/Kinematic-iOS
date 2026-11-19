//
//  KinematicWidgetControl.swift
//  KinematicWidget
//
//  Control Center toggle: "Check In". Lives in the KinematicWidgetExtension
//  target alongside the home-screen widgets (already iOS 18.0 in every one
//  of its own build configs — see KinematicWidgetBundle.swift — but CI's
//  `xcodebuild -target Kinematic` smoke build still resolves the Swift
//  frontend for this file to -target ...-ios17.0-simulator, so every
//  Control-only symbol below is explicitly @available-gated rather than
//  relying on the target's own deployment target).
//
//  A real check-in needs a fresh GPS fix and, for most roles, a selfie
//  (AttendancePunch.selfieDemanded) — neither of which a Control can gather
//  in its own short-lived, UI-less process. So this never calls the
//  attendance API itself: it reflects the REAL cached status (read-only,
//  from the same App Group cache the Field Force home-screen widget already
//  reads) and, when tapped, opens the app — exactly what that widget's own
//  "Check in" link already does (KinematicFieldForceWidget.swift). The app
//  then completes the real punch through its normal flow, selfie and all.
//
//  The toggle therefore never lies: perform() does not flip any state, so
//  once WidgetKit next asks for the current value, the control settles back
//  to whatever is actually true.
//

import AppIntents
import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct KinematicWidgetControl: ControlWidget {
    static let kind: String = "com.shaggywize63.kinematic.checkin"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: Self.kind,
            provider: Provider()
        ) { isCheckedIn in
            ControlWidgetToggle(
                "Check In",
                isOn: isCheckedIn,
                action: ToggleCheckInControlIntent()
            ) { isOn in
                Label(
                    isOn ? "Checked In" : "Check In",
                    systemImage: isOn ? "checkmark.circle.fill" : "location.fill"
                )
            }
        }
        .displayName("Check In")
        .description("Shows whether you're checked in. Tap to open Kinematic and check in or out.")
    }

    struct Provider: ControlValueProvider {
        var previewValue: Bool { false }
        func currentValue() async throws -> Bool {
            FieldForceWidgetCache.read()?.checkedIn ?? false
        }
    }
}

/// Opens the app so the rep can complete a real check-in / check-out (GPS + selfie, where required).
/// Never performs the punch itself — see the file header.
@available(iOS 18.0, *)
struct ToggleCheckInControlIntent: SetValueIntent {
    static var title: LocalizedStringResource = "Toggle Check-In"
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Checked In")
    var value: Bool

    func perform() async throws -> some IntentResult {
        .result()
    }
}
