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

    /// What the live policy check depends on — the lines AND whether mileage is priced by vehicle (and whether the route is sent).
    private struct CheckKey: Equatable { let fields: [ExpenseLineFields]; let byVehicle: Bool; let routeFields: Bool }

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
        /// What the odometer reader said about the Before / After photo (policies with camera-only odometer photos).
        var odoStartNote: OdometerScanNote?
        var odoEndNote: OdometerScanNote?
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
        // The policy's only vehicle (if it lists exactly one) is pre-selected on mileage lines that have none.
        let sole = ExpenseLogic.soleVehicleId(ExpenseLogic.policyVehicles(vm.policy?.rules))
        for item in claim?.items ?? [] {
            var f = item.toFields()
            if f.itemDate.isEmpty { f.itemDate = Self.today() }
            seeded.append(EditorLine(f: f.withSoleVehicle(sole), receiptView: item.receipt_signed_url,
                                     odoStartView: item.odometer_start_photo_signed_url, odoEndView: item.odometer_end_photo_signed_url))
        }
        // The policy may already be known (the list loads it); if it arrives later, onlyCategory and
        // applySoleVehicle below catch up.
        if seeded.isEmpty { seeded = [Self.blankLine(category: ExpenseLogic.defaultCategory(vm.policy?.rules), soleVehicle: sole)] }
        _lines = State(initialValue: seeded)
    }

    /// A new, untouched line. `category` is the policy's only enabled category in single-category mode, else "food".
    /// `soleVehicle` is the policy's only vehicle, pre-selected when the line is a mileage line.
    private static func blankLine(category: String, soleVehicle: String?) -> EditorLine {
        EditorLine(f: ExpenseLineFields(category: category, itemDate: Self.today()).withSoleVehicle(soleVehicle))
    }

    private var status: String { (claim?.status ?? "draft").lowercased() }
    private var currency: String { vm.policy?.currency ?? claim?.currency ?? "INR" }
    private var rate: Double { vm.policy?.rules?.mileage_rate ?? vm.policy?.mileage_rate ?? 0 }
    /// Where the policy pays mileage by vehicle, a mileage line takes the vehicle + odometer readings instead of a
    /// typed distance; the server works the distance and amount out.
    /// Only the vehicles of the policy that governs this person (GET /expenses/policy is resolved per user).
    private var vehicles: [ExpenseVehicleRate] { ExpenseLogic.policyVehicles(vm.policy?.rules) }
    private var byVehicle: Bool { !vehicles.isEmpty }
    /// The policy's only vehicle, when it lists exactly one — pre-selected on mileage lines (nil for none or several).
    private var soleVehicle: String? { ExpenseLogic.soleVehicleId(vehicles) }
    private var photosRequired: Bool { vm.policy?.rules?.odometer_photos_required != false }
    private var rules: ExpensePolicyRules? { vm.policy?.rules }
    /// The policy's own category names (mileage → "Travel"); every category name on this screen goes through them.
    private var categoryLabels: [String: String]? { rules?.category_labels }
    /// From / To on mileage lines (default on).
    private var routeFields: Bool { ExpenseLogic.showsRoute(rules) }
    /// One line per claim: no "Add another expense".
    private var singleLine: Bool { ExpenseLogic.isSingleLine(rules) }
    /// Odometer photos only from the camera, and the number is read from the photo.
    private var cameraOnlyOdometer: Bool { ExpenseLogic.odometerCameraOnly(rules) }
    /// The one category the policy allows, when it allows exactly one.
    private var onlyCategory: String? { ExpenseLogic.singleCategory(rules) }
    /// "Last reading: 12392 km (5 Oct 2026)" under the Before field, from the odometer history.
    private var lastReadingHint: String? {
        guard byVehicle, let r = ExpenseLogic.lastReading(in: vm.odometerHistory, excludingClaim: savedId ?? claim?.id) else { return nil }
        return ExpenseLogic.lastReadingText(r)
    }
    private var total: Double { lines.reduce(0) { $0 + $1.f.effectiveAmount(mileageRate: rate, vehicles: vehicles) } }
    /// A new line carrying only the pre-selected sole vehicle is still untouched (see `isFilledIgnoring`).
    private var filled: [EditorLine] { lines.filter { $0.f.isFilledIgnoring(soleVehicle: soleVehicle) } }
    /// The lines that went into the policy check, in order — findings are indexed by position among them.
    private var checked: [EditorLine] { lines.filter { $0.f.isFilledIgnoring(soleVehicle: soleVehicle) && $0.f.canSave(byVehicle: byVehicle) } }
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
                    if !singleLine {
                        Button { lines.append(Self.blankLine(category: ExpenseLogic.defaultCategory(rules), soleVehicle: soleVehicle)) } label: { Label("Add another expense", systemImage: "plus") }
                    }
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
            .task(id: CheckKey(fields: checkedFields, byVehicle: byVehicle, routeFields: routeFields)) { await runCheck() }
            // The policy arrives after the editor can open: once it says "one category only", new lines take it.
            .onChange(of: onlyCategory, initial: true) { _, only in applyOnlyCategory(only) }
            // Likewise the vehicle: a policy with exactly one vehicle pre-selects it on every mileage line that has none
            // — when the policy arrives late, when a line is added and when a line becomes a mileage line.
            .onChange(of: soleVehicleKey, initial: true) { applySoleVehicle() }
            // Vehicle flow: fetch the odometer history for the "last reading" hint (best effort).
            .task(id: byVehicle) { if byVehicle { await vm.loadOdometerHistory() } }
            // Work from the policy as it is now, not the one fetched when the Expenses screen first opened: the
            // vehicles offered are its vehicles. A late arrival is caught up by the two onChange handlers above.
            .task { await vm.loadPolicy() }
            .sheet(isPresented: $showCamera, onDismiss: handleCamera) {
                // Camera-only odometer photos never fall back to the photo library on a phone without a camera.
                ImagePicker(image: $cameraImage, sourceType: .camera, cameraDevice: .rear,
                            allowLibraryFallback: !(odoTarget != nil && cameraOnlyOdometer))
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
            // Single-category mode has nothing to choose, so the picker is hidden — except on an older line
            // that is still on another category, which needs a way to move to the allowed one.
            if ExpenseLogic.showsCategoryPicker(rules, current: l.f.category) {
                Picker("Category", selection: line.f.category) {
                    ForEach(ExpenseLogic.allowedCategories(rules, current: l.f.category), id: \.self) {
                        Text(ExpenseLogic.categoryLabel($0, labels: categoryLabels)).tag($0)
                    }
                }
            }
            DatePicker("Date", selection: dateBinding(line), in: ...Date(), displayedComponents: .date)

            if mileage && byVehicle {
                // Travel allowance by vehicle: pick the vehicle, enter the odometer before / after (with a photo of
                // each). The distance and amount are worked out from the readings, here and again by the server.
                if routeFields {
                    TextField("From", text: line.f.fromLocation)
                    TextField("To", text: line.f.toLocation)
                }
                Picker("Vehicle *", selection: line.f.vehicleType) {
                    Text("Choose a vehicle…").tag("")
                    ForEach(vehicles) { v in Text("\(v.label) · \(expenseMoney(v.rate_per_km, currency))/km").tag(v.id) }
                }
                odometerRow(line, start: true)
                odometerRow(line, start: false)
                odometerSummaryRow(l)
            } else if mileage {
                if routeFields {
                    TextField("From", text: line.f.fromLocation)
                    TextField("To", text: line.f.toLocation)
                }
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
            if start, let hint = lastReadingHint {
                Text(hint).font(.caption).foregroundColor(.secondary)
            }
            if let note = (start ? l.odoStartNote : l.odoEndNote) {
                Text(note.text).font(.caption).foregroundColor(note == .unreadable ? .orange : .blue)
            }
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
                    odometerPhotoMenu(l.id, start: start, label: "Replace", replacing: true)
                    Button {
                        if start { line.wrappedValue.f.odoStartPhoto = ""; line.wrappedValue.odoStartView = nil; line.wrappedValue.odoStartNote = nil }
                        else { line.wrappedValue.f.odoEndPhoto = ""; line.wrappedValue.odoEndView = nil; line.wrappedValue.odoEndNote = nil }
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                    }.buttonStyle(.borderless).accessibilityLabel("Remove photo")
                }
            } else {
                odometerPhotoMenu(l.id, start: start, label: photosRequired ? "Add odometer photo" : "Add odometer photo (optional)")
            }
        }
    }

    @ViewBuilder private func odometerPhotoMenu(_ id: UUID, start: Bool, label: String, replacing: Bool = false) -> some View {
        if cameraOnlyOdometer {
            // Camera only: no photo-library choice at all, so the photo (and the number read from it) comes from
            // the vehicle in front of the person.
            Button { openOdometerCamera(id, start: start) } label: {
                Label(replacing ? "Retake photo" : (photosRequired ? "Take a photo" : "Take a photo (optional)"), systemImage: "camera")
            }
            .buttonStyle(.borderless)
        } else {
            Menu {
                Button { beginOdometer(id, start: start); showCamera = true } label: { Label("Take a photo", systemImage: "camera") }
                Button { beginOdometer(id, start: start); showLibrary = true } label: { Label("Choose a photo", systemImage: "photo.on.rectangle") }
            } label: {
                Label(label, systemImage: "camera")
            }
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
        // The same list the Vehicle picker offers (the policy's own vehicles, nothing merged in).
        let travel = ExpenseLogic.policyVehicles(rules).map { "\($0.label) \(expenseMoney($0.rate_per_km, currency))/km" }
        let mileageName = ExpenseLogic.categoryLabel("mileage", labels: rules?.category_labels)
        let travelName = ExpenseLogic.customLabel("mileage", labels: rules?.category_labels) ?? "Travel"
        let flatRate = expenseMoney(rules?.mileage_rate ?? p.mileage_rate, currency)
        let head: String = travel.isEmpty ? "\(mileageName) \(flatRate)/km" : "\(travelName) " + travel.joined(separator: ", ")
        var parts: [String] = [head,
                               "receipt needed over \(expenseMoney(rules?.receipt_required_over ?? p.require_receipt_over, currency))"]
        let auto = rules?.auto_approve_under ?? p.auto_approve_under ?? 0
        if auto > 0 { parts.append("auto-approved up to \(expenseMoney(auto, currency))") }
        if let esc = rules?.escalate_over ?? p.escalate_over { parts.append("second approver over \(expenseMoney(esc, currency))") }
        for (cat, rule) in (rules?.categories ?? [:]).sorted(by: { $0.key < $1.key }) where rule.enabled != false {
            if let d = rule.per_day_limit { parts.append("\(ExpenseLogic.categoryLabel(cat, labels: rules?.category_labels)) ≤ \(expenseMoney(d, currency))/day") }
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

    /// Single-category mode: every new line (not one already saved on the claim) takes the only enabled category.
    /// Called when the policy loads — it can arrive after the editor opened — and whenever it changes.
    private func applyOnlyCategory(_ only: String?) {
        guard let only = only else { return }
        for i in lines.indices where lines[i].f.id == nil && lines[i].f.category != only {
            lines[i].f.category = only
        }
    }

    /// What decides whether a vehicle must be pre-selected: the sole vehicle and the mileage lines still lacking one.
    private struct SoleVehicleKey: Equatable { let vehicle: String; let lines: [UUID] }
    private var soleVehicleKey: SoleVehicleKey? {
        guard let sole = soleVehicle else { return nil }
        return SoleVehicleKey(vehicle: sole, lines: lines.filter { $0.f.lacksVehicle }.map { $0.id })
    }

    /// Put the policy's only vehicle on every mileage line that has no vehicle. Never replaces a chosen vehicle.
    private func applySoleVehicle() {
        guard let sole = soleVehicle else { return }
        for i in lines.indices where lines[i].f.lacksVehicle {
            lines[i].f = lines[i].f.withSoleVehicle(sole)
        }
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
        let r = await vm.check(items: fields.map { $0.toInput(byVehicle: byVehicle, routeFields: routeFields) }, claimId: savedId)
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

    /// Camera-only odometer photo: open the camera, or say so when this device has none — never the library.
    private func openOdometerCamera(_ id: UUID, start: Bool) {
        beginOdometer(id, start: start)
        guard ImagePicker.isCameraAvailable else {
            odoTarget = nil
            errorText = "This device has no camera available, so the odometer photo can't be taken."
            return
        }
        showCamera = true
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

    /// An odometer photo: shrunk and stored like a receipt, but not read as one. On a policy with camera-only
    /// odometer photos the server also reads the number off it (`?scan=odometer`): it goes into the Before / After
    /// field (replacing what was there, still editable) with a note to check it, or a note to type it in when it
    /// could not be read. The photo is attached either way.
    private func attachOdometer(image: UIImage, target: OdoTarget) async {
        guard let i = lines.firstIndex(where: { $0.id == target.lineId }) else { return }
        lines[i].odoUploading = target.start ? "start" : "end"
        guard let data = KinematicRepository.compressForUpload(image, maxDim: 1800, targetKB: 1500), !data.isEmpty else {
            lines[i].odoUploading = nil; errorText = "Couldn't read that photo."; return
        }
        if data.count > 10 * 1024 * 1024 {
            lines[i].odoUploading = nil; errorText = "That photo is larger than 10 MB."; return
        }
        let read = cameraOnlyOdometer
        var (result, error) = await vm.uploadReceipt(data: data, filename: "odometer.jpg", mime: "image/jpeg", scan: read ? .odometer : .storeOnly)
        if result == nil && read {
            // The photo matters more than the number: if the reading step failed, store the photo without it.
            (result, error) = await vm.uploadReceipt(data: data, filename: "odometer.jpg", mime: "image/jpeg", scan: .storeOnly)
        }
        guard let j = lines.firstIndex(where: { $0.id == target.lineId }) else { return }
        lines[j].odoUploading = nil
        guard let r = result else { errorText = error ?? "Couldn't upload the photo."; return }
        if target.start { lines[j].f.odoStartPhoto = r.url; lines[j].odoStartView = r.signed_url }
        else { lines[j].f.odoEndPhoto = r.url; lines[j].odoEndView = r.signed_url }
        var note: OdometerScanNote? = nil
        if read {
            var f = lines[j].f
            note = f.applyOdometerScan(r.odometer, start: target.start)
            lines[j].f = f
        }
        if target.start { lines[j].odoStartNote = note } else { lines[j].odoEndNote = note }
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
        lines[i].f = lines[i].f.withScan(r.scan, receiptUrl: r.url, allowedCategories: onlyCategory.map { [$0] })
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
        if let bad = lines.firstIndex(where: { $0.f.isFilledIgnoring(soleVehicle: soleVehicle) && !$0.f.canSave(byVehicle: byVehicle) }) {
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
        let out = await vm.save(claimId: savedId, title: t.isEmpty ? nil : t, items: filled.map { $0.f.toInput(byVehicle: byVehicle, routeFields: routeFields) }, submit: submit)
        if let id = out.savedId { savedId = id }
        if let e = out.error { errorText = e; return }
        if let id = out.savedId { onDone(id, out.submitted); dismiss() }
    }
}
