import CoreBluetooth
import Foundation
import Observation

enum BluetoothStatus: Equatable {
    case unknown
    case unavailable(String)
    case ready

    var message: String {
        switch self {
        case .unknown: "正在检查蓝牙"
        case let .unavailable(message): message
        case .ready: "蓝牙已就绪"
        }
    }
}

enum BluetoothError: LocalizedError {
    case notReady
    case deviceLost
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notReady: "蓝牙尚未就绪"
        case .deviceLost: "未找到该设备，请重新扫描"
        case let .connectionFailed(message): "连接失败：\(message)"
        }
    }
}

@Observable
@MainActor
final class BluetoothManager: NSObject {
    private(set) var status: BluetoothStatus = .unknown
    private(set) var isScanning = false
    private(set) var nearbyDevices: [NearbyDevice] = []
    private(set) var connectedDevice: NearbyDevice?

    @ObservationIgnored private var centralManager: CBCentralManager!
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var connectionContinuation: CheckedContinuation<Void, Error>?

    override init() {
        super.init()
        centralManager = CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionRestoreIdentifierKey: "com.fabriceyes.fabriclab.central"]
        )
    }

    func startScanning() {
        guard status == .ready else { return }
        nearbyDevices.removeAll()
        isScanning = true
        // NIR 的正式 Service UUID 将由硬件协议文档写入；当前仅在前台按名称过滤。
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }

    func loadDemoDevices() {
        nearbyDevices = [
            NearbyDevice(id: UUID(), name: "NIR-DEMO-01", kind: .nir, rssi: -48),
            NearbyDevice(id: UUID(), name: "IR2210-DEMO-02", kind: .ir2210, rssi: -63),
            NearbyDevice(id: UUID(), name: "NIR-NEW-03", kind: .nir, rssi: -71)
        ]
    }

    func connect(to device: NearbyDevice) async throws {
        stopScanning()
        guard let peripheral = peripherals[device.id] else {
            // Mock 设备不对应 CBPeripheral。
            try await Task.sleep(nanoseconds: 350_000_000)
            connectedDevice = device
            return
        }

        if connectionContinuation != nil {
            throw BluetoothError.connectionFailed("已有连接正在进行")
        }

        try await withCheckedThrowingContinuation { continuation in
            connectionContinuation = continuation
            connectedDevice = device
            centralManager.connect(peripheral, options: nil)
        }
    }

    func disconnect() {
        guard let connectedDevice,
              let peripheral = peripherals[connectedDevice.id]
        else {
            failPendingConnection(with: .deviceLost)
            self.connectedDevice = nil
            return
        }
        centralManager.cancelPeripheralConnection(peripheral)
        failPendingConnection(with: .deviceLost)
        self.connectedDevice = nil
    }

    private func update(_ peripheral: CBPeripheral, rssi: Int) {
        guard let name = peripheral.name,
              let kind = DeviceKind.identify(name: name)
        else { return }

        peripherals[peripheral.identifier] = peripheral
        let device = NearbyDevice(id: peripheral.identifier, name: name, kind: kind, rssi: rssi)
        if let index = nearbyDevices.firstIndex(where: { $0.id == device.id }) {
            nearbyDevices[index] = device
        } else {
            nearbyDevices.append(device)
        }
        nearbyDevices.sort { $0.rssi > $1.rssi }
    }

    private func failPendingConnection(with error: BluetoothError) {
        connectionContinuation?.resume(throwing: error)
        connectionContinuation = nil
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            status = .ready
        case .poweredOff:
            status = .unavailable("蓝牙已关闭")
            failPendingConnection(with: .notReady)
        case .unauthorized:
            status = .unavailable("请在系统设置中允许蓝牙访问")
            failPendingConnection(with: .notReady)
        case .unsupported:
            status = .unavailable("此设备不支持蓝牙")
            failPendingConnection(with: .notReady)
        case .resetting:
            status = .unknown
            failPendingConnection(with: .deviceLost)
        case .unknown:
            status = .unknown
        @unknown default:
            status = .unknown
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        update(peripheral, rssi: RSSI.intValue)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        connectionContinuation?.resume()
        connectionContinuation = nil
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        connectedDevice = nil
        failPendingConnection(
            with: .connectionFailed(error?.localizedDescription ?? "未知原因")
        )
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        if connectedDevice?.id == peripheral.identifier {
            connectedDevice = nil
        }
        failPendingConnection(
            with: .connectionFailed(error?.localizedDescription ?? "设备已断开")
        )
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral] ?? []
        for peripheral in restored {
            peripheral.delegate = self
            peripherals[peripheral.identifier] = peripheral
        }
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil, let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.properties.contains(.notify) {
            peripheral.setNotifyValue(true, for: characteristic)
        }
    }
}
