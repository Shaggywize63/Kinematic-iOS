import SwiftUI

/// Inline stage stepper rendered at the top of DealDetailView. Each
/// stage is a tappable pill; tapping moves the deal there (with a
/// confirmation sheet when the target is a Won/Lost stage so we also
/// capture the close reason).
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
        VStack(alignment: .leading, spacing: 10) {
            heading
            pillsRow
            metricsRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
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
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundColor(Brand.red)
                .font(.system(size: 11))
            Text("STAGE PROGRESS")
                .font(.system(size: 10, weight: .black))
                .tracking(0.8)
                .foregroundColor(Brand.red)
            Spacer()
            if moving {
                ProgressView().controlSize(.small)
            } else if let current = currentStage {
                Text(current.name)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Pills row

    private var pillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 6) {
                ForEach(Array(sortedStages.enumerated()), id: \.element.id) { idx, stage in
                    pill(for: stage, idx: idx)
                    if idx < sortedStages.count - 1 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func pill(for stage: Stage, idx: Int) -> some View {
        let role = stageRole(stage, idx: idx)
        Button {
            handleTap(stage)
        } label: {
            HStack(spacing: 5) {
                if role.iconName != nil {
                    Image(systemName: role.iconName!)
                        .font(.system(size: 9, weight: .black))
                }
                Text(stage.name.uppercased())
                    .font(.system(size: 11, weight: .black))
                    .tracking(0.4)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule().fill(role.bg)
            )
            .overlay(
                Capsule().stroke(role.border, lineWidth: 1)
            )
            .foregroundColor(role.fg)
            .shadow(color: role.shadow, radius: role.shadowRadius, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .disabled(role.isCurrent || moving)
    }

    // MARK: - Metrics row

    @ViewBuilder
    private var metricsRow: some View {
        let inStage = daysInStage
        let toClose = daysToClose
        if inStage != nil || toClose != nil {
            HStack(spacing: 6) {
                if let d = inStage {
                    metricPill(
                        text: d == 0 ? "today" : "\(d)d in stage",
                        icon: "clock",
                        tint: .secondary
                    )
                }
                if let d = toClose {
                    metricPill(
                        text: d < 0
                            ? "\(abs(d))d overdue"
                            : d == 0 ? "closes today" : "\(d)d to close",
                        icon: d < 0 ? "exclamationmark.triangle.fill" : "calendar",
                        tint: d < 0 ? .red : (d < 7 ? .orange : .secondary)
                    )
                }
                Spacer()
            }
        }
    }

    private func metricPill(text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 9))
            Text(text).font(.system(size: 10, weight: .bold))
        }
        .padding(.horizontal, 9).padding(.vertical, 4)
        .foregroundColor(tint)
        .background(Capsule().fill(tint.opacity(0.14)))
        .overlay(Capsule().stroke(tint.opacity(0.3), lineWidth: 0.5))
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

    private var currentStage: Stage? {
        guard let sid = deal.stageId else { return nil }
        return sortedStages.first(where: { $0.id == sid })
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
