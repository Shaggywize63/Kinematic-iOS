//
//  AttendanceViewModel+Punch.swift
//  Kinematic
//
//  The attendance rules at work (see AttendanceRules.swift, OfflinePunch.swift, AttendancePunch.swift). Everything in
//  here is opt-in per client BY DATA and idle for a client that configured nothing:
//    • "How are you travelling today?" in front of Clock-In, Home's "Travelling by X" + Change, the self-heal;
//    • the GPS-only punch (rule `selfie_required: false`): one tap, a fresh location, no camera, no selfie upload;
//    • the offline-capable punch (rule `allow_offline_checkin`): real capture time, selfie kept on the phone, the
//      stand-in record while it waits;
//    • the signal workstream C reads: `freshCheckoutDate` (a shift's check-out has JUST reached the server) and
//      `todayTransportMode`.
//
//  The stored state is declared with the class (ViewModels.swift); the flow entry points (`startFlow`,
//  `toggleAttendance`, `refresh`) call into here with one or two lines each.
//

import SwiftUI
import Combine
import CoreLocation

/// The travel mode this phone knows for a day — what the Home payload leaves out, laid over every read of today.
struct KnownTransportMode: Equatable {
    var date: String          // yyyy-MM-dd
    var mode: String
    var label: String?
}

/// One showing of the "How are you travelling today?" step.
struct TransportPickRequest: Identifiable {
    let id = UUID()
    var title: String = "How are you travelling today?"
    var confirmLabel: String = "Clock in"
    var options: [TransportOption]
    var initial: String? = nil
}

extension AttendanceViewModel {

    // MARK: - The question in front of Clock-In

    /// How long an answer stays good for the Clock-In it was given for (camera + waiting for GPS). A cancelled camera
    /// therefore does not make the next attempt a quarter of an hour later reuse a stale answer.
    static let transportChoiceLifetime: TimeInterval = 300

    /// Is there a still-valid answer to the question for the Clock-In in progress?
    func transportAnswerIsCurrent(_ rules: AttendanceRules) -> Bool {
        guard let choice = transportChoice, let at = transportChoiceAt else { return false }
        if Date().timeIntervalSince(at) > Self.transportChoiceLifetime { return false }
        return TransportMode.choice(picked: choice, options: rules.transportModes) != nil
    }

    /// Must "How are you travelling today?" be answered before this punch goes any further? True (and the picker is now
    /// on screen; `resume` runs once the rep has answered) only for a CHECK-IN of a client whose rule is on, has choices,
    /// and has no current answer. False for every other punch and every other client — the caller carries on as ever.
    func askClockInQuestionIfNeeded(isCheckIn: Bool, resume: @escaping () -> Void) -> Bool {
        guard isCheckIn else { return false }
        let rules: AttendanceRules = AttendanceRulesStore.shared.currentRules()
        guard rules.transportPromptActive else { return false }
        if transportAnswerIsCurrent(rules) { return false }
        afterTransportChoice = resume
        transportRequest = TransportPickRequest(options: rules.transportModes)
        return true
    }

    /// The rep picked a way of travelling. The sheet closes; `transportSheetDismissed()` then re-enters the flow.
    func transportAnswered(_ id: String) {
        transportChoice = id
        transportChoiceAt = Date()
        transportRequest = nil
    }

    /// The rep backed out of the question: nothing is chosen, the Clock-In does not go on.
    func transportCancelled() {
        afterTransportChoice = nil
        transportRequest = nil
    }

    /// The question's sheet has finished closing. If it was answered, carry on with the interrupted flow (doing it here,
    /// not at the tap, keeps the camera from being presented while the sheet is still on its way out).
    func transportSheetDismissed() {
        let next = afterTransportChoice
        afterTransportChoice = nil
        if transportChoice != nil { next?() }
    }

    /// The answer belonged to one Clock-In; the next one asks again.
    func clearTransportChoice() {
        transportChoice = nil
        transportChoiceAt = nil
    }

