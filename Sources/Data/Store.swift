import Foundation

/// One drink as a list card shows it (pdt_card).
struct DrinkRef: Hashable, Identifiable {
	let id: Int
	let name: String
}

/// One book's data: each method is a port of the matching proc / query in lib/direct.tcl,
/// so a page in the app lists exactly what the same page on the website lists.
final class Store {
	let book: Book
	let db: SQLiteDB
	private var cache: [String: Any] = [:]
	private let cacheLock = NSLock()

	private static var stores: [String: Store] = [:]
	private static let lock = NSLock()
	static func `for`(_ book: Book) -> Store {
		lock.lock(); defer { lock.unlock() }
		if let s = stores[book.key] { return s }
		let s = Store(book)
		stores[book.key] = s
		return s
	}
	private init(_ book: Book) {
		self.book = book
		db = SQLiteDB(path: Img.dataDir.appendingPathComponent(book.db).path)
	}
	/// the language changed: the cached cards and lists hold translated text
	static func clearCaches() {
		lock.lock(); let all = Array(stores.values); lock.unlock()
		for s in all { s.cacheLock.lock(); s.cache = [:]; s.cacheLock.unlock() }
	}
	func memo<T>(_ key: String, _ make: () -> T) -> T {
		cacheLock.lock()
		if let v = cache[key] as? T { cacheLock.unlock(); return v }
		cacheLock.unlock()
		let v = make()
		cacheLock.lock(); cache[key] = v; cacheLock.unlock()
		return v
	}

	// MARK: spirits & categories

	static let baseSpirits = ["gin", "whiskey", "rum", "tequila", "vodka", "mezcal", "brandy"]
	static let garnishSplitCats = ["fruit"]

	static func spiritLabel(_ k: String) -> String {
		let m = ["gin": "Gin", "whiskey": "Whiskey", "rum": "Rum", "tequila": "Tequila", "vodka": "Vodka", "mezcal": "Mezcal", "brandy": "Brandy"]
		return T(m[k] ?? k.replacingOccurrences(of: "_", with: " ").capitalized)
	}
	static func spiritHex(_ k: String) -> String {
		["gin": "#2F7E54", "whiskey": "#B9761E", "rum": "#A75B2B", "tequila": "#2F8F82", "vodka": "#6E7E95", "mezcal": "#7E7264", "brandy": "#9A3B2C"][k] ?? "#B0894A"
	}
	/// pdt_pretty_cat
	static func prettyCat(_ c: String) -> String {
		let m = ["misc_alcohol": "Other spirits", "spice_herb_garnish": "Spices, herbs & garnishes", "fat_oil": "Fats & oils",
			"sugar_sweetener": "Sugars & sweeteners", "mixer_soda": "Mixers & sodas", "tea_coffee": "Tea & coffee",
			"fortified_wine": "Fortified wine", "fruit_puree": "Fruit purée", "dairy_cream": "Dairy & cream",
			"ice_cream": "Ice cream", "straw": "Strawberries & straws", "garnish_tool": "Straws & umbrellas"]
		return T(m[c] ?? c.replacingOccurrences(of: "_", with: " ").capitalized(firstOnly: true))
	}
	/// pdt_second_label: base spirit | cat:<cat> | kw:<word> | ing:<name>
	static func secondLabel(_ second: String) -> String {
		if second.isEmpty { return "" }
		if baseSpirits.contains(second) { return spiritLabel(second) }
		if second.hasPrefix("cat:") { return prettyCat(String(second.dropFirst(4))) }
		if second.hasPrefix("kw:") { return T(String(second.dropFirst(3)).capitalized(firstOnly: true)) }
		if second.hasPrefix("ing:") { return T(String(second.dropFirst(4))) }
		return second
	}

	/// SQL condition: the ingredient in column `col` is only ever used as a garnish (pdt_garnish_only_sql)
	static func garnishOnlySQL(_ col: String) -> String {
		"(EXISTS (SELECT 1 FROM step gs WHERE gs.ingredient_id=\(col)) AND NOT EXISTS (SELECT 1 FROM step gs JOIN mixtype gm ON gm.mixtype_id=gs.mixtype_id WHERE gs.ingredient_id=\(col) AND lower(gm.name) NOT IN ('garnish','twist','rim')) AND NOT EXISTS (SELECT 1 FROM ingtag gt WHERE gt.ingredient_id=\(col) AND gt.name='dairy_cream'))"
	}
	func isGarnishOnly(_ name: String) -> Bool {
		memo("garnonly \(name)") { db.one("SELECT COUNT(*) FROM ingredient i WHERE i.name=?1 AND \(Store.garnishOnlySQL("i.ingredient_id"))", name).int > 0 }
	}
	/// pdt_display_cat
	func displayCat(_ cat: String, _ name: String) -> String {
		Store.garnishSplitCats.contains(cat) && isGarnishOnly(name) ? "garnishes" : cat
	}
	func ingCats(_ name: String) -> [String] {
		db.column("SELECT t.name FROM ingtag t JOIN ingredient i ON i.ingredient_id=t.ingredient_id WHERE i.name=?1", name).map(\.string)
	}
	/// pdt_ing_primary_cat
	func ingPrimaryCat(_ name: String) -> String {
		let cats = ingCats(name)
		return Store.baseSpirits.first { cats.contains($0) } ?? cats.first ?? ""
	}

