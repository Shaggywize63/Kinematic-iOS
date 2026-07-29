// Bluetooth (BLE) thermal-printer manager.
//
// iOS can only talk to BLE thermal printers through CoreBluetooth — the
// old Classic / SPP printers (and any non-MFi accessory) are invisible to a
// standard app. So we scan for BLE peripherals, connect, discover the first
// *writable* characteristic under whatever vendor service the printer exposes
// (FFE0/FFE1, FF00/FF02, 18F0/2AF1, …), and stream the ESC/POS bytes to it in
// small chunks with a short gap so the printer's tiny buffer keeps up.
//
// This is intentionally driver-less: we don't hard-code a service UUID because
// every cheap 58mm printer uses a different one. Scanning with `nil` services
// and picking the first `.write` / `.writeWithoutResponse` characteristic works
// across the common clones van-sales reps buy.

import Foundation
import CoreBluetooth
import Combine

/// High-level connection state the UI can render.
enum PrinterConnectionState: Equatable {
    case idle
    case scanning
    case connecting
    case connected      // connected AND a writable characteristic was found
    case failed(String)
}

@MainActor
final class BluetoothPrinterManager: NSObject, ObservableObject {

    // MARK: - Published state (observed by the picker + order detail)

    /// Named peripherals we've seen while scanning.
    @Published private(set) var discovered: [CBPeripheral] = []
    @Published private(set) var state: PrinterConnectionState = .idle
    /// Peripheral we're currently connected to (may not yet be printable).
    @Published private(set) var connectedPeripheral: CBPeripheral?
    /// Human-readable status / error to surface in the UI.
    @Published var statusMessage: String?

    /// True once we have both a live connection and a characteristic to write to.
    var isReady: Bool { state == .connected && writeCharacteristic != nil }

    // MARK: - Internals

    private var central: CBCentralManager!
    private var writeCharacteristic: CBCharacteristic?
    /// Set true when the user asked to scan before Bluetooth finished powering on.
    private var wantsScan = false
    /// Set when we want to auto-reconnect the last-used printer once powered on.
    private var wantsReconnect = false
    /// Off-main queue used to pace chunked writes.
    private let writeQueue = DispatchQueue(label: "com.kinematic.printer.write")

    private static let lastPeripheralKey = "kinematic_last_printer_id"

