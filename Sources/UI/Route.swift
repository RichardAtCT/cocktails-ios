import SwiftUI

/// Every page of the site, as a navigation destination. Mirrors the URL routes of
/// direct_pdt (/cocktails/<book>/<seg2>/<seg3>...).
enum Route: Hashable {
	case home(String)                              // /<book>/
	case recipes(String, sort: String)             // /<book>/recipes/?sort=
	case recipe(String, name: String)              // /<book>/recipes/<name>
	case spirits(String)                           // /<book>/spirits
	case spirit(String, key: String, and: String)  // /<book>/spirit/<a>[/<b>], /mix?a=&b=
	case glasses(String)                           // /<book>/glasses
	case glass(String, name: String)               // /<book>/glass/<name>
	case category(String, cat: String)             // /<book>/category/<cat>
	case ingredients(String)                       // /<book>/ingredients/
	case ingredient(String, name: String, with: String) // /<book>/ingredients/<a>[/<b>]
	case search(String, q: String)                 // /<book>/search?q=
	case usage(String)                             // /<book>/usage

	var bookKey: String {
		switch self {
		case .home(let b), .recipes(let b, _), .recipe(let b, _), .spirits(let b), .spirit(let b, _, _), .glasses(let b),
			 .glass(let b, _), .category(let b, _), .ingredients(let b), .ingredient(let b, _, _), .search(let b, _), .usage(let b):
			return b
		}
	}

	/// pdt_cat_url: a base spirit's category is its spirit page
	static func cat(_ book: String, _ cat: String) -> Route {
		Store.baseSpirits.contains(cat) ? .spirit(book, key: cat, and: "") : .category(book, cat: cat)
	}

	/// false where the site answers 404 (direct_pdt's pdt_404 checks)
	var exists: Bool {
		let s = Book.get(bookKey).store
		switch self {
		case .spirit(_, let k, let a):
			return Store.baseSpirits.contains(k) && (a.isEmpty || a.contains(":") || (Store.baseSpirits.contains(a) && a != k))
		case .glass(_, let n): return !s.drinksInGlass(n).isEmpty
		case .category(_, let c): return !s.category(c).ings.isEmpty
		case .ingredient(_, let n, let w): return s.ingredientExists(n) && (w.isEmpty || (w != n && s.ingredientExists(w)))
		default: return true
		}
	}

	@ViewBuilder var view: some View {
		if exists { page } else { NotFoundView(book: Book.get(bookKey)) }
	}
	@ViewBuilder private var page: some View {
		switch self {
		case .home(let b): HomeView(book: Book.get(b))
		case .recipes(let b, let sort): RecipesView(book: Book.get(b), sort: sort)
		case .recipe(let b, let name): RecipeView(book: Book.get(b), name: name)
		case .spirits(let b): SpiritsView(book: Book.get(b))
		case .spirit(let b, let key, let and): SpiritView(book: Book.get(b), key: key, and: and)
		case .glasses(let b): GlassesView(book: Book.get(b))
		case .glass(let b, let name): GlassView(book: Book.get(b), name: name)
		case .category(let b, let cat): CategoryView(book: Book.get(b), cat: cat)
		case .ingredients(let b): IngredientsView(book: Book.get(b))
		case .ingredient(let b, let name, let with): IngredientView(book: Book.get(b), name: name, with: with)
		case .search(let b, let q): SearchView(book: Book.get(b), initial: q)
		case .usage(let b): UsageView(book: Book.get(b))
		}
	}
}

extension Route {
	/// A site path -> its page: "/cocktails/pdt/recipes/Negroni", "/cocktails/deathco/spirit/gin/rum",
	/// "/cocktails/pdt/mix?a=gin&b=ing:Lime Juice". For deep links and the -open launch argument.
	/// Returns the pages to push (a book's home first), [] for the book chooser.
	static func fromPath(_ raw: String) -> [Route] {
		guard let comps = URLComponents(string: raw.hasPrefix("/") ? raw : "/" + raw) else { return [] }
		var segs = comps.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
		if segs.first == "cocktails" { segs.removeFirst() }
		guard let b = segs.first, Book.all.contains(where: { $0.key == b }) else { return [] }
		let q = { (k: String) in comps.queryItems?.first { $0.name == k }?.value ?? "" }
		let s2 = segs.count > 1 ? segs[1] : "", s3 = segs.count > 2 ? segs[2] : "", s4 = segs.count > 3 ? segs[3] : ""
		let page: Route?
		switch s2 {
		case "": page = nil
		case "recipes": page = s3.isEmpty ? .recipes(b, sort: q("sort").isEmpty ? "pop" : q("sort")) : .recipe(b, name: s3)
		case "spirits": page = .spirits(b)
		case "spirit": page = .spirit(b, key: s3, and: s4.isEmpty ? q("and") : s4)
		case "mix": page = .spirit(b, key: q("a"), and: q("b"))
		case "glasses": page = .glasses(b)
		case "glass": page = .glass(b, name: s3)
		case "category": page = .category(b, cat: s3)
		case "ingredients": page = s3.isEmpty ? .ingredients(b) : .ingredient(b, name: s3, with: s4)
		case "search": page = .search(b, q: q("q"))
		case "usage": page = .usage(b)
		default: page = nil
		}
		return [.home(b)] + (page.map { [$0] } ?? [])
	}
}
