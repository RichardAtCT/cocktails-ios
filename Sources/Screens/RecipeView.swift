import SwiftUI

/// /<book>/recipes/<name>: the phone layout of the recipe page (pdt_mobile.css <= 699px):
/// title + description with the photo floated right, the ingredient strip, the numbered
/// steps with the serve row, the facts, and the similar cocktails.
struct RecipeView: View {
	let book: Book
	let name: String
	/// the batch size: every amount, the facts and the photo follow it (window.pdtBatch)
	/// (the debug launch argument -drinks 2 starts at that size, for screenshots)
	@State private var n: Double = UserDefaults.standard.double(forKey: "drinks") > 0 ? UserDefaults.standard.double(forKey: "drinks") : 1
	@State private var sizeOpen = false
	@State private var photoOpen = false

	var body: some View {
		if let r = book.store.recipe(name) {
			content(r)
		} else {
			NotFoundView(book: book)
		}
	}

	@ViewBuilder private func content(_ r: Recipe) -> some View {
		PageScroll {
			let sp = book.store.drinkSpirits(r.id).first
			Crumb(items: [(T("Home"), .home(book.key)),
				sp.map { (Store.spiritLabel($0), Route.spirit(book.key, key: $0, and: "")) } ?? (T("All recipes"), .recipes(book.key, sort: "pop")),
				(r.name, nil)]).padding(.top, 10)
			HStack(alignment: .top, spacing: 16) {
				VStack(alignment: .leading, spacing: 0) {
					H1(r.name)
					if let d = r.description {
						Text(d).font(Theme.sans(15.2)).foregroundStyle(Theme.soft).lineSpacing(3).padding(.top, 12)
					}
				}
				if r.image != nil {
					Button { photoOpen = true } label: { photos(r) }.buttonStyle(.plain)
						.accessibilityLabel(T("See it larger"))
				}
			}
			ForEach(Array(r.alsoIn.enumerated()), id: \.offset) { _, o in
				NavigationLink(value: Route.recipe(o.book.key, name: o.name)) {
					(Text(T("Also in ")) + Text(o.book.title).italic() + Text(o.same ? T(", with the same recipe") : T(", with a different recipe")) + Text(" →"))
						.font(Theme.sans(14.4)).foregroundStyle(Theme.ink).underline(color: Theme.line2).multilineTextAlignment(.leading)
				}.buttonStyle(.plain).padding(.top, 10)
			}
			// ingredient strip: one picture per ingredient, edge to edge, scaled to fit one line
			if !r.strip.isEmpty {
				HStack(alignment: .bottom, spacing: 0) {
					ForEach(r.strip, id: \.self) { ing in
						NavigationLink(value: Route.ingredient(book.key, name: ing, with: "")) {
							Pic(url: Img.ingredient(ing)).aspectRatio(1, contentMode: .fit).frame(maxHeight: 100)
						}.buttonStyle(.plain)
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(.top, 16).padding(.bottom, 6)
			}
			batch.frame(maxWidth: .infinity, alignment: .trailing).padding(.top, 18)
			spec(r).padding(.top, 10)
			if n > 1, let w = r.stats?.water, w > 0 {
				Text(T("Pre-batching {n} drinks? Add {w} g of water to stand in for the ice dilution, and chill it well.",
					["n": Recipe.num(n), "w": Int((w * n).rounded())]))
					.font(Theme.sans(13.8)).foregroundStyle(Theme.soft).lineSpacing(3)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.horizontal, 14).padding(.vertical, 10)
					.background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
					.overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
					.padding(.top, 14)
			}
			scaleCTA.padding(.top, 14)
			facts(r).padding(.top, 22)
			if !r.similar.isEmpty {
				Block(top: 30) {
					SectionHead(title: T("Similar cocktails"))
					ScrollView(.horizontal, showsIndicators: false) {
						LazyHStack(alignment: .top, spacing: 16) {
							ForEach(r.similar, id: \.self) { s in
								NavigationLink(value: Route.recipe(book.key, name: s.drink.name)) {
									SimilarCard(card: book.store.card(s.drink), s: s)
								}.buttonStyle(.plain).frame(width: 280)
							}
						}
					}
				}.padding(.top, 30)
			}
		}
		.sheet(isPresented: $sizeOpen) { SizePanel(stats: r.stats, n: $n).presentationDetents([.medium, .large]) }
		.fullScreenCover(isPresented: $photoOpen) { PhotoView(url: r.image, name: r.name) }
	}

	/// the cocktail picture once per drink: 2.5 drinks = 2 glasses and a faded third; 8 at most, then "+N"
	@ViewBuilder private func photos(_ r: Recipe) -> some View {
		let k = n > 1 ? min(8, Int((n - 1e-9).rounded(.up))) : 1
		if k < 2 {
			Pic(url: r.image).frame(width: 130, height: 150)
		} else {
			let cols = k <= 3 ? k : (k <= 4 ? 2 : (k <= 6 ? 3 : 4))
			LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: cols), spacing: 6) {
				ForEach(0..<k, id: \.self) { i in
					Pic(url: r.image).aspectRatio(1, contentMode: .fit)
						.opacity(i == k - 1 && n < 8 && n.truncatingRemainder(dividingBy: 1) > 1e-9 ? 0.35 : 1)
				}
			}
			.frame(width: 150)
			.overlay(alignment: .bottomTrailing) {
				if n > 8 {
					Text("+\(Int((n - 8 - 1e-9).rounded(.up)))").font(Theme.mono(12.8, .semibold)).foregroundStyle(Theme.ink)
						.padding(.horizontal, 9).padding(.vertical, 3).background(Theme.line2, in: Capsule()).padding(8)
				}
			}
		}
	}

	/// .batch: − [1 DRINK] +, the middle opens the size panel
	private var batch: some View {
		HStack(spacing: 6) {
			Button { n = Recipe.step(n, -1) } label: { Text("−").font(Theme.mono(16)).frame(width: 34, height: 30) }
				.disabled(n <= 0.25).accessibilityLabel(T("Fewer drinks"))
			Button { sizeOpen = true } label: {
				HStack(alignment: .firstTextBaseline, spacing: 5) {
					Text(Recipe.num(n)).font(Theme.mono(14.4)).foregroundStyle(Theme.ink).frame(minWidth: 18)
					Text((n == 1 ? T("drink") : T("drinks")).uppercased()).font(Theme.mono(11.5)).kerning(0.45).foregroundStyle(Theme.faint)
				}.padding(.horizontal, 12).frame(height: 30)
			}.accessibilityLabel(T("Adjust the size"))
			Button { n = Recipe.step(n, 1) } label: { Text("+").font(Theme.mono(16)).frame(width: 34, height: 30) }
				.disabled(n >= 99).accessibilityLabel(T("More drinks"))
		}
		.buttonStyle(BatchButton())
	}

	/// .spec: the numbered rows, the serve row at its place
	private func spec(_ r: Recipe) -> some View {
		VStack(spacing: 0) {
			ForEach(Array(r.rows.enumerated()), id: \.offset) { i, row in
				if i == r.serveAt { serveRow(r, last: false) }
				ingRow(row, last: i == r.rows.count - 1)
			}
			if r.serveAt >= r.rows.count { serveRow(r, last: true) }
		}
		.overlay(Rectangle().stroke(Theme.line))
	}

	private func ingRow(_ row: Recipe.Row, last: Bool) -> some View {
		HStack(alignment: .center, spacing: 10) {
			Text("\(row.n)").font(Theme.mono(11.5)).foregroundStyle(Theme.faint).frame(width: 20, alignment: .leading)
			NavigationLink(value: Route.ingredient(book.key, name: row.ingredient, with: "")) {
				Pic(url: Img.ingredient(row.ingredient)).frame(width: 40, height: 40)
			}.buttonStyle(.plain)
			VStack(alignment: .leading, spacing: 2) {
				NavigationLink(value: Route.ingredient(book.key, name: row.ingredient, with: "")) {
					Text(row.label).font(Theme.sans(16, .semibold)).foregroundStyle(Theme.ink).multilineTextAlignment(.leading)
						.fixedSize(horizontal: false, vertical: true)
				}.buttonStyle(.plain)
				HStack(alignment: .firstTextBaseline, spacing: 8) {
					if !row.cat.isEmpty {
						NavigationLink(value: Route.cat(book.key, row.cat)) {
							Text(Store.prettyCat(row.cat).uppercased()).font(Theme.mono(11.5, .semibold)).kerning(0.25).foregroundStyle(Theme.soft)
						}.buttonStyle(.plain)
					}
					Text(row.mixLabel.uppercased()).font(Theme.mono(11.5)).kerning(0.45).foregroundStyle(Theme.faint)
				}
				.lineLimit(1).minimumScaleFactor(0.8)
			}
			Spacer(minLength: 4)
			amount(row)
		}
		.padding(.vertical, 15).padding(.horizontal, 16)
		.overlay(alignment: .bottom) { if !last { Rectangle().fill(Theme.line).frame(height: 1) } }
	}

	/// the amount at the batch size (pdtAmt): grams, else a counted amount, else "to taste"; the book's amount under it
	@ViewBuilder private func amount(_ row: Recipe.Row) -> some View {
		VStack(alignment: .trailing, spacing: 1) {
			if let g = row.grams {
				if g.hasPrefix("~") { gramsText("~" + Recipe.num((Double(row.mg) / 1000 * n).rounded())) }
				else { gramsText(String(format: "%.1f", Double(row.mg) / 1000 * n)) }
			} else if let c = row.count {
				Text(Recipe.scaleQ(c, n)).font(Theme.mono(17, .semibold)).foregroundStyle(Theme.acc)
			} else if row.toTaste {
				Text(T("to taste")).font(Theme.mono(15, .semibold)).foregroundStyle(Theme.faint)
			}
			if let oz = row.oz { Text(Recipe.scaleQ(oz, n)).font(Theme.mono(11.8)).foregroundStyle(Theme.faint) }
		}
	}
	/// "28.4g" with the decimals and the g at half size, the number in the accent colour
	private func gramsText(_ g: String) -> Text {
		let parts = g.split(separator: ".", maxSplits: 1).map(String.init)
		var t = Text(parts[0]).font(Theme.mono(17, .semibold)).foregroundColor(Theme.acc)
		if parts.count > 1 { t = t + Text(".\(parts[1])").font(Theme.mono(9.5, .semibold)).foregroundColor(Theme.acc) }
		return t + Text("g").font(Theme.mono(9.5, .semibold)).foregroundColor(Theme.ink)
	}

	private func serveRow(_ r: Recipe, last: Bool) -> some View {
		var g = r.glass.replacingOccurrences(of: "\\s*glass$", with: "", options: [.regularExpression, .caseInsensitive])
		g = g.isEmpty ? T("Glass") : T(g.capitalized(firstOnly: true))
		return HStack(alignment: .center, spacing: 10) {
			Text("\(r.serveNumber)").font(Theme.mono(11.5)).foregroundStyle(Theme.faint).frame(width: 20, alignment: .leading)
			NavigationLink(value: Route.glass(book.key, name: r.glass)) {
				Pic(url: Img.glass(r.glass)).frame(width: 40, height: 40)
			}.buttonStyle(.plain)
			VStack(alignment: .leading, spacing: 6) {
				Text(g.uppercased()).font(Theme.mono(11.5, .semibold)).kerning(0.25).foregroundStyle(Theme.soft)
				Text(T("Glass").uppercased()).font(Theme.mono(11.5)).kerning(0.45).foregroundStyle(Theme.faint)
			}
			.frame(width: 96, alignment: .leading)
			Text(r.method).font(Theme.sans(16, .semibold)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
			Spacer(minLength: 0)
		}
		.padding(.vertical, 15).padding(.horizontal, 16)
		.overlay(alignment: .bottom) { if !last { Rectangle().fill(Theme.line).frame(height: 1) } }
	}

	/// .facts: pictures | label | values, for the batch size; then the book citation. Tapping it opens
	/// the size panel (it rescales these numbers)
	@ViewBuilder private func facts(_ r: Recipe) -> some View {
		let rows = r.facts(n)
		if !rows.isEmpty || r.cite != nil {
			VStack(alignment: .leading, spacing: 0) {
				ForEach(Array(rows.enumerated()), id: \.offset) { i, fr in
					HStack(alignment: .center, spacing: 12) {
						FactIcons(pics: fr.icons, more: fr.more).frame(width: 86, alignment: .leading)
						Text(fr.label).font(Theme.sans(15.2)).foregroundStyle(Theme.soft)
						Spacer(minLength: 8)
						VStack(alignment: .trailing, spacing: 2) {
							ForEach(Array(fr.lines.enumerated()), id: \.offset) { j, v in
								Text(v).font(Theme.sans(15.2, j == 0 ? .semibold : .medium)).foregroundStyle(j == 0 ? Theme.ink : Theme.soft)
							}
						}.multilineTextAlignment(.trailing)
					}
					.padding(.vertical, 9)
					.overlay(alignment: .bottom) { if i < rows.count - 1 || r.cite != nil { Rectangle().fill(Theme.line).frame(height: 1) } }
				}
				if let c = r.cite {
					HStack(alignment: .top, spacing: 10) {
						Image(systemName: "book").foregroundStyle(Color(hex: 0x7A5530))
						Text(c).font(Theme.sans(15.2)).foregroundStyle(Theme.soft)
					}.padding(.vertical, 8)
				}
			}
			.padding(.horizontal, 16).padding(.vertical, 4)
			.overlay(Rectangle().stroke(Theme.line))
			.frame(maxWidth: 520, alignment: .leading)
			.contentShape(Rectangle())
			.onTapGesture { if r.stats != nil { sizeOpen = true } }
		}
	}

	/// .scaleCta: the scale picture and "Make this cocktail with the Half Decent Scale →"
	/// (opens the scale maker, milestone 4)
	private var scaleCTA: some View {
		HStack(spacing: 10) {
			Pic(url: Img.local("img/scale-cta.avif"), bg: nil).frame(width: 50, height: 32)
			Text("\(T("Make this cocktail with the Half Decent Scale")) →").font(Theme.sans(13.8, .medium)).foregroundStyle(Theme.soft)
		}
		.padding(.horizontal, 16).padding(.vertical, 5)
		.overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2))
	}
}

