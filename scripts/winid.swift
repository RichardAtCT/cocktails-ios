import CoreGraphics
let name = CommandLine.arguments[1]
let ws = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in ws where ((w["kCGWindowOwnerName"] as? String) ?? "") == name && (w["kCGWindowLayer"] as? Int) == 0 {
	print(w["kCGWindowNumber"]!); break
}