	/// list of (key, count) for the 7 base spirits, most cocktails first (pdt_spirit_counts)
	func spiritCounts() -> [(String, Int)] {
		memo("spiritcounts") {
			Store.baseSpirits.map { b in
				(b, db.one("SELECT COUNT(DISTINCT s.drink_id) FROM ingtag t JOIN step s ON s.ingredient_id=t.ingredient_id WHERE t.name=?1", b).int)
			}.sorted { $0.1 > $1.1 }
		}
	}
	/// distinct base spirits in a drink, canonical order
	func drinkSpirits(_ id: Int) -> [String] {
		let have = Set(db.column("SELECT DISTINCT t.name FROM ingtag t JOIN step s ON s.ingredient_id=t.ingredient_id WHERE s.drink_id=?1", id).map(\.string))
		return Store.baseSpirits.filter { have.contains($0) }
	}

	// MARK: pictures that depend on the book's data

	/// pdt_spirit_img: a curated icon, else a famous bottle, else the most-used bottle
	func spiritImg(_ key: String) -> URL? {
		if let u = Img.local("img/spirits/\(key).avif") { return u }
		let famous = ["gin": "Plymouth Gin", "whiskey": "Rittenhouse Bonded Rye Whiskey", "rum": "Bacardi 8 Rum",
			"tequila": "Don Julio Reposado Tequila", "vodka": "Belvedere Vodka", "mezcal": "Sombra Mezcal", "brandy": "Hine V.S.O.P. Cognac"]
		if let f = famous[key], let u = Img.ingredient(f) { return u }
		let name = memo("spiritbrand \(key)") {
			db.one("""
				SELECT i.name FROM ingtag t JOIN ingredient i ON i.ingredient_id=t.ingredient_id
				JOIN step s ON s.ingredient_id=i.ingredient_id WHERE t.name=?1 GROUP BY i.ingredient_id
				ORDER BY COUNT(DISTINCT s.drink_id) DESC, i.ingredient_id ASC LIMIT 1
				""", key).string
		}
		return name.isEmpty ? nil : Img.ingredient(name)
	}
	/// pdt_cat_img: a hand-picked ingredient per category, else the most-used one
	func catImg(_ cat: String) -> URL? {
		let pick = ["fruit": "Orange Slice", "spice_herb_garnish": "Mint Sprig", "liqueur": "Cointreau",
			"syrup": "Deep Mountain Grade B Maple Syrup", "wine": "Channing Daughters Scuttlehole Chardonnay",
			"whiskey": "Rittenhouse Bonded Rye Whiskey", "rum": "Bacardi 8 Rum", "misc_alcohol": "Krogstad Aquavit",
			"sugar_sweetener": "Sugar Cube", "bitters": "Angostura Bitters", "fortified_wine": "Dow's Tawny Port",
			"tequila": "Don Julio Reposado Tequila", "vegetables": "Cucumber Slice", "brandy": "Hine V.S.O.P. Cognac",
			"juice": "Orange Juice", "gin": "Plymouth Gin", "beer": "Southampton Double White Ale",
			"vermouth": "Carpano Antica Sweet Vermouth", "mixer_soda": "Fever-Tree Ginger Ale",
			"water": "Ice-Cold Filtered Water", "tea_coffee": "Freshly Brewed Coffee", "vodka": "Belvedere Vodka",
			"straw": "Strawberry", "absinthe": "Vieux Pontarlier Absinthe", "savory": "Cholula",
			"fruit_puree": "Boiron Passion Fruit Puree", "dairy_cream": "Heavy Cream", "absolutes": "Aftel Anise Hyssop Essence",
			"shrubb": "Concord Shrubb", "mezcal": "Sombra Mezcal", "fat_oil": "Vanilla Butter", "egg": "Whole Egg",
			"champagne": "Moet Imperial Champagne", "nut": "Walnut-Infused Hine V.S.O.P. Cognac",
			"ice_cream": "Ciao Bella Coconut Sorbet", "horchata": "Horchata"]
		if let p = pick[cat], let u = Img.ingredient(p) { return u }
		let name = memo("catimg \(cat)") { () -> String in
			if cat == "garnishes" {
				return db.one("SELECT i.name FROM ingredient i JOIN step s ON s.ingredient_id=i.ingredient_id WHERE \(Store.garnishOnlySQL("i.ingredient_id")) GROUP BY i.ingredient_id ORDER BY COUNT(DISTINCT s.drink_id) DESC, i.ingredient_id ASC LIMIT 1").string
			}
			return db.one("""
				SELECT i.name FROM ingtag t JOIN ingredient i ON i.ingredient_id=t.ingredient_id
				JOIN step s ON s.ingredient_id=i.ingredient_id WHERE t.name=?1 GROUP BY i.ingredient_id
				ORDER BY COUNT(DISTINCT s.drink_id) DESC, i.ingredient_id ASC LIMIT 1
				""", cat).string
		}
		return name.isEmpty ? nil : Img.ingredient(name)
	}
	func cocktailImg(_ name: String) -> URL? { Img.cocktail(book.key, name) }

