//
//  NewOutletView.swift
//  Kinematic
//
//  "Add new outlet": a rep proposes an outlet (name, owner, phone, address, on/off-trade, and the phone's GPS fix when
//  there is one). It goes to a manager for approval and cannot take orders or collections until then. Below the form the
//  rep sees their own proposals that are waiting or were refused (with the reason). Needs a connection — the server
//  makes the unique outlet code. `NewOutletFormLogic` is pure and unit-tested.
//

import SwiftUI

enum NewOutletFormLogic {
    private static let phonePattern = #"^[0-9+()\-\s]{6,20}$"#

    /// Why the form can't be sent yet; nil when it can.
    static func problem(name: String, phone: String) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Enter the outlet name" }
        let p = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        if !p.isEmpty, p.range(of: phonePattern, options: .regularExpression) == nil { return "Phone number looks invalid" }
        return nil
    }

    private static func clean(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    static func input(name: String, owner: String, phone: String, address: String, tradeType: String?,
                      lat: Double?, lng: Double?) -> NewOutletInput {
        NewOutletInput(name: name.trimmingCharacters(in: .whitespacesAndNewlines), owner_name: clean(owner),
                       phone: clean(phone), address: clean(address), trade_type: tradeType, lat: lat, lng: lng)
    }

    /// One line for the rep about where a proposal stands.
    static func statusLine(_ o: ProposedOutlet) -> String {
        switch (o.approval_status ?? "").lowercased() {
        case "rejected":
            let reason = (o.rejection_reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return reason.isEmpty ? "Refused" : "Refused: \(reason)"
        case "approved": return "Approved"
        default: return "Waiting for approval"
        }
    }
}

struct NewOutletView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var owner = ""
    @State private var phone = ""
    @State private var address = ""
    @State private var tradeType = ""          // "", "on_trade", "off_trade"
    @State private var busy = false
    @State private var error: String? = nil
    @State private var sentCode: String? = nil
    @State private var proposals: [ProposedOutlet] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("A manager approves new outlets before they can take orders or collections.")
                        .font(.footnote).foregroundColor(.secondary)
                }
                if let code = sentCode {
                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Sent for approval").font(.headline)
                            Text("Outlet code \(code). You'll see it in your outlet list once a manager approves it.")
                                .font(.subheadline)
                        }
                        Button("Add another outlet") { reset() }
                    }
                } else {
                    Section("Outlet") {
                        TextField("Outlet name *", text: $name)
                        TextField("Owner / contact name", text: $owner)
                        TextField("Phone", text: $phone).keyboardType(.phonePad)
                        TextField("Address", text: $address, axis: .vertical).lineLimit(2...4)
                        Picker("Trade channel", selection: $tradeType) {
                            Text("Not set").tag("")
                            Text("On-trade").tag("on_trade")
                            Text("Off-trade").tag("off_trade")
                        }
                    } footer: {
                        Text("The outlet's location is taken from your phone's GPS when it is available.")
                    }
                    if let error {
                        Section { Text(error).font(.caption).foregroundColor(.red) }
                    }
                    Section {
                        Button(busy ? "Sending…" : "Send for approval") { Task { await submit() } }
                            .disabled(busy)
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                            .listRowBackground(Color(red: 208/255, green: 30/255, blue: 44/255))
                    }
                }
                if !proposals.isEmpty {
                    Section("Your proposals") {
                        ForEach(proposals) { p in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.name ?? p.store_code ?? p.id).font(.subheadline.weight(.semibold))
                                Text([p.store_code, NewOutletFormLogic.statusLine(p)].compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add new outlet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task(id: sentCode) { proposals = await DistributionAPI.shared.proposedOutlets() }
        }
    }

    private func reset() {
        sentCode = nil; name = ""; owner = ""; phone = ""; address = ""; tradeType = ""; error = nil
    }

    private func submit() async {
        if let problem = NewOutletFormLogic.problem(name: name, phone: phone) { error = problem; return }
        busy = true; error = nil
        let fix = await CurrentLocationProvider.oneShot()
        let input = NewOutletFormLogic.input(name: name, owner: owner, phone: phone, address: address,
                                             tradeType: tradeType.isEmpty ? nil : tradeType, lat: fix?.lat, lng: fix?.lng)
        switch await DistributionAPI.shared.createOutlet(input) {
        case .created(let outlet): sentCode = outlet.store_code ?? "—"
        case .offline: error = "No connection — connect to the internet to add an outlet."
        case .failed(let message): error = message
        }
        busy = false
    }
}
