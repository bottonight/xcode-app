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
    case missingCharacteristic(String)
    case invalidData(String)
    case timeout(String)
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notReady: "蓝牙尚未就绪"
        case .deviceLost: "设备连接已断开"
        case let .missingCharacteristic(name): "设备缺少必要特征：\(name)"
        case let .invalidData(message): message
        case let .timeout(operation): "\(operation)超时，请重试"
        case let .connectionFailed(message): "连接失败：\(message)"
        }
    }
}

private enum BLEUUID {
    static let deviceInformation = CBUUID(string: "180A")
    static let serialNumber = CBUUID(string: "2A25")
    static let systemID = CBUUID(string: "2A23")

    static let nirScanService = CBUUID(string: "53455206-444C-5020-4E49-52204E616E6F")
    static let nirStartScan = CBUUID(string: "4348411D-444C-5020-4E49-52204E616E6F")
    static let nirRequestScanData = CBUUID(string: "43484127-444C-5020-4E49-52204E616E6F")
    static let nirReturnScanData = CBUUID(string: "43484128-444C-5020-4E49-52204E616E6F")

    static let irService = CBUUID(string: "FFE0")
    static let irWrite = CBUUID(string: "FFE1")
    static let irNotify = CBUUID(string: "FFE2")
}

private enum BluetoothOperation {
    case idle
    case nirIdentity
    case irIdentity
    case nirWaitingForScanIndex
    case nirCollecting
    case irCollecting
}

private struct IRFrameAssembler {
    private var buffer: [UInt8] = []

    mutating func reset() {
        buffer.removeAll()
    }

    mutating func feed(_ data: Data) -> [[UInt8]] {
        buffer.append(contentsOf: data)
        if buffer.count > 2_048 {
            buffer = Array(buffer.suffix(2))
        }

        var frames: [[UInt8]] = []
        while buffer.count >= 4 {
            guard let start = buffer.indices.dropLast().first(where: {
                buffer[$0] == 0x55 && buffer[$0 + 1] == 0xD5
            }) else {
                buffer = buffer.last == 0x55 ? [0x55] : []
                break
            }
            if start > 0 {
                buffer.removeFirst(start)
            }
            guard buffer.count >= 4 else { break }

            if buffer[2] == 0xAA {
                frames.append(Array(buffer.prefix(4)))
                buffer.removeFirst(4)
                continue
            }

            guard buffer.count >= 6 else { break }
            let length = Int(buffer[4]) << 8 | Int(buffer[5])
            guard (8 ... 64).contains(length) else {
                buffer.removeFirst()
                continue
            }
            let totalLength = length + 3
            guard buffer.count >= totalLength else { break }
            frames.append(Array(buffer.prefix(totalLength)))
            buffer.removeFirst(totalLength)
        }
        return frames
    }
}

@Observable
@MainActor
final class BluetoothManager: NSObject {
    private(set) var status: BluetoothStatus = .unknown
    private(set) var isScanning = false
    private(set) var nearbyDevices: [NearbyDevice] = []
    private(set) var connectedDevice: NearbyDevice?
    private(set) var connectedIdentity: DeviceIdentity?