	// MARK: cards

	struct Card: Hashable {
		let id: Int
		let name: String
		let image: URL?
		let glass: String
		let spiritHex: String
		let ingredients: String
	}
	/// pdt_card's data: picture, name, and the ingredient line
	func card(_ d: DrinkRef) -> Card {
		memo("card \(d.id)") {
			let glass = db.one("SELECT g.name FROM drink2glass d2 JOIN glass g ON d2.glass_id=g.glass_id WHERE d2.drink_id=?1 LIMIT 1", d.id).string
			let sp = drinkSpirits(d.id).first
			let ings = db.column("SELECT i.name FROM step s JOIN ingredient i ON i.ingredient_id=s.ingredient_id WHERE s.drink_id=?1 AND s.sortorder IS NOT NULL ORDER BY s.sortorder", d.id).map { T($0.string) }
			return Card(id: d.id, name: d.name, image: cocktailImg(d.name), glass: glass,
				spiritHex: sp.map(Store.spiritHex) ?? "#B0894A", ingredients: ings.joined(separator: ", "))
		}
	}
	private func refs(_ rows: [SQLiteDB.Row]) -> [DrinkRef] { rows.map { DrinkRef(id: $0.i(0), name: $0.s(1)) } }

	func popularity() -> [Int: Int] {
		memo("pop") { Dictionary(db.rows("SELECT drink_id, score FROM popularity").map { ($0.i(0), $0.i(1)) }, uniquingKeysWith: { a, _ in a }) }
	}
	func byPopularity(limit: Int = -1) -> [DrinkRef] {
		refs(db.rows("SELECT d.drink_id, d.name FROM drink d LEFT JOIN popularity p ON p.drink_id=d.drink_id ORDER BY COALESCE(p.score,0) DESC, d.name LIMIT ?1", limit))
	}
	func allAZ() -> [DrinkRef] { refs(db.rows("SELECT drink_id, name FROM drink ORDER BY name")) }

	/// /recipes/?sort=spirit: one group per base spirit (most popular first), then Other
	func groupsBySpirit() -> [(key: String?, label: String, drinks: [DrinkRef])] {
		var out: [(key: String?, label: String, drinks: [DrinkRef])] = []
		for (k, _) in spiritCounts() {
			let g = refs(db.rows("""
				SELECT DISTINCT d.drink_id did, d.name nm, COALESCE(p.score,0) sc
				FROM drink d JOIN step s ON s.drink_id=d.drink_id JOIN ingtag t ON t.ingredient_id=s.ingredient_id
				LEFT JOIN popularity p ON p.drink_id=d.drink_id WHERE t.name=?1 ORDER BY sc DESC, d.name
				""", k))
			if !g.isEmpty { out.append((k, Store.spiritLabel(k), g)) }
		}
		let bsin = Store.baseSpirits.map { "'\($0)'" }.joined(separator: ",")
		let other = refs(db.rows("""
			SELECT d.drink_id did, d.name nm FROM drink d LEFT JOIN popularity p ON p.drink_id=d.drink_id
			WHERE NOT EXISTS (SELECT 1 FROM step s JOIN ingtag t ON t.ingredient_id=s.ingredient_id WHERE s.drink_id=d.drink_id AND t.name IN (\(bsin)))
			ORDER BY COALESCE(p.score,0) DESC, d.name
			"""))
		if !other.isEmpty { out.append((nil, T("Other"), other)) }
		return out
	}
	/// /recipes/?sort=sweet: grouped by drink_stats.balance
	func groupsBySweetness() -> [(label: String, drinks: [DrinkRef])] {
		var out: [(label: String, drinks: [DrinkRef])] = []
		for (cit, lab) in [(true, "Tart"), (true, "Balanced"), (true, "Sweet"), (false, "Dry"), (false, "Off-dry"), (false, "Sweet"), (false, "Very sweet")] {
			let g: [DrinkRef]
			let head: String
			if cit {
				g = refs(db.rows("SELECT d.drink_id did, d.name nm FROM drink d JOIN drink_stats s ON s.drink_id=d.drink_id WHERE s.acid_pct >= 0.4 AND s.balance=?1 ORDER BY s.sugar_pct/s.acid_pct, d.name", lab))
				head = T("Citrus: {label}", ["label": T(lab)])
			} else {
				g = refs(db.rows("SELECT d.drink_id did, d.name nm FROM drink d JOIN drink_stats s ON s.drink_id=d.drink_id WHERE s.acid_pct < 0.4 AND s.balance=?1 ORDER BY s.sugar_pct, d.name", lab))
				head = T("Non-Citrus: {label}", ["label": T(lab)])
			}
			if !g.isEmpty { out.append((head, g)) }
		}
		return out
	}

