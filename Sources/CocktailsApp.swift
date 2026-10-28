import SwiftUI

@main
struct CocktailsApp: App {
	var body: some Scene {
		WindowGroup {
			RootView()
		}
	}
}

/// /cocktails/: the book chooser, with every page of the site pushed on one stack.
struct RootView: View {
	@State private var path = NavigationPath()
	var body: some View {
		NavigationStack(path: $path) {
			BooksView()
				.navigationDestination(for: Route.self) { r in
					r.view.bookChrome(Book.get(r.bookKey))
				}
		}
		.tint(Theme.acc)
		.environment(\.navPush) { path.append($0) }
		.onAppear {
			// debug / screenshots: launch straight onto a page, e.g. -open /cocktails/pdt/recipes/Negroni
			if let p = UserDefaults.standard.string(forKey: "open") { for r in Route.fromPath(p) { path.append(r) } }
		}
		.onOpenURL { url in
			let r = Route.fromPath(url.path + (url.query.map { "?\($0)" } ?? ""))
			if !r.isEmpty { path = NavigationPath(); for x in r { path.append(x) } }
		}
	}
}

/// The site header for a book's pages: brand in the bar, and the nav links + search
/// (header.site / nav.main) as a strip under it.
struct BookChrome: ViewModifier {
	let book: Book
	func body(content: Content) -> some View {
		content
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .principal) {
					NavigationLink(value: Route.home(book.key)) {
						Text("\(book.short) Cocktails").font(Theme.sans(17, .bold)).kerning(-0.3).foregroundStyle(Theme.ink)
					}.buttonStyle(.plain)
				}
				ToolbarItem(placement: .topBarTrailing) {
					NavigationLink(value: Route.search(book.key, q: "")) {
						Image(systemName: "magnifyingglass").foregroundStyle(Theme.soft)
					}
				}
			}
			.safeAreaInset(edge: .top, spacing: 0) {
				VStack(spacing: 0) {
					ScrollView(.horizontal, showsIndicators: false) {
						HStack(spacing: 18) {
							navLink(T("Cocktails"), .recipes(book.key, sort: "pop"))
							navLink(T("Spirits"), .spirits(book.key))
							navLink(T("Ingredients"), .ingredients(book.key))
							navLink(T("Glasses"), .glasses(book.key))
						}
						.padding(.horizontal, 16).padding(.vertical, 7)
					}
					Rectangle().fill(Theme.line2).frame(height: 1)
				}
				.background(.bar)
			}
	}
	private func navLink(_ label: String, _ r: Route) -> some View {
		NavigationLink(value: r) { Text(label).font(Theme.sans(13.5)).foregroundStyle(Theme.soft) }.buttonStyle(.plain)
	}
}
extension View {
	func bookChrome(_ book: Book) -> some View { modifier(BookChrome(book: book)) }
}