    @ObservationIgnored private var centralManager: CBCentralManager!
    @ObservationIgnored private var peripherals: [UUID: CBPeripheral] = [:]
    @ObservationIgnored private var characteristics: [String: [CBCharacteristic]] = [:]
    @ObservationIgnored private var pendingServiceCount = 0
    @ObservationIgnored private var connectionContinuation: CheckedContinuation<Void, Error>?
    @ObservationIgnored private var identityContinuation: CheckedContinuation<DeviceIdentity, Error>?
    @ObservationIgnored private var scanContinuation: CheckedContinuation<ScanCapture, Error>?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?
    @ObservationIgnored private var operation: BluetoothOperation = .idle
    @ObservationIgnored private var nirSerialHex: String?
    @ObservationIgnored private var nirSystemHex: String?
    @ObservationIgnored private var nirExpectsSystemID = false
    @ObservationIgnored private var nirBuffer: [UInt8] = []
    @ObservationIgnored private var irAssembler = IRFrameAssembler()
    @ObservationIgnored private var irSNGroups: [Int: [UInt8]] = [:]
    @ObservationIgnored private var irMeasurementGroups: [Int: [UInt8]] = [:]

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil, options: nil)
    }

    func startScanning() {
        guard status == .ready else { return }
        nearbyDevices.removeAll()
        isScanning = true
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScanning() {
        centralManager.stopScan()
        isScanning = false
    }

    func connect(to device: NearbyDevice) async throws {
        stopScanning()
        guard let peripheral = peripherals[device.id] else {
            throw BluetoothError.deviceLost
        }
        guard connectionContinuation == nil else {
            throw BluetoothError.connectionFailed("已有连接正在进行")
        }

        connectedDevice = device
        connectedIdentity = nil
        characteristics.removeAll()
        try await withCheckedThrowingContinuation { continuation in
            connectionContinuation = continuation
            centralManager.connect(peripheral, options: nil)
            startTimeout(seconds: 12, operationName: "连接设备") { [weak self] in
                self?.failConnection(with: .timeout("连接设备"))
            }
        }
    }

    func readIdentity(for device: NearbyDevice) async throws -> DeviceIdentity {
        if let connectedIdentity { return connectedIdentity }
        guard connectedDevice?.id == device.id,
              let peripheral = peripherals[device.id]
        else { throw BluetoothError.deviceLost }

        return try await withCheckedThrowingContinuation { continuation in
            identityContinuation = continuation
            switch device.kind {
            case .nir:
                guard let serial = characteristic(BLEUUID.serialNumber, readable: true) else {
                    failIdentity(with: .missingCharacteristic("NIR Serial Number 2A25"))
                    return
                }
                operation = .nirIdentity
                nirSerialHex = nil
                nirSystemHex = nil
                let systemID = characteristic(BLEUUID.systemID, readable: true)
                nirExpectsSystemID = systemID != nil
                peripheral.readValue(for: serial)
                if let systemID {
                    peripheral.readValue(for: systemID)
                }
                startTimeout(seconds: 6, operationName: "读取设备编号") { [weak self] in
                    self?.failIdentity(with: .timeout("读取设备编号"))
                }
            case .ir2210:
                operation = .irIdentity
                irSNGroups.removeAll()
                irAssembler.reset()
                startTimeout(seconds: 6, operationName: "读取设备编号") { [weak self] in
                    self?.failIdentity(with: .timeout("读取设备编号"))
                }
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    guard let self, self.operation == .irIdentity else { return }
                    do {
                        try self.writeIRCommand(
                            address: 0x40003007,
                            data: [0x00, 0x10],
                            on: peripheral
                        )
                    } catch {
                        self.failIdentity(with: error)
                    }
                }
            }
        }
    }

    func disconnect() {
        timeoutTask?.cancel()
        if let device = connectedDevice, let peripheral = peripherals[device.id] {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        failAllPending(with: .deviceLost)
        connectedDevice = nil
        connectedIdentity = nil
        operation = .idle
    }

    private func update(_ peripheral: CBPeripheral, rssi: Int) {
        let name = peripheral.name ?? ""
        guard let kind = DeviceKind.identify(name: name) else { return }
        peripherals[peripheral.identifier] = peripheral
        let device = NearbyDevice(id: peripheral.identifier, name: name, kind: kind, rssi: rssi)
        if let index = nearbyDevices.firstIndex(where: { $0.id == device.id }) {
            nearbyDevices[index] = device
        } else {
            nearbyDevices.append(device)
        }
        nearbyDevices.sort { $0.rssi > $1.rssi }
    }

    private func characteristic(
        _ uuid: CBUUID,
        readable: Bool = false,
        writable: Bool = false,
        notifiable: Bool = false
    ) -> CBCharacteristic? {
        characteristics[uuid.uuidString.uppercased()]?.first { item in
            (!readable || item.properties.contains(.read))
                && (!writable || item.properties.contains(.write)
                    || item.properties.contains(.writeWithoutResponse))
                && (!notifiable || item.properties.contains(.notify)
                    || item.properties.contains(.indicate))
        }
    }

    private func store(_ characteristic: CBCharacteristic) {
        characteristics[characteristic.uuid.uuidString.uppercased(), default: []].append(characteristic)
    }

    private func finishServiceDiscovery() {
        pendingServiceCount -= 1
        guard pendingServiceCount == 0 else { return }
        for values in characteristics.values {
            for characteristic in values where characteristic.properties.contains(.notify)
                || characteristic.properties.contains(.indicate) {
                characteristic.service?.peripheral.setNotifyValue(true, for: characteristic)
            }
        }
        timeoutTask?.cancel()
        connectionContinuation?.resume()
        connectionContinuation = nil
    }

    private func write(_ data: Data, to characteristic: CBCharacteristic, on peripheral: CBPeripheral) throws {
        if characteristic.properties.contains(.write) {
            peripheral.writeValue(data, for: characteristic, type: .withResponse)
        } else if characteristic.properties.contains(.writeWithoutResponse),
                  peripheral.canSendWriteWithoutResponse {
            peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
        } else {
            throw BluetoothError.missingCharacteristic(characteristic.uuid.uuidString)
        }
    }

    private func writeIRCommand(address: UInt32, data: [UInt8], on peripheral: CBPeripheral) throws {
        guard let writeCharacteristic = characteristic(BLEUUID.irWrite, writable: true) else {
            throw BluetoothError.missingCharacteristic("IR2210 FFE1")
        }
        let packet = Self.irReadPacket(address: address, data: data)
        try write(packet, to: writeCharacteristic, on: peripheral)
    }

    private static func irReadPacket(address: UInt32, data: [UInt8]) -> Data {
        let length = 8 + data.count
        var body: [UInt8] = [
            0xCD, 0xC4,
            UInt8((length >> 8) & 0xFF), UInt8(length & 0xFF),
            UInt8((address >> 24) & 0xFF), UInt8((address >> 16) & 0xFF),
            UInt8((address >> 8) & 0xFF), UInt8(address & 0xFF)
        ]
        body.append(contentsOf: data)
        let checksum = body.reduce(0) { ($0 + Int($1)) & 0xFF }
        return Data([0x55, 0xD5] + body + [UInt8(checksum)])
    }

    private func handleNIRIdentity(_ data: Data, uuid: CBUUID) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        if uuid == BLEUUID.serialNumber {
            nirSerialHex = hex
        } else if uuid == BLEUUID.systemID {
            nirSystemHex = hex
        }
        guard let serial = nirSerialHex,
              !nirExpectsSystemID || nirSystemHex != nil,
              let device = connectedDevice
        else { return }
        let identity = DeviceIdentity(
            name: device.name,
            serialNumber: serial,
            macNIR: device.id.uuidString,
            uuid: nirSystemHex
        )
        completeIdentity(identity)
    }

    private func handleNIRNotification(_ data: Data, uuid: CBUUID, peripheral: CBPeripheral) {
        let bytes = [UInt8](data)
        if uuid == BLEUUID.nirStartScan,
           operation == .nirWaitingForScanIndex,
           bytes.first == 0xFF,
           bytes.count >= 5 {
            guard let request = characteristic(BLEUUID.nirRequestScanData, writable: true) else {
                failScan(with: .missingCharacteristic("NIR Request Scan Data"))
                return
            }
            operation = .nirCollecting
            nirBuffer.removeAll(keepingCapacity: true)
            do {
                try write(Data(bytes[1 ... 4]), to: request, on: peripheral)
            } catch {
                failScan(with: error)
            }
            return
        }

        guard uuid == BLEUUID.nirReturnScanData,
              operation == .nirCollecting,
              let packetNumber = bytes.first
        else { return }
        if packetNumber != 0 {
            nirBuffer.append(contentsOf: bytes.dropFirst())
        }
        if packetNumber == 202 {
            guard nirBuffer.count == 3822 else {
                failScan(with: .invalidData("NIR 光谱长度为 \(nirBuffer.count)，应为 3822"))
                return
            }
            completeScan(
                ScanCapture(
                    id: UUID(),
                    capturedAt: Date(),
                    data: .nir(nirBuffer.map(Int.init)),
                    preview: []
                )
            )
        }
    }

    private func handleIRNotification(_ data: Data) {
        for frame in irAssembler.feed(data) {
            guard frame.count >= 11, frame[2] == 0xDD, Self.hasValidChecksum(frame) else { continue }
            let address = UInt32(frame[6]) << 24
                | UInt32(frame[7]) << 16
                | UInt32(frame[8]) << 8
                | UInt32(frame[9])

            if address == 0x40003007, operation == .irIdentity, frame.count >= 20 {
                irSNGroups[Int(frame[10])] = Array(frame[11 ..< 19])
                if let first = irSNGroups[1], let second = irSNGroups[2],
                   let device = connectedDevice {
                    let serial = String(bytes: first + second, encoding: .ascii)?
                        .trimmingCharacters(in: .controlCharacters) ?? ""
                    guard !serial.isEmpty else {
                        failIdentity(with: .invalidData("IR2210 序列号为空"))
                        return
                    }
                    completeIdentity(
                        DeviceIdentity(
                            name: device.name,
                            serialNumber: serial,
                            macNIR: nil,
                            uuid: nil
                        )
                    )
                }
            } else if address == 0x40003005, operation == .irCollecting, frame.count >= 20 {
                irMeasurementGroups[Int(frame[10])] = Array(frame[11 ..< 19])
                if irMeasurementGroups.count == 64 {
                    var values: [Double] = []
                    for group in 1 ... 64 {
                        guard let payload = irMeasurementGroups[group], payload.count == 8 else {
                            failScan(with: .invalidData("IR2210 光谱分包不完整"))
                            return
                        }
                        stride(from: 0, to: 8, by: 2).forEach { index in
                            values.append(Double(UInt16(payload[index]) << 8 | UInt16(payload[index + 1])))
                        }
                    }
                    completeScan(
                        ScanCapture(
                            id: UUID(),
                            capturedAt: Date(),
                            data: .ir2210(values),
                            preview: values.enumerated().map {
                                SpectrumPoint(index: $0.offset, intensity: $0.element)
                            }
                        )
                    )
                }
            }
        }
    }

    private static func hasValidChecksum(_ frame: [UInt8]) -> Bool {
        guard frame.count > 3, let expected = frame.last else { return false }
        let actual = frame.dropFirst(2).dropLast().reduce(0) { ($0 + Int($1)) & 0xFF }
        return UInt8(actual) == expected
    }

    private func completeIdentity(_ identity: DeviceIdentity) {
        timeoutTask?.cancel()
        connectedIdentity = identity
        operation = .idle
        identityContinuation?.resume(returning: identity)
        identityContinuation = nil
    }

    private func completeScan(_ capture: ScanCapture) {
        timeoutTask?.cancel()
        operation = .idle
        scanContinuation?.resume(returning: capture)
        scanContinuation = nil
    }

    private func failConnection(with error: BluetoothError) {
        timeoutTask?.cancel()
        connectionContinuation?.resume(throwing: error)
        connectionContinuation = nil
    }

    private func failIdentity(with error: Error) {
        timeoutTask?.cancel()
        operation = .idle
        identityContinuation?.resume(throwing: error)
        identityContinuation = nil
    }

    private func failScan(with error: Error) {
        timeoutTask?.cancel()
        operation = .idle
        scanContinuation?.resume(throwing: error)
        scanContinuation = nil
    }

    private func failAllPending(with error: BluetoothError) {
        failConnection(with: error)
        failIdentity(with: error)
        failScan(with: error)
    }

    private func startTimeout(
        seconds: UInt64,
        operationName: String,
        action: @escaping @MainActor () -> Void
    ) {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            guard !Task.isCancelled else { return }
            action()
        }
    }
}