	// MARK: spirit / mix pages

	/// pdt_drinks_for_spirit
	func drinksForSpirit(_ key: String, and: String = "") -> [DrinkRef] {
		if and.isEmpty {
			return refs(db.rows("""
				SELECT DISTINCT d.drink_id, d.name FROM drink d JOIN step s ON s.drink_id=d.drink_id
				JOIN ingtag t ON t.ingredient_id=s.ingredient_id WHERE t.name=?1 ORDER BY d.name
				""", key))
		}
		return refs(db.rows("""
			SELECT d.drink_id, d.name FROM drink d
			WHERE EXISTS (SELECT 1 FROM step s JOIN ingtag t ON t.ingredient_id=s.ingredient_id WHERE s.drink_id=d.drink_id AND t.name=?1)
			  AND EXISTS (SELECT 1 FROM step s2 JOIN ingtag t2 ON t2.ingredient_id=s2.ingredient_id WHERE s2.drink_id=d.drink_id AND t2.name=?2)
			ORDER BY d.name
			""", key, and))
	}
	/// pdt_drinks_for_combo: base spirit AND (spirit | cat:<cat> | kw:<substring> | ing:<name>)
	func drinksForCombo(_ key: String, _ second: String) -> [DrinkRef] {
		if second.isEmpty || Store.baseSpirits.contains(second) { return drinksForSpirit(key, and: second) }
		let spiritCond = "EXISTS (SELECT 1 FROM step s JOIN ingtag t ON t.ingredient_id=s.ingredient_id WHERE s.drink_id=d.drink_id AND t.name=?1)"
		if second.hasPrefix("cat:") {
			return refs(db.rows("SELECT d.drink_id, d.name FROM drink d WHERE \(spiritCond) AND EXISTS (SELECT 1 FROM step s2 JOIN ingtag t2 ON t2.ingredient_id=s2.ingredient_id WHERE s2.drink_id=d.drink_id AND t2.name=?2) ORDER BY d.name", key, String(second.dropFirst(4))))
		}
		if second.hasPrefix("kw:") {
			return refs(db.rows("SELECT d.drink_id, d.name FROM drink d WHERE \(spiritCond) AND EXISTS (SELECT 1 FROM step s3 JOIN ingredient i ON i.ingredient_id=s3.ingredient_id WHERE s3.drink_id=d.drink_id AND i.name LIKE ?2) ORDER BY d.name", key, "%\(second.dropFirst(3))%"))
		}
		if second.hasPrefix("ing:") {
			return refs(db.rows("SELECT d.drink_id, d.name FROM drink d WHERE \(spiritCond) AND EXISTS (SELECT 1 FROM step s3 JOIN ingredient i ON i.ingredient_id=s3.ingredient_id WHERE s3.drink_id=d.drink_id AND i.name=?2) ORDER BY d.name", key, String(second.dropFirst(4))))
		}
		return drinksForSpirit(key)
	}
	/// most popular first (the spirit page's default sort): popularity desc, then name
	func sortedByPopularity(_ list: [DrinkRef]) -> [DrinkRef] {
		let sc = popularity()
		return list.sorted { a, b in
			let x = sc[a.id] ?? 0, y = sc[b.id] ?? 0
			return x != y ? x > y : a.name.localizedStandardCompare(b.name) == .orderedAscending
		}
	}

	struct IngCount: Hashable { let id: Int; let name: String; let count: Int }

