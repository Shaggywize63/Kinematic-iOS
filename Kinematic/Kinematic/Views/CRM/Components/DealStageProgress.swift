import SwiftUI

/// Compact stage strip rendered at the top of DealDetailView: one
/// horizontally scrollable row of small stage chips with the current
/// stage highlighted. Tapping a chip moves the deal there (with a
/// confirmation sheet when the target is a Won/Lost stage so we also
/// capture the close reason). Timing signals (days in stage, days to
/// close / overdue) collapse into a single tinted line in the header.
///
/// Web parity: see `src/components/crm/DealStageProgress.tsx` in the
/// kinematic-dashboard repo.
struct DealStageProgress: View {
    @Binding var deal: Deal
    let stages: [Stage]
    /// Optional callback invoked after a silent move succeeds — lets
    /// the parent refresh the History/NBA/WinProb cards.
    let onStageChanged: () -> Void

    @State private var moving = false
    @State private var moveError: String?
    @State private var presentingClose = false
    @State private var pendingCloseStage: Stage?
    @State private var moveSuccessTick = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            heading
            chipsRow
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .sensoryFeedback(.success, trigger: moveSuccessTick)
        .alert("Couldn't change stage",
               isPresented: Binding(
                   get: { moveError != nil },
                   set: { if !$0 { moveError = nil } }
               )) {
            Button("OK", role: .cancel) {}
        } message: { Text(moveError ?? "") }
        .sheet(isPresented: $presentingClose, onDismiss: {
            pendingCloseStage = nil
        }) {
            if pendingCloseStage != nil {
                DealCloseView(deal: deal) { updated in
                    deal = updated
                    onStageChanged()
                }
            }
        }
    }

    // MARK: - Heading

    private var heading: some View {
        HStack(spacing: 8) {
            Text("STAGE")
                .font(.system(size: 10, weight: .black))
                .tracking(1)
                .foregroundColor(Brand.red)
            Spacer()
            if moving {
                ProgressView().controlSize(.small)
            } else if let m = metricsSummary {
                HStack(spacing: 4) {
                    Image(systemName: m.icon).font(.system(size: 9))
                    Text(m.text).font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(m.tint)
                .lineLimit(1)
            }
        }
    }

    // MARK: - Chips row

    private var chipsRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 6) {
                    ForEach(Array(sortedStages.enumerated()), id: \.element.id) { idx, stage in
                        chip(for: stage, idx: idx)
                            .id(stage.id)
                    }
                }
                .padding(.vertical, 1)
            }
            .onAppear {
                // Land with the current stage in view — long pipelines
                // otherwise hide the highlight off-screen to the right.
                if let sid = deal.stageId {
                    proxy.scrollTo(sid, anchor: .center)
                }
            }
        }
    }

    @ViewBuilder
    private func chip(for stage: Stage, idx: Int) -> some View {
        let role = stageRole(stage, idx: idx)
        Button {
            handleTap(stage)
        } label: {
            HStack(spacing: 4) {
                if let icon = role.iconName {
                    Image(systemName: icon)
                        .font(.system(size: 8, weight: .black))
                }
                Text(stage.name.uppercased())
                    .font(.system(size: 10, weight: .black))
                    .tracking(0.3)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(role.bg)
            )
            .overlay(
                Capsule().stroke(role.border, lineWidth: 1)
            )
            .foregroundColor(role.fg)
            .shadow(color: role.shadow, radius: role.shadowRadius, x: 0, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(role.isCurrent || moving)
    }

    // MARK: - Metrics summary

    /// Single-line collapse of the old metric pills. Tint escalates with
    /// the most urgent signal: red when overdue, orange when the close
    /// date is today / under a week out, neutral otherwise.
    private var metricsSummary: (text: String, icon: String, tint: Color)? {
        var parts: [String] = []
        var icon = "clock"
        var tint: Color = .secondary
        if let d = daysInStage {
            parts.append(d == 0 ? "in stage today" : "\(d)d in stage")
        }
        if let d = daysToClose {
            if d < 0 {
                parts.append("\(abs(d))d overdue")
                icon = "exclamationmark.triangle.fill"
                tint = .red
            } else if d == 0 {
                parts.append("closes today")
                icon = "calendar"
                tint = .orange
            } else {
                parts.append("\(d)d to close")
                icon = "calendar"
                if d < 7 { tint = .orange }
            }
        }
        guard !parts.isEmpty else { return nil }
        return (parts.joined(separator: " · "), icon, tint)
    }

    // MARK: - Tap handling

    private func handleTap(_ stage: Stage) {
        guard stage.id != deal.stageId else { return }
        if (stage.isClosed ?? false) {
            // Won/Lost stages route through DealCloseView so we also
            // capture the reason — matches the web dashboard's flow.
            pendingCloseStage = stage
            presentingClose = true
        } else {
            Task { await silentMove(to: stage) }
        }
    }

    private func silentMove(to stage: Stage) async {
        moving = true
        defer { moving = false }
        do {
            let updated = try await CRMService.shared.moveDealStage(
                id: deal.id,
                stageId: stage.id
            )
            deal = updated
            moveSuccessTick &+= 1
            onStageChanged()
        } catch {
            moveError = error.localizedDescription
        }
    }

    // MARK: - Derived state

    private var sortedStages: [Stage] {
        stages.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }

    private var currentIndex: Int {
        guard let sid = deal.stageId else { return -1 }
        return sortedStages.firstIndex(where: { $0.id == sid }) ?? -1
    }

    /// Days the deal has been in the current stage. We don't have a
    /// dedicated `stage_changed_at` on the model, but `updatedAt` is the
    /// best signal we have client-side and matches what the kanban deal
    /// rollups use elsewhere.
    private var daysInStage: Int? {
        guard let raw = deal.updatedAt,
              let date = parseISO(raw) else { return nil }
        return daysBetween(date, Date())
    }

    private var daysToClose: Int? {
        guard let close = deal.expectedCloseDate?.prefix(10),
              let date = DealStageProgress.yyyyMMdd.date(from: String(close)) else {
            return nil
        }
        return daysBetween(Date(), date)
    }

    private func daysBetween(_ a: Date, _ b: Date) -> Int {
        let cal = Calendar.current
        let dA = cal.startOfDay(for: a)
        let dB = cal.startOfDay(for: b)
        return cal.dateComponents([.day], from: dA, to: dB).day ?? 0
    }

    // MARK: - Stage role / palette

    private struct StageRole {
        let bg: Color
        let fg: Color
        let border: Color
        let iconName: String?
        let isCurrent: Bool
        let shadow: Color
        let shadowRadius: CGFloat
    }

    private func stageRole(_ stage: Stage, idx: Int) -> StageRole {
        let isCurrent = idx == currentIndex
        let isReached = idx < currentIndex
        let isWonStage = (stage.isWon ?? false)
        let isClosedStage = (stage.isClosed ?? false)
        let isLostStage = isClosedStage && !isWonStage

        if isCurrent {
            return StageRole(
                bg: Brand.red,
                fg: .white,
                border: Brand.red,
                iconName: nil,
                isCurrent: true,
                shadow: Brand.red.opacity(0.35),
                shadowRadius: 6
            )
        }
        if isReached {
            if isWonStage {
                return StageRole(
                    bg: Color.green.opacity(0.18),
                    fg: .green,
                    border: Color.green.opacity(0.4),
                    iconName: "checkmark",
                    isCurrent: false,
                    shadow: .clear,
                    shadowRadius: 0
                )
            }
            if isLostStage {
                return StageRole(
                    bg: Color.red.opacity(0.16),
                    fg: .red,
                    border: Color.red.opacity(0.4),
                    iconName: "xmark",
                    isCurrent: false,
                    shadow: .clear,
                    shadowRadius: 0
                )
            }
            return StageRole(
                bg: Color.green.opacity(0.14),
                fg: .green,
                border: Color.green.opacity(0.32),
                iconName: "checkmark",
                isCurrent: false,
                shadow: .clear,
                shadowRadius: 0
            )
        }
        // Future
        return StageRole(
            bg: Color.clear,
            fg: .secondary,
            border: Color.secondary.opacity(0.4),
            iconName: nil,
            isCurrent: false,
            shadow: .clear,
            shadowRadius: 0
        )
    }

    // MARK: - Date helpers

    private static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    private func parseISO(_ raw: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let d = plain.date(from: raw) { return d }
        let frac = ISO8601DateFormatter()
        frac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return frac.date(from: raw)
    }
}
