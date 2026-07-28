// Printer picker sheet.
//
// Lists BLE printers found while scanning, shows connecting / connected state,
// and calls `onReady` the moment a printer is connected AND has a writable
// characteristic — the caller (order detail) uses that to fire the pending
// print job and dismiss. The last-used printer is remembered by the manager
// (UserDefaults) so the next visit reconnects with one tap.

import SwiftUI
import CoreBluetooth

struct PrinterPickerView: View {
    @ObservedObject var manager: BluetoothPrinterManager
    /// Invoked once a printer reaches the ready (connected + writable) state.
    var onReady: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    statusRow
                }

                Section("Available printers") {
                    if manager.discovered.isEmpty {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Searching…").foregroundColor(.secondary)
                        }
                    } else {
                        ForEach(manager.discovered, id: \.identifier) { peripheral in
                            printerRow(peripheral)
                        }
                    }
                }
            }
            .navigationTitle("Choose Printer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { manager.stopScan(); dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Rescan") { manager.startScan() }
                }
            }
            .task { manager.startScan() }
            .onDisappear { manager.stopScan() }
            // When a printer becomes ready, hand control back to the caller.
            .onChange(of: manager.isReady) { _, ready in
                if ready { onReady() }
            }
        }
    }

    // MARK: - Rows

    @ViewBuilder private var statusRow: some View {
        switch manager.state {
        case .idle:
            Label("Ready to scan", systemImage: "dot.radiowaves.left.and.right")
                .foregroundColor(.secondary)
        case .scanning:
            Label("Scanning for printers…", systemImage: "dot.radiowaves.left.and.right")
        case .connecting:
            HStack(spacing: 10) {
                ProgressView()
                Text(manager.statusMessage ?? "Connecting…")
            }
        case .connected:
            Label(manager.statusMessage ?? "Connected", systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        }
    }

    @ViewBuilder private func printerRow(_ peripheral: CBPeripheral) -> some View {
        let isConnected = manager.connectedPeripheral?.identifier == peripheral.identifier
        let isReady = isConnected && manager.isReady
        Button {
            manager.connect(peripheral)
        } label: {
            HStack {
                Image(systemName: "printer.fill")
                    .foregroundColor(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(manager.displayName(peripheral))
                        .foregroundColor(.primary)
                    if isReady {
                        Text("Connected").font(.caption).foregroundColor(.green)
                    } else if isConnected {
                        Text("Connecting…").font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                if isReady {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                } else if isConnected {
                    ProgressView()
                }
            }
        }
    }
}
