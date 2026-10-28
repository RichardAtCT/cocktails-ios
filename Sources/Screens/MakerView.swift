import SwiftUI

/// #mk: making the cocktail on the Half Decent Scale. The Connect button until a scale is
/// connected; then the weighing box (the step's picture | the reading, its progress bar, the
/// ingredient, what to do, Prev / Next, the drink's total), the result when done, and the steps,
/// with the current one marked. Wide windows put the steps in a second column, as the site does.
struct MakerView: View {
	@StateObject private var maker: Maker
	@ObservedObject private var scale = Scale.shared
	@Environment(\.dismiss) private var dismiss
	@Environment(\.colorScheme) private var scheme
	/// a phone-width window: a narrower picture column and smaller guide text
	@State private var narrow = true

	init(recipe: Recipe, n: Double) {
		_maker = StateObject(wrappedValue: Maker(recipe: recipe, n: n))
	}

	var body: some View {
		GeometryReader { geo in
			let wide = geo.size.width >= 700
			ScrollView {
				VStack(alignment: .leading, spacing: 18) {
					top
					if wide {
						HStack(alignment: .top, spacing: min(48, max(24, geo.size.width * 0.04))) {
							VStack(alignment: .leading, spacing: 18) { left }.frame(maxWidth: .infinity)
							list.frame(maxWidth: .infinity)
						}
					} else {
						left
						list
					}
				}
				.padding(.horizontal, Theme.gutter(geo.size.width))
				.padding(.top, 12).padding(.bottom, 40)
				.frame(maxWidth: 1180)
				.frame(maxWidth: .infinity)
			}
			.background(Theme.paper)
		}
		.onGeometryChange(for: Bool.self) { $0.size.width < 500 } action: { narrow = $0 }
		.onAppear {
			maker.open()
			#if DEBUG
			// screenshots: -fakescale 1 -maker 1 connects the pretend scale straight away
			if scale.fake && UserDefaults.standard.bool(forKey: "maker") && !scale.connected { scale.connect() }
			#endif
			UIApplication.shared.isIdleTimerDisabled = true   // the screen stays on while pouring
		}
		.onDisappear {
			maker.close()
			UIApplication.shared.isIdleTimerDisabled = false
		}
		.onChange(of: scale.state) { _, s in maker.scaleChanged(s) }
		.navigationBarTitleDisplayMode(.inline)
	}

