import Foundation
import SQLite3

/// A read-only SQLite handle on one of the bundled book databases (pdt.db, deathco.db).
/// Mirrors how lib/direct.tcl uses `pdt eval` / `pdt onecolumn`: plain SQL with bound values.
final class SQLiteDB {
	private var db: OpaquePointer?
	private let lock = NSLock()

	init(path: String) {
		if sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
			NSLog("SQLiteDB: cannot open \(path)")
		}
	}
	deinit { sqlite3_close(db) }

	enum Value: Hashable {
		case int(Int64), real(Double), text(String), null
		var string: String {
			switch self {
			case .int(let i): return String(i)
			case .real(let d): return String(d)
			case .text(let s): return s
			case .null: return ""
			}
		}
		var int: Int {
			switch self {
			case .int(let i): return Int(i)
			case .real(let d): return Int(d)
			case .text(let s): return Int(s) ?? 0
			case .null: return 0
			}
		}
		var double: Double? {
			switch self {
			case .int(let i): return Double(i)
			case .real(let d): return d
			case .text(let s): return Double(s)
			case .null: return nil
			}
		}
		var isNull: Bool { if case .null = self { return true }; return false }
	}

	struct Row {
		let cols: [String: Int]
		let vals: [Value]
		subscript(_ i: Int) -> Value { vals[i] }
		subscript(_ name: String) -> Value { cols[name].map { vals[$0] } ?? .null }
		func s(_ i: Int) -> String { vals[i].string }
		func i(_ i: Int) -> Int { vals[i].int }
		func d(_ i: Int) -> Double? { vals[i].double }
	}

	/// Runs a query; args bind to ?1, ?2, ... (Int, Double, String, or nil).
	func rows(_ sql: String, _ args: Any?...) -> [Row] {
		lock.lock(); defer { lock.unlock() }
		var stmt: OpaquePointer?
		guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
			NSLog("SQLiteDB prepare: \(String(cString: sqlite3_errmsg(db))) in \(sql)")
			return []
		}
		defer { sqlite3_finalize(stmt) }
		let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
		for (n, a) in args.enumerated() {
			let k = Int32(n + 1)
			switch a {
			case let v as Int: sqlite3_bind_int64(stmt, k, Int64(v))
			case let v as Double: sqlite3_bind_double(stmt, k, v)
			case let v as String: sqlite3_bind_text(stmt, k, v, -1, transient)
			default: sqlite3_bind_null(stmt, k)
			}
		}
		var cols: [String: Int] = [:]
		let nc = sqlite3_column_count(stmt)
		for c in 0..<nc { cols[String(cString: sqlite3_column_name(stmt, c))] = Int(c) }
		var out: [Row] = []
		while sqlite3_step(stmt) == SQLITE_ROW {
			var vals: [Value] = []
			vals.reserveCapacity(Int(nc))
			for c in 0..<nc {
				switch sqlite3_column_type(stmt, c) {
				case SQLITE_INTEGER: vals.append(.int(sqlite3_column_int64(stmt, c)))
				case SQLITE_FLOAT: vals.append(.real(sqlite3_column_double(stmt, c)))
				case SQLITE_NULL: vals.append(.null)
				default: vals.append(.text(String(cString: sqlite3_column_text(stmt, c))))
				}
			}
			out.append(Row(cols: cols, vals: vals))
		}
		return out
	}

	/// First column of the first row ("" if none), like `pdt onecolumn`.
	func one(_ sql: String, _ args: Any?...) -> SQLiteDB.Value {
		let r = rowsArgs(sql, args)
		return r.first?.vals.first ?? .null
	}
	/// First column of every row.
	func column(_ sql: String, _ args: Any?...) -> [Value] {
		rowsArgs(sql, args).compactMap { $0.vals.first }
	}
	private func rowsArgs(_ sql: String, _ args: [Any?]) -> [Row] {
		// re-dispatch an array of args to the variadic form
		switch args.count {
		case 0: return rows(sql)
		case 1: return rows(sql, args[0])
		case 2: return rows(sql, args[0], args[1])
		case 3: return rows(sql, args[0], args[1], args[2])
		default: return rows(sql, args[0], args[1], args[2], args[3])
		}
	}
}
