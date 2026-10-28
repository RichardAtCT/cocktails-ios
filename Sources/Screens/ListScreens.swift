import SwiftUI

/// /<book>/recipes/ with its sort pills: most popular, A–Z, by base spirit, sweet vs sour
struct RecipesView: View {
	let book: Book
	@State var sort: String
	@State private var open: Set<String> = []
	init(book: Book, sort: String) { self.book = book; _sort = State(initialValue: sort) }

	var body: some View {
		let s = book.store
		PageScroll {
			PageHead(crumb: [(T("Home"), .home(book.key)), (T("All recipes"), nil)], title: T("All recipes"))
				.padding(.bottom, -14)
			FlowLayout(spacing: 8, lineSpacing: 8) {
				Text(nCocktails(book.nstated)).font(Theme.sans(14.4)).foregroundStyle(Theme.soft).padding(.trailing, 2).padding(.top, 6)
				ForEach([("pop", T("most popular")), ("az", T("A–Z")), ("spirit", T("by base spirit")), ("sweet", T("sweet vs sour"))], id: \.0) { k, l in
					Button { sort = k } label: { SortPill(label: l, on: sort == k) }.buttonStyle(.plain)
				}
			}
			.padding(.top, 8).padding(.bottom, 26)
			switch sort {
			case "az": CardGrid(book: book, drinks: s.allAZ())
			case "spirit":
				VStack(spacing: 0) {
					ForEach(s.groupsBySpirit(), id: \.label) { g in
						GroupSection(label: g.label, image: g.key.flatMap { s.spiritImg($0) }, count: g.drinks.count, open: open.contains(g.label), toggle: { toggle(g.label) }) {
							CardGrid(book: book, drinks: g.drinks, ranked: true)
						}
					}
				}
			case "sweet":
				VStack(spacing: 0) {
					ForEach(s.groupsBySweetness(), id: \.label) { g in
						GroupSection(label: g.label, image: nil, count: g.drinks.count, open: open.contains(g.label), toggle: { toggle(g.label) }) {
							CardGrid(book: book, drinks: g.drinks)
						}
					}
				}
			default: CardGrid(book: book, drinks: s.byPopularity(), ranked: true)
			}
		}
	}
	private func toggle(_ k: String) { if open.contains(k) { open.remove(k) } else { open.insert(k) } }
}

/// .sgroup: a collapsible group (collapsed by default), as the grouped recipe sorts
struct GroupSection<Content: View>: View {
	let label: String
	let image: URL?
	let count: Int
	let open: Bool
	let toggle: () -> Void
	@ViewBuilder var content: Content
	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Button(action: toggle) {
				HStack(spacing: 12) {
					Image(systemName: "arrowtriangle.right.fill").font(.system(size: 8)).foregroundStyle(Theme.faint).rotationEffect(.degrees(open ? 90 : 0))
					if let image { Pic(url: image).frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 7)) }
					Text(label).font(Theme.sans(20.8, .semibold)).kerning(-0.2).foregroundStyle(Theme.ink)
					Spacer()
					Text("\(count)").font(Theme.mono(13)).foregroundStyle(Theme.faint)
				}
				.padding(.vertical, 14).padding(.horizontal, 2).contentShape(Rectangle())
			}.buttonStyle(.plain)
			if open { content.padding(.top, 4).padding(.bottom, 24) }
			Rectangle().fill(Theme.line).frame(height: 1)
		}
	}
}

/// /<book>/spirits
struct SpiritsView: View {
	let book: Book
	var body: some View {
		PageScroll {
			PageHead(crumb: [(T("Home"), .home(book.key)), (T("Spirits"), nil)], title: T("Choose a base spirit"))
			VStack(spacing: 0) { ForEach(book.store.spiritCounts(), id: \.0) { SpiritRow(book: book, key: $0.0, count: $0.1) } }
			FlowLayout { NavigationLink(value: Route.glasses(book.key)) { Chip(label: "\(T("Browse by glass")) →") }.buttonStyle(.plain) }
				.padding(.top, 22)
		}
	}
}

