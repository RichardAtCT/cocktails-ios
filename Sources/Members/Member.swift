import Foundation
import SwiftUI

/// The signed-in member's cocktail data, in the same permacookies the website uses, so the app and
/// the site stay one: pdt_wish / pdt_made (drink ids from every book), pdt_made_on ({id: unix
/// seconds} when last made), pdt_notes ({id: comment}), pdt_bar (Your Bar) and pdt_hide_unmakeable.
/// A copy is kept on the device so the lists show offline; each change is written straight back.
@MainActor
final class Member: ObservableObject {
	static let shared = Member()

	@Published private(set) var wish: [Int] = []
	@Published private(set) var made: [Int] = []
	@Published private(set) var madeOn: [String: Int] = [:]
	@Published private(set) var notes: [String: String] = [:]
	@Published private(set) var bar = Bar.normalized(nil)
	@Published private(set) var hideUnmakeable = false
	@Published private(set) var loaded = false
	/// the server's pdt_bar couldn't be read: never overwrite it (as the site's "I have this")
	private var barUnreadable = false
	/// the same for pdt_made_on: skip the date writes rather than wipe the dates
	private var madeOnUnreadable = false

	private let cacheKey = "member.cache"
	private var account: Account { Account.shared }

	init() { restore() }

	// MARK: load / clear

	func load() async {
		guard account.signedIn else { return }
		async let w = account.get("pdt_wish"), m = account.get("pdt_made"), on = account.get("pdt_made_on"),
			n = account.get("pdt_notes"), b = account.get("pdt_bar"), h = account.get("pdt_hide_unmakeable")
		let (rw, rm, ron, rn, rb, rh) = await (w, m, on, n, b, h)
		if case .value(let s) = rw { wish = Self.ids(s) }
		if case .value(let s) = rm { made = Self.ids(s) }
		if case .value(let s) = ron {
			if let o = Self.object(s) { madeOn = o.compactMapValues { ($0 as? Int) ?? ($0 as? Double).map { Int($0) } ?? ($0 as? String).flatMap { Int($0) } }; madeOnUnreadable = false }
			else { madeOnUnreadable = true }
		}
		if case .value(let s) = rn, let o = Self.object(s) { notes = o.compactMapValues { $0 as? String } }
		if case .value(let s) = rb {
			if let parsed = Bar.decode(s) { bar = Bar.normalized(parsed); barUnreadable = false } else { barUnreadable = true }
		}
		if case .value(let s) = rh { hideUnmakeable = s == "1" }
		loaded = true
		save()
	}
	func clear() {
		wish = []; made = []; madeOn = [:]; notes = [:]; bar = Bar.normalized(nil); hideUnmakeable = false; loaded = false
		UserDefaults.standard.removeObject(forKey: cacheKey)
	}

	// MARK: marks (pdt_marks_js)

	func isWish(_ id: Int) -> Bool { wish.contains(id) }
	func isMade(_ id: Int) -> Bool { made.contains(id) }

	func toggleWish(_ id: Int) {
		if let i = wish.firstIndex(of: id) { wish.remove(at: i) } else { wish.append(id) }
		write("pdt_wish", Self.json(wish))
	}
	/// marking Made stamps today; un-marking removes the date
	func toggleMade(_ id: Int) {
		let adding = !made.contains(id)
		if adding { made.append(id) } else { made.removeAll { $0 == id } }
		write("pdt_made", Self.json(made))
		stamp(id, adding)
	}
	/// the scale maker reaching the glass: made, and re-made today if it was already
	func addMade(_ id: Int) {
		if !made.contains(id) { made.append(id); write("pdt_made", Self.json(made)) }
		stamp(id, true)
	}
	private func stamp(_ id: Int, _ yes: Bool) {
		guard !madeOnUnreadable else { return }
		if yes { madeOn[String(id)] = Int(Date().timeIntervalSince1970) } else { madeOn.removeValue(forKey: String(id)) }
		write("pdt_made_on", Self.json(madeOn))
	}
	func note(_ id: Int) -> String { notes[String(id)] ?? "" }
	func setNote(_ id: Int, _ text: String) {
		let v = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
		guard v != note(id) else { return }
		if v.isEmpty { notes.removeValue(forKey: String(id)) } else { notes[String(id)] = v }
		write("pdt_notes", Self.json(notes))
	}

