#if DEBUG
import Foundation

/// -dumpbar: Your Bar's numbers as text, in the website's order (bar.js), for checking the port
@MainActor
enum BarDump {
	static func print(_ book: Book) {
		let m = Member.shared, ix = BarIndex.of(book), items = m.items, o = ix.owned(items)
		var out = "can make: \(ix.makeable(o).map(\.name).joined(separator: ", "))\n\nBLOCKERS\n"
		for b in ix.blockers(items).prefix(8) { out += "\(ix.keyLabel(b.key)) +\(b.count)\n" }
		let plan = ix.bestPlan(items, 10, assume: ix.basics, only: ix.isBottle)
		out += "\nPLAN: \(plan.count) to make \(plan.reduce(0) { $0 + $1.recipes.count })\n"
		for p in plan { out += "\(ix.keyLabel(p.key)) +\(p.recipes.count) \(p.recipes.prefix(6).map(\.name).joined(separator: ", "))\n" }
		out += "\nMISSING\n"
		for c in ix.computeBuy(items).filter({ !$0.now.isEmpty || !$0.next.isEmpty }).prefix(12) {
			out += "[\(ix.typeOf(c.key))] \(ix.keyLabel(c.key)) now \(c.now.count) next \(c.next.count): \(c.now.prefix(6).map(\.name).joined(separator: ", "))\n"
		}
		out += "\nSEARCH bourbon: \(ix.search("bourbon").prefix(8).map { ix.itemLabel($0) }.joined(separator: " | "))\n"
		FileHandle.standardOutput.write(Data(out.utf8))
	}
}

/// -checkfacts: the scale maker's facts for every recipe as written vs the recipe page's facts
/// (drink_stats, admin/pdt_facts.py): they're the same model, so they should agree
@MainActor
enum FactsCheck {
	static func run() {
		var out = "", n = 0, bad = 0
		for b in Book.all {
			for name in b.store.db.rows("SELECT name FROM drink ORDER BY name").map({ $0.s(0) }) {
				guard let r = b.store.recipe(name), r.stats != nil else { continue }
				n += 1
				let page = r.facts(1).map { "\($0.label): \($0.lines.joined(separator: " / "))" }
				let mk = Maker(recipe: r, n: 1).plannedFacts().map { "\($0.label): \($0.value.replacingOccurrences(of: "\n", with: " / "))" }
				if !close(page.joined(separator: " "), mk.joined(separator: " ")) {
					bad += 1
					if bad <= 25 { out += "\(b.key) \(name)\n  page  \(page.joined(separator: " | "))\n  maker \(mk.joined(separator: " | "))\n" }
				}
			}
		}
		out += "\n\(n) recipes, \(bad) differ by more than rounding\n"
		FileHandle.standardOutput.write(Data(out.utf8))
	}
	/// the same words, and every number within rounding (one in its last place, or 3%)
	private static func close(_ a: String, _ b: String) -> Bool {
		let re = try! NSRegularExpression(pattern: "[0-9]+(\\.[0-9]+)?")
		func nums(_ s: String) -> [String] { re.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { String(s[Range($0.range, in: s)!]) } }
		func words(_ s: String) -> String { re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: "#") }
		let x = nums(a), y = nums(b)
		guard words(a) == words(b), x.count == y.count else { return false }
		for (p, q) in zip(x, y) {
			let u = Double(p)!, v = Double(q)!
			let unit = pow(10, -Double(max(p.split(separator: ".").dropFirst().first?.count ?? 0, q.split(separator: ".").dropFirst().first?.count ?? 0)))
			if abs(u - v) > max(unit * 1.01, 0.03 * max(abs(u), abs(v))) { return false }
		}
		return true
	}
}
#endif
