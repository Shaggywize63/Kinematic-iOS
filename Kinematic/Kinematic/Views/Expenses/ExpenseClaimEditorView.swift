import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

/// Create or edit a claim. Receipts are uploaded straight from the form (photo or PDF) and read by
/// OCR to fill the line; the policy is checked as the lines change so problems show before anyone
/// presses Submit; a rejected claim opens here for fixing and resubmitting.
///
/// `claim` is the full claim (lines come only from the detail fetch) or nil for a new one.
struct ExpenseClaimEditorView: View {
    @ObservedObject var vm: ExpensesViewModel
    let claim: ExpenseClaim?
    let onDone: (_ claimId: String, _ submitted: Bool) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var lines: [EditorLine]
    /// Once a draft has been created from this form, a retry updates it instead of creating a second one.
    @State private var savedId: String?
    @State private var check: ExpenseClaimCheck?
    @State private var saving = false
    @State private var errorText: String?

    @State private var attachId: UUID?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var showFiles = false
    @State private var photoItem: PhotosPickerItem?
    @State private var cameraImage: UIImage?
    @State private var viewing: ReceiptRef?
    /// Set while the next picked photo is an odometer photo (not a receipt): which line, and which reading.
    @State private var odoTarget: OdoTarget?

    private struct OdoTarget { let lineId: UUID; let start: Bool }

    /// What the live policy check depends on — the lines AND whether mileage is priced by vehicle.
    private struct CheckKey: Equatable { let fields: [ExpenseLineFields]; let byVehicle: Bool }

    private struct EditorLine: Identifiable {
        let id = UUID()
        var f: ExpenseLineFields
        /// A link to show the attached receipt right now.
        var receiptView: String?
        /// Links to show the odometer photos right now (travel allowance by vehicle).
        var odoStartView: String?
        var odoEndView: String?
        var uploading = false
        /// "start" or "end" while that odometer photo is uploading.
        var odoUploading: String?
        var suggesting = false
        var scanNote: String?
    }

