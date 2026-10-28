import SwiftUI

/// The facts panel's small pictures (the DRAW / ICON / row() script on the recipe page):
/// the same SVG shapes, drawn from their path strings so they match the site exactly.
enum FactIcon {
	/// one shape of a picture: an SVG path, its fill and/or stroke (nil stroke colour = currentColor)
	struct Layer {
		var d: String
		var fill: Color? = nil
		var stroke: Color? = nil
		var strokeCurrent = false
		var width: CGFloat = 1
		var opacity: Double = 1
	}
	/// a picture, `w` wide in a 24-high box; `fraction` < 1 cuts it from the left, the rest faint;
	/// `level` fills the `vessel` shape from the bottom (the glasses)
	struct Pic: Identifiable {
		let id = UUID()
		var w: CGFloat
		var layers: [Layer]
		var fraction: Double = 1
		var level: (shape: String, top: CGFloat, bottom: CGFloat, color: Color, f: Double)? = nil
	}

	static func glass(_ f: Double) -> Pic {
		Pic(w: 13, layers: [Layer(d: "M1.5 1.5H11.5L10.6 22.5H2.4Z", strokeCurrent: true, width: 1.3)],
			level: ("M1.5 1.5H11.5L10.6 22.5H2.4Z", 1.5, 22.5, Color(hex: 0xE8B04A), f))
	}
	static func shot(_ f: Double) -> Pic {
		Pic(w: 13, layers: [Layer(d: "M1.5 9H11.5L10 22.5H3Z", strokeCurrent: true, width: 1.3)],
			level: ("M1.5 9H11.5L10 22.5H3Z", 9, 22.5, Color(hex: 0xD9D3C7), f))
	}
	static func flame(_ f: Double) -> Pic {
		Pic(w: 16, layers: [
			Layer(d: "M8 1.5C9.6 5.6 14.5 8.4 14 14.2 13.6 19.6 11 22.5 8 22.5S2.2 19.8 2 14.6C1.8 10.6 4.2 8.6 5.2 5.8 6 8.4 7.1 9.6 8.2 9.3 7.3 6.6 7.2 3.8 8 1.5Z", fill: Color(hex: 0xF08A24)),
			Layer(d: "M8 12.5C9.2 14.4 10.8 15.7 10.5 18.2 10.2 20.6 9.2 21.6 8 21.6S5.6 20.6 5.5 18.6C5.4 16.6 7 15 8 12.5Z", fill: Color(hex: 0xFFD25E)),
		], fraction: f)
	}
	static func cube(_ f: Double) -> Pic {
		let edge = Color(hex: 0x9A9488)
		return Pic(w: 20, layers: [
			Layer(d: "M10 3 18.5 7.2 10 11.4 1.5 7.2Z", fill: .white, stroke: edge),
			Layer(d: "M1.5 7.2 10 11.4V21.5L1.5 17.3Z", fill: Color(hex: 0xEDEAE3), stroke: edge),
			Layer(d: "M18.5 7.2 10 11.4V21.5L18.5 17.3Z", fill: Color(hex: 0xDCD7CC), stroke: edge),
		], fraction: f)
	}
	static func citrus(_ rind: UInt32, _ flesh: UInt32, _ f: Double) -> Pic {
		let pith = Color(hex: 0xFDF8E2)
		return Pic(w: 22, layers: [
			Layer(d: circle(11, 12, 10), fill: Color(hex: rind)),
			Layer(d: circle(11, 12, 8.3), fill: pith),
			Layer(d: circle(11, 12, 7.4), fill: Color(hex: flesh)),
			Layer(d: "M11 4.6V19.4M3.6 12H18.4M5.8 6.8 16.2 17.2M16.2 6.8 5.8 17.2", stroke: pith),
		], fraction: f)
	}
	static func lime(_ f: Double) -> Pic { citrus(0x5E9E2F, 0xB5D86A, f) }
	static func lemon(_ f: Double) -> Pic { citrus(0xF2C318, 0xFBE47A, f) }
	/// sweetness gauge: a honey drop, filled or empty
	static func drop(_ on: Bool) -> Pic {
		let d = "M8 2C8 2 2.5 10 2.5 15A5.5 5.5 0 0 0 13.5 15C13.5 10 8 2 8 2Z"
		return Pic(w: 16, layers: on
			? [Layer(d: d, fill: Color(hex: 0xE3A21A)), Layer(d: ellipse(5.8, 14.5, 1.1, 2.3), fill: Color(hex: 0xF6D27A))]
			: [Layer(d: d, stroke: Color(hex: 0xC9B48E), width: 1.3)])
	}
	/// citrus balance: a level scale (balanced)
	static var scale: Pic {
		let c = Color(hex: 0x7A6E5E)
		return Pic(w: 30, layers: [
			Layer(d: "M15 5V21M10 21.5H20", stroke: c, width: 1.8), Layer(d: "M4 8H26", stroke: c, width: 1.8),
			Layer(d: circle(15, 5, 1.5), fill: c), Layer(d: "M1 12.5a3 2.2 0 0 0 6 0Z", fill: c), Layer(d: "M23 12.5a3 2.2 0 0 0 6 0Z", fill: c),
			Layer(d: "M4 8V12.5M26 8V12.5", stroke: c),
		])
	}
	/// citrus balance: a lollipop (sweet)
	static var lolly: Pic {
		Pic(w: 18, layers: [
			Layer(d: "M9 14.5V23", stroke: Color(hex: 0xC9B48E), width: 1.8), Layer(d: circle(9, 8, 6.5), fill: Color(hex: 0xE8457A)),
			Layer(d: "M9 8m-4 0a4 4 0 1 0 8 0a2.6 2.6 0 1 0 -5.2 0a1.3 1.3 0 1 0 2.6 0", stroke: Color(hex: 0xFFD1DF), width: 1.3),
		])
	}
	private static func circle(_ cx: Double, _ cy: Double, _ r: Double) -> String { ellipse(cx, cy, r, r) }
	private static func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> String {
		"M\(cx - rx) \(cy)a\(rx) \(ry) 0 1 0 \(2 * rx) 0a\(rx) \(ry) 0 1 0 \(-2 * rx) 0Z"
	}

