import SwiftUI

/// /cocktails/ (direct_cocktails_home): "Choose a cocktail book" and one card per book.
struct BooksView: View {
	var body: some View {
		PageScroll {
			VStack(alignment: .leading, spacing: 0) {
				H1(T("Choose a cocktail book")).padding(.top, 18)
				Text(TM("Recipes from <b><i>The PDT Cocktail Book</i></b> and <b><i>Death & Co: Modern Classic Cocktails</i></b>. Every ingredient weighed to the gram, every step described. Ready to make on our <a href=\"/scale\">Half Decent Scale</a>."))
					.font(Theme.sans(15.2)).foregroundStyle(Theme.soft).lineSpacing(3).padding(.top, 12)
			}
			.padding(.bottom, 26)
			LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 26)], spacing: 26) {
				ForEach(Book.all) { BookCard(book: $0) }
			}
		}
		.navigationTitle("Decent Cocktails")
		.navigationBarTitleDisplayMode(.inline)
		.toolbar { ToolbarItem(placement: .topBarTrailing) { LanguageMenu() } }
		.safeAreaInset(edge: .top, spacing: 0) { SiteNav(book: nil) }
	}
}

struct BookCard: View {
	let book: Book
	/// the book's three pictures: Death & Co's picks (dark drinks), else the 3 most popular
	private var shown: [DrinkRef] {
		let s = book.store
		if book.key == "deathco" {
			let picks = ["Negroni", "Get Lucky", "Black Market Brandy"].compactMap { nm -> DrinkRef? in
				let v = s.db.one("SELECT drink_id FROM drink WHERE name=?1", nm)
				return v.isNull ? nil : DrinkRef(id: v.int, name: nm)
			}
			if !picks.isEmpty { return picks }
		}
		return s.byPopularity(limit: 3)
	}
	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(alignment: .bottom, spacing: 8) {
				ForEach(shown) { d in
					NavigationLink(value: Route.recipe(book.key, name: d.name)) {
						Pic(url: book.store.cocktailImg(d.name)).frame(height: 150)
					}.buttonStyle(.plain)
				}
			}
			.padding(EdgeInsets(top: 18, leading: 18, bottom: 14, trailing: 18))
			.frame(maxWidth: .infinity, minHeight: 190)
			.background(Theme.picBG)
			Rectangle().fill(Theme.line).frame(height: 1)
			NavigationLink(value: Route.home(book.key)) {
				VStack(alignment: .leading, spacing: 6) {
					Eye("\(book.authors) · \(book.year)")
					Text(book.title).font(Theme.sans(21, .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
					Text(nCocktails(book.nstated)).font(Theme.mono(13.4)).foregroundStyle(Theme.ink)
					Text("\(T("Browse the recipes")) →").font(Theme.mono(12.5)).foregroundStyle(Theme.acc).padding(.top, 8)
				}
				.padding(EdgeInsets(top: 18, leading: 20, bottom: 20, trailing: 20))
				.frame(maxWidth: .infinity, alignment: .leading)
				// the text half in light grey, so each book reads as its own card
				.background(Theme.bookCard)
				.contentShape(Rectangle())
			}.buttonStyle(.plain)
		}
		.overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line2))
		.clipShape(RoundedRectangle(cornerRadius: 14))
	}
}

/// /<book>/ (direct_pdt HOME)
struct HomeView: View {
	let book: Book
	@State private var q = ""
	@State private var mixA = ""
	@State private var mixB = ""
	@State private var openCats: Set<String> = []
	@State private var openIngs: Set<String> = []
	@Environment(\.navPush) private var push

