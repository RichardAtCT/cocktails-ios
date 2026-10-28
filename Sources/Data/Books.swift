import Foundation

/// The cocktail books, as `pdt_books` in lib/direct.tcl. Drink ids don't overlap between the
/// books (Death & Co starts at 10001); ingredient ids and names are shared (same bottle = same
/// id = same picture).
struct Book: Hashable, Identifiable {
	let key: String
	let db: String
	let title: String
	let short: String
	let bar: String
	let city: String
	let authors: String
	let year: Int
	let nstated: Int
	var id: String { key }

	static let all: [Book] = [
		Book(key: "pdt", db: "pdt.db", title: "The PDT Cocktail Book", short: "PDT", bar: "Please Don't Tell",
			city: "New York", authors: "Jim Meehan", year: 2011, nstated: 300),
		Book(key: "deathco", db: "deathco.db", title: "Death & Co: Modern Classic Cocktails", short: "Death & Co",
			bar: "Death & Co", city: "New York", authors: "David Kaplan, Nick Fauchald and Alex Day", year: 2014, nstated: 500),
	]
	static func get(_ key: String) -> Book { all.first { $0.key == key } ?? all[0] }

	/// the home page's hero picture (cocktails/img/hero-<book>, else PDT's hero)
	var heroURL: URL? { Img.local("img/hero-\(key).avif") ?? Img.local("img/hero.avif") }
	var store: Store { Store.for(self) }
}
