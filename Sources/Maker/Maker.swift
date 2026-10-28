import Foundation
import SwiftUI

/// The guided weighing of one cocktail on the scale: cocktails/js/scale_maker.js's state machine.
/// Connect -> Tare (the shaker, with its ice, goes on the scale) -> one step per row: every step
/// tares the scale first, so the readout shows what that step added, and the drink's weight is the
/// sum of the steps' tallies -> the serve row (reaching it marks the drink Made) -> the garnishes
/// -> Done, with the target vs what went in, and the facts as it was made.
@MainActor
final class Maker: ObservableObject {
	enum Phase { case connect, tare, step, done }
	enum Kind { case info, success, warn, error }
	struct FinalRow: Identifiable { let id = UUID(); let label: String; let value: String; var ok: Bool? = nil }

	let recipe: Recipe
	let n: Double
	private let scale = Scale.shared

	@Published private(set) var phase: Phase = .connect
	/// the current row (the serve row counts; steps[] doesn't)
	@Published private(set) var idx = 0
	@Published private(set) var readout = "0.0"
	@Published private(set) var progress: Double = 0
	@Published private(set) var progressKind: String = ""     // "", ok, under, over
	@Published private(set) var guide: [String] = []
	@Published private(set) var guideKind: Kind = .info
	@Published private(set) var ingredient: String?
	@Published private(set) var picture: URL?
	@Published private(set) var total: String?
	@Published private(set) var final: [FinalRow] = []
	@Published private(set) var facts: [FinalRow] = []

	private static let zeroTol = 0.2, stableSpread = 0.4, stableN = 4, tol = 1.0
	private static let tareMin = 0.4, tareMax = 2.0, tareZero = 0.5

	private var steps: [Recipe.Row] { recipe.rows }
	private var sv: Int { min(max(recipe.serveAt, 0), steps.count) }
	private func stepAt(_ r: Int) -> Recipe.Row? { r == sv ? nil : steps[r < sv ? r : r - 1] }
	private func rowOf(_ i: Int) -> Int { i < sv ? i : i + 1 }

	// every step starts from a tared scale; zero is the reading meaning "nothing added yet" in the
	// current tare frame (nil while taring), zeroStep the step that frame belongs to, totalInCup the
	// tallies of the steps before it
	private var current = 0.0
	private var zero: Double?
	private var zeroStep = -1
	private var rawMode = true
	private var madeMarked = false
	private var taring = false
	private var tareAt = Date()
	private var tareTimer: Timer?
	private var onZero: (() -> Void)?
	private var doneWeight: Double?
	private var starts: [Int: Double] = [:]
	private var totalInCup = 0.0
	private var added: [Int: Double] = [:]       // row + 1 -> grams
	private var stable: [Double] = []
	private var dosing = false
	private var dose = (t: 0.0, lo: 0.0, hi: 0.0)
	private var doseSaved = false

	init(recipe: Recipe, n: Double) {
		self.recipe = recipe
		self.n = n
	}

	// MARK: lifecycle

	/// the maker opened: straight to Tare when the scale is still connected, else try the last one
	func open() {
		scale.onWeight = { [weak self] w in self?.setWeight(w) }
		if scale.connected { startMaking() } else { viewPreconnect() }
	}
	func close() {
		scale.onWeight = nil
		reset()
	}
	/// the scale's state changed (connected: the Tare step; dropped: back to Connect)
	func scaleChanged(_ s: Scale.State) {
		if s == .connected { if phase == .connect { startMaking() } }
		else if phase != .connect { viewPreconnect() }
	}

	// MARK: amounts

	private func grams(_ s: Recipe.Row) -> Double { Double(s.mg) / 1000 * n }
	/// every step with a gram weight is weighed (dashes, a rinse too); counted ones are done by hand
	private func weighed(_ s: Recipe.Row) -> Bool { s.count == nil && s.mg > 0 }
	/// a bar measure worth showing beside the grams ("2 dashes", "1 barspoon"; not oz/ml)
	private func measure(_ s: Recipe.Row?) -> String {
		guard let s, !s.qty.isEmpty, s.qty.range(of: "(oz|ml|cl)\\b", options: [.regularExpression, .caseInsensitive]) == nil else { return "" }
		return " (" + Recipe.scaleQ(Store.qty(s.qty), n) + ")"
	}
	/// the recipe's weight: every step before the serve row with one, counted ones too
	private var target: Double {
		steps.enumerated().reduce(0) { a, e in e.offset < sv && e.element.mg > 0 ? a + grams(e.element) : a }
	}
	private func f1(_ v: Double) -> String { String(format: "%.1f", v) }