/// the same page in the other books, with how many cocktails it has there
func otherBooks(_ book: Book, _ count: (Store) -> Int, _ route: (Book) -> Route) -> [(book: Book, n: Int, route: Route)] {
	Book.all.filter { $0 != book }.compactMap { ob in
		let n = count(ob.store)
		return n > 0 ? (ob, n, route(ob)) : nil
	}
}

/// /<book>/spirit/<a>, /spirit/<a>/<b> and /mix?a=&b= (cat:, kw:, ing: combos)
struct SpiritView: View {
	let book: Book
	let key: String
	let and: String
	@State private var sort = "pop"

	var body: some View {
		let s = book.store
		let flat = s.drinksForCombo(key, and)
		let n = flat.count
		let label = Store.spiritLabel(key)
		let others = otherBooks(book, { $0.drinksForCombo(key, and).count }, { .spirit($0.key, key: key, and: and) })
		PageScroll {
			if and.isEmpty {
				Crumb(items: [(T("Home"), .home(book.key)), (T("Spirits"), .spirits(book.key)), (label, nil)]).padding(.top, 10)
				HStack(spacing: 18) {
					VStack(alignment: .leading, spacing: 10) {
						H1(label)
						Text(n == 1 ? T("1 cocktail features {spirit}", ["spirit": label]) : T("{n} cocktails feature {spirit}", ["n": n, "spirit": label]))
							.font(Theme.mono(13)).foregroundStyle(Theme.soft)
					}
					Spacer()
					if let u = s.spiritImg(key) { Pic(url: u, bg: nil).frame(width: 84, height: 84) }
				}
				// + other base spirits that pair with it
				FlowLayout {
					Text("+").font(Theme.mono(16)).foregroundStyle(Theme.faint)
					ForEach(s.spiritCounts().filter { $0.0 != key }, id: \.0) { k2, _ in
						let cc = s.drinksForSpirit(key, and: k2).count
						if cc > 0 {
							NavigationLink(value: Route.spirit(book.key, key: key, and: k2)) { Chip(label: Store.spiritLabel(k2), image: s.spiritImg(k2), count: cc) }.buttonStyle(.plain)
						}
					}
				}.padding(.top, 16)
				FlowLayout {
					Text("+").font(Theme.mono(16)).foregroundStyle(Theme.faint)
					ForEach(s.spiritCompanions(key), id: \.id) { ic in
						NavigationLink(value: Route.spirit(book.key, key: key, and: "ing:\(ic.name)")) { Chip(label: T(ic.name), image: Img.ingredient(ic.name), count: ic.count) }.buttonStyle(.plain)
					}
				}.padding(.top, 16).padding(.bottom, 24)
				let types = s.spiritTypes(key)
				if !types.isEmpty {
					Block(rule: false, top: 20) {
						SectionHead(title: T("Types of {spirit}", ["spirit": label]), count: types.count)
						IngGrid(items: types.map { (T($0.name), Img.ingredient($0.name), Route.ingredient(book.key, name: $0.name, with: "")) })
					}
				}
				Block {
					SectionHead(title: T("{spirit} cocktails", ["spirit": label]), count: n) { OtherBookPills(others: others) }
					FlowLayout {
						Text(T("sort")).font(Theme.sans(14.4)).foregroundStyle(Theme.soft).padding(.top, 6)
						Button { sort = "pop" } label: { SortPill(label: T("most popular"), on: sort == "pop") }.buttonStyle(.plain)
						Button { sort = "az" } label: { SortPill(label: T("A–Z"), on: sort == "az") }.buttonStyle(.plain)
					}.padding(.bottom, 20)
					if sort == "az" { CardGrid(book: book, drinks: flat) } else { CardGrid(book: book, drinks: s.sortedByPopularity(flat), ranked: true) }
				}
			} else {
				// spirit + anything: the ingredient-pair layout
				let alabel = Store.secondLabel(and)
				Crumb(items: [(T("Home"), .home(book.key)), (T("Spirits"), .spirits(book.key)), (label, .spirit(book.key, key: key, and: "")), (alabel, nil)]).padding(.top, 10)
				pairPictures(s, alabel)
				(Text(label) + Text(" + \(alabel)").foregroundColor(Theme.faint))
					.font(Theme.sans(34, .semibold)).kerning(-0.8).foregroundStyle(Theme.ink).padding(.top, 14)
				Eye(T("Pairs most with")).padding(.top, 16).padding(.bottom, 7)
				FlowLayout(spacing: 7, lineSpacing: 7) {
					if !Store.baseSpirits.contains(and) {
						NavigationLink(value: Route.spirit(book.key, key: key, and: "")) { PairChip(label: alabel, selected: true) }.buttonStyle(.plain)
					}
					ForEach(s.spiritCounts().filter { $0.0 != key }, id: \.0) { k2, _ in
						if and == k2 {
							NavigationLink(value: Route.spirit(book.key, key: key, and: "")) { PairChip(label: Store.spiritLabel(k2), selected: true) }.buttonStyle(.plain)
						} else {
							let cc = s.drinksForSpirit(key, and: k2).count
							if cc > 0 { NavigationLink(value: Route.spirit(book.key, key: key, and: k2)) { PairChip(label: Store.spiritLabel(k2), count: cc) }.buttonStyle(.plain) }
						}
					}
				}.padding(.bottom, 26)
				Block {
					SectionHead(title: T("Cocktails with {ingredient} and {other}", ["ingredient": label, "other": alabel]), count: n) { OtherBookPills(others: others) }
					CardGrid(book: book, drinks: s.sortedByPopularity(flat))
				}
			}
		}
	}

