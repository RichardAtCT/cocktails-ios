import SwiftUI
import UIKit

// MARK: pictures

/// A bundled picture (AVIF), decoded once and cached.
final class PicCache {
	static let shared = NSCache<NSURL, UIImage>()
	static func image(_ url: URL) -> UIImage? {
		if let i = shared.object(forKey: url as NSURL) { return i }
		guard let i = UIImage(contentsOfFile: url.path) else { return nil }
		shared.setObject(i, forKey: url as NSURL)
		return i
	}
}

/// A picture fitted into its frame (object-fit:contain), on white like the site's .viz boxes.
struct Pic: View {
	let url: URL?
	var bg: Color? = Theme.picBG
	var body: some View {
		ZStack {
			if let bg { bg }
			if let url, let img = PicCache.image(url) {
				Image(uiImage: img).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
			}
		}
	}
}

// MARK: page structure

/// .wrap: the page column with the site's side gutters
struct PageScroll<Content: View>: View {
	@ViewBuilder var content: Content
	var body: some View {
		GeometryReader { geo in
			ScrollView {
				VStack(alignment: .leading, spacing: 0) { content }
					.padding(.horizontal, Theme.gutter(geo.size.width))
					.frame(maxWidth: 1180, alignment: .leading)
					.frame(maxWidth: .infinity)
					.padding(.bottom, 40)
			}
			.background(Theme.paper)
		}
	}
}

/// .crumb: Home / Spirits / Gin (mono, faint); the last item is the current page
struct Crumb: View {
	let items: [(String, Route?)]
	var body: some View {
		FlowLayout(spacing: 9, lineSpacing: 4) {
			ForEach(Array(items.enumerated()), id: \.offset) { i, it in
				HStack(spacing: 9) {
					if i > 0 { Text("/").foregroundStyle(Theme.faint) }
					if let r = it.1 {
						NavigationLink(value: r) { Text(it.0).foregroundStyle(Theme.faint) }.buttonStyle(.plain)
					} else {
						Text(it.0).foregroundStyle(Theme.faint)
					}
				}
			}
		}
		.font(Theme.mono(12))
		.padding(.bottom, 14)
	}
}

/// .phead: breadcrumb, big title, optional mono sub line
struct PageHead: View {
	var crumb: [(String, Route?)] = []
	let title: String
	var sub: String? = nil
	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			if !crumb.isEmpty { Crumb(items: crumb) }
			H1(title)
			if let sub { Text(sub).font(Theme.mono(13)).foregroundStyle(Theme.soft).padding(.top, 10) }
		}
		.padding(.top, 10)
		.padding(.bottom, 22)
	}
}

/// .phead h1: clamp(2rem,5vw,3.2rem), tight leading
struct H1: View {
	let text: String
	init(_ t: String) { text = t }
	var body: some View {
		Text(text).font(Theme.sans(34, .semibold)).kerning(-0.8).lineSpacing(-4).foregroundStyle(Theme.ink)
			.fixedSize(horizontal: false, vertical: true)
	}
}

/// section.blk: a block with a top rule
struct Block<Content: View>: View {
	var rule = true
	var top: CGFloat = 38
	@ViewBuilder var content: Content
	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			if rule { Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, -40) }
			content.padding(.top, top)
		}
		.padding(.bottom, 4)
	}
}

/// .sh: section head: title, a hairline to the right, then a count and/or a pill link
struct SectionHead<Trailing: View>: View {
	let title: String
	var count: Int? = nil
	@ViewBuilder var trailing: Trailing
	var body: some View {
		// one line when the title fits beside the link; on a narrow screen the link goes under it
		ViewThatFits(in: .horizontal) {
			HStack(alignment: .firstTextBaseline, spacing: 14) {
				titleText.fixedSize()
				rule
				trailing
			}
			VStack(alignment: .leading, spacing: 10) {
				HStack(alignment: .firstTextBaseline, spacing: 14) {
					titleText.fixedSize(horizontal: false, vertical: true)
					rule
				}
				trailing
			}
		}
		.padding(.bottom, 22)
	}
	private var titleText: some View {
		Text(title).font(Theme.sans(22, .semibold)).kerning(-0.3).foregroundStyle(Theme.ink)
	}
	@ViewBuilder private var rule: some View {
		Rectangle().fill(Theme.line).frame(height: 1).frame(minWidth: 10).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 6 }
		if let count { Text("\(count)").font(Theme.mono(12)).foregroundStyle(Theme.faint) }
	}
}
extension SectionHead where Trailing == EmptyView {
	init(title: String, count: Int? = nil) { self.title = title; self.count = count; trailing = EmptyView() }
}

/// .sh a: the accent pill link at the end of a section head ("All →")
struct PillLink: View {
	let label: String
	let route: Route
	var body: some View {
		NavigationLink(value: route) {
			Text("\(label) →").font(Theme.mono(12)).foregroundStyle(Theme.acc).lineLimit(1)
				.padding(.horizontal, 10).padding(.vertical, 4)
				.overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.line2))
				.fixedSize()
		}.buttonStyle(.plain)
	}
}