	/// a spirit's types (ingredients tagged with it), most used first
	func spiritTypes(_ key: String) -> [IngCount] {
		db.rows("""
			SELECT i.ingredient_id iid, i.name nm, COUNT(DISTINCT s.drink_id) c FROM ingtag t JOIN ingredient i ON i.ingredient_id=t.ingredient_id
			LEFT JOIN step s ON s.ingredient_id=i.ingredient_id WHERE t.name=?1 GROUP BY i.ingredient_id ORDER BY c DESC, i.name
			""", key).map { IngCount(id: $0.i(0), name: $0.s(1), count: $0.i(2)) }
	}
	/// the spirit page's companion chips: non-spirit, non-garnish ingredients its cocktails use most
	func spiritCompanions(_ key: String) -> [IngCount] {
		db.rows("""
			SELECT i.ingredient_id iid, i.name nm,
				(SELECT COUNT(DISTINCT s4.drink_id) FROM step s4 WHERE s4.ingredient_id=i.ingredient_id AND s4.drink_id IN
					(SELECT s5.drink_id FROM step s5 JOIN ingtag t5 ON t5.ingredient_id=s5.ingredient_id WHERE t5.name=?1)) c
			FROM step s JOIN ingredient i ON i.ingredient_id=s.ingredient_id JOIN mixtype m ON m.mixtype_id=s.mixtype_id
			WHERE s.drink_id IN (SELECT DISTINCT s2.drink_id FROM step s2 JOIN ingtag t2 ON t2.ingredient_id=s2.ingredient_id WHERE t2.name=?1)
			  AND lower(m.name) NOT IN ('garnish','twist','rim','spritz','flame')
			  AND i.ingredient_id NOT IN (SELECT ingredient_id FROM ingtag WHERE name IN ('gin','whiskey','rum','tequila','vodka','mezcal','brandy','liqueur','misc_alcohol','absinthe','shrubb'))
			GROUP BY i.ingredient_id ORDER BY c DESC, i.name LIMIT 18
			""", key).map { IngCount(id: $0.i(0), name: $0.s(1), count: $0.i(2)) }
	}
	/// for a keyword combo, the most-used ingredient whose name has it (its picture)
	func keywordIngredient(_ kw: String) -> String {
		db.one("SELECT i.name FROM ingredient i JOIN step s ON s.ingredient_id=i.ingredient_id WHERE i.name LIKE ?1 GROUP BY i.ingredient_id ORDER BY COUNT(DISTINCT s.drink_id) DESC LIMIT 1", "%\(kw)%").string
	}

	// MARK: home page

	struct MixOption: Hashable { let value: String; let label: String; let count: Int; let group: String }
	/// "Base spirit + ..." mixer: for each base spirit the valid second choices with counts
	func mixData() -> [String: [MixOption]] {
		memo("mixdata") {
			let bsl = Store.baseSpirits
			let bsin = bsl.map { "'\($0)'" }.joined(separator: ",")
			var stylecats: [String] = []
			for r in db.rows("SELECT name nm, COUNT(*) c FROM ingtag GROUP BY name HAVING c>=10 ORDER BY c DESC") {
				let nm = r.s(0)
				if bsl.contains(nm) || nm == "fruit" || nm == "juice" || stylecats.count >= 8 { continue }
				stylecats.append(nm)
			}
			var flavs: [String] = []
			for kw in ["mint", "lemon", "lime", "orange", "grapefruit", "ginger", "pineapple", "cranberry", "egg", "cucumber", "honey", "coffee", "basil"] {
				if db.one("SELECT COUNT(*) FROM ingredient WHERE name LIKE ?1", "%\(kw)%").int > 0 { flavs.append(kw) }
			}
			var spsp: [String: Int] = [:]
			for r in db.rows("""
				SELECT t1.name a, t2.name b, COUNT(DISTINCT s1.drink_id) c FROM step s1 JOIN ingtag t1 ON t1.ingredient_id=s1.ingredient_id
				JOIN step s2 ON s2.drink_id=s1.drink_id JOIN ingtag t2 ON t2.ingredient_id=s2.ingredient_id
				WHERE t1.name IN (\(bsin)) AND t2.name IN (\(bsin)) AND t1.name!=t2.name GROUP BY t1.name,t2.name
				""") { spsp["\(r.s(0)),\(r.s(1))"] = r.i(2) }
			var spcat: [String: Int] = [:]
			if !stylecats.isEmpty {
				let stin = stylecats.map { "'\($0)'" }.joined(separator: ",")
				for r in db.rows("""
					SELECT t1.name a, t2.name cat, COUNT(DISTINCT s1.drink_id) c FROM step s1 JOIN ingtag t1 ON t1.ingredient_id=s1.ingredient_id
					JOIN step s2 ON s2.drink_id=s1.drink_id JOIN ingtag t2 ON t2.ingredient_id=s2.ingredient_id
					WHERE t1.name IN (\(bsin)) AND t2.name IN (\(stin)) GROUP BY t1.name,t2.name
					""") { spcat["\(r.s(0)),\(r.s(1))"] = r.i(2) }
			}
			var spkw: [String: Int] = [:]
			for kw in flavs {
				for r in db.rows("""
					SELECT t1.name a, COUNT(DISTINCT s1.drink_id) c FROM step s1 JOIN ingtag t1 ON t1.ingredient_id=s1.ingredient_id
					JOIN step s3 ON s3.drink_id=s1.drink_id JOIN ingredient i ON i.ingredient_id=s3.ingredient_id
					WHERE t1.name IN (\(bsin)) AND i.name LIKE ?1 GROUP BY t1.name
					""", "%\(kw)%") { spkw["\(r.s(0)),\(kw)"] = r.i(1) }
			}
			var out: [String: [MixOption]] = [:]
			for a in bsl {
				var rows: [MixOption] = []
				for b in bsl where b != a { if let c = spsp["\(a),\(b)"], c > 0 { rows.append(MixOption(value: b, label: Store.spiritLabel(b), count: c, group: "sp")) } }
				for cat in stylecats { if let c = spcat["\(a),\(cat)"], c > 0 { rows.append(MixOption(value: "cat:\(cat)", label: Store.prettyCat(cat), count: c, group: "st")) } }
				for kw in flavs { if let c = spkw["\(a),\(kw)"], c > 0 { rows.append(MixOption(value: "kw:\(kw)", label: T(kw.capitalized(firstOnly: true)), count: c, group: "fl")) } }
				out[a] = rows
			}
			return out
		}
	}

