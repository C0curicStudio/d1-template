import Foundation
import CoreBluetooth
import PDFKit
import UIKit

/// 蓝牙打印机（BLE）：自动搜索附近设备、把像打印机的排在前面、自动重连上次用的，
/// 把页面转成 1 位点阵，用 ESC/POS 光栅指令（GS v 0）分块发送。
/// 说明：iOS 上普通 A4 喷墨/激光打印机走 AirPrint（Wi-Fi），不走蓝牙；这里适用于 BLE 热敏/便携打印机。
final class BTPrinter: NSObject, ObservableObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    struct Found: Identifiable {
        let id: UUID
        var name: String
        var rssi: Int
        var likelyPrinter: Bool
    }

    enum PaperWidth: Int, CaseIterable, Identifiable {
        case mm58 = 384, mm80 = 576, a4 = 1728
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .mm58: return "58mm"
            case .mm80: return "80mm"
            case .a4: return "A4 宽"
            }
        }
    }

    @Published var found: [Found] = []
    @Published var status = "正在检查蓝牙…"
    @Published var scanning = false
    @Published var connectedName: String?
    @Published var progress: Double?
    @Published var ready = false // 已连接并找到可写通道
    @Published var paper: PaperWidth = .a4

    private var central: CBCentralManager!
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var target: CBPeripheral?
    private var writeChar: CBCharacteristic?
    private var withoutResponse = true
    private var queue: [Data] = []
    private var total = 0
    private let lastKey = "lastPrinter"

    // 常见 BLE 打印机的服务 / 写入特征
    private let hintServices: [CBUUID] = [CBUUID(string: "18F0"), CBUUID(string: "FF00"), CBUUID(string: "FFE0"), CBUUID(string: "E7810A71-73AE-499D-8C15-FAA9AEF0C3F2"), CBUUID(string: "49535343-FE7D-4AE5-8FA9-9FAFD205E455")]
    private let hintWrite: [CBUUID] = [CBUUID(string: "2AF1"), CBUUID(string: "FF02"), CBUUID(string: "BEF8D6C9-9C21-4C9E-B632-BD58C1009F9F"), CBUUID(string: "49535343-8841-43F4-A8D4-ECBE34729BB3"), CBUUID(string: "FFE1")]
    private let nameWords = ["print", "printer", "phomemo", "peri", "goojprt", "mpt", "mini", "pt-", "pos", "thermal", "m02", "m04", "m08", "t02", "t04", "a4", "mx", "bluetooth printer", "打印"]

    override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: nil)
    }

    // MARK: 搜索与连接
    func start() {
        guard central.state == .poweredOn else { return }
        found.removeAll()
        scanning = true
        status = "正在搜索附近的蓝牙设备…"
        // 先试着重连上次的打印机
        if let s = UserDefaults.standard.string(forKey: lastKey), let id = UUID(uuidString: s), let p = central.retrievePeripherals(withIdentifiers: [id]).first, target == nil {
            peripherals[id] = p
            connect(id)
        }
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.stop() }
    }

    func stop() {
        central.stopScan()
        scanning = false
        if !ready && target == nil { status = found.isEmpty ? "没有找到设备，确认打印机已开机并靠近手机" : "选择你的打印机" }
    }

    func connect(_ id: UUID) {
        guard let p = peripherals[id] else { return }
        if let t = target, t.identifier != id { central.cancelPeripheralConnection(t) }
        target = p
        p.delegate = self
        ready = false
        writeChar = nil
        connectedName = p.name ?? "打印机"
        status = "正在连接 \(connectedName ?? "")…"
        central.connect(p)
    }

    func disconnect() {
        if let t = target { central.cancelPeripheralConnection(t) }
        target = nil; ready = false; connectedName = nil; writeChar = nil
        status = "已断开"
    }

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        switch c.state {
        case .poweredOn: status = "蓝牙已开启"; start()
        case .poweredOff: status = "蓝牙未开启，请在控制中心打开"
        case .unauthorized: status = "没有蓝牙权限：设置 → MAX NOTE → 蓝牙"
        case .unsupported: status = "这台设备不支持蓝牙"
        default: status = "正在检查蓝牙…"
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name ?? ""
        guard !name.isEmpty else { return } // 没名字的多半是别的设备，不列出来
        peripherals[p.identifier] = p
        let services = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
        let low = name.lowercased()
        let likely = services.contains(where: { hintServices.contains($0) }) || nameWords.contains(where: { low.contains($0) })
        let item = Found(id: p.identifier, name: name, rssi: RSSI.intValue, likelyPrinter: likely)
        if let i = found.firstIndex(where: { $0.id == item.id }) { found[i] = item } else { found.append(item) }
        found.sort { ($0.likelyPrinter ? 0 : 1, -$0.rssi) < ($1.likelyPrinter ? 0 : 1, -$1.rssi) }
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        status = "已连接，正在识别打印通道…"
        p.discoverServices(nil)
    }
    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        target = nil; ready = false; connectedName = nil
        status = "连接失败：\(error?.localizedDescription ?? "未知原因")"
    }
    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        if p.identifier == target?.identifier { target = nil; ready = false; connectedName = nil; writeChar = nil; progress = nil; queue.removeAll(); status = "打印机已断开" }
    }

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        for s in p.services ?? [] { p.discoverCharacteristics(nil, for: s) }
    }
    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        guard writeChar == nil else { return }
        let all = s.characteristics ?? []
        let pick = all.first(where: { hintWrite.contains($0.uuid) && ($0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse)) })
            ?? all.first(where: { $0.properties.contains(.writeWithoutResponse) })
            ?? all.first(where: { $0.properties.contains(.write) })
        if let c = pick {
            writeChar = c
            withoutResponse = c.properties.contains(.writeWithoutResponse)
            ready = true
            status = "已连接 \(p.name ?? "打印机")，可以打印"
            UserDefaults.standard.set(p.identifier.uuidString, forKey: lastKey)
        }
    }

    // MARK: 发送
    private var chunkSize: Int {
        guard let p = target else { return 20 }
        return max(20, min(512, p.maximumWriteValueLength(for: withoutResponse ? .withoutResponse : .withResponse)))
    }

    private func enqueue(_ data: Data) {
        let n = chunkSize
        var i = 0
        while i < data.count {
            queue.append(data.subdata(in: i..<min(i + n, data.count)))
            i += n
        }
    }

    private func pump() {
        guard let p = target, let c = writeChar else { return }
        if withoutResponse {
            while !queue.isEmpty && p.canSendWriteWithoutResponse {
                p.writeValue(queue.removeFirst(), for: c, type: .withoutResponse)
                tick()
            }
        } else if !queue.isEmpty {
            p.writeValue(queue.removeFirst(), for: c, type: .withResponse)
            tick()
        }
        if queue.isEmpty && total > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self = self, self.queue.isEmpty else { return }
                self.progress = nil; self.total = 0
                self.status = "已发送完成"
            }
        }
    }
    private func tick() { if total > 0 { progress = 1 - Double(queue.count) / Double(total) } }

    func peripheralIsReady(toSendWriteWithoutResponse p: CBPeripheral) { pump() }
    func peripheral(_ p: CBPeripheral, didWriteValueFor c: CBCharacteristic, error: Error?) { pump() }

    /// 打印整个 PDF（每页一张 A4）
    func print(_ doc: PDFDocument) {
        guard ready else { return }
        var bytes = Data([0x1B, 0x40]) // ESC @ 初始化
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i), let r = BTPrinter.raster(page, width: paper.rawValue) else { continue }
            let rowBytes = r.width / 8
            var y = 0
            while y < r.height {
                let n = min(120, r.height - y) // 分条发送，缓冲小的打印机也不会溢出
                bytes.append(contentsOf: [0x1D, 0x76, 0x30, 0x00, UInt8(rowBytes & 0xFF), UInt8(rowBytes >> 8), UInt8(n & 0xFF), UInt8(n >> 8)])
                bytes.append(r.bits.subdata(in: (y * rowBytes)..<((y + n) * rowBytes)))
                y += n
            }
            bytes.append(contentsOf: [0x1B, 0x64, 0x03]) // ESC d 3 走纸
        }
        queue.removeAll()
        enqueue(bytes)
        total = queue.count
        progress = 0
        status = "正在发送到打印机…"
        pump()
    }

    /// PDF 页 → 灰度 → 阈值二值化 → 1 位/像素（1 = 黑）
    static func raster(_ page: PDFPage, width: Int) -> (bits: Data, width: Int, height: Int)? {
        let w = (width / 8) * 8
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0 else { return nil }
        let scale = CGFloat(w) / box.width
        let h = Int((box.height * scale).rounded())
        guard h > 0, let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        guard let base = ctx.data else { return nil }
        let px = base.bindMemory(to: UInt8.self, capacity: w * h)
        var out = Data(count: (w / 8) * h)
        out.withUnsafeMutableBytes { raw in
            let o = raw.bindMemory(to: UInt8.self)
            for y in 0..<h {
                for xb in 0..<(w / 8) {
                    var b: UInt8 = 0
                    for bit in 0..<8 where px[y * w + xb * 8 + bit] < 170 { b |= UInt8(0x80 >> bit) }
                    o[y * (w / 8) + xb] = b
                }
            }
        }
        return (out, w, h)
    }
}