extension BluetoothManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: status = .ready
        case .poweredOff:
            status = .unavailable("蓝牙已关闭")
            failAllPending(with: .notReady)
        case .unauthorized:
            status = .unavailable("请在系统设置中允许蓝牙访问")
            failAllPending(with: .notReady)
        case .unsupported:
            status = .unavailable("此设备不支持蓝牙")
            failAllPending(with: .notReady)
        case .resetting:
            status = .unknown
            failAllPending(with: .deviceLost)
        case .unknown: status = .unknown
        @unknown default: status = .unknown
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
        let services = connectedDevice?.kind == .ir2210
            ? [BLEUUID.irService]
            : [BLEUUID.deviceInformation, BLEUUID.nirScanService]
        peripheral.discoverServices(services)
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        connectedDevice = nil
        failConnection(with: .connectionFailed(error?.localizedDescription ?? "未知原因"))
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        if connectedDevice?.id == peripheral.identifier {
            connectedDevice = nil
            connectedIdentity = nil
        }
        failAllPending(with: .connectionFailed(error?.localizedDescription ?? "设备已断开"))
    }
}

extension BluetoothManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil, let services = peripheral.services, !services.isEmpty else {
            failConnection(with: .connectionFailed(error?.localizedDescription ?? "未发现设备服务"))
            return
        }
        pendingServiceCount = services.count
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let values = service.characteristics {
            values.forEach(store)
        }
        finishServiceDiscovery()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil, let data = characteristic.value else {
            if let error { failAllPending(with: .connectionFailed(error.localizedDescription)) }
            return
        }
        if operation == .nirIdentity,
           characteristic.uuid == BLEUUID.serialNumber || characteristic.uuid == BLEUUID.systemID {
            handleNIRIdentity(data, uuid: characteristic.uuid)
        } else if characteristic.uuid == BLEUUID.irNotify {
            handleIRNotification(data)
        } else {
            handleNIRNotification(data, uuid: characteristic.uuid, peripheral: peripheral)
        }
    }
}