	/// "By spirit pairs": each base spirit with the other spirits it is used with
	func spiritPairs() -> [(key: String, count: Int, pairs: [(String, Int)])] {
		let bs = Store.baseSpirits.map { "'\($0)'" }.joined(separator: ",")
		var grp: [String: [(String, Int)]] = [:]
		var order: [String] = []
		for r in db.rows("""
			SELECT t1.name a, t2.name b, COUNT(DISTINCT s1.drink_id) c FROM step s1 JOIN ingtag t1 ON t1.ingredient_id=s1.ingredient_id
			JOIN step s2 ON s2.drink_id=s1.drink_id JOIN ingtag t2 ON t2.ingredient_id=s2.ingredient_id
			WHERE t1.name IN (\(bs)) AND t2.name IN (\(bs)) AND t1.name < t2.name GROUP BY t1.name,t2.name ORDER BY c DESC, b
			""") {
			if grp[r.s(0)] == nil { order.append(r.s(0)) }
			grp[r.s(0), default: []].append((r.s(1), r.i(2)))
		}
		let spcount = Dictionary(uniqueKeysWithValues: spiritCounts())
		return order.map { (key: $0, count: spcount[$0] ?? 0, pairs: grp[$0] ?? []) }
			.sorted { $0.count > $1.count }
	}