	/// n copies of one picture, the last cut to the fraction left over; more than `max` -> "+N"
	static func row(_ draw: (Double) -> Pic, _ count: Double, max: Int) -> (pics: [Pic], more: Int) {
		let full = Int((count + 1e-9).rounded(.down)), part = count - Double(full)
		var pics = (0..<min(full, max)).map { _ in draw(1) }
		if full < max && part > 0.05 { pics.append(draw(part)) }
		return (pics, full > max ? Int((count - 1e-9).rounded(.up)) - max : 0)
	}
}

/// a row of fact pictures, one text line high (.ficons / .fi: 1.05em)
struct FactIcons: View {
	let pics: [FactIcon.Pic]
	var more = 0
	var height: CGFloat = 16
	var body: some View {
		HStack(alignment: .bottom, spacing: 1) {
			ForEach(pics) { p in FactPicView(pic: p).frame(width: height * p.w / 24, height: height) }
			if more > 0 { Text("+\(more)").font(Theme.mono(11)).foregroundStyle(Theme.soft).padding(.leading, 3) }
		}
	}
}

private struct FactPicView: View {
	let pic: FactIcon.Pic
	@Environment(\.colorScheme) private var scheme
	var body: some View {
		Canvas { ctx, size in
			let s = size.height / 24
			ctx.scaleBy(x: s, y: s)
			let current = Theme.soft
			if let lv = pic.level {
				let shape = SVGPath.parse(lv.shape)
				let y = lv.bottom - (lv.bottom - lv.top) * lv.f
				var c = ctx
				c.clip(to: shape)
				c.fill(Path(CGRect(x: 0, y: y, width: pic.w, height: 24 - y)), with: .color(lv.color))
			}
			func draw(_ c: GraphicsContext) {
				for l in pic.layers {
					let p = SVGPath.parse(l.d)
					if let f = l.fill { c.fill(p, with: .color(f.opacity(l.opacity))) }
					if let st = l.strokeCurrent ? current : l.stroke {
						c.stroke(p, with: .color(st), style: StrokeStyle(lineWidth: l.width, lineCap: .round, lineJoin: .round))
					}
				}
			}
			if pic.fraction >= 1 {
				draw(ctx)
			} else {
				var faint = ctx
				faint.opacity = 0.22
				draw(faint)
				var cut = ctx
				cut.clip(to: Path(CGRect(x: 0, y: 0, width: pic.w * pic.fraction, height: 24)))
				draw(cut)
			}
		}
	}
}

