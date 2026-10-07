import SwiftUI

// Shared building blocks for the expense screens: status chip, policy findings,
// receipt viewer, the remark sheet and the claim history.

// MARK: - Formatting

func expenseMoney(_ v: Double, _ currency: String) -> String { ExpenseLogic.money(v, currency) }

func expenseStatusColor(_ status: String?) -> Color {
    switch (status ?? "draft").lowercased() {
    case "approved": return .green
    case "submitted": return .orange
    case "rejected": return .red
    case "reimbursed": return .blue
    default: return .gray
    }
}

let expenseCategories = ExpenseLogic.categories

let expenseDayFmt: DateFormatter = {
    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(secondsFromGMT: 0); f.dateFormat = "yyyy-MM-dd"; return f
}()

private func flagColor(_ f: ExpenseFlag) -> Color {
    if f.blocking == true || f.severity == "high" { return .red }
    return f.severity == "warn" ? .orange : .blue
}

// MARK: - Status chip

struct ExpenseStatusChip: View {
    let claim: ExpenseClaim

    private var label: String {
        let s = (claim.status ?? "draft").lowercased()
        switch s {
        case "approved":   return ExpenseLogic.isPartlyApproved(claim) ? "Partly approved" : "Approved"
        case "submitted":  return "Awaiting approval"
        case "reimbursed": return ExpenseLogic.isPartlyApproved(claim) ? "Reimbursed (partly)" : "Reimbursed"
        default:           return claim.statusLabel
        }
    }
    private var color: Color {
        ExpenseLogic.isPartlyApproved(claim) && (claim.status ?? "") == "approved" ? .orange : expenseStatusColor(claim.status)
    }

    var body: some View {
        Text(label).font(.caption2).bold()
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .clipShape(Capsule())
    }
}

// MARK: - Policy findings

/// Policy findings as readable lines. A blocking one says it must be fixed before the claim can be submitted.
struct ExpenseFindingsList: View {
    let flags: [ExpenseFlag]