/// .eye: small mono upper-case label
struct Eye: View {
	let text: String
	init(_ t: String) { text = t }
	var body: some View {
		Text(text.uppercased()).font(Theme.mono(11.5)).kerning(0.5).foregroundStyle(Theme.faint)
	}
}

// MARK: cards

/// .cards: the recipe card grid (2-up on phones, auto-fill 210px wider)
struct CardGrid: View {
	let book: Book
	let drinks: [DrinkRef]
	var ranked = false
	var body: some View {
		if drinks.isEmpty {
			Text(T("No cocktails found.")).font(Theme.mono(13.5)).foregroundStyle(Theme.faint).padding(.vertical, 26)
		} else {
			LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 400), spacing: 14, alignment: .top)], alignment: .leading, spacing: 14) {
				ForEach(Array(drinks.enumerated()), id: \.element.id) { i, d in
					NavigationLink(value: Route.recipe(book.key, name: d.name)) {
						DrinkCard(card: book.store.card(d), rank: ranked ? i + 1 : nil)
					}.buttonStyle(.plain)
				}
			}
		}
	}
}

/// .card: picture on white, name (with a small #rank), the ingredient line
struct DrinkCard: View {
	let card: Store.Card
	var rank: Int? = nil
	var description: String? = nil
	/// more below the description (a similar cocktail's comparison)
	var extra: AnyView? = nil
	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Pic(url: card.image).frame(height: 104).frame(maxWidth: .infinity).padding(.vertical, 4).background(Theme.picBG)
				.padding(.bottom, 8)
			(rankText + Text(card.name).font(Theme.sans(16.5, .semibold)).foregroundColor(Theme.ink))
				.kerning(-0.15).lineSpacing(-1).fixedSize(horizontal: false, vertical: true)
			Text(description ?? card.ingredients).font(Theme.sans(12.2)).foregroundStyle(Theme.soft).lineSpacing(2)
				.padding(.top, 7).fixedSize(horizontal: false, vertical: true)
			if let extra { extra }
			Spacer(minLength: 0)
		}
		.padding(10)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
		.background(Theme.paper)
		.overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line))
		.contentShape(Rectangle())
	}
	private var rankText: Text {
		guard let rank else { return Text("") }
		return Text("#\(rank) ").font(Theme.mono(10.5, .medium)).foregroundColor(Theme.faint)
	}
}

/// .inggrid / .ingcard: square picture on white, name under a hairline
struct IngGrid: View {
	let items: [(label: String, image: URL?, route: Route)]
	var body: some View {
		LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 200), spacing: 13, alignment: .top)], alignment: .leading, spacing: 13) {
			ForEach(Array(items.enumerated()), id: \.offset) { _, it in
				NavigationLink(value: it.route) {
					VStack(alignment: .leading, spacing: 0) {
						Pic(url: it.image).aspectRatio(1, contentMode: .fit)
						Rectangle().fill(Theme.line).frame(height: 1)
						Text(it.label).font(Theme.sans(12.8, .semibold)).foregroundStyle(Theme.ink).lineSpacing(0)
							.padding(.horizontal, 10).padding(.vertical, 8)
							.fixedSize(horizontal: false, vertical: true)
						Spacer(minLength: 0)
					}
					.frame(maxHeight: .infinity, alignment: .top)
					.background(Theme.panel)
					.overlay(Rectangle().stroke(Theme.line))
				}.buttonStyle(.plain)
			}
		}
	}
}

// MARK: chips and rows

/// .lchip: mono upper-case chip, optional picture, count, selected (×) or dashed reset
struct Chip: View {
	let label: String
	var image: URL? = nil
	var count: Int? = nil
	var selected = false
	var reset = false
	var body: some View {
		HStack(spacing: 0) {
			if let image { Pic(url: image).frame(width: 18, height: 18).clipShape(RoundedRectangle(cornerRadius: 3)).padding(.trailing, 7) }
			Text(label.uppercased()).kerning(0.35)
			if let count { Text("\(count)").foregroundStyle(Theme.faint).padding(.leading, 8) }
			if selected { Text("×").fontWeight(.bold).padding(.leading, 8) }
		}
		.font(Theme.mono(11.5))
		.foregroundStyle(reset ? Theme.faint : selected ? Theme.ink : Theme.soft)
		.padding(.horizontal, 11).padding(.vertical, 6)
		.background(selected ? Theme.line : Color.clear)
		.overlay(Rectangle().stroke(Theme.line2, style: StrokeStyle(lineWidth: 1, dash: reset ? [3, 2] : [])))
	}
}

