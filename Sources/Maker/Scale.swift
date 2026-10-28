import CoreBluetooth
import Foundation

/// The Half Decent Scale over Bluetooth (CoreBluetooth; the site's scale_maker.js does the same
/// with Web Bluetooth): service FFF0, weight notifications on FFF4, commands written to 36F5.
/// A weight packet is 7 bytes, 03 CE|CA then a big-endian int16 in 0.1 g. Tare is one command;
/// a heartbeat every 4 s keeps the scale talking. The last scale used is remembered, so the next
/// time it's reconnected without a scan (a connected scale doesn't advertise).
///
/// Debug builds take -fakescale 1: a pretend scale that streams readings like the real one
/// (10/s, ±0.1 g jitter) and, with the maker, places the shaker and pours each step by itself,
/// as the site's ?fakescale=1 does for the explainer videos. The simulator has no Bluetooth.
@MainActor
final class Scale: NSObject, ObservableObject {
	static let shared = Scale()

	enum State: Equatable { case off, scanning, connecting, connected, unavailable(String) }
	@Published private(set) var state: State = .off
	/// the latest reading, in grams
	@Published private(set) var weight: Double = 0
	/// called with each reading (the maker's state machine)
	var onWeight: ((Double) -> Void)?

	static let service = CBUUID(string: "FFF0")
	static let readChar = CBUUID(string: "FFF4")
	static let writeChar = CBUUID(string: "36F5")
	static let name = "Decent Scale"
	private static let tareCmd: [UInt8] = [0x03, 0x0f, 0x01, 0x00, 0x00, 0x01, 0x0c]
	private static let heartbeatCmd: [UInt8] = [0x03, 0x0a, 0x03, 0xff, 0xff, 0x00, 0x0a]
	private let lastKey = "scale.last"

	private var central: CBCentralManager?
	private var peripheral: CBPeripheral?
	private var wchar: CBCharacteristic?
	private var heartbeat: Timer?
	private var scanTimeout: Timer?
	/// connect() was asked for before Bluetooth was powered on
	private var wantConnect = false

	let fake: Bool = {
		#if DEBUG
		return UserDefaults.standard.bool(forKey: "fakescale")
		#else
		return false
		#endif
	}()

	var connected: Bool { state == .connected }

	// MARK: connect / disconnect

	func connect() {
		if fake { fakeConnect(); return }
		if connected { return }
		wantConnect = true
		if central == nil { central = CBCentralManager(delegate: self, queue: .main) }   // asks for Bluetooth permission once
		else { go() }
	}
	func disconnect() {
		wantConnect = false
		stopTimers()
		if fake { fakeStop() }
		if let p = peripheral { central?.cancelPeripheralConnection(p) }
		central?.stopScan()
		peripheral = nil; wchar = nil
		state = .off
	}

