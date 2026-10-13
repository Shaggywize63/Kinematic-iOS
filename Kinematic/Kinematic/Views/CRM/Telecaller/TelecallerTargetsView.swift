//
//  TelecallerTargetsView.swift
//  Kinematic CRM
//
//  The telecaller's "Targets" tab: the shared rupee-target card (Scheme Amount
//  ₹ for Rajkamal, reused verbatim) plus a "Calls this month" tile fed by the
//  owner-scoped activities summary.
//

import SwiftUI

struct TelecallerTargetsView: View {
    @StateObject private var targets = MyTargetsViewModel()
    @State private var callsThisMonth: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                callsTile
                // Scheme Amount ₹ progress — the shared card. Draws nothing if
                // the tenant configured no rupee targets.
                MyTargetsCard(model: targets, title: "My targets", horizontalPadding: 20)
                Spacer(minLength: 20)
            }
            .padding(.top, 14)
        }
        .navigationTitle("Targets")
        .task { await reload() }
        .refreshable { await reload() }
    }

    private var callsTile: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Brand.red.opacity(0.12)).frame(width: 46, height: 46)
                Image(systemName: "phone.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(Brand.red)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(callsThisMonth.map(String.init) ?? "—")
                    .font(.system(size: 24, weight: .black))
                    .foregroundColor(Color(uiColor: .label))
                Text("CALLS THIS MONTH")
                    .font(.system(size: 9, weight: .black)).tracking(0.5)
                    .foregroundColor(.gray)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
        .padding(.horizontal, 20)
    }

    private func reload() async {
        await targets.load()
        callsThisMonth = await CRMService.shared.activityCount(
            type: "call",
            from: Self.monthStartISO(),
            to: ISO8601DateFormatter().string(from: Date()))
    }

    /// ISO timestamp for the first instant of the current (local) month.
    private static func monthStartISO() -> String {
        let cal = Calendar.current
        let now = Date()
        let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        return ISO8601DateFormatter().string(from: start)
    }
}
