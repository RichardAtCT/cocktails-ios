import SwiftUI
import UIKit

/// The site's design tokens (pdt_html_page :root), light and dark.
enum Theme {
	static let paper = dyn(0xFFFFFF, 0x0B0B0C)
	static let panel = dyn(0xFAFAF8, 0x141416)
	static let ink = dyn(0x0A0A0A, 0xF2F1EC)
	static let soft = dyn(0x55554E, 0xAFAEA6)
	static let faint = dyn(0x9B9B92, 0x6D6D66)
	static let line = dyn(0xE7E7E1, 0x242428)
	static let line2 = dyn(0xD9D9D2, 0x323238)
	static let acc = dyn(0xFF3B1D, 0xFF5338)
	static let green = Color(hex: 0x1AA35A)
	/// picture backgrounds stay white in dark mode, as on the site (.card .viz)
	static let picBG = Color.white
	/// the book chooser cards' text half: a light grey, so each book reads as its own card
	static let bookCard = dyn(0xF1F1ED, 0x18181B)

	private static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
		Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
	}

	/// Archivo (--sans), a variable font: weight via .weight()
	static func sans(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
		.custom("Archivo", size: size).weight(weight)
	}
	/// IBM Plex Mono (--mono)
	static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
		let name = weight == .semibold || weight == .bold ? "IBMPlexMono-SemiBold" : weight == .medium ? "IBMPlexMono-Medium" : "IBMPlexMono-Regular"
		return .custom(name, size: size).monospacedDigit()
	}
	/// the page gutter (.wrap padding-inline: clamp(16px,4vw,34px))
	static func gutter(_ width: CGFloat) -> CGFloat { min(34, max(16, width * 0.04)) }
}

extension Color {
	init(hex: UInt32) { self.init(UIColor(hex: hex)) }
	init(hexString: String) {
		self.init(hex: UInt32(hexString.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0)
	}
}
extension UIColor {
	convenience init(hex: UInt32) {
		self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
	}
}