	/// the scale from last time, if iOS still knows it, else a scan for one by name
	private func go() {
		guard let c = central, wantConnect else { return }
		switch c.state {
		case .poweredOn: break
		case .unauthorized: state = .unavailable(T("Bluetooth is turned off for this app in Settings.")); return
		case .poweredOff: state = .unavailable(T("Bluetooth is off. Turn it on to use the scale.")); return
		case .unsupported: state = .unavailable(T("This device has no Bluetooth.")); return
		default: return   // .unknown / .resetting: centralManagerDidUpdateState calls again
		}
		let known = c.retrieveConnectedPeripherals(withServices: [Self.service]).first { $0.name == nil || $0.name == Self.name }
			?? UserDefaults.standard.string(forKey: lastKey).flatMap(UUID.init).flatMap { c.retrievePeripherals(withIdentifiers: [$0]).first }
		if let p = known {
			attach(p)
			// a remembered scale that's off never answers: give it a few seconds, then scan instead
			scanTimeout?.invalidate()
			scanTimeout = Timer.scheduledTimer(withTimeInterval: 6, repeats: false) { [weak self] _ in
				MainActor.assumeIsolated {
					guard let self, self.state == .connecting, self.peripheral === p else { return }
					c.cancelPeripheralConnection(p)
					self.peripheral = nil
					self.scan()
				}
			}
		} else {
			scan()
		}
	}
	private func scan() {
		guard let c = central else { return }
		state = .scanning
		c.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
		scanTimeout?.invalidate()
		scanTimeout = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in
			MainActor.assumeIsolated {
				guard let self, self.state == .scanning else { return }
				c.stopScan()
				self.wantConnect = false
				self.state = .unavailable(T("No scale found. Is it turned on and nearby?"))
			}
		}
	}
	private func attach(_ p: CBPeripheral) {
		peripheral = p
		p.delegate = self
		state = .connecting
		central?.connect(p)
	}

	// MARK: commands

	func tare() {
		if fake { fakeTare(); return }
		send(Self.tareCmd)
	}
	private func send(_ bytes: [UInt8]) {
		guard let p = peripheral, let w = wchar else { return }
		p.writeValue(Data(bytes), for: w, type: w.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse)
	}
	private func startHeartbeat() {
		heartbeat?.invalidate()
		send(Self.heartbeatCmd)
		heartbeat = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
			MainActor.assumeIsolated { self?.send(Self.heartbeatCmd) }
		}
	}
	private func stopTimers() {
		heartbeat?.invalidate(); heartbeat = nil
		scanTimeout?.invalidate(); scanTimeout = nil
	}

	fileprivate func reading(_ d: Data) {
		guard d.count == 7, d[d.startIndex] == 0x03 else { return }
		let t = d[d.startIndex + 1]
		guard t == 0xce || t == 0xca else { return }
		let raw = Int16(bitPattern: UInt16(d[d.startIndex + 2]) << 8 | UInt16(d[d.startIndex + 3]))
		setWeight(Double(raw) / 10)
	}
	private func setWeight(_ w: Double) {
		weight = w
		onWeight?(w)
	}

	// MARK: fake scale (debug)

	private var fakeW = 0.0
	private var fakeTick: Timer?
	private var fakeAnim: Timer?
	/// the maker pours each step by itself (fakeAuto), as the site's fake scale does
	var fakeAuto = true

	private func fakeConnect() {
		state = .scanning
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [self] in
			fakeW = 0
			fakeTick?.invalidate()
			fakeTick = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
				MainActor.assumeIsolated {
					guard let self else { return }
					self.setWeight(((self.fakeW + (Double.random(in: 0..<1) - 0.5) * 0.2) * 10).rounded() / 10)
				}
			}
			state = .connected
		}
	}
	private func fakeStop() { fakeTick?.invalidate(); fakeTick = nil; fakeAnim?.invalidate(); fakeAnim = nil }
	private func fakeTare() { fakeAnim?.invalidate(); fakeAnim = nil; fakeW = 0 }
	/// move the reading to w over a time, easing out as a pour slows near its target
	func fakeTo(_ w: Double, _ secs: Double, then: (() -> Void)? = nil) {
		fakeAnim?.invalidate()
		let from = fakeW, t0 = Date()
		fakeAnim = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
			MainActor.assumeIsolated {
				guard let self else { return }
				let k = min(1, Date().timeIntervalSince(t0) / secs)
				self.fakeW = from + (w - from) * (1 - pow(1 - k, 3))
				if k >= 1 { t.invalidate(); self.fakeAnim = nil; then?() }
			}
		}
	}
	/// put g grams on (negative takes some off)
	func fakePour(_ g: Double) { fakeTo(fakeW + g, 0.7 + min(1.8, g * 0.022)) }
	var fakeWeight: Double { fakeW }
}

extension Scale: CBCentralManagerDelegate, CBPeripheralDelegate {
	nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
		MainActor.assumeIsolated {
			if central.state == .poweredOn { go() }
			else if central.state != .unknown && central.state != .resetting {
				if connected || wantConnect { stopTimers(); peripheral = nil; wchar = nil; state = .off }
				if wantConnect { go() }
			}
		}
	}
	nonisolated func centralManager(_ central: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
		MainActor.assumeIsolated {
			let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? p.name
			guard state == .scanning, name == Self.name else { return }
			central.stopScan()
			scanTimeout?.invalidate()
			attach(p)
		}
	}
	nonisolated func centralManager(_ central: CBCentralManager, didConnect p: CBPeripheral) {
		MainActor.assumeIsolated {
			scanTimeout?.invalidate()
			p.discoverServices([Self.service])
		}
	}
	nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
		MainActor.assumeIsolated {
			guard p === peripheral else { return }
			peripheral = nil
			if wantConnect { scan() }
		}
	}
	nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
		MainActor.assumeIsolated {
			guard p === peripheral else { return }
			stopTimers()
			peripheral = nil; wchar = nil
			wantConnect = false
			state = .off
		}
	}
	nonisolated func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
		MainActor.assumeIsolated {
			guard let s = p.services?.first(where: { $0.uuid == Self.service }) else { failed(p); return }
			p.discoverCharacteristics([Self.readChar, Self.writeChar], for: s)
		}
	}
	nonisolated func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
		MainActor.assumeIsolated {
			let cs = s.characteristics ?? []
			guard let r = cs.first(where: { $0.uuid == Self.readChar }), let w = cs.first(where: { $0.uuid == Self.writeChar }) else { failed(p); return }
			wchar = w
			p.setNotifyValue(true, for: r)
			UserDefaults.standard.set(p.identifier.uuidString, forKey: lastKey)
			state = .connected
			startHeartbeat()
		}
	}
	nonisolated func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
		let v = c.value
		MainActor.assumeIsolated { if let v { reading(v) } }
	}
	private func failed(_ p: CBPeripheral) {
		central?.cancelPeripheralConnection(p)
		peripheral = nil; wchar = nil
		wantConnect = false
		state = .unavailable(T("That doesn't look like a Decent Scale."))
	}
}