    var body: some View {
        if !flags.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(flags) { f in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundColor(flagColor(f)).padding(.top, 2)
                        Text(text(for: f)).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private func text(for f: ExpenseFlag) -> String {
        var s = ExpenseLogic.flagLabel(f.code) + "."
        if let d = f.detail, !d.isEmpty { s += " " + d }
        if f.blocking == true { s += " Fix this to submit." }
        return s
    }
}

// MARK: - Receipt viewer

struct ReceiptRef: Identifiable { let url: String; var id: String { url } }

struct ReceiptThumbnail: View {
    let url: String?
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(Color(.secondarySystemBackground))
            if let url = url, let u = URL(string: url), !url.lowercased().contains(".pdf") {
                AsyncImage(url: u) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    case .failure: Image(systemName: "photo").foregroundColor(.secondary)
                    default: ProgressView()
                    }
                }
            } else {
                Image(systemName: url == nil ? "receipt" : "doc.richtext").foregroundColor(.secondary)
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

/// Full-size receipt. The link is private and short-lived; reopen the claim for a fresh one.
struct ReceiptViewerSheet: View {
    let url: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let u = URL(string: url), !url.lowercased().contains(".pdf") {
                    ScrollView([.horizontal, .vertical]) {
                        AsyncImage(url: u) { phase in
                            switch phase {
                            case .success(let img): img.resizable().scaledToFit()
                            case .failure: Text("This receipt couldn't be shown. Reopen the claim and try again.").foregroundColor(.secondary).padding()
                            default: ProgressView().padding(40)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else if let u = URL(string: url) {
                    VStack(spacing: 14) {
                        Image(systemName: "doc.richtext").font(.system(size: 52)).foregroundColor(.secondary)
                        Text("PDF receipt")
                        Link("Open", destination: u).buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

// MARK: - Remark sheet

/// Collects the remark that a rejection requires. The confirm button stays disabled until
/// something is written, so a rejection can never be sent without a reason.
struct ExpenseRemarkSheet: View {
    let title: String
    let message: String
    let confirmLabel: String
    let onConfirm: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section { Text(message).font(.subheadline).foregroundColor(.secondary) }
                Section("Remark (required)") {
                    TextEditor(text: $text).frame(minHeight: 110)
                    if trimmed.isEmpty { Text("What is wrong, and what should be fixed?").font(.caption).foregroundColor(.secondary) }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(confirmLabel, role: .destructive) { onConfirm(trimmed); dismiss() }.disabled(trimmed.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Rejection banner

/// The rejection reason, front and centre, on any claim that was rejected.
struct ExpenseRejectionBanner: View {
    let claim: ExpenseClaim

    var body: some View {
        if (claim.status ?? "").lowercased() == "rejected" {
            VStack(alignment: .leading, spacing: 4) {
                Label("Rejected" + (claim.reviewer_name.map { " by \($0)" } ?? ""), systemImage: "xmark.circle.fill")
                    .font(.subheadline).bold().foregroundColor(.red)
                Text((claim.review_note ?? "").isEmpty ? "No remark was left." : (claim.review_note ?? ""))
                Text("Fix the points above and resubmit — nothing else needs to be re-entered.").font(.caption).foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.red.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - History

struct ExpenseTimelineView: View {
    let claim: ExpenseClaim

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(expenseTimeline(claim).enumerated()), id: \.offset) { _, step in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: icon(step.tone)).foregroundColor(color(step.tone)).frame(width: 18).padding(.top, 1)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title).font(.subheadline).bold()
                        if let d = step.date { Text(d).font(.caption2).foregroundColor(.secondary) }
                        if let r = step.remark {
                            Text(r).font(.subheadline)
                                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemBackground)).clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        ForEach(step.rejectedLines, id: \.self) { l in
                            Text("Line rejected · \(l)").font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func icon(_ t: ExpenseStepTone) -> String {
        switch t { case .done: return "checkmark.circle.fill"; case .bad: return "xmark.circle.fill"; case .waiting: return "clock.fill"; case .info: return "circle" }
    }
    private func color(_ t: ExpenseStepTone) -> Color {
        switch t { case .done: return .green; case .bad: return .red; case .waiting: return .orange; case .info: return .secondary }
    }
}

// MARK: - A line, read-only

struct ExpenseLineView: View {
    let item: ExpenseClaimItem
    let currency: String
    var onViewReceipt: (String) -> Void

    private var rejected: Bool { item.decision == "rejected" }
    private var detail: String {
        if item.category == "mileage" {
            var s = "\(item.from_location ?? "—") → \(item.to_location ?? "—")"
            if let km = item.distance_km { s += " · \(ExpenseLogic.trimNumber(km)) km" }
            return s
        }
        return [item.merchant, item.description].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(ExpenseLogic.categoryLabel(item.category)).font(.subheadline).bold()
                        Text(item.item_date ?? "").font(.caption).foregroundColor(.secondary)
                    }
                    if !detail.isEmpty { Text(detail).font(.subheadline).foregroundColor(.secondary) }
                    // Travel allowance by vehicle: which vehicle, and the odometer readings the amount came from.
                    if let o = item.odometerSummary() { Text(o).font(.subheadline).foregroundColor(.secondary) }
                }
                Spacer()
                Text(expenseMoney(item.amount, currency)).font(.subheadline).bold()
                    .strikethrough(rejected).foregroundColor(rejected ? .secondary : .primary)
            }
            HStack(spacing: 6) {
                if rejected { tag("Line rejected", .red) }
                if item.decision == "approved" { tag("Approved", .green) }
                if item.flagged == true { tag("Flagged", .orange) }
            }
            if rejected, let n = item.decision_note, !n.isEmpty {
                Text("Remark: \(n)").font(.subheadline)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if item.flagged == true, let r = item.flag_reason, !r.isEmpty { Text(r).font(.caption).foregroundColor(.orange) }
            if let r = item.receipt_url, !r.isEmpty {
                Button { if let u = item.receipt_signed_url { onViewReceipt(u) } } label: {
                    HStack(spacing: 8) { ReceiptThumbnail(url: item.receipt_signed_url); Text("Receipt").font(.caption).foregroundColor(.accentColor) }
                }.buttonStyle(.plain)
            } else if item.category != "mileage" {
                Text("No receipt").font(.caption).foregroundColor(.secondary)
            }
            // The approver's evidence for the readings: a photo of the odometer before and after the trip.
            if !(item.odometer_start_photo_url ?? "").isEmpty || !(item.odometer_end_photo_url ?? "").isEmpty {
                HStack(spacing: 14) {
                    odometerPhoto("Odometer before", stored: item.odometer_start_photo_url, signed: item.odometer_start_photo_signed_url)
                    odometerPhoto("Odometer after", stored: item.odometer_end_photo_url, signed: item.odometer_end_photo_signed_url)
                }
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder private func odometerPhoto(_ label: String, stored: String?, signed: String?) -> some View {
        if !(stored ?? "").isEmpty {
            Button { if let u = signed { onViewReceipt(u) } } label: {
                HStack(spacing: 8) { ReceiptThumbnail(url: signed); Text(label).font(.caption).foregroundColor(.accentColor) }
            }.buttonStyle(.plain)
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption2).bold()
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15)).foregroundColor(color).clipShape(Capsule())
    }
}