	struct DrillCat: Hashable { let cat: String; let name: String; let n: Int; let ings: [DrillIng] }
	struct DrillIng: Hashable { let name: String; let count: Int; let spirits: [SpiritCount] }
	struct SpiritCount: Hashable { let key: String; let count: Int }
	/// "By ingredient type": category -> top ingredients -> base spirits they're used with
	func drill() -> [DrillCat] {
		memo("drill") {
			var cats: [String] = []
			for r in db.rows("SELECT name nm, COUNT(*) c FROM ingtag GROUP BY name HAVING c>=5 ORDER BY c DESC") {
				if Store.baseSpirits.contains(r.s(0)) || cats.count >= 12 { continue }
				cats.append(r.s(0))
			}
			let catin = cats.map { "'\($0.replacingOccurrences(of: "'", with: "''"))'" }.joined(separator: ",")
			let bsin = Store.baseSpirits.map { "'\($0)'" }.joined(separator: ",")
			var catcoc: [String: Int] = [:]
			for r in db.rows("SELECT tc.name cat, COUNT(DISTINCT st.drink_id) c FROM ingtag tc JOIN step st ON st.ingredient_id=tc.ingredient_id WHERE tc.name IN (\(catin)) GROUP BY tc.name") { catcoc[r.s(0)] = r.i(1) }
			var catings: [String: [(String, Int)]] = [:]
			for r in db.rows("SELECT tc.name cat, i.name ing, MIN(i.ingredient_id) iid, COUNT(DISTINCT st.drink_id) c FROM ingtag tc JOIN ingredient i ON i.ingredient_id=tc.ingredient_id JOIN step st ON st.ingredient_id=i.ingredient_id WHERE tc.name IN (\(catin)) GROUP BY tc.name, i.name") {
				catings[r.s(0), default: []].append((r.s(1), r.i(3)))
			}
			var sprow: [String: [SpiritCount]] = [:]
			for r in db.rows("""
				SELECT tc.name cat, i.name ing, ts.name sp, COUNT(DISTINCT st.drink_id) c
				FROM ingtag tc JOIN ingredient i ON i.ingredient_id=tc.ingredient_id JOIN step st ON st.ingredient_id=i.ingredient_id
				JOIN step st2 ON st2.drink_id=st.drink_id JOIN ingtag ts ON ts.ingredient_id=st2.ingredient_id
				WHERE tc.name IN (\(catin)) AND ts.name IN (\(bsin)) GROUP BY tc.name, i.name, ts.name ORDER BY c DESC
				""") { sprow["\(r.s(0))\u{1}\(r.s(1))", default: []].append(SpiritCount(key: r.s(2), count: r.i(3))) }
			return cats.compactMap { cat in
				guard let list = catings[cat] else { return nil }
				// stable sort by count desc, as Tcl's lsort keeps equal elements in order
				let top = list.enumerated().sorted { $0.element.1 != $1.element.1 ? $0.element.1 > $1.element.1 : $0.offset < $1.offset }.prefix(10).map(\.element)
				return DrillCat(cat: cat, name: Store.prettyCat(cat), n: catcoc[cat] ?? 0,
					ings: top.map { DrillIng(name: $0.0, count: $0.1, spirits: sprow["\(cat)\u{1}\($0.0)"] ?? []) })
			}
		}
	}

	// MARK: glasses

	func glasses() -> [(String, Int)] {
		db.rows("SELECT g.name nm, COUNT(d2.drink_id) c FROM glass g LEFT JOIN drink2glass d2 ON g.glass_id=d2.glass_id GROUP BY g.glass_id HAVING c>0 ORDER BY c DESC").map { ($0.s(0), $0.i(1)) }
	}
	func drinksInGlass(_ g: String) -> [DrinkRef] {
		refs(db.rows("SELECT DISTINCT d.drink_id, d.name FROM drink d JOIN drink2glass d2 ON d.drink_id=d2.drink_id JOIN glass g ON d2.glass_id=g.glass_id WHERE g.name=?1 ORDER BY d.name", g))
	}

	// MARK: ingredients & categories

	/// /ingredients/ category chips: (cat, count), count >= 3, most first
	func categoryChips() -> [(String, Int)] {
		var c: [String: Int] = [:]
		for r in db.rows("SELECT name nm, COUNT(*) c FROM ingtag GROUP BY name") { c[r.s(0)] = r.i(1) }
		for sc in Store.garnishSplitCats where c[sc] != nil {
			c[sc] = db.one("SELECT COUNT(*) FROM ingtag t WHERE t.name=?1 AND NOT \(Store.garnishOnlySQL("t.ingredient_id"))", sc).int
		}
		c["garnishes"] = db.one("SELECT COUNT(*) FROM ingredient i WHERE \(Store.garnishOnlySQL("i.ingredient_id"))").int
		// lsort -stride 2 -index 1 -integer -decreasing on a dict: stable over the dict's order
		return c.filter { $0.value >= 3 }.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.map { ($0.key, $0.value) }
	}
	func allIngredients() -> [String] { db.column("SELECT name FROM ingredient ORDER BY name").map(\.string) }

	/// the ingredients of a category page, and the cocktails using any of them (most popular first)
	func category(_ cat: String) -> (ings: [String], drinks: [DrinkRef]) {
		let ingsql: String, usesql: String
		if cat == "garnishes" {
			ingsql = "SELECT DISTINCT i.ingredient_id iid, i.name nm FROM ingredient i WHERE \(Store.garnishOnlySQL("i.ingredient_id")) ORDER BY i.name"
			usesql = "EXISTS (SELECT 1 FROM step s WHERE s.drink_id=d.drink_id AND \(Store.garnishOnlySQL("s.ingredient_id")))"
		} else {
			let split = Store.garnishSplitCats.contains(cat)
			let notg = split ? "AND NOT \(Store.garnishOnlySQL("i.ingredient_id"))" : ""
			let notgs = split ? "AND NOT \(Store.garnishOnlySQL("s.ingredient_id"))" : ""
			ingsql = "SELECT DISTINCT i.ingredient_id iid, i.name nm FROM ingtag t JOIN ingredient i ON i.ingredient_id=t.ingredient_id WHERE t.name=?1 \(notg) ORDER BY i.name"
			usesql = "EXISTS (SELECT 1 FROM step s JOIN ingtag t ON t.ingredient_id=s.ingredient_id WHERE s.drink_id=d.drink_id AND t.name=?1 \(notgs))"
		}
		let ings = db.rows(ingsql, cat).map { $0.s(1) }
		let drinks = refs(db.rows("SELECT d.drink_id, d.name FROM drink d LEFT JOIN popularity p ON p.drink_id=d.drink_id WHERE \(usesql) ORDER BY COALESCE(p.score,0) DESC, d.name", cat))
		return (ings, drinks)
	}
	func ingredientName(_ id: Int) -> String? {
		let v = db.one("SELECT name FROM ingredient WHERE ingredient_id=?1", id)
		return v.isNull ? nil : v.string
	}
	func ingredientExists(_ name: String) -> Bool { db.one("SELECT COUNT(*) FROM ingredient WHERE name=?1", name).int > 0 }
	func ingredientId(_ name: String) -> Int? {
		let v = db.one("SELECT ingredient_id FROM ingredient WHERE name=?1", name)
		return v.isNull ? nil : v.int
	}
	func drinksWith(_ ing: String, _ with: String = "") -> [DrinkRef] {
		if with.isEmpty {
			return refs(db.rows("SELECT DISTINCT d.drink_id, d.name FROM drink d JOIN step s ON d.drink_id=s.drink_id JOIN ingredient i ON s.ingredient_id=i.ingredient_id WHERE i.name=?1 ORDER BY d.name", ing))
		}
		return refs(db.rows("""
			SELECT DISTINCT d.drink_id, d.name FROM drink d
			JOIN step s1 ON d.drink_id=s1.drink_id JOIN ingredient i1 ON s1.ingredient_id=i1.ingredient_id
			JOIN step s2 ON d.drink_id=s2.drink_id JOIN ingredient i2 ON s2.ingredient_id=i2.ingredient_id
			WHERE i1.name=?1 AND i2.name=?2 ORDER BY d.name
			""", ing, with))
	}
	/// "Pairs most with": the 12 ingredients most used with this one
	func pairsWith(_ ing: String) -> [(String, Int)] {
		db.rows("""
			SELECT i2.name nm, COUNT(DISTINCT s1.drink_id) c FROM step s1 JOIN step s2 ON s1.drink_id=s2.drink_id
			JOIN ingredient i1 ON s1.ingredient_id=i1.ingredient_id JOIN ingredient i2 ON s2.ingredient_id=i2.ingredient_id
			WHERE i1.name=?1 AND i2.name!=?1 GROUP BY i2.name ORDER BY c DESC, i2.name LIMIT 12
			""", ing).map { ($0.s(0), $0.i(1)) }
	}

	// MARK: search

	/// pdt_search_generics: base spirits and ingredient categories whose tag matches the query
	/// ("whisky" -> Whiskey), prefix matches first, then by how many cocktails use them
	func searchGenerics(_ q: String, limit: Int = 8) -> [(label: String, image: URL?, route: Route)] {
		guard q.count >= 2 else { return [] }
		let fold = { (s: String) in s.lowercased().replacingOccurrences(of: "whiskies", with: "whiskey").replacingOccurrences(of: "whisky", with: "whiskey") }
		let nq = fold(q)
		var hits: [(rk: Int, c: Int, label: String, image: URL?, route: Route)] = []
		for r in db.rows("SELECT t.name tag, COUNT(DISTINCT s.drink_id) c FROM ingtag t LEFT JOIN step s ON s.ingredient_id=t.ingredient_id GROUP BY t.name") {
			let tag = r.s(0)
			let words = fold("\(tag) \(tag.replacingOccurrences(of: "_", with: " "))")
			guard words.contains(nq) else { continue }
			let isbs = Store.baseSpirits.contains(tag)
			hits.append((words.hasPrefix(nq) ? 0 : 1, r.i(1), isbs ? Store.spiritLabel(tag) : Store.prettyCat(tag),
				isbs ? spiritImg(tag) : catImg(tag), Route.cat(book.key, tag)))
		}
		// lsort -index 1 then a stable lsort -index 0: rank, then most cocktails
		return hits.enumerated().sorted { a, b in
			a.element.rk != b.element.rk ? a.element.rk < b.element.rk : a.element.c != b.element.c ? a.element.c > b.element.c : a.offset < b.offset
		}.prefix(limit).map { ($0.element.label, $0.element.image, $0.element.route) }
	}

	func search(_ q: String) -> (drinks: [DrinkRef], ings: [String]) {
		let like = "%\(q)%"
		let drinks = refs(db.rows("""
			SELECT DISTINCT d.drink_id, d.name FROM drink d LEFT JOIN step s ON d.drink_id=s.drink_id
			LEFT JOIN ingredient i ON s.ingredient_id=i.ingredient_id WHERE d.name LIKE ?1 OR i.name LIKE ?1 ORDER BY d.name
			""", like))
		let ings = db.rows("SELECT i.ingredient_id iid, i.name nm FROM ingredient i LEFT JOIN step s ON s.ingredient_id=i.ingredient_id WHERE i.name LIKE ?1 GROUP BY i.ingredient_id ORDER BY COUNT(DISTINCT s.drink_id) DESC, i.name", like).map { $0.s(1) }
		return (drinks, ings)
	}
}

extension String {
	/// Tcl's string totitle: first letter upper, the rest lower
	func capitalized(firstOnly: Bool) -> String {
		guard let f = first else { return self }
		return String(f).uppercased() + dropFirst().lowercased()
	}
}