    // MARK: - Home's chip: change today's mode

    /// "Change" was tapped: may the rep be asked? False (with the reason in `transportMessage`) when there is no
    /// connection, no check-in, or a check-in the server does not have yet — so nobody picks a mode only to be told it
    /// cannot be saved.
    func beginTransportChange() -> Bool {
        if let blocked = TransportMode.cannotChange(online: AttendanceCache.shared.isOnline,
                                                    record: KiniAppState.shared.today,
                                                    checkinQueued: hasQueuedCheckIn()) {
            setTransportMessage(blocked)
            return false
        }
        return true
    }

    /// Change today's mode of transport (`PATCH /attendance/transport-mode`). ONLINE ONLY and honest: with no
    /// connection, no check-in, or a check-in the server does not have yet, nothing is sent and the rep is told why; a
    /// failure says whether it was the connection or the server's own reason. Only a choice the rules offer is sent. A
    /// second tap while one is running is ignored.
    func changeTransportMode(_ mode: String) {
        if transportBusy { return }
        let rules: AttendanceRules = AttendanceRulesStore.shared.currentRules()
        guard rules.transportPromptActive,
              let pick = TransportMode.choice(picked: mode, options: rules.transportModes) else {
            setTransportMessage("Choose one of the listed ways of travelling.")
            return
        }
        let record: AttendanceRecord? = KiniAppState.shared.today
        if let blocked = TransportMode.cannotChange(online: AttendanceCache.shared.isOnline, record: record,
                                                    checkinQueued: hasQueuedCheckIn()) {
            setTransportMessage(blocked)
            return
        }
        transportBusy = true
        let date: String? = TransportMode.changeDate(record: record, now: Date())
        Task { [weak self] in
            let result = await KinematicRepository.shared.setTransportMode(pick, date: date)
            guard let self = self else { return }
            self.transportBusy = false
            if result.success {
                self.applyTransportChange(mode: pick, serverRow: result.record)
                self.setTransportMessage("Travel mode updated")
            } else {
                self.setTransportMessage(TransportMode.changeFailure(
                    httpStatus: result.httpStatus, message: result.message, retryable: result.failure == .transient))
            }
        }
    }

