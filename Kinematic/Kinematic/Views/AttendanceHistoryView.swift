import SwiftUI

/// Paginated attendance history — mirrors Android's `/attendance/history` view.
/// Calls `KinematicRepository.getAttendanceHistory(page:limit:)` and renders
/// each day as a stat-card row matching the CRM module's visual language.
struct AttendanceHistoryView: View {
    @State private var records: [AttendanceRecord] = []
    @State private var isLoading = false
    @State private var page = 1
    @State private var hasMore = true

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                summary
                if records.isEmpty && !isLoading {
                    EmptyHistoryRow().padding(.top, 40)
                } else {
                    ForEach(records, id: \.dayKey) { record in
                        AttendanceHistoryCard(record: record)
                    }
                }
                if isLoading {
                    ProgressView().padding(.vertical, 20)
                } else if hasMore && !records.isEmpty {
                    Button("Load more") { Task { await loadMore() } }
                        .buttonStyle(.bordered)
                        .padding(.top, 8)
                }
            }
            .padding()
        }
        .navigationTitle("Attendance History")
        .navigationBarTitleDisplayMode(.large)
        .task {
            if records.isEmpty { await loadMore() }
        }
        .refreshable {
            page = 1; hasMore = true; records = []
            await loadMore()
        }
    }

    @MainActor
    private func loadMore() async {
        guard !isLoading, hasMore else { return }
        isLoading = true
        let batch = await KinematicRepository.shared.getAttendanceHistory(page: page, limit: 30)
        records.append(contentsOf: batch)
        hasMore = batch.count >= 30
        if hasMore { page += 1 }
        isLoading = false
    }

    private var summary: some View {
        let present = records.filter { $0.checkoutAt != nil || $0.checkinAt != nil }.count
        let avgHours: Double = {
            let total = records.compactMap { $0.totalHours }.reduce(0, +)
            return records.isEmpty ? 0 : total / Double(records.count)
        }()
        return HStack(spacing: 12) {
            statTile(label: "Days", value: "\(records.count)", icon: "calendar", color: Brand.red)
            statTile(label: "Present", value: "\(present)", icon: "checkmark.seal.fill", color: .green)
            statTile(label: "Avg hrs", value: String(format: "%.1f", avgHours), icon: "clock.fill", color: Brand.red)
        }
    }

    private func statTile(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundColor(color)
            Text(value).font(.system(size: 20, weight: .black))
            Text(label.uppercased()).font(.system(size: 10, weight: .black)).tracking(0.5).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
    }
}

private extension AttendanceRecord {
    var dayKey: String { id ?? date ?? UUID().uuidString }
}

private struct AttendanceHistoryCard: View {
    let record: AttendanceRecord

    private static let dayParser: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var dayDate: Date? {
        guard let s = record.date else { return nil }
        return Self.dayParser.date(from: s)
    }

    var body: some View {
        HStack(spacing: 14) {
            dateBadge
            VStack(alignment: .leading, spacing: 4) {
                Text(statusLabel)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(uiColor: .label))
                HStack(spacing: 12) {
                    if let ci = record.firstCheckinAt ?? record.checkinAt {
                        Label(formatTime(ci), systemImage: "arrow.right.circle.fill")
                            .labelStyle(.titleAndIcon).font(.caption2).foregroundColor(.green)
                    }
                    if let co = record.lastCheckoutAt ?? record.checkoutAt {
                        Label(formatTime(co), systemImage: "arrow.left.circle.fill")
                            .labelStyle(.titleAndIcon).font(.caption2).foregroundColor(.red)
                    }
                }
                if let hrs = record.totalHours, hrs > 0 {
                    Text(String(format: "%.1f hrs worked", hrs))
                        .font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            if let url = record.checkinSelfieUrl, let u = URL(string: url) {
                AsyncImage(url: u) { img in
                    img.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { Color(uiColor: .tertiarySystemBackground) }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private var dateBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(record.checkoutAt != nil ? Color.green.opacity(0.12) : Color.orange.opacity(0.12))
                .frame(width: 52, height: 52)
            VStack(spacing: 0) {
                Text(dayString).font(.system(size: 20, weight: .black))
                    .foregroundColor(Color(uiColor: .label))
                Text(monthString).font(.system(size: 9, weight: .black))
                    .foregroundColor(record.checkoutAt != nil ? .green : .orange)
            }
        }
    }

    private var statusLabel: String {
        if record.checkoutAt != nil { return "Shift completed" }
        if record.checkinAt != nil  { return "Shift in progress" }
        return "No record"
    }

    private var dayString: String {
        guard let d = dayDate else { return "--" }
        let f = DateFormatter(); f.dateFormat = "dd"; return f.string(from: d)
    }
    private var monthString: String {
        guard let d = dayDate else { return "---" }
        let f = DateFormatter(); f.dateFormat = "MMM"; return f.string(from: d).uppercased()
    }
}