    override init() {
        super.init()
        // Delegate callbacks are delivered on the main queue so @Published
        // mutations stay on the main actor.
        central = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API

    /// Begin scanning for BLE printers. Safe to call before Bluetooth is ready —
    /// the scan is deferred until `centralManagerDidUpdateState` reports poweredOn.
    func startScan() {
        wantsScan = true
        discovered.removeAll()
        switch central.state {
        case .poweredOn:
            beginScanning()
        case .poweredOff:
            state = .failed("Bluetooth is off. Turn it on in Control Centre or Settings.")
        case .unauthorized:
            state = .failed("Bluetooth permission is off. Enable it for Kinematic in Settings.")
        case .unsupported:
            state = .failed("This device has no Bluetooth LE support.")
        default:
            // .resetting / .unknown — wait for the state callback.
            state = .scanning
        }
    }

    func stopScan() {
        wantsScan = false
        if central.state == .poweredOn { central.stopScan() }
        if state == .scanning { state = .idle }
    }

    /// Connect to a chosen peripheral and look for its writable characteristic.
    func connect(_ peripheral: CBPeripheral) {
        stopScan()
        state = .connecting
        statusMessage = "Connecting to \(displayName(peripheral))…"
        connectedPeripheral = peripheral
        peripheral.delegate = self
        central.connect(peripheral, options: nil)
    }

    /// Try to silently reconnect the last printer this device used.
    func reconnectLast() {
        guard let idString = UserDefaults.standard.string(forKey: Self.lastPeripheralKey),
              let uuid = UUID(uuidString: idString) else { return }
        wantsReconnect = true
        if central.state == .poweredOn {
            attemptReconnect(uuid)
        }
        // else: deferred to the poweredOn state callback.
    }

    func disconnect() {
        if let p = connectedPeripheral { central.cancelPeripheralConnection(p) }
        writeCharacteristic = nil
        connectedPeripheral = nil
        state = .idle
    }

    /// Write ESC/POS bytes to the connected printer, chunked with a small gap.
    /// `completion` fires on the main actor once every chunk has been queued.
    func print(_ data: Data, completion: (@MainActor (Bool) -> Void)? = nil) {
        guard let peripheral = connectedPeripheral, let ch = writeCharacteristic else {
            statusMessage = "No printer connected."
            completion?(false)
            return
        }

        let type: CBCharacteristicWriteType = ch.properties.contains(.writeWithoutResponse)
            ? .withoutResponse : .withResponse

        // Respect the negotiated MTU but never exceed ~180 bytes/chunk — cheap
        // printers drop bytes above that even when the MTU claims more.
        let mtu = peripheral.maximumWriteValueLength(for: type)
        let chunkSize = max(20, min(180, mtu))

        var chunks: [Data] = []
        var idx = 0
        while idx < data.count {
            let end = min(idx + chunkSize, data.count)
            chunks.append(data.subdata(in: idx..<end))
            idx = end
        }

        writeQueue.async {
            for chunk in chunks {
                peripheral.writeValue(chunk, for: ch, type: type)
                // ~20ms breather so the printer's buffer keeps up.
                Thread.sleep(forTimeInterval: 0.02)
            }
            Task { @MainActor in
                self.statusMessage = "Sent to printer."
                completion?(true)
            }
        }
    }

    // MARK: - Helpers

    func displayName(_ peripheral: CBPeripheral) -> String {
        peripheral.name ?? "Unknown printer"
    }

    private func beginScanning() {
        state = .scanning
        statusMessage = "Searching for printers…"
        // nil services => broad scan; cheap printers advertise vendor UUIDs we
        // can't enumerate ahead of time. Allow duplicates off so the list is stable.
        central.scanForPeripherals(withServices: nil,
                                   options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }

    private func attemptReconnect(_ uuid: UUID) {
        let known = central.retrievePeripherals(withIdentifiers: [uuid])
        guard let peripheral = known.first else {
            wantsReconnect = false
            return
        }
        connect(peripheral)
    }

    private func rememberLast(_ peripheral: CBPeripheral) {
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: Self.lastPeripheralKey)
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothPrinterManager: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                if wantsReconnect,
                   let idString = UserDefaults.standard.string(forKey: Self.lastPeripheralKey),
                   let uuid = UUID(uuidString: idString) {
                    attemptReconnect(uuid)
                }
                if wantsScan { beginScanning() }
            case .poweredOff:
                state = .failed("Bluetooth is off. Turn it on to print.")
                discovered.removeAll()
                connectedPeripheral = nil
                writeCharacteristic = nil
            case .unauthorized:
                state = .failed("Bluetooth permission is off. Enable it for Kinematic in Settings.")
            case .unsupported:
                state = .failed("This device has no Bluetooth LE support.")
            case .resetting, .unknown:
                break
            @unknown default:
                break
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDiscover peripheral: CBPeripheral,
                                    advertisementData: [String: Any],
                                    rssi RSSI: NSNumber) {
        // Prefer the advertised local name; fall back to the cached peripheral name.
        let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advName ?? peripheral.name
        Task { @MainActor in
            // Only surface named devices — an unnamed peripheral is almost never
            // the printer the rep is looking for, and clutters the picker.
            guard name != nil, !name!.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            if !discovered.contains(where: { $0.identifier == peripheral.identifier }) {
                discovered.append(peripheral)
            }
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            statusMessage = "Discovering services…"
            peripheral.delegate = self
            peripheral.discoverServices(nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didFailToConnect peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            state = .failed("Couldn't connect: \(error?.localizedDescription ?? "unknown error").")
            connectedPeripheral = nil
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager,
                                    didDisconnectPeripheral peripheral: CBPeripheral,
                                    error: Error?) {
        Task { @MainActor in
            if connectedPeripheral?.identifier == peripheral.identifier {
                writeCharacteristic = nil
                connectedPeripheral = nil
                if case .connected = state { state = .idle }
            }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothPrinterManager: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error = error {
            Task { @MainActor in state = .failed("Service discovery failed: \(error.localizedDescription)") }
            return
        }
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral,
                                didDiscoverCharacteristicsFor service: CBService,
                                error: Error?) {
        guard error == nil else { return }
        // First characteristic that accepts writes wins.
        let writable = (service.characteristics ?? []).first { ch in
            ch.properties.contains(.write) || ch.properties.contains(.writeWithoutResponse)
        }
        guard let ch = writable else { return }
        Task { @MainActor in
            // Only latch the very first writable characteristic we find.
            guard writeCharacteristic == nil else { return }
            writeCharacteristic = ch
            connectedPeripheral = peripheral
            state = .connected
            statusMessage = "Connected to \(displayName(peripheral))."
            rememberLast(peripheral)
        }
    }
}