	@ViewBuilder private func pairPictures(_ s: Store, _ alabel: String) -> some View {
		if Store.baseSpirits.contains(and), let pair = Img.spiritPair(key, and) {
			Pic(url: pair, bg: nil).frame(maxWidth: .infinity).frame(height: 180)
		} else {
			let aimg: URL? = and.hasPrefix("cat:") ? s.catImg(String(and.dropFirst(4)))
				: and.hasPrefix("ing:") ? Img.ingredient(String(and.dropFirst(4)))
				: and.hasPrefix("kw:") ? Img.ingredient(s.keywordIngredient(String(and.dropFirst(3))))
				: nil
			HStack(spacing: -56) {
				if let u = s.spiritImg(key) { Pic(url: u).frame(width: 168, height: 168).blendMode(.multiply) }
				if let aimg { Pic(url: aimg).frame(width: 168, height: 168).blendMode(.multiply) }
			}
			.background(Theme.picBG)
		}
	}
}

/// /<book>/glasses
struct GlassesView: View {
	let book: Book
	var body: some View {
		PageScroll {
			PageHead(crumb: [(T("Home"), .home(book.key)), (T("Glasses"), nil)], title: T("Browse by glass"))
			VStack(spacing: 0) {
				ForEach(book.store.glasses(), id: \.0) { g, c in
					LinkRow(label: T(g), image: Img.glass(g), imageSize: 51, count: c, route: .glass(book.key, name: g), topRule: false)
				}
			}
		}
	}
}

/// /<book>/glass/<name>
struct GlassView: View {
	let book: Book
	let name: String
	var body: some View {
		let flat = book.store.drinksInGlass(name)
		PageScroll {
			Crumb(items: [(T("Home"), .home(book.key)), (T("Glasses"), .glasses(book.key)), (T(name), nil)]).padding(.top, 10)
			HStack(spacing: 18) {
				VStack(alignment: .leading, spacing: 10) {
					H1(T("{glass} cocktails", ["glass": T(name)]))
					Text(nCocktails(flat.count)).font(Theme.mono(13)).foregroundStyle(Theme.soft)
				}
				Spacer()
				if let u = Img.glass(name) { Pic(url: u, bg: nil).frame(width: 84, height: 84) }
			}
			.padding(.bottom, 28)
			CardGrid(book: book, drinks: flat)
		}
	}
}

/// /<book>/category/<cat>
struct CategoryView: View {
	let book: Book
	let cat: String
	var body: some View {
		let c = book.store.category(cat)
		let label = Store.prettyCat(cat)
		PageScroll {
			PageHead(crumb: [(T("Home"), .home(book.key)), (T("Ingredients"), .ingredients(book.key)), (label, nil)], title: label,
				sub: c.ings.count == 1 ? T("1 ingredient in this category") : T("{n} ingredients in this category", ["n": c.ings.count]))
			IngGrid(items: c.ings.map { (T($0), Img.ingredient($0), Route.ingredient(book.key, name: $0, with: "")) })
				.padding(.bottom, 30)
			Block {
				SectionHead(title: T("Cocktails using this"), count: c.drinks.count)
				CardGrid(book: book, drinks: c.drinks, ranked: true)
			}
		}
	}
}

