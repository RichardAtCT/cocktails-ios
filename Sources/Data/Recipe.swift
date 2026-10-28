import Foundation

/// Everything a recipe page shows, built as the ONE RECIPE branch of direct_pdt does.
struct Recipe {
	struct Row: Hashable {
		let n: Int
		let ingredient: String       // English name (route key)
		let ingredientId: Int
		let label: String            // translated
		let cat: String              // display category ("" if none)
		let mix: String              // English mix type ("Add" for Build)
		let mixLabel: String
		let grams: String?           // "28.4", "~5", nil
		let count: String?           // a counted amount ("3")
		let toTaste: Bool
		let oz: String?              // the book's amount, "1.5 oz"
		let mg: Int                  // the scale target in mg (maker)
		let isGarnish: Bool
		let qty: String              // the book's amount as stored ("2dashes"), for the maker's "(2 dashes)"
		let fx: Fx                   // what it adds to the drink, for the maker's after-the-fact facts
	}
	/// one step's share of the drink (the maker data's "fx", admin/pdt_facts.py's model): ml per
	/// drink, ABV %, sugar and acid per 100 ml or 100 g (per), grams (g), and whether it's diluted
	/// with the rest (base), added after it (top), or not in the glass (none)
	struct Fx: Hashable {
		let v, abv, s, a, g: Double
		let per, ph: String
	}
	/// drink_stats for one drink: what the facts panel and the size panel scale
	struct Stats {
		let vol, eth, ethg, vod, water, abv, acid: Double
		let sug: Double?, sugp: Double
		let bal: String              // English: Dry / Off-dry / Sweet / Very sweet / Tart / Balanced
	}
	/// one line of the facts panel at a batch size: its pictures, label and value lines
	struct FactRow: Identifiable {
		let id: String               // vol abv eth sug acid bal
		let label: String
		let lines: [String]
		let icons: [FactIcon.Pic]
		let more: Int
	}
	struct Similar: Hashable {
		let drink: DrinkRef
		let description: String?
		let taste: String?
		let same: String?, different: String?
		let shared: String?, differs: [String]
	}

	let book: Book
	let id: Int
	let name: String
	let image: URL?
	let glass: String
	let howto: String                // English, "" if none (the maker's dilution kind)
	let method: String
	let description: String?
	let alsoIn: [(book: Book, name: String, same: Bool)]
	let rows: [Row]
	let serveAt: Int                 // rows before the serve row
	let total: Double                // grams in the glass
	let stats: Stats?
	let cite: String?
	let similar: [Similar]
	let strip: [String]              // ingredient names, first appearance, step order

	var serveNumber: Int { serveAt + 1 }

	/// the facts panel for n drinks (the page's FT / LINE / ICON / staticIcons)
	func facts(_ n: Double) -> [FactRow] {
		guard let f = stats else { return [] }
		var out: [FactRow] = []
		let vol = FactIcon.row(FactIcon.glass, f.vol * n / 250, max: 3)
		out.append(FactRow(id: "vol", label: T("Volume"), lines: ["\(Int((f.vol * n).rounded())) ml"], icons: vol.pics, more: vol.more))
		let abv = FactIcon.row(FactIcon.flame, f.abv / 10, max: 6)
		out.append(FactRow(id: "abv", label: T("Strength"), lines: [T("{n}% ABV", ["n": Int(f.abv.rounded())])], icons: abv.pics, more: abv.more))
		let shots = FactIcon.row(FactIcon.shot, f.vod * n / 30, max: 4)
		out.append(FactRow(id: "eth", label: T("Alcohol"), lines: [Recipe.line("eth", f, n), Recipe.line("vod", f, n), Recipe.line("shots", f, n)],
			icons: shots.pics, more: shots.more))
		if let sug = f.sug {
			let cubes = FactIcon.row(FactIcon.cube, sug * n / 4, max: 4)
			let c = (sug * n / 4 * 2).rounded() / 2
			out.append(FactRow(id: "sug", label: T("Sugar"), lines: [Recipe.line("sug", f, n)] + (c > 0 ? [Recipe.line("cubes", f, n)] : []),
				icons: cubes.pics, more: cubes.more))
			let lime: (pics: [FactIcon.Pic], more: Int) = f.acid > 0.005 ? FactIcon.row(FactIcon.lime, f.acid / 0.2, max: 6) : ([], 0)
			out.append(FactRow(id: "acid", label: T("Acidity"), lines: [f.acid < 0.005 ? T("none") : String(format: "%.2f%%", f.acid)], icons: lime.pics, more: lime.more))
			var bal: [FactIcon.Pic] = []
			if f.acid >= 0.4 { bal = [f.bal == "Tart" ? FactIcon.lemon(1) : f.bal == "Sweet" ? FactIcon.lolly : FactIcon.scale] }
			else if let k = ["Dry": 1, "Off-dry": 2, "Sweet": 3, "Very sweet": 4][f.bal] { bal = (0..<k).map { _ in FactIcon.drop(true) } }
			out.append(FactRow(id: "bal", label: f.acid >= 0.4 ? T("Sweet vs sour") : T("Sweetness"), lines: [T(f.bal)], icons: bal, more: 0))
		}
		return out
	}