	// MARK: Your Bar (bar.js)

	var items: [Bar.Item] { bar.current.items }
	func has(_ it: Bar.Item) -> Bool { items.contains { $0.key == it.key } }
	func add(_ it: Bar.Item) { editBar { b in let i = b.curIndex; if !b.locs[i].items.contains(where: { $0.key == it.key }) { b.locs[i].items.append(it) } } }
	func add(_ its: [Bar.Item]) { editBar { b in let i = b.curIndex; for it in its where !b.locs[i].items.contains(where: { $0.key == it.key }) { b.locs[i].items.append(it) } } }
	func remove(_ it: Bar.Item) { editBar { b in let i = b.curIndex; b.locs[i].items.removeAll { $0.key == it.key } } }
	func setLocation(_ id: String) { editBar { $0.cur = id } }
	func renameLocation(_ name: String) {
		let n = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
		guard !n.isEmpty else { return }
		editBar { b in b.locs[b.curIndex].name = n }
	}
	func newLocation(_ name: String) {
		let n = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
		guard !n.isEmpty else { return }
		editBar { b in let l = Bar.Loc(id: Bar.newId(), name: n, items: []); b.locs.append(l); b.cur = l.id }
	}
	func deleteLocation() {
		guard bar.locs.count > 1 else { return }
		editBar { b in let c = b.cur; b.locs.removeAll { $0.id == c }; b.cur = b.locs[0].id }
	}
	var canEditBar: Bool { account.signedIn && !barUnreadable }
	private func editBar(_ f: (inout Bar) -> Void) {
		guard canEditBar else { return }
		var b = bar
		f(&b)
		bar = Bar.normalized(b)
		write("pdt_bar", bar.json())
	}
	func setHideUnmakeable(_ v: Bool) {
		hideUnmakeable = v
		write("pdt_hide_unmakeable", v ? "1" : "0")
	}

	// MARK: can make (pdt_canmake_names), per book

	/// the names of a book's cocktails the bar can make, and what each other one is missing
	func canMake(_ book: Book) -> (names: Set<String>, missing: [String: [String]]) {
		let ix = BarIndex.of(book), o = ix.owned(items)
		var ok = Set<String>(), miss: [String: [String]] = [:]
		for r in ix.recipes {
			let m = ix.missingNames(r, o)
			if m.isEmpty { ok.insert(r.name) } else { miss[r.name] = m }
		}
		return (ok, miss)
	}

	// MARK: plumbing

	private func write(_ key: String, _ value: String) {
		save()
		Task { await account.set(key, value) }
	}
	private struct Cache: Codable { var wish, made: [Int]; var madeOn: [String: Int]; var notes: [String: String]; var bar: Bar; var hide: Bool }
	private func save() {
		let c = Cache(wish: wish, made: made, madeOn: madeOn, notes: notes, bar: bar, hide: hideUnmakeable)
		if let d = try? JSONEncoder().encode(c) { UserDefaults.standard.set(d, forKey: cacheKey) }
	}
	private func restore() {
		guard Account.shared.signedIn, let d = UserDefaults.standard.data(forKey: cacheKey), let c = try? JSONDecoder().decode(Cache.self, from: d) else { return }
		wish = c.wish; made = c.made; madeOn = c.madeOn; notes = c.notes; bar = c.bar; hideUnmakeable = c.hide
	}
	/// the drink ids in a stored list (pdt_canmake_json reads them with a \d+ regexp; this is as lenient)
	private static func ids(_ s: String) -> [Int] {
		guard let d = s.data(using: .utf8), let a = try? JSONSerialization.jsonObject(with: d) as? [Any] else { return [] }
		return a.compactMap { ($0 as? Int) ?? ($0 as? String).flatMap { Int($0) } }
	}
	private static func object(_ s: String) -> [String: Any]? {
		if s.isEmpty { return [:] }
		guard let d = s.data(using: .utf8) else { return nil }
		return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
	}
	private static func json(_ v: Any) -> String {
		guard let d = try? JSONSerialization.data(withJSONObject: v, options: [.sortedKeys, .withoutEscapingSlashes]) else { return "" }
		return String(decoding: d, as: UTF8.self)
	}
}
