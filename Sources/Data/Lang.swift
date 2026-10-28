import Foundation

/// Page text, as pdt_t / pdt_ta in lib/direct.tcl: the English phrase is the key, {name}
/// placeholders are filled AFTER translation, and {book} defaults to the current book's title.
/// Translations (the site's [dt] phrase table) come in milestone 5; until then English.
enum Lang {
	static var table: [String: String] = [:]

	static func t(_ s: String, book: Book? = nil, _ args: [String: Any] = [:]) -> String {
		var r = table[s] ?? s
		var a = args
		if a["book"] == nil, let b = book, s.contains("{book}") { a["book"] = b.title }
		for (k, v) in a { r = r.replacingOccurrences(of: "{\(k)}", with: "\(v)") }
		return r
	}
}

/// shorthand used throughout the views
func T(_ s: String, _ args: [String: Any] = [:], book: Book? = nil) -> String { Lang.t(s, book: book, args) }

/// "1 cocktail" / "N cocktails" (pdt_ncocktails)
func nCocktails(_ n: Int) -> String { n == 1 ? T("1 cocktail") : T("{n} cocktails", ["n": n]) }