	/// one value line of the facts at n drinks; also what the size panel lets you type a target for
	static func line(_ key: String, _ f: Stats, _ n: Double) -> String {
		switch key {
		case "vol": return "\(Int((f.vol * n).rounded())) ml"
		case "eth": return "\(Int((f.eth * n).rounded())) ml (\(Int((f.ethg * n).rounded())) g)"
		case "vod": return T("{n} ml of vodka (40%)", ["n": Int((f.vod * n).rounded())])
		case "shots":
			let sh = (f.vod * n / 30 * 2).rounded() / 2
			return sh == 1 ? T("1 shot (of 30ml)") : T("{n} shots (of 30ml)", ["n": num(sh)])
		case "sug":
			let g = (f.sug ?? 0) * n
			return "\(g < 10 ? num((g * 10).rounded() / 10) : "\(Int(g.rounded()))") g (\(String(format: "%.1f", f.sugp))%)"
		case "cubes":
			let c = ((f.sug ?? 0) * n / 4 * 2).rounded() / 2
			return c == 1 ? T("1 sugar cube") : T("{n} sugar cubes", ["n": num(c)])
		default: return ""
		}
	}
	/// what one unit of each typeable line is per drink (LINE[k].base)
	static func lineBase(_ key: String, _ f: Stats) -> (base: Double, unit: String) {
		switch key {
		case "vol": return (f.vol, "ml")
		case "eth": return (f.eth, "ml")
		case "vod": return (f.vod, "ml")
		case "shots": return (f.vod / 30, "")
		case "sug": return (f.sug ?? 0, "g")
		case "cubes": return ((f.sug ?? 0) / 4, "")
		default: return (0, "")
		}
	}
	/// 2 decimals at most, no trailing zeros (the page's num())
	static func num(_ v: Double) -> String {
		let r = (v * 100).rounded() / 100
		return r == r.rounded() ? "\(Int(r))" : String(format: "%g", r)
	}
	/// "2 oz" x2 -> "4 oz", ".75 oz" x2 -> "1.5 oz", "4.5-6 oz" x2 -> "9-12 oz" (scaleQ)
	static func scaleQ(_ q: String, _ n: Double) -> String {
		guard n != 1 else { return q }
		let re = try! NSRegularExpression(pattern: "[0-9]*\\.?[0-9]+")
		var out = q
		for m in re.matches(in: q, range: NSRange(q.startIndex..., in: q)).reversed() {
			let r = Range(m.range, in: q)!
			var s = num((Double(q[r]) ?? 0) * n)
			if s.hasPrefix("0.") { s.removeFirst() }
			out.replaceSubrange(Range(m.range, in: out)!, with: s)
		}
		return out
	}
	/// whole drinks above 1; at or below 1, quarters (.75 .5 .25), never down to 0 (stepDrinks)
	static func step(_ n: Double, _ d: Int) -> Double {
		let q = 1e-9
		if d < 0 {
			if n > 1 + q { return max(1, (n - q).rounded(.up) - 1) }
			return max(0.25, (n * 4 - q).rounded(.up) / 4 - 0.25)
		}
		if n < 1 - q { return min(1, (n * 4 + q).rounded(.down) / 4 + 0.25) }
		return (n + q).rounded(.down) + 1
	}
}