    /// Show a line about the travel mode once (it clears itself).
    func setTransportMessage(_ text: String) {
        transportMessage = text
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self = self else { return }
            if self.transportMessage == text { self.transportMessage = nil }
        }
    }

    /// The server now holds `mode` for today: show it (and remember it, so a Home read that leaves it out cannot undo it).
    func applyTransportChange(mode: String, serverRow: AttendanceRecord?) {
        if let updated = TransportMode.applyChange(record: KiniAppState.shared.today, mode: mode, serverRow: serverRow) {
            KiniAppState.shared.today = updated
            rememberTransport(mode: updated.transportMode ?? mode, label: updated.transportLabel, record: updated)
        }
        if let mirror = TransportMode.applyChange(record: self.today, mode: mode, serverRow: serverRow) {
            self.today = mirror
        }
    }

    /// Remember the mode the server holds for the record's day.
    func rememberTransport(mode: String, label: String?, record: AttendanceRecord?) {
        knownTransport = KnownTransportMode(date: recordDay(record), mode: mode, label: label)
    }

    /// The `yyyy-MM-dd` of a record (today in India when it carries no date).
    func recordDay(_ record: AttendanceRecord?) -> String {
        if let d = record?.date, !d.isEmpty { return OfflinePunchState.isoDateOf(d) }
        return OfflinePunch.istDate(Date())
    }

    /// Is a check-in waiting in the queue (so the server has no attendance row to change yet)?
    func hasQueuedCheckIn() -> Bool {
        let cache = AttendanceCache.shared
        // The common case (nothing queued) answers without looking up who is signed in.
        if !cache.rows.contains(where: { $0.kind == "checkin" && !$0.isSynced && $0.rejectedReason == nil }) { return false }
        return cache.pendingForCurrentUser().contains(where: { $0.kind == "checkin" })
    }

    /// Today's mode of transport id (an id of the attendance rules' `transport_modes`), or nil when none is recorded or the
    /// client does not ask. For the post-checkout travel prompt (`TransportMode.preselectVehicle`).
    var todayTransportMode: String? {
        if let m = KiniAppState.shared.today?.transportMode, TransportMode.isValidId(m) { return m }
        if let known = knownTransport, known.date == recordDay(KiniAppState.shared.today) { return known.mode }
        return nil
    }

    // MARK: - Self-heal

    /// Silent self-heal for mode of transport: the check-in carried `modeSent`, but the record the server handed back has
    /// none (`TransportMode.needsRepair`: the data layer lost the column for that request). Then the mode is set once with
    /// the same PATCH "Change" uses. Nothing is shown either way: on success the chip simply shows the mode; on any
    /// failure the "Set" chip stays so the rep can set it themselves.
    func repairTransportModeIfNeeded(modeSent: String?, returned: AttendanceRecord?, expectedDate: String? = nil) {
        guard let mode = modeSent,
              TransportMode.needsRepair(modeSent: mode, returned: returned, expectedDate: expectedDate) else { return }
        let date: String? = TransportMode.changeDate(record: returned, now: Date())
        Task { [weak self] in
            let result = await KinematicRepository.shared.setTransportMode(mode, date: date)
            guard let self = self, result.success else { return }
            self.applyTransportChange(mode: mode, serverRow: result.record)
        }
    }

    // MARK: - What a punch that reached the server means

    /// A punch the server accepted while the rep was waiting (online). A check-in: remember the travel mode it holds and
    /// heal one the server lost. A check-out: raise the final-check-out signal (`freshCheckoutDate`). Either way, offer
    /// the daily odometer-trip capture (START at check-in, END at check-out) — inert unless the policy opts in.
    func punchReachedServerOnline(isCheckIn: Bool, modeSent: String?, record: AttendanceRecord?, shiftBefore: AttendanceRecord?) {
        if isCheckIn {
            if let r = record, let mode = r.transportMode, TransportMode.isValidId(mode) {
                rememberTransport(mode: mode, label: r.transportLabel, record: r)
            }
            repairTransportModeIfNeeded(modeSent: modeSent, returned: record)
            // Daily odometer trip (opt-in clients only): offer the START capture now the check-in has reached the
            // server. Optional and skippable — the model self-gates on the policy + the server's `enabled`.
            let day = recordDay(record)
            Task { @MainActor in OdometerCaptureModel.shared.onCheckIn(date: day) }
        } else {
            let shiftDay = OfflinePunchState.shiftDate(today: shiftBefore, capturedAt: Date())
            freshCheckoutDate = shiftDay
            // Daily odometer trip: offer the END capture after the final check-out (prices and closes the trip).
            Task { @MainActor in OdometerCaptureModel.shared.onCheckOut(date: shiftDay) }
        }
    }

    /// Whoever acts on the final-check-out signal (the travel prompt) calls this once it has taken it.
    func consumeFreshCheckout() {
        freshCheckoutDate = nil
    }

    /// A queued punch (one `AttendanceCache.flush` sent) has reached the server. Heal a travel mode the server lost; and for
    /// an offline-capable punch — whose stand-in just left the queue — pull the real record.
    func queuedPunchReachedServer(_ row: PendingAttendance, record: AttendanceRecord?) {
        guard Session.isAuthenticated else { return }
        if row.kind == "checkin" {
            repairTransportModeIfNeeded(modeSent: row.transportMode, returned: record, expectedDate: row.attendanceDate)
        }
        if row.capturedAt != nil {
            Task { [weak self] in
                await self?.refresh(force: true)
            }
        }
    }

    /// Sign-out: nothing of this person's attendance flow may be left for the next one.
    func resetForSignOut() {
        transportChoice = nil
        transportChoiceAt = nil
        transportRequest = nil
        afterTransportChoice = nil
        transportBusy = false
        transportMessage = nil
        gpsPunching = false
        freshCheckoutDate = nil
        knownTransport = nil
        // The daily odometer-trip capture belongs to the person who was signed in; nothing of it may carry over.
        Task { @MainActor in OdometerCaptureModel.shared.reset() }
    }

    // MARK: - Reading today

    /// A server read of today's record with what this phone knows laid over it: the travel mode (the Home payload omits
    /// it) and any punch still waiting in the offline queue (a stand-in record). Returns `server` untouched when there
    /// is neither — i.e. for every client that does not use these rules.
    func mergedToday(_ server: AttendanceRecord?) -> AttendanceRecord? {
        var rec: AttendanceRecord? = server
        if var r = rec, r.checkinAt != nil, r.transportMode == nil, let known = knownTransport,
           known.date == recordDay(r) {
            r.transportMode = known.mode
            if r.transportLabel == nil { r.transportLabel = known.label }
            rec = r
        }
        return OfflinePunchState.effectiveToday(base: rec, punches: AttendanceCache.shared.punchesForCurrentUser())
    }

    /// When the client asks "How are you travelling today?", the Home payload (which has no `transport_mode`) is topped
    /// up from `GET /attendance/today`. Returns `rec` untouched (and asks nothing) for every other client.
    func todayWithTransportMode(_ rec: AttendanceRecord?) async -> AttendanceRecord? {
        guard var r = rec, r.checkinAt != nil, r.transportMode == nil else { return rec }
        guard AttendanceRulesStore.shared.currentRules().transportPromptActive else { return rec }
        // Already known for this day (`mergedToday` lays it over the Home payload): no need to ask again every refresh.
        if let known = knownTransport, known.date == recordDay(r) { return rec }
        guard let full = await KinematicRepository.shared.fetchAttendanceToday(), full.checkinAt != nil else { return rec }
        guard recordDay(full) == recordDay(r) else { return rec }
        guard let mode = full.transportMode, TransportMode.isValidId(mode) else { return rec }
        r.transportMode = mode
        r.transportLabel = full.transportLabel
        rememberTransport(mode: mode, label: full.transportLabel, record: r)
        return r
    }

    // MARK: - GPS-only punch (rule selfie_required: false)

    /// Check in / check out with ONE tap: a fresh location, then the same `toggleAttendance` the camera flow ends in —
    /// with no photo. A second tap while one is running is ignored. Without a usable fix nothing is sent and the rep is
    /// told to try again — a location is never invented.
    func punchGpsOnly() async {
        if gpsPunching || isLoading { return }
        let isCheckIn: Bool = KiniAppState.shared.today?.checkinAt == nil
        gpsPunching = true
        message = ""
        defer { gpsPunching = false }

        var fix: CLLocation? = LocationTrackingService.shared.lastLocation
        if !AttendancePunch.isFreshEnough(fixTime: fix?.timestamp, now: Date()) {
            fix = await FreshLocationProvider.fix()
        }
        guard let location = fix else {
            message = AttendancePunch.noFixMessage(isCheckIn: isCheckIn)
            return
        }
        await toggleAttendance(loc: location)
    }

    // MARK: - Offline-capable punch (rule allow_offline_checkin)

    /// Check in / check out for a client with `allow_offline_checkin`. Same steps as the online flow (the location and
    /// security gates have already passed), plus:
    ///  - one Idempotency-Key and one capture instant fixed at the tap, reused by every attempt;
    ///  - the selfie is kept on the phone until it can be uploaded;
    ///  - the server is tried inline with `captured_at` + the key; if that cannot get through for a connectivity reason
    ///    the punch stays in the queue and the screens show it as done ("Checked in 09:12 — will sync when online"),
    ///    with a stand-in record laid over Home;
    ///  - a real refusal (a 4xx, `success:false`) is shown exactly as before and nothing is saved.
    func performOfflineCapablePunch(loc: CLLocation, isCheckIn: Bool, rules: AttendanceRules, modeToSend: String?) async {
        let kind: OfflinePunch.Kind = isCheckIn ? .checkIn : .checkOut
        let cache = AttendanceCache.shared
        let capturedAt = Date()
        let previousToday: AttendanceRecord? = self.today
        let shiftBefore: AttendanceRecord? = KiniAppState.shared.today
        let isExecutive: Bool = Session.currentUser?.role.lowercased().contains("executive") ?? false
        let selfieMandatory: Bool = AttendancePunch.selfieDemanded(isExecutive: isExecutive, ruleRequired: rules.selfieRequired)
        let image: UIImage? = selfie

        // A selfie is demanded but there is none to keep: ask for one instead of saving a punch the server would refuse.
        if OfflinePunch.decide(allowOffline: true, retryable: true, hasPhoto: image != nil, selfieRequired: selfieMandatory) == .needSelfie {
            message = "\(kind.noun) failed: \(OfflinePunch.selfieRequiredMessage)"
            return
        }

        isLoading = true
        message = ""
        lastAttendanceActionTime = Date()

        // The selfie stays on the phone until it is uploaded (it cannot be uploaded without a connection).
        var photoName: String? = nil
        if let img = image {
            if let data = KinematicRepository.compressForUpload(img) {
                photoName = cache.savePhoto(data, key: OfflinePunch.newKey(kind))
            }
            if photoName == nil && selfieMandatory {
                isLoading = false
                lastAttendanceActionTime = nil
                message = "\(kind.noun) failed: couldn't save it on this phone. Please try again."
                return
            }
        }

        // OPTIMISTIC UI — flip `today` at once, as the online flow does; rolled back below if the server refuses.
        let localIso: String = OfflinePunch.formatLocalIso(capturedAt)
        var optimistic: AttendanceRecord = previousToday ?? AttendanceRecord(
            id: nil, date: nil, status: nil, checkinAt: nil, checkoutAt: nil,
            totalHours: 0, checkinSelfieUrl: nil, checkoutSelfieUrl: nil)
        if isCheckIn {
            optimistic.status = "present"
            if optimistic.firstCheckinAt == nil { optimistic.firstCheckinAt = localIso }
            optimistic.checkinAt = localIso
            optimistic.checkoutAt = nil
            if let mode = modeToSend { optimistic.transportMode = mode; optimistic.transportLabel = nil }
        } else {
            optimistic.status = "checked_out"
            optimistic.checkoutAt = localIso
            optimistic.lastCheckoutAt = localIso
        }
        self.today = optimistic
        KiniAppState.shared.today = optimistic

        UIDevice.current.isBatteryMonitoringEnabled = true
        let batteryLevel: Int = Int(UIDevice.current.batteryLevel * 100)
        let isMock = SecurityCheck.isMockLocation(loc)
        let accuracy: Double? = loc.horizontalAccuracy >= 0 ? loc.horizontalAccuracy : nil
        let attendanceDate: String = isCheckIn
            ? OfflinePunch.istDate(capturedAt)
            : OfflinePunchState.shiftDate(today: shiftBefore, capturedAt: capturedAt)

        // Persist the intent BEFORE any network call, with the key and the capture time that every attempt will carry.
        let row = cache.enqueue(
            kind: kind.rawValue,
            lat: loc.coordinate.latitude, lng: loc.coordinate.longitude,
            selfieUrl: nil,
            battery: batteryLevel >= 0 ? batteryLevel : nil,
            isMock: isMock, locationAccuracyM: accuracy,
            transportMode: modeToSend,
            capturedAt: capturedAt, attendanceDate: attendanceDate,
            photoFile: photoName, selfieRequired: selfieMandatory)
        cache.beginInline(row.id)

        // Face-recognition attendance (module face_attendance) needs the server (the enrolled reference), so it is
        // skipped without a connection, and a failed enrolment never stands as a verified match.
        if cache.isOnline, ClientFeatures.hasFaceAttendance, let img = image, await FaceRecognition.shared.isAvailable {
            if case .success(let vec, let mid) = await FaceRecognition.shared.embed(img) {
                var faceScore: Double? = nil
                var faceVerified: Bool? = nil
                if let ref = await KinematicRepository.shared.fetchFaceEnrollment(), ref.modelId == mid {
                    let sim = FaceRecognition.shared.similarity(vec, ref.embedding)
                    faceScore = Double(sim)
                    faceVerified = sim >= FACE_MATCH_THRESHOLD
                } else {
                    let enrolled = await KinematicRepository.shared.enrollFace(embedding: vec, modelId: mid, selfieUrl: nil, quality: nil)
                    if enrolled { faceScore = 1.0; faceVerified = true }
                }
                if faceScore != nil || faceVerified != nil {
                    cache.annotateFace(row.id, score: faceScore, verified: faceVerified, modelId: mid)
                }
            }
        }

        // The inline attempt (skipped when the phone itself reports no network: don't sit through timeouts).
        let outcome: AttendanceCache.PunchOutcome
        if cache.isOnline {
            outcome = await cache.attempt(row.id)
        } else {
            cache.recordError(row.id, error: "No connection")
            outcome = .held("No connection")
        }
        cache.endInline(row.id)
        if isCheckIn { clearTransportChoice() }

        switch outcome {
        case .synced(let record):
            var merged: AttendanceRecord = record ?? KiniAppState.shared.today ?? AttendanceRecord(
                id: nil, date: nil, status: nil, checkinAt: nil, checkoutAt: nil,
                totalHours: 0, checkinSelfieUrl: nil, checkoutSelfieUrl: nil)
            if isCheckIn {
                merged.status = "present"
                if merged.firstCheckinAt == nil { merged.firstCheckinAt = merged.checkinAt ?? localIso }
                if merged.checkinAt == nil { merged.checkinAt = localIso }
                merged.checkoutAt = nil
            } else {
                merged.status = "checked_out"
                if merged.checkoutAt == nil { merged.checkoutAt = localIso }
                merged.lastCheckoutAt = merged.checkoutAt
            }
            KiniAppState.shared.today = merged
            self.today = merged
            self.selfie = nil
            message = isCheckIn ? "Checked in!" : "Checked out!"
            punchReachedServerOnline(isCheckIn: isCheckIn, modeSent: modeToSend, record: record, shiftBefore: shiftBefore)
            if isCheckIn {
                rememberCheckinLocation(loc)
                LocationTrackingService.shared.startTracking()
            } else {
                LocationTrackingService.shared.stopTracking()
            }
        case .held:
            // Stays in the queue; Home shows the stand-in and the "will sync when online" notice.
            self.selfie = nil
            if isCheckIn { rememberCheckinLocation(loc) }
            cache.scheduleRetry()
        case .rejected(let reason, let locationRequired):
            // The server (or the punch itself) said no: nothing is saved, so don't say it is — undo the optimistic state.
            cache.remove(row.id)
            self.today = previousToday
            KiniAppState.shared.today = shiftBefore
            self.selfie = nil
            self.lastAttendanceActionTime = nil
            if locationRequired {
                message = ""
                KiniAppState.shared.locationGatePrompt = LocationGatePrompt(verb: isCheckIn ? "check in" : "check out")
                LocationTrackingService.shared.reportLocationStatus()
            } else {
                let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                message = trimmed.isEmpty ? "Couldn't record your attendance. Please try again." : trimmed
            }
        }

        // Pull GROUND TRUTH, bypassing the throttles (the stand-in is laid over it while the punch is still queued).
        await refresh(force: true)
        isLoading = false
    }

    /// The "lat, lng" stamp the Attendance screen shows when the server returns no coordinates.
    private func rememberCheckinLocation(_ loc: CLLocation) {
        let stamp = String(format: "%.4f, %.4f", loc.coordinate.latitude, loc.coordinate.longitude)
        checkinLocationStamp = stamp
        UserDefaults.standard.set(stamp, forKey: "checkin_location_stamp")
    }
}