/// .pairs a: "Pairs most with" chips
struct PairChip: View {
	let label: String
	var count: Int? = nil
	var selected = false
	var body: some View {
		HStack(spacing: 5) {
			Text(label)
			if let count { Text("\(count)").foregroundStyle(Theme.faint) }
			if selected { Text("×") }
		}
		.font(Theme.mono(12.2))
		.foregroundStyle(selected ? Theme.acc : Theme.soft)
		.padding(.horizontal, 11).padding(.vertical, 6)
		.overlay(Rectangle().stroke(selected ? Theme.acc : Theme.line2))
	}
}

/// .srow: one base spirit: bottle, name, count, arrow
struct SpiritRow: View {
	let book: Book
	let key: String
	let count: Int
	var body: some View {
		NavigationLink(value: Route.spirit(book.key, key: key, and: "")) {
			VStack(spacing: 0) {
				Rectangle().fill(Theme.line).frame(height: 1)
				HStack(spacing: 18) {
					HStack(spacing: 11) {
						if let u = book.store.spiritImg(key) {
							Pic(url: u).frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 7))
						} else {
							Circle().fill(Color(hexString: Store.spiritHex(key))).frame(width: 9, height: 9)
						}
						Text(Store.spiritLabel(key)).font(Theme.sans(21.6, .semibold)).kerning(-0.2).foregroundStyle(Theme.ink)
					}
					Spacer()
					Text("\(count)").font(Theme.mono(13.4)).foregroundStyle(Theme.ink)
					Text("→").font(Theme.mono(14)).foregroundStyle(Theme.faint).frame(width: 18, alignment: .trailing)
				}
				.padding(.vertical, 15).padding(.horizontal, 6)
			}
			.contentShape(Rectangle())
		}.buttonStyle(.plain)
	}
}

/// .ll: a link row with a dotted leader to its count
struct LinkRow: View {
	let label: String
	var image: URL? = nil
	var imageSize: CGFloat = 22
	let count: Int
	let route: Route
	var indent: CGFloat = 0
	var sub = false
	var topRule = true
	var body: some View {
		NavigationLink(value: route) {
			VStack(spacing: 0) {
				if topRule && !sub { Rectangle().fill(Theme.line).frame(height: 1) }
				HStack(alignment: .center, spacing: 8) {
					if let image { Pic(url: image).frame(width: imageSize, height: imageSize).clipShape(RoundedRectangle(cornerRadius: imageSize > 30 ? 6 : 5)) }
					Text(label).font(sub ? Theme.sans(14.7, .medium) : Theme.sans(16, .medium)).foregroundStyle(sub ? Theme.soft : Theme.ink)
					Dotted().frame(height: 1).padding(.top, 8)
					Text("\(count)").font(Theme.mono(12.5)).foregroundStyle(Theme.faint)
				}
				.padding(.vertical, sub ? 4 : 11).padding(.leading, 4 + indent).padding(.trailing, 4)
			}
			.contentShape(Rectangle())
		}.buttonStyle(.plain)
	}
}

struct Dotted: View {
	var body: some View {
		GeometryReader { g in
			Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: g.size.width, y: 0)) }
				.stroke(Theme.line2, style: StrokeStyle(lineWidth: 1, dash: [1, 2]))
		}
	}
}

/// .sortpill
struct SortPill: View {
	let label: String
	let on: Bool
	var body: some View {
		Text(label.uppercased()).font(Theme.mono(11.8)).kerning(0.35)
			.foregroundStyle(on ? Theme.ink : Theme.soft)
			.padding(.horizontal, 12).padding(.vertical, 7)
			.background(on ? Theme.line : Color.clear)
			.overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line2))
			.clipShape(RoundedRectangle(cornerRadius: 8))
	}
}

/// "12 more in Death & Co →" pills (pdt_other_books_links)
struct OtherBookPills: View {
	let others: [(book: Book, n: Int, route: Route)]
	var body: some View {
		ForEach(Array(others.enumerated()), id: \.offset) { _, o in
			PillLink(label: T("{n} more in {book}", ["n": o.n, "book": o.book.short]), route: o.route)
		}
	}
}

// MARK: layout

/// Wrapping row layout (flex-wrap), for chips
struct FlowLayout: Layout {
	var spacing: CGFloat = 8
	var lineSpacing: CGFloat = 8
	func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
		let w = proposal.width ?? .infinity
		var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
		for s in subviews {
			let sz = s.sizeThatFits(.unspecified)
			if x > 0 && x + sz.width > w { y += rowH + lineSpacing; x = 0; rowH = 0 }
			x += sz.width + spacing; rowH = max(rowH, sz.height); maxX = max(maxX, x - spacing)
		}
		return CGSize(width: proposal.width ?? maxX, height: y + rowH)
	}
	func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
		var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
		for s in subviews {
			let sz = s.sizeThatFits(.unspecified)
			if x > bounds.minX && x + sz.width > bounds.maxX { y += rowH + lineSpacing; x = bounds.minX; rowH = 0 }
			s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
			x += sz.width + spacing; rowH = max(rowH, sz.height)
		}
	}
}