extension Store {
	/// pdt_name_key: lowercase, accents folded, & -> and, quotes and dots dropped, any other run of
	/// non [a-z0-9] -> one space, leading "the " dropped
	static func nameKey(_ s: String) -> String {
		let map: [Character: String] = ["à": "a", "á": "a", "â": "a", "ä": "a", "ã": "a", "å": "a", "è": "e", "é": "e", "ê": "e", "ë": "e",
			"ì": "i", "í": "i", "î": "i", "ï": "i", "ò": "o", "ó": "o", "ô": "o", "ö": "o", "õ": "o", "ø": "o",
			"ù": "u", "ú": "u", "û": "u", "ü": "u", "ñ": "n", "ç": "c", "ý": "y", "ÿ": "y", "œ": "oe", "æ": "ae", "ß": "ss",
			"&": " and ", "'": "", "’": "", "‘": "", "`": "", ".": ""]
		var k = ""
		for ch in s.lowercased() { if let r = map[ch] { k += r } else { k.append(ch) } }
		k = k.replacingOccurrences(of: "[^a-z0-9]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
		if k.hasPrefix("the ") { k = String(k.dropFirst(4)) }
		return k
	}
	/// sorted {ingredient_id, quantity without spaces, lowercased} pairs: equal = "the same recipe"
	func recipeSignature(_ id: Int) -> [String] {
		db.rows("SELECT s.ingredient_id, COALESCE(q.name,'') FROM step s LEFT JOIN quantity q ON q.quantity_id=s.quantity_id WHERE s.drink_id=?1 AND s.sortorder IS NOT NULL AND s.ingredient_id IS NOT NULL", id)
			.map { "\($0.s(0)) \($0.s(1).replacingOccurrences(of: " ", with: "").lowercased())" }.sorted()
	}
	func drinkByNameKey(_ key: String) -> DrinkRef? {
		let idx: [String: DrinkRef] = memo("namekeys") {
			var m: [String: DrinkRef] = [:]
			for r in db.rows("SELECT drink_id, name FROM drink") { m[Store.nameKey(r.s(1))] = DrinkRef(id: r.i(0), name: r.s(1)) }
			return m
		}
		return idx[key]
	}
	/// the drink's in-the-glass ingredients (no garnish/twist/rim/spritz/rinse), id -> name
	func glassIngs(_ id: Int) -> [(Int, String)] {
		db.rows("SELECT i.ingredient_id, i.name, LOWER(COALESCE(m.name,'build')) FROM step s JOIN ingredient i ON i.ingredient_id=s.ingredient_id LEFT JOIN mixtype m ON m.mixtype_id=s.mixtype_id WHERE s.drink_id=?1 AND s.sortorder IS NOT NULL ORDER BY s.sortorder", id)
			.filter { !["garnish", "twist", "rim", "spritz", "rinse"].contains($0.s(2)) }
			.reduce(into: [(Int, String)]()) { acc, r in if !acc.contains(where: { $0.0 == r.i(0) }) { acc.append((r.i(0), r.s(1))) } }
	}

	func recipe(_ name: String) -> Recipe? {
		let idv = db.one("SELECT drink_id FROM drink WHERE name=?1 LIMIT 1", name)
		if idv.isNull { return nil }
		let id = idv.int
		let glass = db.one("SELECT g.name FROM drink2glass d2 JOIN glass g ON d2.glass_id=g.glass_id WHERE d2.drink_id=?1 LIMIT 1", id).string
		let howto = db.one("SELECT DISTINCT h.name FROM step s JOIN howto h ON s.howto_id=h.howto_id WHERE s.drink_id=?1 LIMIT 1", id).string

		var rows: [Recipe.Row] = []
		var serveAt: Int? = nil
		var idx = 0
		var total = 0.0
		var strip: [String] = []
		// garnishes go after the serve row, whatever the book's order
		for r in db.rows("""
			SELECT q.name qty, s.grams sg, i.name ing, i.ingredient_id iid, mi.name mix, s.sortorder so,
				COALESCE(i.abv,0), COALESCE(i.sugar,0), COALESCE(i.acid,0), COALESCE(i.sugar_per,'100ml')
			FROM step s LEFT JOIN ingredient i ON s.ingredient_id=i.ingredient_id
			LEFT JOIN mixtype mi ON s.mixtype_id=mi.mixtype_id LEFT JOIN quantity q ON s.quantity_id=q.quantity_id
			WHERE s.drink_id=?1 AND s.sortorder IS NOT NULL
			ORDER BY (lower(COALESCE(mi.name,'')) IN ('garnish','twist','flame')), s.sortorder
			""", id) {
			let qty = r.s(0), ing = r.s(2), iid = r.i(3), mix = r.s(4)
			let sg = r.d(1)
			if ing.isEmpty { continue }
			let mixl = mix.lowercased()
			if serveAt == nil && ["garnish", "twist", "flame"].contains(mixl) { serveAt = rows.count; idx += 1 }
			idx += 1
			let cat = displayCat(ingPrimaryCat(ing), ing)
			let isg = mix.range(of: "garnish|twist|rim|spritz|flame", options: [.regularExpression, .caseInsensitive]) != nil
			let iscount = !qty.isEmpty && qty.range(of: "^[0-9][0-9./-]*$", options: .regularExpression) != nil
			var grams: String? = nil
			var mg = 0
			var est = false
			var estMl = 0.0
			if let sg, !(iscount && isg) {
				var g = String(format: "%.1f", sg)
				if g == "0.0" { g = "0.1" }
				grams = g
				mg = Int((sg * 1000).rounded())
				if !isg && !iscount { total += sg }
			}
			if grams == nil && !iscount {
				if mixl == "rinse" { grams = "5"; mg = 5000; est = true }
				else if mixl == "top" {
					var eg = 0
					if ing.range(of: "champagne|sparkling|prosecco|cava|cr.?mant|lambrusco|sekt|cider|moscato|asti", options: [.regularExpression, .caseInsensitive]) != nil { eg = 60 }
					else if ing.range(of: "soda|tonic|seltzer|cola|ginger beer|ginger ale|pellegrino", options: [.regularExpression, .caseInsensitive]) != nil { eg = 90 }
					if eg > 0 { grams = "\(eg)"; mg = eg * 1000; est = true; estMl = Double(eg); total += Double(eg) }
				}
			}
			let toTaste = grams == nil && !iscount && mix.range(of: "garnish|twist|rim", options: [.regularExpression, .caseInsensitive]) == nil
			let oz: String? = (!qty.isEmpty && !(iscount && grams == nil)) ? Store.qty(qty) : nil
			let mixen = (!mix.isEmpty && mix != "Build") ? mix : "Add"
			let ml = mix.isEmpty ? "build" : mixl
			let fx = Recipe.Fx(v: estMl > 0 ? estMl : Store.qtyMl(qty, ing), abv: r.d(6) ?? 0, s: r.d(7) ?? 0, a: r.d(8) ?? 0,
				g: sg ?? (estMl > 0 ? estMl : 0), per: r.s(9).isEmpty ? "100ml" : r.s(9),
				ph: ["garnish", "twist", "rim", "spritz", "rinse"].contains(ml) ? "none" : (["top", "float", "flame"].contains(ml) ? "top" : "base"))
			rows.append(Recipe.Row(n: idx, ingredient: ing, ingredientId: iid, label: T(ing), cat: cat, mix: mixen, mixLabel: T(mixen),
				grams: grams.map { est ? "~\($0)" : $0 }, count: iscount ? qty : nil, toTaste: toTaste, oz: oz, mg: mg, isGarnish: isg,
				qty: qty, fx: fx))
			if Img.ingredient(ing) != nil && !strip.contains(ing) { strip.append(ing) }
		}
		let serve = serveAt ?? rows.count

		// facts (drink_stats) and the book citation (drink_book)
		var stats: Recipe.Stats? = nil
		if let st = db.rows("SELECT volume_ml, abv, ethanol_ml, ethanol_g, vodka40_ml, water_ml, sugar_g, sugar_pct, acid_pct, balance FROM drink_stats WHERE drink_id=?1", id).first,
		   let abv = st.d(1) {
			stats = Recipe.Stats(vol: st.d(0) ?? 0, eth: st.d(2) ?? 0, ethg: st.d(3) ?? 0, vod: st.d(4) ?? 0, water: st.d(5) ?? 0, abv: abv,
				acid: st.d(8) ?? 0, sug: st.d(6), sugp: st.d(7) ?? 0, bal: st.s(9))
		}
		var cite: String? = nil
		if let b = db.rows("SELECT credit, source, date_text FROM drink_book WHERE drink_id=?1", id).first {
			var parts: [String] = []
			if !b.s(0).isEmpty { parts.append(b.s(0)) }
			if !b.s(1).isEmpty { parts.append("“\(b.s(1))”") }
			var m = parts.joined(separator: ", ")
			if !b.s(2).isEmpty { m += (m.isEmpty ? "" : " ") + "(\(b.s(2)))" }
			if !m.isEmpty { cite = m }
		}

		// similar cocktails: a hand-written comparison when there is one, else shared/differs lines
		let mine = glassIngs(id)
		let mineIds = Set(mine.map(\.0))
		var similar: [Recipe.Similar] = []
		for r in db.rows("SELECT d.drink_id, d.name FROM drink_similar s JOIN drink d ON d.drink_id=s.similar_id WHERE s.drink_id=?1 ORDER BY s.rank", id) {
			let sid = r.i(0)
			let theirs = glassIngs(sid)
			let theirIds = Set(theirs.map(\.0))
			var nx = 0
			var diff: [String] = []
			for (k, v) in theirs { if mineIds.contains(k) { nx += 1 } else { diff.append("+ \(T(v))") } }
			for (k, v) in mine where !theirIds.contains(k) { diff.append("− \(T(v))") }
			let pct = mine.isEmpty ? 0 : Int((100.0 * Double(nx) / Double(mine.count)).rounded())
			let note = db.rows("SELECT similar, different FROM drink_similar_note WHERE drink_id=?1 AND similar_id=?2", id, sid).first
			let ssim = note?.s(0) ?? "", sdif = note?.s(1) ?? ""
			let sdesc = db.one("SELECT description FROM drink_description WHERE drink_id=?1", sid).string
			let hasNote = !ssim.isEmpty || !sdif.isEmpty
			similar.append(Recipe.Similar(drink: DrinkRef(id: sid, name: r.s(1)), description: sdesc.isEmpty ? nil : T(sdesc),
				taste: hasNote ? similarTaste(id, sid).map { T($0) } : nil,
				same: ssim.isEmpty ? nil : T(ssim), different: sdif.isEmpty ? nil : T(sdif),
				shared: hasNote ? nil : T("{x} of {y} ({p}%)", ["x": nx, "y": mine.count, "p": pct]), differs: hasNote ? [] : diff))
		}

		// the same cocktail in the other books (same name key)
		var also: [(book: Book, name: String, same: Bool)] = []
		let key = Store.nameKey(name)
		let sig = recipeSignature(id)
		for ob in Book.all where ob != book {
			if let d = ob.store.drinkByNameKey(key) { also.append((ob, d.name, ob.store.recipeSignature(d.id) == sig)) }
		}

		let descr = db.one("SELECT description FROM drink_description WHERE drink_id=?1", id).string
		return Recipe(book: book, id: id, name: name, image: cocktailImg(name), glass: glass, howto: howto,
			method: howto.isEmpty ? T("Stir or shake well, then serve.") : T(howto),
			description: descr.isEmpty ? nil : T(descr), alsoIn: also, rows: rows, serveAt: serve,
			total: total, stats: stats, cite: cite, similar: similar, strip: strip)
	}

	/// a book amount in ml, for the facts (pdt_qty_ml): oz, dashes, drops, spoons, scoops; eggs by count
	static func qtyMl(_ qty: String, _ ing: String) -> Double {
		let q = qty.trimmingCharacters(in: .whitespaces)
		guard let re = try? NSRegularExpression(pattern: "^([0-9.]+)(?:-([0-9.]+))?\\s*([A-Za-z]*)$"),
			  let m = re.firstMatch(in: q, range: NSRange(q.startIndex..., in: q)) else { return 0 }
		func g(_ i: Int) -> String? { Range(m.range(at: i), in: q).map { String(q[$0]) } }
		guard let a = Double(g(1) ?? ""), let b = Double(g(2) ?? g(1) ?? "") else { return 0 }
		let n = (a + b) / 2, u = (g(3) ?? "").lowercased()
		let ml: [String: Double] = ["oz": 29.5735, "dash": 0.92, "dashes": 0.92, "drop": 0.05, "drops": 0.05, "barspoon": 5, "barspoons": 5,
			"tsp": 4.93, "tbsp": 14.79, "scoop": 60]
		if let k = ml[u] { return n * k }
		return n * (["egg white": 30.0, "egg yolk": 18, "whole egg": 50][ing.lowercased()] ?? 0)
	}

	/// book quantity "2dashes" / ".75oz" -> "2 dashes" / ".75 oz", unit translated (pdt_qty)
	static func qty(_ q: String) -> String {
		guard let m = q.range(of: "^([0-9./]+)\\s*([A-Za-z].*)$", options: .regularExpression) else { return q }
		let s = String(q[m])
		let num = s.prefix { "0123456789./".contains($0) }
		let unit = s.dropFirst(num.count).trimmingCharacters(in: .whitespaces)
		return "\(num) \(T(unit))"
	}

	/// taste note for a similar pair, from admin/<book>_similar_taste.json
	func similarTaste(_ did: Int, _ sid: Int) -> String? {
		let m: [String: String] = memo("taste") {
			guard let data = try? Data(contentsOf: Img.dataDir.appendingPathComponent("\(book.key)_similar_taste.json")),
				  let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return [:] }
			var m: [String: String] = [:]
			for r in arr { if let d = r["did"], let s = r["sid"], let t = r["taste"] as? String { m["\(d),\(s)"] = t } }
			return m
		}
		return m["\(did),\(sid)"]
	}
}