	var body: some View {
		let s = book.store
		PageScroll {
			// hero
			VStack(alignment: .leading, spacing: 0) {
				// Home (the book chooser) / PDT
				Crumb(items: [(T("Home"), .home(book.key))]).padding(.top, 10)
				// h1: the <em> words in the accent colour, the scale in green (not italic)
				Text(TM("{n} <em>cocktails</em> using a <em class=\"g\">scale</em>", ["n": book.nstated], style: [
					"em": { $0.inlinePresentationIntent = nil; $0.foregroundColor = Theme.acc },
					"em.g": { $0.inlinePresentationIntent = nil; $0.foregroundColor = Theme.green },
				]))
					.font(Theme.sans(40, .semibold)).kerning(-1.2).lineSpacing(-6).foregroundStyle(Theme.ink)
					.padding(.top, 16)
				lede.font(Theme.sans(16)).foregroundStyle(Theme.soft).lineSpacing(4).padding(.top, 26)
				SearchBox(q: $q) { push(.search(book.key, q: q)) }.padding(.top, 28)
				Pic(url: book.heroURL, bg: nil).aspectRatio(1, contentMode: .fit)
					.clipShape(RoundedRectangle(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
					.padding(.top, 24).padding(.bottom, 30)
			}
			// 01 By base spirit
			Block {
				SectionHead(title: T("By base spirit")) { PillLink(label: T("All"), route: .spirits(book.key)) }
				VStack(spacing: 0) { ForEach(s.spiritCounts(), id: \.0) { SpiritRow(book: book, key: $0.0, count: $0.1) } }
			}
			// 02 Base spirit + ...?
			Block {
				SectionHead(title: "\(T("Base spirit +")) …?")
				MixBox(book: book, a: $mixA, b: $mixB)
			}
			// spirit pairs + ingredient types
			Block {
				Eye(T("By spirit pairs")).padding(.bottom, 10)
				VStack(spacing: 0) {
					ForEach(s.spiritPairs(), id: \.key) { g in
						LinkRow(label: Store.spiritLabel(g.key), image: s.spiritImg(g.key), count: g.count, route: .spirit(book.key, key: g.key, and: ""))
						ForEach(g.pairs, id: \.0) { p in
							LinkRow(label: Store.spiritLabel(p.0), image: s.spiritImg(p.0), count: p.1, route: .spirit(book.key, key: g.key, and: p.0), indent: 14, sub: true)
						}
					}
				}
				Eye(T("By ingredient type")).padding(.top, 34).padding(.bottom, 10)
				Drill(book: book, open: $openCats, openIngs: $openIngs)
			}
			// 03 Most popular
			Block {
				SectionHead(title: T("Most popular cocktails")) { PillLink(label: T("Browse all {n}", ["n": book.nstated]), route: .recipes(book.key, sort: "pop")) }
				CardGrid(book: book, drinks: s.byPopularity(limit: 12))
			}
		}
		.onAppear { if mixA.isEmpty { mixA = s.spiritCounts().first?.0 ?? "gin" } }
	}

	private var lede: Text {
		if book.key == "pdt" {
			return Text(TM("Recipes from the <b><i>Please Don't Tell</i></b> (New York) bar book. Every ingredient weighed, every step described."))
		}
		return Text(TM("Recipes from <b><i>{book}</i></b>. Every ingredient weighed, every step described.", ["book": book.title]))
	}
}

/// .heroSearch: the search field with its mono SEARCH → button
struct SearchBox: View {
	@Binding var q: String
	var autofocus = false
	let go: () -> Void
	@FocusState private var focused: Bool
	var body: some View {
		HStack(spacing: 0) {
			TextField(T("Negroni, mezcal, lime..."), text: $q)
				.font(Theme.sans(17)).foregroundStyle(Theme.ink).padding(.vertical, 11)
				.textInputAutocapitalization(.never).autocorrectionDisabled().submitLabel(.search)
				.focused($focused).onSubmit(go)
			Button(action: go) {
				Text("\(T("Search").uppercased()) →").font(Theme.mono(13)).kerning(0.5).foregroundStyle(Theme.acc)
					.padding(.horizontal, 15).padding(.vertical, 9)
					.overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2))
			}.buttonStyle(.plain).padding(.leading, 8)
		}
		.padding(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 5))
		.overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
		.frame(maxWidth: 480)
		.onAppear { if autofocus { focused = true } }
	}
}

