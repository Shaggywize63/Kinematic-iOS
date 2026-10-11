//
//  TravelPromptViews.swift
//  Kinematic
//
//  "Add today's travel to expenses?" — the sheet that follows the final check-out, and the card on Home that is the way
//  back into it (also the way in when the check-out was queued offline and could not be asked about).
//
//  Opt-in by DATA: nothing here shows unless the rep's expense policy says `gps_distance: true` with vehicle rates and
//  the client has the expenses module. All the rules (when to offer, what the server's answer means, the amount, the
//  claim body, what "Not now" remembers) live in `TravelPrompt` / `TravelPromptModel` and are unit-tested.
//

import SwiftUI
import UIKit

/// The small card on Home after check-out, until the travel is added or the card is closed for the day.
struct TravelPromptCard: View {
    @ObservedObject private var model = TravelPromptModel.shared
    @ObservedObject private var appState = KiniAppState.shared

    private var shiftCompleted: Bool {
        appState.today?.checkinAt != nil && appState.today?.checkoutAt != nil
    }

    var body: some View {
        if TravelPrompt.showCard(eligible: model.eligible, shiftCompleted: shiftCompleted, memory: model.memory) {
            HStack(spacing: 12) {
                Image(systemName: "road.lanes")
                    .font(.system(size: 22))
                    .foregroundColor(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add today's travel to expenses")
                        .font(.subheadline.weight(.bold))
                        .foregroundColor(Color(uiColor: .label))
                    Text("Claim the distance you covered today, from your GPS route")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { model.openSheet() }
                Button {
                    model.dismissCard()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.red.opacity(0.08)))
            // Inside the `if`: a card that draws nothing must not leave a padded empty slot in Home's stack.
            .padding(.horizontal, 20)
        }
    }
}

/// The sheet: the day's distance, the vehicle to claim it with, the amount it comes to, and the two buttons.
struct TravelPromptSheet: View {
    @ObservedObject var model: TravelPromptModel

    private var vehicles: [ExpenseVehicleRate] { TravelPrompt.vehicles(model.rules) }
    private var dayText: String { ExpenseLogic.shortDate(model.date) ?? model.date }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Add today's travel to expenses?")
                    .font(.title3.bold())
                content
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .interactiveDismissDisabled(model.creating)
    }

    @ViewBuilder
    private var content: some View {
        if model.loading || model.outcome == nil {
            HStack(spacing: 10) {
                ProgressView()
                Text("Working out how far you travelled…")
                    .font(.subheadline)
            }
        } else if let outcome = model.outcome {
            switch outcome {
            case .ready(let km, let legs, let method):
                ready(km: km, legs: legs, method: method)
            case .noTravel:
                message("No travel was recorded for \(dayText), so there is nothing to add.")
                // Nothing to claim today: closing it ends the prompt for the day (the Home card goes too).
                Button("Close") { model.dismissCard() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
            case .notSynced:
                message("Your check-out hasn't reached the server yet, so today's distance isn't final. Try again once it has synced.")
                retryButtons
            case .unavailable(let text):
                message(text)
                retryButtons
            }
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var retryButtons: some View {
        VStack(spacing: 8) {
            Button("Try again") { model.retry() }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .frame(maxWidth: .infinity)
            Button("Not now") { model.notNow() }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func ready(km: Double, legs: Int, method: String?) -> some View {
        let chosen: ExpenseVehicleRate? = ExpenseLogic.vehicleRate(model.vehicleId, in: vehicles)
        let preview: Double? = TravelPrompt.amountPreview(km: km, vehicle: chosen)

        Text("\(TravelPrompt.kmText(km)) on \(dayText) · \(TravelPrompt.legsText(legs))")
            .font(.headline)
        if let note = TravelPrompt.methodNote(method) {
            Text(note)
                .font(.caption)
                .foregroundColor(.secondary)
        }

        Text("Vehicle")
            .font(.subheadline.weight(.semibold))
        VStack(spacing: 6) {
            ForEach(vehicles) { v in
                vehicleRow(v)
            }
        }

        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Amount")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Distance × the vehicle's rate. The final amount is worked out when you save.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            Text(preview.map { ExpenseLogic.money($0, model.currency) } ?? "—")
                .font(.headline)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))

        if let err = model.errorText {
            Text(err)
                .font(.caption)
                .foregroundColor(.red)
                .fixedSize(horizontal: false, vertical: true)
        }

        Button {
            Task { await model.add() }
        } label: {
            HStack(spacing: 8) {
                if model.creating { ProgressView().tint(.white) }
                Text("Add to expenses")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(chosen == nil || model.creating)

        Button("Not now") { model.notNow() }
            .buttonStyle(.bordered)
            .frame(maxWidth: .infinity)
            .disabled(model.creating)
    }

    private func vehicleRow(_ v: ExpenseVehicleRate) -> some View {
        let selected: Bool = model.vehicleId == v.id
        return Button {
            model.selectVehicle(v.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selected ? .red : .secondary)
                Text(TravelPrompt.chipLabel(v, currency: model.currency))
                    .font(.subheadline)
                    .foregroundColor(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Color.red.opacity(0.08) : Color(uiColor: .secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .disabled(model.creating)
    }
}
