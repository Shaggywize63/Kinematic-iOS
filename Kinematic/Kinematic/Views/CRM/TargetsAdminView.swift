import SwiftUI

/// Manager-facing Targets screen — set the daily lead target per hierarchy
/// level (e.g. Consumer Champion, Area Sales Officer). Everyone at that level
/// inherits it. Mirrors the web Settings → Targets (per-level control).
struct TargetsAdminView: View {
    @State private var levels: [CRMHierarchyLevel] = []
    @State private var values: [String: Int] = [:]   // level id → target
    @State private var loading = true
    @State private var savingId: String?
    @State private var toast: String?

    var body: some View {
        Form {
            if loading {
                HStack { Spacer(); ProgressView(); Spacer() }
            } else if levels.isEmpty {
                Section {
                    Text("No hierarchy levels are set up for this client yet. Define them on the web dashboard (CRM → Settings → Org Hierarchy), then set per-level targets here.")
                        .font(.caption).foregroundColor(.secondary)
                }
            } else {
                Section(header: Text("Daily lead target per level"),
                        footer: Text("Everyone at a level inherits its target. Individual overrides can be set on the web dashboard.")) {
                    ForEach(levels) { level in
                        HStack(spacing: 12) {
                            Text(level.name)
                                .font(.system(size: 15, weight: .semibold))
                            Spacer()
                            TextField("0", value: Binding(
                                get: { values[level.id] ?? 0 },
                                set: { values[level.id] = max(0, $0) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 56)
                            .textFieldStyle(.roundedBorder)
                            Text("/day").font(.caption).foregroundColor(.secondary)
                            Button {
                                Task { await save(level) }
                            } label: {
                                if savingId == level.id { ProgressView() }
                                else { Text("Save").font(.system(size: 13, weight: .bold)) }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Brand.red)
                            .disabled(savingId == level.id)
                        }
                    }
                }
            }
        }
        .navigationTitle("Targets")
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if let toast {
                Text(toast)
                    .font(.caption.weight(.semibold)).foregroundColor(.white)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Capsule().fill(Brand.success))
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        let lv = await CRMService.shared.listHierarchyLevels()
        let cfg = await CRMService.shared.listTargetsAdmin()
        var map: [String: Int] = [:]
        cfg?.perLevel.forEach { map[$0.hierarchyLevelId] = $0.targetValue }
        await MainActor.run {
            levels = lv
            values = map
            loading = false
        }
    }

    private func save(_ level: CRMHierarchyLevel) async {
        savingId = level.id
        let ok = await CRMService.shared.setLevelTarget(levelId: level.id, value: values[level.id] ?? 0)
        await MainActor.run {
            savingId = nil
            withAnimation { toast = ok ? "Saved \(level.name)" : "Couldn't save" }
        }
        try? await Task.sleep(nanoseconds: 1_800_000_000)
        await MainActor.run { withAnimation { toast = nil } }
    }
}