/// pdt_404: "Page not found"
struct NotFoundView: View {
	let book: Book
	var body: some View {
		PageScroll {
			PageHead(crumb: [(T("Home"), .home(book.key)), (T("Not found"), nil)], title: T("Page not found"),
				sub: T("There is no cocktail page at this address."))
		}
	}
}

/// a similar cocktail: its card, its description, then the taste note and how it differs
/// (inside the card, as .cndiff / the shared-ingredients lines)
struct SimilarCard: View {
	let card: Store.Card
	let s: Recipe.Similar
	var body: some View {
		DrinkCard(card: card, description: s.description, extra: AnyView(extra))
	}
	private var extra: some View {
		VStack(alignment: .leading, spacing: 8) {
			Rectangle().fill(Theme.line).frame(height: 1).padding(.bottom, 2)
			if let t = s.taste { Text(t).font(Theme.sans(13.6)).foregroundStyle(Theme.ink).lineSpacing(3) }
			if s.same != nil || s.different != nil {
				VStack(alignment: .leading, spacing: 4) {
					if let x = s.same { bullet(T("Same"), x) }
					if let x = s.different { bullet(T("Different"), x) }
				}.padding(.leading, 4)
			}
			if let x = s.shared { (Text("\(T("Shared ingredients")): ").foregroundColor(Theme.faint) + Text(x).foregroundColor(Theme.soft)).font(Theme.sans(12.2)) }
			if !s.differs.isEmpty { (Text("\(T("Differs")): ").foregroundColor(Theme.faint) + Text(s.differs.joined(separator: ", ")).foregroundColor(Theme.soft)).font(Theme.sans(12.2)) }
		}
		.lineSpacing(2).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
	}
	private func bullet(_ k: String, _ v: String) -> some View {
		HStack(alignment: .firstTextBaseline, spacing: 7) {
			Text("•").foregroundStyle(Theme.faint)
			(Text("\(k): ").foregroundColor(Theme.faint) + Text(v).foregroundColor(Theme.soft))
		}.font(Theme.sans(12.2))
	}
}

/// the .batch buttons: hairline box, mono, dim when disabled
struct BatchButton: ButtonStyle {
	@Environment(\.isEnabled) private var enabled
	func makeBody(configuration: Configuration) -> some View {
		configuration.label.foregroundStyle(Theme.soft)
			.overlay(RoundedRectangle(cornerRadius: 8).stroke(configuration.isPressed ? Theme.ink : Theme.line2))
			.opacity(enabled ? 1 : 0.3)
			.contentShape(Rectangle())
	}
}