	/// .mkTop: ← Back to recipe ... the drink's name
	private var top: some View {
		HStack(spacing: 14) {
			Button { dismiss() } label: {
				Text("← " + T("Back to recipe").uppercased()).font(Theme.mono(11.8)).kerning(0.35).foregroundStyle(Theme.soft)
			}.buttonStyle(.plain)
			Spacer(minLength: 8)
			Text(maker.recipe.name).font(Theme.sans(17.6, .bold)).foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.7)
		}
	}

	@ViewBuilder private var left: some View {
		if maker.phase == .connect { connectRow } else { box }
		if !maker.final.isEmpty { finalPanel }
	}

	// MARK: connect

	private var connectRow: some View {
		VStack(alignment: .leading, spacing: 12) {
			HStack(spacing: 14) {
				Button { scale.connect() } label: { Text(T("Connect to scale")) }
					.buttonStyle(MakerButton(kind: .primary))
					.disabled(scale.state == .scanning || scale.state == .connecting)
				switch scale.state {
				case .scanning: Text(T("Scanning…")).font(Theme.mono(12.2)).foregroundStyle(Theme.faint)
				case .connecting: Text(T("Reconnecting…")).font(Theme.mono(12.2)).foregroundStyle(Theme.faint)
				default: EmptyView()
				}
			}
			if case .unavailable(let why) = scale.state {
				Text(why).font(Theme.sans(13.6)).foregroundStyle(Theme.soft)
					.padding(.horizontal, 14).padding(.vertical, 12)
					.frame(maxWidth: .infinity, alignment: .leading)
					.background(Theme.panel, in: RoundedRectangle(cornerRadius: 10))
					.overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.line))
			}
		}
	}

	// MARK: the weighing box

	private var box: some View {
		HStack(alignment: .center, spacing: 16) {
			if let p = maker.picture {
				// the pictures are on white: multiplied into the page in light mode, as the site does
				Pic(url: p, bg: scheme == .light ? Theme.picBG : nil).frame(maxWidth: narrow ? 92 : 150, maxHeight: 260)
					.blendMode(scheme == .light ? .multiply : .normal)
					.clipShape(RoundedRectangle(cornerRadius: scheme == .light ? 0 : 8))
			}
			VStack(spacing: 14) {
				VStack(spacing: 0) {
					HStack(alignment: .firstTextBaseline, spacing: 6) {
						Text(maker.readout).font(Theme.mono(60, .semibold)).kerning(-1).monospacedDigit()
							.foregroundStyle(Theme.ink).lineLimit(1).minimumScaleFactor(0.5)
						Text("g").font(Theme.mono(19)).foregroundStyle(Theme.faint)
					}
					.accessibilityElement(children: .combine)
					progressBar.padding(.top, 18).padding(.bottom, 2)
				}
				if let ing = maker.ingredient {
					Text(ing).font(Theme.sans(20.8, .bold)).foregroundStyle(Theme.soft).multilineTextAlignment(.center)
				}
				guidePanel
				controls
				if let t = maker.total {
					Text(t).font(Theme.mono(12.8)).foregroundStyle(Theme.faint)
				}
			}
			.frame(maxWidth: .infinity)
		}
		.padding(.horizontal, narrow ? 12 : 18).padding(.vertical, 20)
		.overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
	}

	private var progressBar: some View {
		GeometryReader { g in
			ZStack(alignment: .leading) {
				Capsule().fill(Theme.line)
				Capsule().fill(progressColor).frame(width: g.size.width * maker.progress)
					.animation(.easeOut(duration: 0.12), value: maker.progress)
			}
		}
		.frame(height: 12)
		.accessibilityHidden(true)
	}
	private var progressColor: Color {
		switch maker.progressKind {
		case "ok": return Theme.green
		case "under": return Color(hex: 0xE0A32E)
		case "over": return Theme.acc
		default: return Theme.faint
		}
	}

	/// .mkGuide: what to do now, coloured by how it's going; on Done it's the button back
	@ViewBuilder private var guidePanel: some View {
		let (fg, bg): (Color, Color) = {
			switch maker.guideKind {
			case .success: return (Color(hex: 0x148A4E), Theme.green.opacity(0.10))
			case .warn: return (Color(hex: 0x9A6A00), Color(hex: 0xE0A32E).opacity(0.14))
			case .error: return (Theme.acc, Theme.acc.opacity(0.09))
			case .info: return (Theme.ink, .clear)
			}
		}()
		let panel = VStack(spacing: 10) {
			ForEach(Array(maker.guide.enumerated()), id: \.offset) { _, l in Text(l) }
		}
		.font(Theme.sans(narrow ? 18.4 : 22.4, .semibold)).lineSpacing(3).multilineTextAlignment(.center)
		.fixedSize(horizontal: false, vertical: true)
		.foregroundStyle(fg)
		.frame(maxWidth: .infinity, minHeight: 72)
		.padding(12)
		.background(bg, in: RoundedRectangle(cornerRadius: 10))
		if maker.phase == .done {
			Button { dismiss() } label: { panel }.buttonStyle(.plain).accessibilityHint(T("Back to recipe"))
		} else if !maker.guide.isEmpty {
			panel
		}
	}

	@ViewBuilder private var controls: some View {
		HStack(spacing: 10) {
			switch maker.phase {
			case .tare:
				Button { maker.next() } label: { Text(T("Next") + " →") }.buttonStyle(MakerButton(kind: .primary))
			case .step:
				Button { maker.prev() } label: { Text("← " + T("Prev")) }.buttonStyle(MakerButton(kind: .ghost))
				Button { maker.next() } label: { Text(T("Next") + " →") }.buttonStyle(MakerButton(kind: .go))
					.keyboardShortcut(.return, modifiers: [])
			default: EmptyView()
			}
		}
	}

	// MARK: done

	/// .mkFinal: target vs what went in, then the facts as it was made
	private var finalPanel: some View {
		VStack(alignment: .leading, spacing: 9) {
			ForEach(maker.final) { finalRow($0) }
			if !maker.facts.isEmpty {
				Text(T("As you made it").uppercased()).font(Theme.mono(11.5)).kerning(0.7).foregroundStyle(Theme.faint)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.top, 12)
					.overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
					.padding(.top, 10)
				ForEach(maker.facts) { finalRow($0) }
			}
		}
		.padding(.horizontal, 18).padding(.vertical, 16)
		.overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line))
	}
	private func finalRow(_ r: Maker.FinalRow) -> some View {
		HStack(alignment: .firstTextBaseline) {
			Text(r.label).font(Theme.sans(15.4)).foregroundStyle(Theme.ink)
			Spacer(minLength: 10)
			Text(r.value).font(Theme.mono(15.4, .semibold)).multilineTextAlignment(.trailing)
				.foregroundStyle(r.ok == true ? Color(hex: 0x148A4E) : r.ok == false ? Theme.acc : Theme.ink)
		}
	}

	// MARK: the steps

	/// .mkList: the recipe's rows (the serve row at its place); the current one marked, done ones faded
	private var list: some View {
		let r = maker.recipe
		return VStack(spacing: 0) {
			ForEach(0...r.rows.count, id: \.self) { i in
				let st = maker.state(ofRow: i)
				Group {
					if i == r.serveAt { serveRow(r, i) }
					else { stepRow(r.rows[i < r.serveAt ? i : i - 1], i) }
				}
				.background(st == .current ? Theme.ink.opacity(0.04) : .clear)
				.opacity(st == .done ? 0.45 : 1)
				.overlay(alignment: .bottom) { if i < r.rows.count { Rectangle().fill(Theme.line).frame(height: 1) } }
			}
		}
		.overlay(Rectangle().stroke(Theme.line))
	}
	private func ix(_ i: Int) -> some View {
		Text("\(i + 1)").font(Theme.mono(11.5)).foregroundStyle(maker.state(ofRow: i) == .current ? Theme.acc : Theme.faint)
			.frame(width: 20, alignment: .leading)
	}
	private func thumb(_ url: URL?, _ i: Int) -> some View {
		Pic(url: url).frame(width: 40, height: 40)
			.overlay {
				if maker.state(ofRow: i) == .current { RoundedRectangle(cornerRadius: 8).stroke(Theme.line2).padding(-3) }
			}
	}
	private func stepRow(_ row: Recipe.Row, _ i: Int) -> some View {
		HStack(alignment: .center, spacing: 10) {
			ix(i)
			thumb(Img.ingredient(row.ingredient), i)
			VStack(alignment: .leading, spacing: 2) {
				Text(row.label).font(Theme.sans(16, .semibold)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
				HStack(spacing: 8) {
					if !row.cat.isEmpty {
						Text(Store.prettyCat(row.cat).uppercased()).font(Theme.mono(11.5, .semibold)).kerning(0.25).foregroundStyle(Theme.soft)
					}
					Text(row.mixLabel.uppercased()).font(Theme.mono(11.5)).kerning(0.45).foregroundStyle(Theme.faint)
				}.lineLimit(1).minimumScaleFactor(0.8)
			}
			Spacer(minLength: 4)
			RowAmount(row: row, n: maker.n)
		}
		.padding(.vertical, 13).padding(.horizontal, 16)
	}
	private func serveRow(_ r: Recipe, _ i: Int) -> some View {
		var g = r.glass.replacingOccurrences(of: "\\s*glass$", with: "", options: [.regularExpression, .caseInsensitive])
		g = g.isEmpty ? T("Glass") : T(g.capitalized(firstOnly: true))
		return HStack(alignment: .center, spacing: 10) {
			ix(i)
			thumb(Img.glass(r.glass), i)
			VStack(alignment: .leading, spacing: 6) {
				Text(g.uppercased()).font(Theme.mono(11.5, .semibold)).kerning(0.25).foregroundStyle(Theme.soft)
				Text(T("Glass").uppercased()).font(Theme.mono(11.5)).kerning(0.45).foregroundStyle(Theme.faint)
			}.frame(width: 96, alignment: .leading)
			Text(r.method).font(Theme.sans(15.2, .semibold)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
			Spacer(minLength: 0)
		}
		.padding(.vertical, 13).padding(.horizontal, 16)
	}
}

/// .mkBtn: grey, the ghost one (Prev) in the quieter text colour
struct MakerButton: ButtonStyle {
	enum Kind { case primary, go, ghost }
	let kind: Kind
	@Environment(\.isEnabled) private var enabled
	func makeBody(configuration: Configuration) -> some View {
		configuration.label
			.font(Theme.sans(14.7, .semibold)).lineLimit(1).fixedSize()
			.foregroundStyle(kind == .ghost ? Theme.soft : Theme.ink)
			.padding(.horizontal, 20).padding(.vertical, 12)
			.background(Theme.line2.opacity(configuration.isPressed ? 0.7 : 1), in: RoundedRectangle(cornerRadius: 10))
			.opacity(enabled ? 1 : 0.5)
	}
}
