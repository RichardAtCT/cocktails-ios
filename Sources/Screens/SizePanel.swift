import SwiftUI

/// The size panel (the recipe page's #bpop): − / + in quarter drinks, a 0–8× slider, and the
/// facts at that size. Tap the number to type how many drinks (5.34 is fine); tap a fact line to
/// type the amount you want (ml of drink, ml of alcohol, shots, g of sugar, sugar cubes) and the
/// whole recipe scales to it.
struct SizePanel: View {
	let stats: Recipe.Stats?
	@Binding var n: Double
	@Environment(\.dismiss) private var dismiss
	/// the line being typed into ("count" for the drink count, else a Recipe.line key)
	@State private var editing: String? = nil
	@State private var typed = ""
	@FocusState private var focus: Bool

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 12) {
				stepButton("−", -0.25, T("Less"))
				Spacer()
				if editing == "count" {
					field(big: true)
				} else {
					Button { begin("count", Recipe.num(n)) } label: {
						HStack(alignment: .firstTextBaseline, spacing: 6) {
							Text(Recipe.num(n)).font(Theme.mono(41.6, .semibold)).foregroundStyle(Theme.ink)
							Text(n == 1 ? T("drink") : T("drinks")).font(Theme.sans(16)).foregroundStyle(Theme.soft)
						}
					}.buttonStyle(.plain)
				}
				Spacer()
				stepButton("+", 0.25, T("More"))
			}
			Slider(value: Binding(get: { min(8, n) }, set: { n = ($0 * 20).rounded() / 20 }), in: 0...8)
				.tint(Theme.acc).padding(.top, 22)
			HStack {
				ForEach(["0", "2×", "4×", "6×", "8×"], id: \.self) { Text($0) }.frame(maxWidth: .infinity)
			}
			.font(Theme.mono(11.2)).foregroundStyle(Theme.faint).padding(.horizontal, -12)
			if let f = stats {
				VStack(spacing: 0) {
					factRow(T("Volume"), FactIcon.row(FactIcon.glass, f.vol * n / 250, max: 3), ["vol"], f)
					factRow(T("Alcohol"), FactIcon.row(FactIcon.shot, f.vod * n / 30, max: 4), ["eth", "vod", "shots"], f)
					if f.sug != nil { factRow(T("Sugar"), FactIcon.row(FactIcon.cube, (f.sug ?? 0) * n / 4, max: 4), ["sug", "cubes"], f) }
				}
				.overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
				.padding(.top, 18)
			}
			Button { commit(); dismiss() } label: {
				Text(T("Done")).font(Theme.sans(16, .semibold)).foregroundStyle(Theme.ink)
					.frame(maxWidth: .infinity).padding(14)
					.background(Theme.line2, in: RoundedRectangle(cornerRadius: 12))
			}.buttonStyle(.plain).padding(.top, 18)
			Spacer(minLength: 0)
		}
		.padding(.horizontal, 24).padding(.top, 24)
		.background(Theme.paper)
		.accessibilityLabel(T("Make:"))
	}

	private func stepButton(_ label: String, _ s: Double, _ name: String) -> some View {
		Button {
			commit()
			n = s > 0 ? ((n * 4 + 1e-9).rounded(.down) / 4 + s) : max(0.25, (n * 4 - 1e-9).rounded(.up) / 4 + s)
			n = min(99, n)
		} label: {
			Text(label).font(Theme.mono(22)).foregroundStyle(Theme.ink).frame(width: 52, height: 52)
				.overlay(Circle().stroke(Theme.line2))
		}.buttonStyle(.plain).accessibilityLabel(name)
	}

	private func factRow(_ label: String, _ icons: (pics: [FactIcon.Pic], more: Int), _ keys: [String], _ f: Recipe.Stats) -> some View {
		HStack(alignment: .center, spacing: 0) {
			FactIcons(pics: icons.pics, more: icons.more).padding(.trailing, 10)
			Text(label).font(Theme.sans(15.2)).foregroundStyle(Theme.soft).padding(.leading, 5)
			Spacer(minLength: 8)
			VStack(alignment: .trailing, spacing: 3) {
				ForEach(Array(keys.enumerated()), id: \.offset) { j, k in
					if editing == k {
						HStack(spacing: 4) {
							field(big: false)
							let unit = Recipe.lineBase(k, f).unit
							if !unit.isEmpty { Text(unit).font(Theme.sans(15.2)) }
						}
					} else {
						Button {
							let (base, _) = Recipe.lineBase(k, f)
							guard base > 0 else { return }
							let cur = base * n
							begin(k, cur < 10 ? Recipe.num(cur) : "\(Int(cur.rounded()))")
						} label: {
							Text(Recipe.line(k, f, n)).font(Theme.sans(15.2, j == 0 ? .semibold : .medium))
								.foregroundStyle(j == 0 ? Theme.ink : Theme.soft).lineLimit(1).minimumScaleFactor(0.8)
								.padding(.horizontal, 4).padding(.vertical, 2)
						}.buttonStyle(.plain)
					}
				}
			}
		}
		.padding(.vertical, 10)
		.overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
	}

	private func field(big: Bool) -> some View {
		TextField("", text: $typed)
			.keyboardType(.decimalPad)
			.font(big ? Theme.mono(32) : Theme.sans(15.2, .semibold))
			.multilineTextAlignment(big ? .center : .trailing)
			.frame(width: big ? 120 : 88)
			.padding(.horizontal, 6).padding(.vertical, 4)
			.overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.acc))
			.focused($focus)
			.onSubmit(commit)
	}

	private func begin(_ key: String, _ value: String) {
		commit()
		editing = key; typed = value; focus = true
	}
	/// the typed number becomes the drink count (or the count that makes that amount)
	private func commit() {
		guard let key = editing else { return }
		editing = nil
		guard let x = Double(typed.replacingOccurrences(of: ",", with: ".")), x.isFinite, x > 0 else { return }
		if key == "count" { n = min(99, x); return }
		if let f = stats { let base = Recipe.lineBase(key, f).base; if base > 0 { n = min(99, x / base) } }
	}
}

/// "See it larger": the cocktail picture over the whole screen; tap or Done to close
struct PhotoView: View {
	let url: URL?
	let name: String
	@Environment(\.dismiss) private var dismiss
	var body: some View {
		ZStack(alignment: .topTrailing) {
			Color.white.ignoresSafeArea()
			Pic(url: url).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
				.accessibilityLabel(name)
			Button { dismiss() } label: {
				Image(systemName: "xmark").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(hex: 0x0A0A0A))
					.frame(width: 44, height: 44).background(Color(hex: 0xE7E7E1), in: Circle())
			}.padding(16).accessibilityLabel(T("Close"))
		}
		.contentShape(Rectangle())
		.onTapGesture { dismiss() }
	}
}