/// /<book>/ingredients/
struct IngredientsView: View {
	let book: Book
	var body: some View {
		let s = book.store
		PageScroll {
			PageHead(crumb: [(T("Home"), .home(book.key)), (T("Ingredients"), nil)], title: T("All ingredients")).padding(.bottom, -22)
			FlowLayout {
				ForEach(s.categoryChips(), id: \.0) { nm, c in
					NavigationLink(value: Route.cat(book.key, nm)) { Chip(label: "\(Store.prettyCat(nm)) \(c)", image: s.catImg(nm)) }.buttonStyle(.plain)
				}
			}.padding(.top, 16).padding(.bottom, 30)
			Block {
				SectionHead(title: T("Every ingredient")) { PillLink(label: T("Most-used ingredients"), route: .usage(book.key)) }
				IngGrid(items: s.allIngredients().map { (T($0), Img.ingredient($0), Route.ingredient(book.key, name: $0, with: "")) })
			}
		}
	}
}

/// /<book>/ingredients/<a>[/<b>]
struct IngredientView: View {
	let book: Book
	let name: String
	let with: String
	var body: some View {
		let s = book.store
		let flat = s.drinksWith(name, with)
		let n = flat.count
		let ingt = T(name)
		let cats = Array(Set(s.ingCats(name).map { s.displayCat($0, name) })).sorted()
		let others = otherBooks(book, { $0.ingredientExists(name) && (with.isEmpty || $0.ingredientExists(with)) ? $0.drinksWith(name, with).count : 0 },
			{ .ingredient($0.key, name: name, with: with) })
		PageScroll {
			let crumb: [(String, Route?)] = with.isEmpty
				? [(T("Home"), .home(book.key)), (T("Ingredients"), .ingredients(book.key)), (ingt, nil)]
				: [(T("Home"), .home(book.key)), (T("Ingredients"), .ingredients(book.key)), (ingt, .ingredient(book.key, name: name, with: "")), (T(with), nil)]
			Crumb(items: crumb).padding(.top, 10)
			// the picture (two side by side for a pair)
			HStack(spacing: with.isEmpty ? 0 : -56) {
				Pic(url: Img.ingredient(name), bg: with.isEmpty ? nil : Theme.picBG).frame(width: 168, height: 168).blendMode(with.isEmpty ? .normal : .multiply)
				if !with.isEmpty { Pic(url: Img.ingredient(with)).frame(width: 168, height: 168).blendMode(.multiply) }
			}
			.frame(maxWidth: .infinity)
			Group {
				if with.isEmpty { H1(ingt) } else {
					(Text(ingt) + Text(" + \(T(with))").foregroundColor(Theme.faint)).font(Theme.sans(34, .semibold)).kerning(-0.8).foregroundStyle(Theme.ink)
				}
			}.padding(.top, 14)
			FlowLayout {
				ForEach(cats, id: \.self) { ct in
					NavigationLink(value: Route.cat(book.key, ct)) { Chip(label: Store.prettyCat(ct), image: s.catImg(ct)) }.buttonStyle(.plain)
				}
			}.padding(.top, 16)
			let pairs = s.pairsWith(name)
			if !pairs.isEmpty {
				Eye(T("Pairs most with")).padding(.top, 16).padding(.bottom, 7)
				FlowLayout(spacing: 7, lineSpacing: 7) {
					if !with.isEmpty && !pairs.contains(where: { $0.0 == with }) {
						NavigationLink(value: Route.ingredient(book.key, name: name, with: "")) { PairChip(label: T(with), selected: true) }.buttonStyle(.plain)
					}
					ForEach(pairs, id: \.0) { nm, c in
						if nm == with {
							NavigationLink(value: Route.ingredient(book.key, name: name, with: "")) { PairChip(label: T(nm), selected: true) }.buttonStyle(.plain)
						} else {
							NavigationLink(value: Route.ingredient(book.key, name: name, with: nm)) { PairChip(label: T(nm), count: c) }.buttonStyle(.plain)
						}
					}
				}
			}
			Block(top: 38) {
				let title = with.isEmpty
					? (n == 1 ? T("1 cocktail with {ingredient}", ["ingredient": ingt]) : T("{n} cocktails with {ingredient}", ["n": n, "ingredient": ingt]))
					: (n == 1 ? T("1 cocktail with {ingredient} and {other}", ["ingredient": ingt, "other": T(with)]) : T("{n} cocktails with {ingredient} and {other}", ["n": n, "ingredient": ingt, "other": T(with)]))
				SectionHead(title: title) { OtherBookPills(others: others) }
				CardGrid(book: book, drinks: flat)
			}.padding(.top, 24)
		}
	}
}