/// A small SVG path-data parser: M L H V C S A Z, absolute and relative (what the icons use).
enum SVGPath {
	static func parse(_ d: String) -> Path {
		var p = Path()
		var toks: [String] = []
		var cur = ""
		for ch in d {
			if ch.isLetter {
				if !cur.isEmpty { toks.append(cur); cur = "" }
				toks.append(String(ch))
			} else if ch == " " || ch == "," {
				if !cur.isEmpty { toks.append(cur); cur = "" }
			} else if ch == "-" && !cur.isEmpty && !cur.hasSuffix("e") {
				toks.append(cur); cur = "-"
			} else if ch == "." && cur.contains(".") {
				toks.append(cur); cur = "."
			} else {
				cur.append(ch)
			}
		}
		if !cur.isEmpty { toks.append(cur) }

		var i = 0, cmd: Character = "M"
		var pt = CGPoint.zero, start = CGPoint.zero, lastCtrl: CGPoint? = nil
		func num() -> CGFloat { defer { i += 1 }; return CGFloat(Double(toks[i]) ?? 0) }
		while i < toks.count {
			if let c = toks[i].first, c.isLetter { cmd = c; i += 1; if c == "Z" || c == "z" { p.closeSubpath(); pt = start; lastCtrl = nil; continue } }
			if i >= toks.count { break }
			let rel = cmd.isLowercase
			let o = rel ? pt : .zero
			switch cmd.uppercased() {
			case "M":
				pt = CGPoint(x: o.x + num(), y: o.y + num()); p.move(to: pt); start = pt; lastCtrl = nil
				cmd = rel ? "l" : "L"   // further pairs are line-tos
			case "L":
				pt = CGPoint(x: o.x + num(), y: o.y + num()); p.addLine(to: pt); lastCtrl = nil
			case "H":
				pt = CGPoint(x: (rel ? pt.x : 0) + num(), y: pt.y); p.addLine(to: pt); lastCtrl = nil
			case "V":
				pt = CGPoint(x: pt.x, y: (rel ? pt.y : 0) + num()); p.addLine(to: pt); lastCtrl = nil
			case "C":
				let c1 = CGPoint(x: o.x + num(), y: o.y + num()), c2 = CGPoint(x: o.x + num(), y: o.y + num())
				pt = CGPoint(x: o.x + num(), y: o.y + num()); p.addCurve(to: pt, control1: c1, control2: c2); lastCtrl = c2
			case "S":
				let c1 = lastCtrl.map { CGPoint(x: 2 * pt.x - $0.x, y: 2 * pt.y - $0.y) } ?? pt
				let c2 = CGPoint(x: o.x + num(), y: o.y + num())
				pt = CGPoint(x: o.x + num(), y: o.y + num()); p.addCurve(to: pt, control1: c1, control2: c2); lastCtrl = c2
			case "A":
				let rx = num(), ry = num(); _ = num()
				let large = num() != 0, sweep = num() != 0
				let to = CGPoint(x: o.x + num(), y: o.y + num())
				arc(&p, from: pt, to: to, rx: rx, ry: ry, large: large, sweep: sweep)
				pt = to; lastCtrl = nil
			default:
				i += 1
			}
		}
		return p
	}

	/// an SVG elliptical arc (no rotation) as a circular arc in y-scaled space
	private static func arc(_ p: inout Path, from a: CGPoint, to b: CGPoint, rx: CGFloat, ry: CGFloat, large: Bool, sweep: Bool) {
		guard rx > 0, ry > 0 else { p.addLine(to: b); return }
		let k = rx / ry                       // stretch y so the ellipse is a circle of radius rx
		let a1 = CGPoint(x: a.x, y: a.y * k), b1 = CGPoint(x: b.x, y: b.y * k)
		let dx = (a1.x - b1.x) / 2, dy = (a1.y - b1.y) / 2
		let d2 = dx * dx + dy * dy
		guard d2 > 0 else { return }
		let r = max(rx, sqrt(d2))
		let coef = (large == sweep ? -1 : 1) * sqrt(max(0, (r * r - d2) / d2))
		let c = CGPoint(x: coef * dy + (a1.x + b1.x) / 2, y: -coef * dx + (a1.y + b1.y) / 2)
		let t1 = atan2(a1.y - c.y, a1.x - c.x), t2 = atan2(b1.y - c.y, b1.x - c.x)
		// sweep=1 is increasing angle, which is clockwise on a y-down screen; SwiftUI's
		// `clockwise` is the y-up sense, so it is the opposite
		p.addArc(center: c, radius: r, startAngle: .radians(Double(t1)), endAngle: .radians(Double(t2)),
			clockwise: !sweep, transform: CGAffineTransform(scaleX: 1, y: 1 / k))
	}
}
