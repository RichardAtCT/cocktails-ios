import Foundation
import SwiftUI

/// Page text, as pdt_t / pdt_ta in lib/direct.tcl: the English phrase is the key, {name}
/// placeholders are filled AFTER translation, and {book} defaults to the current book's title.
/// The translations are the website's own [dt] phrase table (human first, else machine), as
/// scripts/sync_lang.py bundles it: Data/lang/<code>.json, {english: translation}. A phrase
/// missing from the table shows in English, as on the site.
enum Lang {
	static private(set) var table: [String: String] = [:]
	/// the site's language code: en de fr es kr ar zh-hans zh-hant (kr, not ko, as the subdomain)
	static private(set) var code = "en"

	/// the languages, each in its own words (the site's language menu)
	static let all: [(code: String, name: String)] = [
		("en", "English"), ("de", "Deutsch"), ("fr", "Français"), ("es", "Español"), ("kr", "한국어"),
		("ar", "العربية"), ("zh-hans", "简体中文"), ("zh-hant", "繁體中文"),
	]
	static var name: String { all.first { $0.code == code }?.name ?? "English" }
	/// the website in the chosen language (decent_lang_host): decentespresso.com, de.decentespresso.com …
	static var siteHost: URL { URL(string: code == "en" ? "https://decentespresso.com" : "https://\(code).decentespresso.com")! }
	/// for dates and numbers in the chosen language
	static var locale: Locale {
		Locale(identifier: ["kr": "ko", "zh-hans": "zh-Hans", "zh-hant": "zh-Hant"][code] ?? code)
	}

	private static let key = "lang"

	/// at launch: the language chosen in the app, else the device's first one the site has
	/// (debug builds also take the launch argument -lang de)
	static func start() {
		load(UserDefaults.standard.string(forKey: key) ?? deviceLanguage())
	}
	/// the language menu's choice: kept, and the screens are rebuilt (LangState)
	@MainActor static func choose(_ c: String) {
		UserDefaults.standard.set(c, forKey: key)
		load(c)
		Store.clearCaches()
		BarIndex.clearCache()
		LangState.shared.code = code
	}

	private static func load(_ c: String) {
		let c = all.contains { $0.code == c } ? c : "en"
		code = c
		guard c != "en", let d = try? Data(contentsOf: Img.dataDir.appendingPathComponent("lang/\(c).json")),
			  let t = try? JSONDecoder().decode([String: String].self, from: d) else { table = [:]; return }
		table = t
	}
	static func deviceLanguage() -> String {
		for l in Locale.preferredLanguages {
			let id = l.lowercased()
			if id.hasPrefix("zh") {
				// Traditional: zh-Hant, and Taiwan / Hong Kong / Macau without a script
				return id.contains("hant") || id.hasSuffix("-tw") || id.hasSuffix("-hk") || id.hasSuffix("-mo") ? "zh-hant" : "zh-hans"
			}
			let base = String(id.prefix { $0 != "-" && $0 != "_" })
			if base == "ko" { return "kr" }
			if ["en", "de", "fr", "es", "ar"].contains(base) { return base }
		}
		return "en"
	}

	static func t(_ s: String, book: Book? = nil, _ args: [String: Any] = [:]) -> String {
		var r = table[s] ?? s
		var a = args
		if a["book"] == nil, let b = book, s.contains("{book}") { a["book"] = b.title }
		for (k, v) in a { r = r.replacingOccurrences(of: "{\(k)}", with: "\(v)") }
		return r
	}
}

/// the chosen language, for the root view to rebuild every screen when it changes
@MainActor
final class LangState: ObservableObject {
	static let shared = LangState()
	@Published var code = Lang.code
}

/// shorthand used throughout the views
func T(_ s: String, _ args: [String: Any] = [:], book: Book? = nil) -> String { Lang.t(s, book: book, args) }

/// "1 cocktail" / "N cocktails" (pdt_ncocktails)
func nCocktails(_ n: Int) -> String { n == 1 ? T("1 cocktail") : T("{n} cocktails", ["n": n]) }

/// A site phrase with its markup, translated whole (the site's pdt_t phrases carry <b>, <i>,
/// <em> and <a href>, and their translations move them as the language needs), then styled:
/// b/strong bold, i/em italic, a a link (site paths go to decentespresso.com). `style` restyles a
/// tag ("em", or "em.g" for <em class="g">) as the page's CSS does.
func TM(_ s: String, _ args: [String: Any] = [:], book: Book? = nil,
		style: [String: (inout AttributeContainer) -> Void] = [:]) -> AttributedString {
	let src = T(s, args, book: book)
	let tag = try! NSRegularExpression(pattern: "<(/?)(b|strong|i|em|a)((?:\\s+[a-z]+=\"[^\"]*\")*)\\s*>", options: .caseInsensitive)
	var out = AttributedString()
	var open: [(name: String, attrs: AttributeContainer)] = []
	var pos = src.startIndex
	func text(_ t: Substring) {
		var piece = AttributedString(String(t).replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&lt;", with: "<")
			.replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&rarr;", with: "→"))
		for o in open { piece.mergeAttributes(o.attrs) }
		out += piece
	}
	for m in tag.matches(in: src, range: NSRange(src.startIndex..., in: src)) {
		let r = Range(m.range, in: src)!
		text(src[pos..<r.lowerBound])
		pos = r.upperBound
		let closing = !Range(m.range(at: 1), in: src)!.isEmpty
		let name = src[Range(m.range(at: 2), in: src)!].lowercased()
		if closing {
			if let i = open.lastIndex(where: { $0.name == name }) { open.remove(at: i) }
			continue
		}
		let attrText = String(src[Range(m.range(at: 3), in: src)!])
		func attr(_ a: String) -> String? {
			guard let r = attrText.range(of: "\(a)=\"([^\"]*)\"", options: .regularExpression) else { return nil }
			return String(attrText[r].dropFirst(a.count + 2).dropLast())
		}
		var c = AttributeContainer()
		switch name {
		case "b", "strong": c.inlinePresentationIntent = .stronglyEmphasized
		case "i", "em": c.inlinePresentationIntent = .emphasized
		case "a":
			if let h = attr("href") { c.link = URL(string: h, relativeTo: URL(string: "https://decentespresso.com"))?.absoluteURL }
		default: break
		}
		let key = attr("class").map { "\(name).\($0)" } ?? name
		if let f = style[key] ?? style[name] { f(&c) }
		// nested tags combine (bold + italic)
		if let outer = open.last?.attrs.inlinePresentationIntent, let inner = c.inlinePresentationIntent {
			c.inlinePresentationIntent = outer.union(inner)
		}
		open.append((name, c))
	}
	text(src[pos...])
	return out
}