/// /<book>/search?q=
struct SearchView: View {
	let book: Book
	@State private var q: String
	@State private var submitted: String
	init(book: Book, initial: String) { self.book = book; _q = State(initialValue: initial); _submitted = State(initialValue: initial) }
	var body: some View {
		let s = book.store
		let res = submitted.isEmpty ? ([], []) : s.search(submitted)
		PageScroll {
			Crumb(items: [(T("Home"), .home(book.key)), (T("Search"), nil)]).padding(.top, 10)
			H1(submitted.isEmpty ? T("Search") : "\(T("Search")) “\(submitted)”")
			SearchBox(q: $q, autofocus: submitted.isEmpty) { submitted = q.trimmingCharacters(in: .whitespaces) }.padding(.top, 18)
			if !submitted.isEmpty {
				let n = res.0.count, ni = res.1.count
				Text((n == 1 ? T("1 cocktail matches") : T("{n} cocktails match", ["n": n])) + (ni > 0 ? " · " + (ni == 1 ? T("1 ingredient") : T("{n} ingredients", ["n": ni])) : ""))
					.font(Theme.mono(13)).foregroundStyle(Theme.soft).padding(.top, 14)
				let gens = s.searchGenerics(submitted)
				if !gens.isEmpty {
					SectionHead(title: T("Spirits & types")).padding(.top, 28)
					IngGrid(items: gens.map { ($0.label, $0.image, $0.route) })
				}
				if ni > 0 {
					SectionHead(title: ni == 1 ? T("1 ingredient") : T("{n} ingredients", ["n": ni])).padding(.top, 28)
					IngGrid(items: res.1.map { (T($0), Img.ingredient($0), Route.ingredient(book.key, name: $0, with: "")) })
				}
				if n > 0 {
					if ni > 0 { SectionHead(title: nCocktails(n)).padding(.top, 28) } else { Spacer().frame(height: 28) }
					CardGrid(book: book, drinks: res.0)
				} else if ni == 0 {
					Text(T("Nothing matched. Try a spirit or ingredient name.")).font(Theme.mono(13.5)).foregroundStyle(Theme.faint).padding(.vertical, 26)
				}
			}
		}
	}
}

/// /<book>/usage: every ingredient ranked by how many cocktails use it
struct UsageView: View {
	let book: Book
	var body: some View {
		let rows = book.store.db.rows("""
			SELECT T1.name, COUNT(DISTINCT T3.drink_id) AS num FROM ingredient AS T1
			LEFT JOIN step AS T4 ON T1.ingredient_id=T4.ingredient_id AND T4.sortorder IS NOT NULL
			LEFT JOIN drink AS T3 ON T4.drink_id=T3.drink_id GROUP BY T1.ingredient_id, T1.name ORDER BY num DESC, T1.name ASC
			""")
		PageScroll {
			PageHead(crumb: [(T("Home"), .home(book.key)), (T("Ingredients"), .ingredients(book.key)), (T("Most-used ingredients"), nil)],
				title: T("Most-used ingredients"), sub: T("Every ingredient ranked by how many cocktails use it"))
			LazyVStack(spacing: 0) {
				ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
					LinkRow(label: T(r.s(0)), image: Img.ingredient(r.s(0)), count: r.i(1), route: .ingredient(book.key, name: r.s(0), with: ""))
				}
			}
		}
	}
}