/// .mix: Spirit [select] + With [select] -> the spirit / mix page
struct MixBox: View {
	let book: Book
	@Binding var a: String
	@Binding var b: String
	@Environment(\.navPush) private var push
	var body: some View {
		let data = book.store.mixData()
		let rows = data[a] ?? []
		HStack(alignment: .center, spacing: 16) {
			VStack(alignment: .leading, spacing: 3) {
				Text(T("Spirit").uppercased()).font(Theme.mono(11.2)).kerning(0.6).foregroundStyle(Theme.faint)
				Menu {
					ForEach(book.store.spiritCounts(), id: \.0) { k, _ in
						Button(Store.spiritLabel(k)) { a = k; b = "" }
					}
				} label: { menuLabel(Store.spiritLabel(a)) }
			}
			Text("+").font(Theme.mono(16.8)).foregroundStyle(Theme.faint)
			VStack(alignment: .leading, spacing: 3) {
				Text(T("With").uppercased()).font(Theme.mono(11.2)).kerning(0.6).foregroundStyle(Theme.faint)
				Menu {
					Button(T("anything")) { b = ""; push(.spirit(book.key, key: a, and: "")) }
					ForEach([("sp", T("Base spirit")), ("st", T("Style")), ("fl", T("Flavour"))], id: \.0) { g, glabel in
						let opts = rows.filter { $0.group == g }
						if !opts.isEmpty {
							Section(glabel) {
								ForEach(opts, id: \.value) { o in
									Button("\(o.label) (\(o.count))") { b = o.value; push(.spirit(book.key, key: a, and: o.value)) }
								}
							}
						}
					}
				} label: { menuLabel(b.isEmpty ? T("anything") : Store.secondLabel(b)) }
			}
		}
		.padding(.horizontal, 18).padding(.vertical, 10)
		.frame(maxWidth: 560, alignment: .leading)
		.overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
	}
	private func menuLabel(_ s: String) -> some View {
		HStack {
			Text(s).font(Theme.sans(15.7)).foregroundStyle(Theme.ink)
			Spacer()
			Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.ink)
		}
		.padding(.vertical, 8)
		.frame(maxWidth: .infinity)
	}
}

/// "By ingredient type": category -> ingredient -> base spirits, each a tap-to-open row
struct Drill: View {
	let book: Book
	@Binding var open: Set<String>
	@Binding var openIngs: Set<String>
	var body: some View {
		let s = book.store
		VStack(alignment: .leading, spacing: 0) {
			ForEach(s.drill(), id: \.cat) { c in
				head(c.name, c.n, s.catImg(c.cat), open.contains(c.cat), level: 0) { toggle(&open, c.cat) }
				if open.contains(c.cat) {
					ForEach(c.ings, id: \.name) { ing in
						let k = "\(c.cat)\u{1}\(ing.name)"
						head(T(ing.name), ing.count, Img.ingredient(ing.name), openIngs.contains(k), level: 1) { toggle(&openIngs, k) }
						if openIngs.contains(k) {
							ForEach(ing.spirits, id: \.key) { sp in
								LinkRow(label: Store.spiritLabel(sp.key), image: s.spiritImg(sp.key), count: sp.count,
									route: .spirit(book.key, key: sp.key, and: "ing:\(ing.name)"), indent: 40, sub: true)
							}
						}
					}
				}
			}
		}
	}
	private func toggle(_ set: inout Set<String>, _ k: String) { if set.contains(k) { set.remove(k) } else { set.insert(k) } }
	private func head(_ label: String, _ count: Int, _ img: URL?, _ isOpen: Bool, level: Int, _ tap: @escaping () -> Void) -> some View {
		Button(action: tap) {
			VStack(spacing: 0) {
				if level == 0 { Rectangle().fill(Theme.line).frame(height: 1) }
				HStack(spacing: 8) {
					Image(systemName: "chevron.right").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.faint)
						.rotationEffect(.degrees(isOpen ? 90 : 0))
					if let img { Pic(url: img).frame(width: 22, height: 22).clipShape(RoundedRectangle(cornerRadius: 5)) }
					Text(label).font(level == 0 ? Theme.sans(16, .medium) : Theme.sans(14.7, .medium)).foregroundStyle(level == 0 ? Theme.ink : Theme.soft)
					Spacer()
					Text("\(count)").font(Theme.mono(12.5)).foregroundStyle(Theme.faint)
				}
				.padding(.vertical, level == 0 ? 11 : 6).padding(.leading, 4 + CGFloat(level) * 18).padding(.trailing, 4)
			}
			.contentShape(Rectangle())
		}.buttonStyle(.plain)
	}
}

// MARK: programmatic navigation

private struct NavPushKey: EnvironmentKey { static let defaultValue: (Route) -> Void = { _ in } }
private struct NavRootKey: EnvironmentKey { static let defaultValue: () -> Void = {} }
extension EnvironmentValues {
	/// back to the book chooser (the stack's root): the crumbs' "Home"
	var navRoot: () -> Void {
		get { self[NavRootKey.self] }
		set { self[NavRootKey.self] = newValue }
	}
	/// push a page from code (a search submit, a menu choice)
	var navPush: (Route) -> Void {
		get { self[NavPushKey.self] }
		set { self[NavPushKey.self] = newValue }
	}
}