	// MARK: weight

	private func setWeight(_ w: Double) {
		current = w
		checkTare()
		showWeight()
		if dosing && zero != nil { onDose(w) }
	}
	/// what has been added in the current tare frame (0 while the scale tares)
	private var amount: Double { (taring || zero == nil) ? 0 : current - (zero ?? 0) }
	private func showWeight() {
		if let d = doneWeight { readout = f1(d); return }
		if rawMode { readout = f1(current); return }
		let t = totalInCup + amount
		// a step's readout is what was added for it; the serve row's is the whole drink
		readout = f1(idx >= sv ? t : amount)
		total = T("Total: {g}g", ["g": f1(t)])
	}
	/// tare and wait for ~0 (at least tareMin, so a reading from before the tare isn't taken for
	/// it); if it never comes (a lost write), the reading after tareMax becomes the zero
	private func tareNow() {
		taring = true; zero = nil; tareAt = Date(); onZero = nil
		scale.tare()
		if tareTimer == nil {
			tareTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
				MainActor.assumeIsolated { self?.checkTare() }
			}
		}
	}
	private func checkTare() {
		guard taring else { return }
		let t = Date().timeIntervalSince(tareAt)
		if (t >= Self.tareMin && abs(current) <= Self.tareZero) || t >= Self.tareMax {
			let f = onZero
			stopTare(); zero = current; showWeight()
			f?()
		}
	}
	private func stopTare() { taring = false; onZero = nil; tareTimer?.invalidate(); tareTimer = nil }
	private func whenZero(_ f: @escaping () -> Void) { if taring { onZero = f } else { f() } }
	private func setProg(_ pct: Double, _ kind: String) { progress = max(0, min(100, pct)) / 100; progressKind = kind }
	private func say(_ s: String, _ k: Kind) { guide = [s]; guideKind = k }

	// MARK: dosing

	private func startDose(_ t: Double) {
		dosing = true; dose = (t, t - Self.tol, t + Self.tol); stable = []; doseSaved = false; setProg(0, "")
		// the pretend scale pours a step once (not again when Prev comes back to it)
		if scale.fake && scale.fakeAuto && amount <= Self.zeroTol { fakePour(t) }
	}
	private func stopDose() { dosing = false; setProg(0, "") }
	private var isStable: Bool {
		guard stable.count >= Self.stableN else { return false }
		let r = stable.suffix(Self.stableN)
		return r.max()! - r.min()! <= Self.stableSpread
	}
	/// the dose is what was added since this step's tare
	private func onDose(_ w: Double) {
		let a = w - (zero ?? 0), t = dose.t, rem = t - a
		setProg(t > 0 ? a / t * 100 : 100, (a >= dose.lo && a <= dose.hi) ? "ok" : (a < dose.lo ? "under" : "over"))
		stable.append(w); if stable.count > Self.stableN { stable.removeFirst() }
		if isStable {
			if doseSaved { return }
			// in range: say so, but never move on by itself; Next always does
			if a >= dose.lo && a <= dose.hi { doseSaved = true; say(T("Good! Press Next for the next ingredient."), .success) }
			else if a > dose.hi { say(T("Over by {g}g", ["g": f1(a - t)]), .error) }
			else if a > Self.zeroTol { say(T("Add {g}g", ["g": f1(rem)]), .info) }
		} else {
			doseSaved = false
			// until something is poured, keep the bar measure beside the grams
			if rem > 0 { say(a <= Self.zeroTol ? T("Add {g}g", ["g": f1(t)]) + measure(stepAt(idx)) : T("Add {g}g", ["g": f1(rem)]), .info) }
			else { say(T("Pouring… over by {g}g", ["g": f1(-rem)]), .warn) }
		}
	}
	/// tally what this step added, add it to the drink, and tare for the next step
	private func tally() {
		let d = amount
		added[idx + 1] = d; totalInCup += d
		tareNow(); zeroStep = idx + 1
	}

	// MARK: steps

	/// z (from Prev): keep the scale as it is and use z as this step's zero, instead of taring
	private func showStep(_ i: Int, z: Double? = nil) {
		idx = i; doneWeight = nil; rawMode = false; phase = .step
		if i <= steps.count { starts[i] = totalInCup }
		if i > steps.count { complete(); return }
		stopDose()
		if let z { stopTare(); zero = z; zeroStep = i }
		else if zeroStep != i { tareNow(); zeroStep = i }
		if i == sv {
			// reaching the glass counts as making it (signed in): not everyone taps through the
			// garnishes to Done. Once per run; addMade also stamps the day
			if !madeMarked && Account.shared.signedIn { madeMarked = true; Member.shared.addMade(recipe.id) }
			ingredient = nil; picture = Img.glass(recipe.glass)
			showWeight()
			say(recipe.method, .success)
			return
		}
		guard let s = stepAt(i) else { return }
		showWeight()
		ingredient = s.label; picture = Img.ingredient(s.ingredient)
		if i < sv && weighed(s) {   // after the serve row the drink is in the glass: nothing is weighed
			say(T("Add {g}g", ["g": f1(grams(s))]) + measure(s), .info)
			whenZero { [weak self] in if self?.idx == i { self?.startDose(self?.grams(s) ?? 0) } }
		} else {
			say(T("{action}, then press Next.", ["action": s.mixLabel + (s.qty.isEmpty ? "" : " " + Recipe.scaleQ(Store.qty(s.qty), n))]), .info)
		}
	}
	/// Next: a counted step, or a weighed one cut short, is tallied at whatever it added, then the
	/// next step tares, so its weight never lands in the next dose
	func next() {
		if phase == .tare { doTare(); return }
		guard phase == .step else { return }
		stopDose()
		if idx < sv && zeroStep <= idx { tally() }
		showStep(idx + 1)
	}
	/// back one step: its readout shows what was poured for it again, without taring (the scale
	/// still holds it); the later steps' tallies are dropped, to be weighed in again
	func prev() {
		guard phase == .step else { return }
		if idx <= 0 { startMaking(); return }
		let k = idx - 1
		var since = 0.0
		if k < zeroStep { for j in k..<zeroStep { since += added[j + 1] ?? 0 } }
		let z = (taring || zero == nil ? 0 : zero!) - since
		if let s = starts[k] { totalInCup = s }
		for m in (k + 1)...(steps.count + 1) { added.removeValue(forKey: m) }
		showStep(k, z: z)
	}

	/// the facts panel's model (ice dilution by Dave Arnold's formulas, toppers after) for how
	/// many drinks' worth of each step went in
	private func drinkFacts(_ f: (Int) -> Double) -> [FinalRow] {
		var bv = 0.0, be = 0.0, tv = 0.0, te = 0.0, sg = 0.0, ac = 0.0
		for (i, s) in steps.enumerated() {
			let x = s.fx
			if x.ph == "none" { continue }
			let k = f(i), v = x.v * k, e = v * x.abv / 100, amt = (x.per == "100g" ? x.g : x.v) * k
			sg += amt * x.s / 100; ac += amt * x.a / 100
			if x.ph == "top" { tv += v; te += e } else { bv += v; be += e }
		}
		guard bv + tv > 0 else { return [] }
		let a = bv > 0 ? be / bv : 0
		var w = 0.0
		switch Store.dilKind(recipe.howto) {
		case "shake": w = bv * (1.567 * a * a + 1.742 * a + 0.203)
		case "stir": w = bv * (-1.21 * a * a + 1.246 * a + 0.145)
		default: break
		}
		let vol = bv + w + tv, eth = be + te, sp = 100 * sg / vol, ap = 100 * ac / vol, vod = eth / 0.4
		let bal: String
		if ap >= 0.4 { let r = sp / ap; bal = r < 6 ? "Tart" : (r < 12 ? "Balanced" : "Sweet") }
		else { bal = sp < 2 ? "Dry" : (sp < 5 ? "Off-dry" : (sp < 10 ? "Sweet" : "Very sweet")) }
		let sh = (vod / 30 * 2).rounded() / 2, cubes = (sg / 4 * 2).rounded() / 2
		let sugg = sg < 10 ? Recipe.num((sg * 10).rounded() / 10) : "\(Int(sg.rounded()))"
		var rows = [
			FinalRow(label: T("Volume"), value: "\(Int(vol.rounded())) ml"),
			FinalRow(label: T("Strength"), value: T("{n}% ABV", ["n": Int((100 * eth / vol).rounded())])),
			FinalRow(label: T("Alcohol"), value: ["\(Int(eth.rounded())) ml (\(Int((eth * 0.789).rounded())) g)",
				T("{n} ml of vodka (40%)", ["n": Int(vod.rounded())]),
				sh == 1 ? T("1 shot (of 30ml)") : T("{n} shots (of 30ml)", ["n": Recipe.num(sh)])].joined(separator: "\n")),
		]
		var sl = ["\(sugg) g (\(String(format: "%.1f", sp))%)"]
		if cubes > 0 { sl.append(cubes == 1 ? T("1 sugar cube") : T("{n} sugar cubes", ["n": Recipe.num(cubes)])) }
		rows.append(FinalRow(label: T("Sugar"), value: sl.joined(separator: "\n")))
		rows.append(FinalRow(label: T("Acidity"), value: ap < 0.005 ? T("none") : String(format: "%.2f%%", ap)))
		rows.append(FinalRow(label: ap >= 0.4 ? T("Sweet vs sour") : T("Sweetness"), value: T(bal)))
		return rows
	}
	/// drinks' worth of step i actually used: weighed steps by what the scale saw, the rest as the
	/// recipe has them (at the batch size)
	private func usedFactor(_ i: Int) -> Double {
		let s = steps[i], per = Double(s.mg) / 1000
		return i < sv && weighed(s) && per > 0 ? (added[rowOf(i) + 1] ?? 0) / per : n
	}
	/// the facts for the recipe as written (scale_maker.js's mkFacts(true)), for checking the port
	func plannedFacts() -> [FinalRow] { drinkFacts { _ in 1 } }
	private func complete() {
		stopDose(); phase = .done; ingredient = nil; picture = recipe.image
		say(T("Done!"), .success)
		let ut = added.values.reduce(0, +)
		doneWeight = ut; showWeight(); total = nil; setProg(0, "")
		let tg = target, diff = ut - tg
		final = [
			FinalRow(label: T("Recipe target"), value: "\(f1(tg)) g"),
			FinalRow(label: T("Your final weight"), value: "\(f1(ut)) g"),
			FinalRow(label: T("Difference"), value: (diff >= 0 ? "+" : "") + f1(diff) + " g"
				+ (tg > 0 ? " (" + (diff >= 0 ? "+" : "") + f1(diff / tg * 100) + "%)" : ""), ok: abs(diff) <= 2),
		]
		facts = drinkFacts(usedFactor)
	}

	// MARK: views

	private func reset() {
		madeMarked = false; starts = [:]; idx = 0; totalInCup = 0; added = [:]; current = 0; stable = []
		stopDose(); readout = "0.0"; final = []; facts = []; picture = nil
		stopTare(); zero = nil; zeroStep = -1; rawMode = true; doneWeight = nil; total = nil
		ingredient = nil; guide = []
	}
	private func viewPreconnect() {
		reset()
		phase = .connect
	}
	/// connected: the Tare prompt, with the shaker-on-the-scale picture
	func startMaking() {
		guard scale.connected else { return }
		reset()
		phase = .tare
		let dil = Store.dilKind(recipe.howto) != "none"
		say(T(dil ? "Put ice in your cocktail shaker and place it on the scale." : "Place your cocktail shaker on the scale."), .info)
		picture = Img.local("img/maker/shaker-scale.jpg")
		if scale.fake && scale.fakeAuto {
			DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
				guard let self, self.phase == .tare else { return }
				self.scale.fakeTo(self.scale.fakeWeight + (dil ? 412.6 : 236.4), 0.7)
			}
		}
	}
	/// the shaker (with its ice) is on: the first step, which tares it
	private func doTare() {
		reset()
		showStep(0)
	}

	// MARK: fake scale

	/// pour a step's dose, a little over or under, as a person pours
	private func fakePour(_ g: Double) {
		let want = g + (Double.random(in: 0..<1) - 0.4) * min(0.8, g * 0.04)
		whenZero { [weak self] in
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.scale.fakePour(want) }
		}
	}

	// MARK: the steps list

	enum RowState { case todo, current, done }
	func state(ofRow r: Int) -> RowState {
		guard phase == .step || phase == .done else { return .todo }
		return r < idx ? .done : (r == idx ? .current : .todo)
	}
}

extension Store {
	/// how a drink picks up ice water (pdt_dil_kind): shake, stir or none, from its first method
	static func dilKind(_ howto: String) -> String {
		let h = (howto.lowercased().components(separatedBy: " or ").first ?? "")
		func has(_ p: String) -> Bool { h.range(of: p, options: .regularExpression) != nil }
		if has("heat|warm|pre-heated|absinthe fountain|drip") { return "none" }
		if has("shake|swizzle|blend|whip") { return "shake" }
		if has("stir|ice|build|crushed|pebble") { return "stir" }
		return "none"
	}
}