    /// Dates are local calendar days ("yyyy-MM-dd"), so the date picker and the stored string agree.
    private static let localDay: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"; return f
    }()
    private static func today() -> String { localDay.string(from: Date()) }

    init(vm: ExpensesViewModel, claim: ExpenseClaim?, onDone: @escaping (_ claimId: String, _ submitted: Bool) -> Void) {
        self.vm = vm
        self.claim = claim
        self.onDone = onDone
        _title = State(initialValue: claim?.title ?? "")
        _savedId = State(initialValue: claim?.id)
        var seeded: [EditorLine] = []
        for item in claim?.items ?? [] {
            var f = item.toFields()
            if f.itemDate.isEmpty { f.itemDate = Self.today() }
            seeded.append(EditorLine(f: f, receiptView: item.receipt_signed_url,
                                     odoStartView: item.odometer_start_photo_signed_url, odoEndView: item.odometer_end_photo_signed_url))
        }
        if seeded.isEmpty { seeded = [EditorLine(f: ExpenseLineFields(itemDate: Self.today()))] }
        _lines = State(initialValue: seeded)
    }

    private var status: String { (claim?.status ?? "draft").lowercased() }
    private var currency: String { vm.policy?.currency ?? claim?.currency ?? "INR" }
    private var rate: Double { vm.policy?.rules?.mileage_rate ?? vm.policy?.mileage_rate ?? 0 }
    /// Where the policy pays mileage by vehicle, a mileage line takes the vehicle + odometer readings instead of a
    /// typed distance; the server works the distance and amount out.
    private var vehicles: [ExpenseVehicleRate] { vm.policy?.rules?.vehicle_rates ?? [] }
    private var byVehicle: Bool { !vehicles.isEmpty }
    private var photosRequired: Bool { vm.policy?.rules?.odometer_photos_required != false }
    private var total: Double { lines.reduce(0) { $0 + $1.f.effectiveAmount(mileageRate: rate, vehicles: vehicles) } }
    private var filled: [EditorLine] { lines.filter { $0.f.isFilled } }
    /// The lines that went into the policy check, in order — findings are indexed by position among them.
    private var checked: [EditorLine] { lines.filter { $0.f.isFilled && $0.f.canSave(byVehicle: byVehicle) } }
    private var checkedFields: [ExpenseLineFields] { checked.map { $0.f } }
    private var blocking: Bool { check?.blocking == true }

    var body: some View {
        NavigationStack {
            Form {
                if let c = claim, (c.status ?? "") == "rejected" { Section { ExpenseRejectionBanner(claim: c).listRowInsets(EdgeInsets()) } }
                Section { TextField("Title (optional)", text: $title) }
                if let p = vm.policy { Section("Your policy") { policySummary(p) } }

                ForEach($lines) { $line in lineSection($line) }

                Section {
                    Button { lines.append(EditorLine(f: ExpenseLineFields(itemDate: Self.today()))) } label: { Label("Add another expense", systemImage: "plus") }
                    HStack { Text("Total").bold(); Spacer(); Text(expenseMoney(total, currency)).bold() }
                }

                Section { policyVerdict }
                if let e = errorText { Section { Text(e).font(.footnote).foregroundColor(.red) } }

                Section {
                    if status == "submitted" {
                        Button(saving ? "Saving…" : "Save changes") { Task { await save(submit: false) } }
                            .disabled(saving || blocking).frame(maxWidth: .infinity)
                    } else {
                        Button(saving ? "Working…" : (status == "rejected" ? "Resubmit for approval" : "Submit for approval")) { Task { await save(submit: true) } }
                            .buttonStyle(.borderedProminent).disabled(saving || blocking).frame(maxWidth: .infinity)
                        Button(status == "rejected" ? "Save changes" : "Save as draft") { Task { await save(submit: false) } }
                            .disabled(saving).frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(claim == nil ? "New claim" : (status == "rejected" ? "Fix and resubmit" : "Edit claim"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() }.disabled(saving) } }
            .task(id: CheckKey(fields: checkedFields, byVehicle: byVehicle)) { await runCheck() }
            .sheet(isPresented: $showCamera, onDismiss: handleCamera) {
                ImagePicker(image: $cameraImage, sourceType: .camera, cameraDevice: .rear)
            }
            .photosPicker(isPresented: $showLibrary, selection: $photoItem, matching: .images)
            .onChange(of: photoItem) { _, item in
                guard let item = item else { return }
                Task {
                    let data = try? await item.loadTransferable(type: Data.self)
                    photoItem = nil
                    if let data = data, let image = UIImage(data: data) { await attach(image: image) }
                    else { markNotUploading(); errorText = "Couldn't read that photo." }
                }
            }
            .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf]) { result in
                guard case .success(let url) = result else { markNotUploading(); return }
                let ok = url.startAccessingSecurityScopedResource()
                defer { if ok { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) { Task { await upload(data: data, filename: "receipt.pdf", mime: "application/pdf") } }
                else { markNotUploading(); errorText = "Couldn't read that PDF." }
            }
            .sheet(item: $viewing) { ReceiptViewerSheet(url: $0.url) }
        }
    }

    // ── one expense line ────────────────────────────────────────────────────

    @ViewBuilder private func lineSection(_ line: Binding<EditorLine>) -> some View {
        let l = line.wrappedValue
        let index = lines.firstIndex(where: { $0.id == l.id }) ?? 0
        let findings = ExpenseLogic.flags(forLine: checked.firstIndex(where: { $0.id == l.id }) ?? -1, in: check?.violations)
        let mileage = l.f.category == "mileage"
        Section("Expense \(index + 1)") {
            Picker("Category", selection: line.f.category) {
                ForEach(allowedCategories(current: l.f.category), id: \.self) { Text(ExpenseLogic.categoryLabel($0)).tag($0) }
            }
            DatePicker("Date", selection: dateBinding(line), in: ...Date(), displayedComponents: .date)

            if mileage && byVehicle {
                // Travel allowance by vehicle: pick the vehicle, enter the odometer before / after (with a photo of
                // each). The distance and amount are worked out from the readings, here and again by the server.
                TextField("From", text: line.f.fromLocation)
                TextField("To", text: line.f.toLocation)
                Picker("Vehicle *", selection: line.f.vehicleType) {
                    Text("Choose a vehicle…").tag("")
                    ForEach(vehicles) { v in Text("\(v.label) · \(expenseMoney(v.rate_per_km, currency))/km").tag(v.id) }
                }
                odometerRow(line, start: true)
                odometerRow(line, start: false)
                odometerSummaryRow(l)
            } else if mileage {
                TextField("From", text: line.f.fromLocation)
                TextField("To", text: line.f.toLocation)
                HStack {
                    TextField("Distance (km)", text: line.f.distanceKm).keyboardType(.decimalPad)
                    Button { Task { await suggestMileage(l.id) } } label: {
                        if l.suggesting { ProgressView() } else { Label("GPS trail", systemImage: "location.fill") }
                    }.buttonStyle(.bordered).controlSize(.small).disabled(l.suggesting)
                }
                TextField("Amount (\(currency)) — blank to price at the policy rate", text: line.f.amount).keyboardType(.decimalPad)
            } else {
                TextField("Merchant", text: line.f.merchant)
                TextField("Amount (\(currency))", text: line.f.amount).keyboardType(.decimalPad)
                TextField("Notes (optional)", text: line.f.description)
                receiptRow(line)
            }
            if let note = l.scanNote { Text(note).font(.caption).foregroundColor(.blue) }
            if !findings.isEmpty { ExpenseFindingsList(flags: findings) }
            if lines.count > 1 {
                Button("Remove this expense", role: .destructive) { lines.removeAll { $0.id == l.id } }
            }
        }
    }

    @ViewBuilder private func receiptRow(_ line: Binding<EditorLine>) -> some View {
        let l = line.wrappedValue
        if l.uploading {
            HStack { ProgressView(); Text("Uploading and reading the receipt…").font(.subheadline) }
        } else if !l.f.receiptUrl.isEmpty {
            HStack(spacing: 10) {
                Button { if let v = l.receiptView { viewing = ReceiptRef(url: v) } } label: { ReceiptThumbnail(url: l.receiptView) }
                    .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Receipt attached").font(.subheadline).bold()
                    Text("Tap the preview to view it").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                attachMenu(l.id, label: "Replace")
                Button { line.wrappedValue.f.receiptUrl = ""; line.wrappedValue.receiptView = nil; line.wrappedValue.f.ocr = nil; line.wrappedValue.scanNote = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }.buttonStyle(.borderless).accessibilityLabel("Remove receipt")
            }
        } else {
            attachMenu(l.id, label: "Attach receipt")
        }
    }

    private func attachMenu(_ id: UUID, label: String) -> some View {
        Menu {
            Button { begin(id); showCamera = true } label: { Label("Take a photo", systemImage: "camera") }
            Button { begin(id); showLibrary = true } label: { Label("Choose a photo", systemImage: "photo.on.rectangle") }
            Button { begin(id); showFiles = true } label: { Label("Choose a PDF", systemImage: "doc.richtext") }
        } label: {
            Label(label, systemImage: "paperclip")
        }
    }

    /// One odometer reading and the photo that backs it.
    @ViewBuilder private func odometerRow(_ line: Binding<EditorLine>, start: Bool) -> some View {
        let l = line.wrappedValue
        let title = start ? "Odometer before the trip" : "Odometer after the trip"
        let photo = start ? l.f.odoStartPhoto : l.f.odoEndPhoto
        let view = start ? l.odoStartView : l.odoEndView
        let uploading = l.odoUploading == (start ? "start" : "end")
        VStack(alignment: .leading, spacing: 8) {
            TextField("\(title) (km) *", text: start ? line.f.odometerStart : line.f.odometerEnd)
                .keyboardType(.decimalPad)
            if uploading {
                HStack { ProgressView(); Text("Uploading the photo…").font(.subheadline) }
            } else if !photo.isEmpty {
                HStack(spacing: 10) {
                    Button { if let v = view { viewing = ReceiptRef(url: v) } } label: { ReceiptThumbnail(url: view) }
                        .buttonStyle(.plain)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Photo attached").font(.subheadline).bold()
                        Text("Tap the preview to view it").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    odometerPhotoMenu(l.id, start: start, label: "Replace")
                    Button {
                        if start { line.wrappedValue.f.odoStartPhoto = ""; line.wrappedValue.odoStartView = nil }
                        else { line.wrappedValue.f.odoEndPhoto = ""; line.wrappedValue.odoEndView = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.borderless).accessibilityLabel("Remove photo")
                }
            } else {
                odometerPhotoMenu(l.id, start: start, label: photosRequired ? "Add odometer photo" : "Add odometer photo (optional)")
            }
        }
    }

    private func odometerPhotoMenu(_ id: UUID, start: Bool, label: String) -> some View {
        Menu {
            Button { beginOdometer(id, start: start); showCamera = true } label: { Label("Take a photo", systemImage: "camera") }
            Button { beginOdometer(id, start: start); showLibrary = true } label: { Label("Choose a photo", systemImage: "photo.on.rectangle") }
        } label: {
            Label(label, systemImage: "camera")
        }
    }

    /// Distance and amount from the readings, or what is wrong with them.
    @ViewBuilder private func odometerSummaryRow(_ l: EditorLine) -> some View {
        if let problem = l.f.odometerOrderProblem {
            Text(problem).font(.footnote).bold().foregroundColor(.red)
        } else {
            let km = l.f.odometerKm
            let chosen = ExpenseLogic.vehicleRate(l.f.vehicleType, in: vehicles)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Distance").font(.caption).foregroundColor(.secondary)
                    Text(km.map { "\(ExpenseLogic.trimNumber($0)) km" } ?? "—").bold()
                }
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text("Amount").font(.caption).foregroundColor(.secondary)
                    Text(km != nil && chosen != nil ? expenseMoney(l.f.effectiveAmount(mileageRate: 0, vehicles: vehicles), currency) : "—").bold()
                }
            }
            Text("Worked out from the readings — distance × the vehicle's rate.").font(.caption).foregroundColor(.secondary)
        }
    }

    private func policySummary(_ p: ExpensePolicy) -> some View {
        let rules = p.rules
        let travel = (rules?.vehicle_rates ?? []).map { "\($0.label) \(expenseMoney($0.rate_per_km, currency))/km" }
        var parts = [travel.isEmpty ? "Mileage \(expenseMoney(rules?.mileage_rate ?? p.mileage_rate, currency))/km" : "Travel " + travel.joined(separator: ", "),
                     "receipt needed over \(expenseMoney(rules?.receipt_required_over ?? p.require_receipt_over, currency))"]
        let auto = rules?.auto_approve_under ?? p.auto_approve_under ?? 0
        if auto > 0 { parts.append("auto-approved up to \(expenseMoney(auto, currency))") }
        if let esc = rules?.escalate_over ?? p.escalate_over { parts.append("second approver over \(expenseMoney(esc, currency))") }
        for (cat, rule) in (rules?.categories ?? [:]).sorted(by: { $0.key < $1.key }) where rule.enabled != false {
            if let d = rule.per_day_limit { parts.append("\(ExpenseLogic.categoryLabel(cat)) ≤ \(expenseMoney(d, currency))/day") }
        }
        return VStack(alignment: .leading, spacing: 4) {
            if let n = p.name { Text(n).font(.subheadline).bold() }
            Text(parts.joined(separator: " · ")).font(.caption).foregroundColor(.secondary)
            if rules?.enforcement == "block" { Text("A claim that breaks these rules can't be submitted.").font(.caption).foregroundColor(.orange) }
        }
    }

    @ViewBuilder private var policyVerdict: some View {
        if let c = check {
            let n = c.violations?.count ?? 0
            let general = ExpenseLogic.claimLevelFlags(c.violations)
            if !general.isEmpty { ExpenseFindingsList(flags: general) }
            if c.blocking == true {
                Text("Fix the highlighted problems before you can submit.").font(.footnote).bold().foregroundColor(.red)
            } else if n == 0 {
                Text(c.would_auto_approve == true ? "Within policy — this will be approved automatically." : "Within policy.").font(.footnote).foregroundColor(.green)
            } else {
                Text("Your approver will see \(n) \(n == 1 ? "point" : "points") flagged.").font(.footnote).foregroundColor(.orange)
            }
        } else {
            Text("Your claim is checked against the policy as you type.").font(.footnote).foregroundColor(.secondary)
        }
    }

    // ── helpers ─────────────────────────────────────────────────────────────

    private func allowedCategories(current: String) -> [String] {
        ExpenseLogic.categories.filter { $0 == current || vm.policy?.rules?.categories?[$0]?.enabled != false }
    }

    private func dateBinding(_ line: Binding<EditorLine>) -> Binding<Date> {
        Binding(
            get: { Self.localDay.date(from: line.wrappedValue.f.itemDate) ?? Date() },
            set: { line.wrappedValue.f.itemDate = Self.localDay.string(from: $0) }
        )
    }

    private func runCheck() async {
        let fields = checkedFields
        if fields.isEmpty { check = nil; return }
        try? await Task.sleep(nanoseconds: 650_000_000)   // debounce while typing
        if Task.isCancelled { return }
        let r = await vm.check(items: fields.map { $0.toInput(byVehicle: byVehicle) }, claimId: savedId)
        if !Task.isCancelled { check = r }
    }

    // ── receipts ────────────────────────────────────────────────────────────

    /// Remember which line the next picked file is for. Nothing is shown as uploading until a file arrives,
    /// so cancelling a picker leaves the line as it was.
    private func begin(_ id: UUID) {
        attachId = id
        odoTarget = nil
        errorText = nil
    }

    /// Same, for an odometer photo: the next picked photo goes to that reading, never through the receipt OCR.
    private func beginOdometer(_ id: UUID, start: Bool) {
        attachId = id
        odoTarget = OdoTarget(lineId: id, start: start)
        errorText = nil
    }

    private func markUploading() {
        if let id = attachId, let i = lines.firstIndex(where: { $0.id == id }) { lines[i].uploading = true }
    }

    private func markNotUploading() {
        if let id = attachId, let i = lines.firstIndex(where: { $0.id == id }) {
            lines[i].uploading = false
            lines[i].odoUploading = nil
        }
    }

    private func handleCamera() {
        guard let image = cameraImage else { markNotUploading(); return }
        cameraImage = nil
        Task { await attach(image: image) }
    }

    /// Shrink the photo (a 6 MB phone shot uploads as a few hundred KB) and send it.
    private func attach(image: UIImage) async {
        if let target = odoTarget {
            odoTarget = nil
            await attachOdometer(image: image, target: target)
            return
        }
        markUploading()
        guard let data = KinematicRepository.compressForUpload(image, maxDim: 1800, targetKB: 1500), !data.isEmpty else {
            markNotUploading(); errorText = "Couldn't read that photo."; return
        }
        await upload(data: data, filename: "receipt.jpg", mime: "image/jpeg")
    }

    /// An odometer photo: shrunk and stored like a receipt, but not read as one.
    private func attachOdometer(image: UIImage, target: OdoTarget) async {
        guard let i = lines.firstIndex(where: { $0.id == target.lineId }) else { return }
        lines[i].odoUploading = target.start ? "start" : "end"
        guard let data = KinematicRepository.compressForUpload(image, maxDim: 1800, targetKB: 1500), !data.isEmpty else {
            lines[i].odoUploading = nil; errorText = "Couldn't read that photo."; return
        }
        if data.count > 10 * 1024 * 1024 {
            lines[i].odoUploading = nil; errorText = "That photo is larger than 10 MB."; return
        }
        let (result, error) = await vm.uploadReceipt(data: data, filename: "odometer.jpg", mime: "image/jpeg", scan: false)
        guard let j = lines.firstIndex(where: { $0.id == target.lineId }) else { return }
        lines[j].odoUploading = nil
        guard let r = result else { errorText = error ?? "Couldn't upload the photo."; return }
        if target.start { lines[j].f.odoStartPhoto = r.url; lines[j].odoStartView = r.signed_url }
        else { lines[j].f.odoEndPhoto = r.url; lines[j].odoEndView = r.signed_url }
    }

    private func upload(data: Data, filename: String, mime: String) async {
        guard let id = attachId else { return }
        markUploading()
        if data.count > 10 * 1024 * 1024 {
            if let i = lines.firstIndex(where: { $0.id == id }) { lines[i].uploading = false }
            errorText = "That file is larger than 10 MB."; return
        }
        let (result, error) = await vm.uploadReceipt(data: data, filename: filename, mime: mime)
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[i].uploading = false
        guard let r = result else { errorText = error ?? "Couldn't upload the receipt."; return }
        lines[i].f = lines[i].f.withScan(r.scan, receiptUrl: r.url)
        lines[i].receiptView = r.signed_url
        if let s = r.scan, s.amount != nil || !(s.merchant ?? "").isEmpty {
            let bits = [s.amount.map { expenseMoney($0, currency) }, (s.merchant ?? "").isEmpty ? nil : s.merchant].compactMap { $0 }
            lines[i].scanNote = "Read from the receipt: \(bits.joined(separator: " · ")). Check it looks right."
        } else {
            lines[i].scanNote = nil
        }
    }

    // ── GPS mileage ─────────────────────────────────────────────────────────

    private func suggestMileage(_ id: UUID) async {
        guard let i = lines.firstIndex(where: { $0.id == id }) else { return }
        let day = lines[i].f.itemDate
        lines[i].suggesting = true
        let (m, err) = await vm.mileage(fromISO: "\(day)T00:00:00.000Z", toISO: "\(day)T23:59:59.999Z")
        guard let j = lines.firstIndex(where: { $0.id == id }) else { return }
        lines[j].suggesting = false
        guard let r = m else { errorText = err; return }
        if r.distance_km <= 0 { errorText = "No GPS trail was recorded for that day."; return }
        lines[j].f.distanceKm = ExpenseLogic.trimNumber(r.distance_km)
        lines[j].f.amount = ExpenseLogic.trimNumber(r.suggested_amount)
        if lines[j].f.description.isEmpty { lines[j].f.description = "\(ExpenseLogic.trimNumber(r.distance_km)) km from your GPS trail" }
    }

    // ── save / submit ───────────────────────────────────────────────────────

    private func save(submit: Bool) async {
        guard !filled.isEmpty else { errorText = "Add at least one expense."; return }
        if let bad = lines.firstIndex(where: { $0.f.isFilled && !$0.f.canSave(byVehicle: byVehicle) }) {
            if byVehicle && lines[bad].f.category == "mileage" {
                errorText = "Expense \(bad + 1) needs a vehicle and the odometer readings."
            } else {
                errorText = "Expense \(bad + 1) needs an amount\(lines[bad].f.category == "mileage" ? " or a distance" : "")."
            }
            return
        }
        if let wrong = lines.firstIndex(where: { byVehicle && $0.f.category == "mileage" && $0.f.odometerOrderProblem != nil }) {
            errorText = "Expense \(wrong + 1): \(lines[wrong].f.odometerOrderProblem ?? "")"; return
        }
        if lines.contains(where: { $0.uploading || $0.odoUploading != nil }) { errorText = "Wait for the upload to finish."; return }
        errorText = nil
        saving = true
        defer { saving = false }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let out = await vm.save(claimId: savedId, title: t.isEmpty ? nil : t, items: filled.map { $0.f.toInput(byVehicle: byVehicle) }, submit: submit)
        if let id = out.savedId { savedId = id }
        if let e = out.error { errorText = e; return }
        if let id = out.savedId { onDone(id, out.submitted); dismiss() }
    }
}