extension BluetoothManager: MeasurementServicing {
    func scan(device: NearbyDevice, calibration: CalibrationMode) async throws -> ScanCapture {
        guard connectedDevice?.id == device.id,
              let peripheral = peripherals[device.id]
        else { throw BluetoothError.deviceLost }
        guard scanContinuation == nil else {
            throw BluetoothError.connectionFailed("已有扫描正在进行")
        }

        return try await withCheckedThrowingContinuation { continuation in
            scanContinuation = continuation
            switch device.kind {
            case .nir:
                guard let start = characteristic(BLEUUID.nirStartScan, writable: true),
                      characteristic(BLEUUID.nirStartScan, notifiable: true) != nil,
                      characteristic(BLEUUID.nirReturnScanData, notifiable: true) != nil
                else {
                    failScan(with: BluetoothError.missingCharacteristic("NIR Scan Data"))
                    return
                }
                operation = .nirWaitingForScanIndex
                nirBuffer.removeAll()
                do {
                    try write(Data([0x00]), to: start, on: peripheral)
                    startTimeout(seconds: 30, operationName: "NIR 扫描") { [weak self] in
                        self?.failScan(with: BluetoothError.timeout("NIR 扫描"))
                    }
                } catch {
                    failScan(with: error)
                }
            case .ir2210:
                operation = .irCollecting
                irMeasurementGroups.removeAll()
                irAssembler.reset()
                startTimeout(seconds: 12, operationName: "IR2210 扫描") { [weak self] in
                    self?.failScan(with: BluetoothError.timeout("IR2210 扫描"))
                }
                Task { @MainActor [weak self] in
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    guard let self, self.operation == .irCollecting else { return }
                    do {
                        try self.writeIRCommand(
                            address: 0x40003005,
                            data: [0x01, 0x00],
                            on: peripheral
                        )
                    } catch {
                        self.failScan(with: error)
                    }
                }
            }
        }
    }

    func calibrate(device: NearbyDevice) async throws {
        throw AppServiceError.unavailable("请先使用默认校准；手动校准接口将在下一步接入")
    }
}
