//
//  FormFieldControls.swift
//  Kinematic
//
//  Form-builder question controls added with the "proper inputs" work: a real date, time and date-and-time picker
//  (one control, three modes), and the single yes/no checkbox. The rules they follow (what is stored, how it is shown)
//  are in `FormFieldLogic`; the rest of the controls live in ActivitySubmissionView.swift.
//

import SwiftUI
import UIKit

/// Which picker a `FormMomentField` shows.
enum FormMomentMode: Equatable {
    case date
    case time
    case dateTime
}

/// How a `FormMomentField` stores what was picked.
enum FormMomentStorage: Equatable {
    /// The rep's own wall clock, no zone: `yyyy-MM-dd`, `HH:mm`, `yyyy-MM-dd'T'HH:mm` (the form-builder questions).
    case local
    /// An ISO instant in UTC, `yyyy-MM-dd'T'HH:mm:ss'Z'` (the CRM `datetime` custom field; `CrmDateTime`).
    case utcInstant
}

/// A date, time or date-and-time question. Nothing is stored until the rep taps "Select …" (a picker that opens on
/// today's date but holds no value would let a required question pass unanswered); once set, a compact system picker
/// edits it and a clear button empties it again.
///
/// Stored as `yyyy-MM-dd`, `HH:mm` or `yyyy-MM-dd'T'HH:mm` on the rep's own clock (`FormFieldLogic`).
struct FormMomentField: View {
    let mode: FormMomentMode
    var storage: FormMomentStorage = .local
    @Binding var value: String
    var placeholder: String

    private var components: DatePickerComponents {
        switch mode {
        case .date:     return .date
        case .time:     return .hourAndMinute
        case .dateTime: return [.date, .hourAndMinute]
        }
    }

    private var icon: String {
        switch mode {
        case .date:     return "calendar"
        case .time:     return "clock"
        case .dateTime: return "calendar.badge.clock"
        }
    }

    /// The moment the stored value stands for; nil when nothing (readable) is stored.
    private var storedMoment: Date? {
        switch mode {
        case .date:
            guard let d = FormFieldLogic.parseDate(value) else { return nil }
            return FormFieldLogic.moment(day: d, hour: 12, minute: 0)
        case .time:
            guard let c = FormFieldLogic.parseTime(value) else { return nil }
            let today: FormDay? = FormFieldLogic.parts(of: Date())?.date
            guard let day = today else { return nil }
            return FormFieldLogic.moment(day: day, hour: c.hour, minute: c.minute)
        case .dateTime:
            if storage == .utcInstant {
                // Shown on the rep's own clock; the day and time are re-read from the instant.
                guard let p = CrmDateTime.localParts(value) else { return nil }
                return FormFieldLogic.moment(day: p.date, hour: p.hour, minute: p.minute)
            }
            guard let p = FormFieldLogic.parseDateTime(value) else { return nil }
            return FormFieldLogic.moment(day: p.date, hour: p.hour, minute: p.minute)
        }
    }

    /// What is stored for a picker answer.
    private func stored(from date: Date) -> String {
        guard let p = FormFieldLogic.parts(of: date) else { return value }
        switch mode {
        case .date:     return FormFieldLogic.formatDate(p.date)
        case .time:     return FormFieldLogic.formatTime(hour: p.hour, minute: p.minute)
        case .dateTime:
            if storage == .utcInstant { return CrmDateTime.store(p) ?? value }
            return FormFieldLogic.formatDateTime(p.date, hour: p.hour, minute: p.minute)
        }
    }

    private var pickerBinding: Binding<Date> {
        Binding<Date>(
            get: { storedMoment ?? Date() },
            set: { newDate in value = stored(from: newDate) }
        )
    }

    var body: some View {
        Group {
            if storedMoment != nil {
                HStack(spacing: 10) {
                    DatePicker("", selection: pickerBinding, displayedComponents: components)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                    Spacer(minLength: 0)
                    Button {
                        value = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
            } else {
                Button {
                    value = stored(from: Date())
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: icon)
                            .foregroundColor(.red)
                        Text(placeholder)
                            .foregroundColor(.secondary)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .cornerRadius(10)
    }
}

/// A single yes/no checkbox question (a builder `checkbox` without options). Stores `true` / `false`; a required one
/// counts as answered only when it is on (`FormFieldLogic.isMissing`).
struct SingleCheckboxField: View {
    @Binding var value: String

    private var isOn: Bool { FormFieldLogic.isAffirmative(value) }

    var body: some View {
        Toggle(isOn: Binding<Bool>(
            get: { isOn },
            set: { on in value = FormFieldLogic.checkboxValue(on) }
        )) {
            Text(isOn ? "Yes" : "No")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isOn ? .primary : .secondary)
        }
        .toggleStyle(SwitchToggleStyle(tint: .green))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .cornerRadius(10)
    }
}
