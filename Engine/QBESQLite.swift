import Foundation

internal class QBESQLiteResult: NSObject {
	let resultSet: COpaquePointer
	let db: QBESQLiteDatabase
	
	init(resultSet: COpaquePointer, db: QBESQLiteDatabase) {
		self.resultSet = resultSet
		self.db = db
	}
	
	init?(sql: String, db: QBESQLiteDatabase) {
		self.db = db
		self.resultSet = nil
		super.init()
		println("SQL \(sql)")
		if !self.db.perform([sqlite3_prepare_v2(self.db.db, sql, -1, &resultSet, nil)]) {
			return nil
		}
	}
	
	deinit {
		sqlite3_finalize(resultSet)
	}
	
	var columnCount: Int { get {
		return Int(sqlite3_column_count(resultSet))
	} }
	
	 var columnNames: [QBEColumn] { get {
		let count = sqlite3_column_count(resultSet)
		return (0..<count).map({QBEColumn(String.fromCString(sqlite3_column_name(self.resultSet, $0))!)})
	} }
}

extension QBESQLiteResult: SequenceType {
	typealias Generator = QBESQLiteResultGenerator
	
	func generate() -> Generator {
		return QBESQLiteResultGenerator(self)
	}
}

internal class QBESQLiteResultGenerator: GeneratorType {
	typealias Element = [QBEValue]
	let result: QBESQLiteResult
	var lastStatus: Int32 = SQLITE_OK
	
	init(_ result: QBESQLiteResult) {
		(self.result) = result
	}
	
	func next() -> Element? {
		if lastStatus == SQLITE_DONE {
			return nil
		}
		
		var item: Element? = nil
		
		self.result.db.perform {
			self.lastStatus = sqlite3_step(self.result.resultSet)
			if self.lastStatus == SQLITE_ROW {
				item = self.row
			}
		}
		
		return item
	}
	
	var row: Element? {
		return (0..<result.columnNames.count).map { idx in
			switch sqlite3_column_type(self.result.resultSet, Int32(idx)) {
			case SQLITE_FLOAT:
				return QBEValue(sqlite3_column_double(self.result.resultSet, Int32(idx)))
				
			case SQLITE_NULL:
				return QBEValue.EmptyValue
				
			case SQLITE_INTEGER:
				// Booleans are represented as integers, but boolean columns are declared as BOOL columns
				let intValue = Int(sqlite3_column_int64(self.result.resultSet, Int32(idx)))
				var bool = false
				if let type = String.fromCString(sqlite3_column_decltype(self.result.resultSet, Int32(idx))) {
					if type.hasPrefix("BOOL") {
						return QBEValue(intValue != 0)
					}
					else {
						return QBEValue(intValue)
					}
				}
				return QBEValue.InvalidValue
				
			case SQLITE_TEXT:
				return QBEValue(String.fromCString(UnsafePointer<CChar>(sqlite3_column_text(self.result.resultSet, Int32(idx))))!)
				
			default:
				return QBEValue.InvalidValue
			}
		}
	}
}

internal class QBESQLiteDatabase {
	class var sharedQueue : dispatch_queue_t {
		struct Static {
			static var onceToken : dispatch_once_t = 0
			static var instance : dispatch_queue_t? = nil
		}
		dispatch_once(&Static.onceToken) {
			Static.instance = dispatch_queue_create("QBESQLiteDatabase.Queue", DISPATCH_QUEUE_SERIAL)
		}
		return Static.instance!
	}
	
	let db: COpaquePointer
	
	private var lastError: String {
		 return String.fromCString(sqlite3_errmsg(self.db)) ?? ""
	}
	
	private func perform(ops: [@autoclosure () -> Int32]) -> Bool {
		var ret: Bool = true
		dispatch_sync(QBESQLiteDatabase.sharedQueue) {
			// FIXME: because of rdar://15217242, for op in ops { op() ... } doesn't work
			for idx in 0..<ops.count {
				if ops[idx]() != SQLITE_OK {
					println("SQLite error: \(self.lastError)")
					ret = false
					break
				}
			}
		}
		return ret
	}
	
	private func perform(fn: () -> ()) {
		dispatch_sync(QBESQLiteDatabase.sharedQueue, fn)
	}
	
	init?(path: String, readOnly: Bool = false) {
		let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE)
		self.db = nil
		
		if !perform([sqlite3_open_v2(path, &self.db, flags, nil)]) {
			return nil
		}
	}
	
	deinit {
		perform([sqlite3_close(self.db)])
	}
	
	func query(sql: String) -> QBESQLiteResult? {
		return QBESQLiteResult(sql: sql, db: self)
	}
	
	var tableNames: [String]? { get {
		if let names = query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name ASC") {
			var nameStrings: [String] = []
			for name in names {
				nameStrings.append(name[0].stringValue!)
			}
			return nameStrings
		}
		return nil
	} }
}

class QBESQLiteDialect: QBEStandardSQLDialect {
}

class QBESQLiteData: QBESQLData {
	private let db: QBESQLiteDatabase
	
	private convenience init(db: QBESQLiteDatabase, tableName: String) {
		let dialect = QBESQLiteDialect()
		self.init(db: db, sql: "SELECT * FROM \(dialect.tableIdentifier(tableName))")
	}
	
	private init(db: QBESQLiteDatabase, sql: String) {
		(self.db) = (db)
		super.init(sql: sql, dialect: QBESQLiteDialect())
	}
	
	override var columnNames: [QBEColumn] { get {
		if let result = self.db.query(self.sql) {
			return result.columnNames
		}
		return []
	} }
	
	override func apply(sql: String) -> QBEData {
		return QBESQLiteData(db: self.db, sql: sql)
	}
	
	override var raster: QBEFuture { get {
		return {() -> QBERaster in
			if let result = self.db.query(self.sql) {
				let columnNames = result.columnNames
				var newRaster: [[QBEValue]] = [columnNames.map({QBEValue($0.name)})]
				
				for row in result {
					newRaster.append(row)
				}
				
				return QBERaster(newRaster)
			}
			return QBERaster()
		}
	}}
}

class QBESQLiteSourceStep: QBERasterStep {
	var url: String
	var tableName: String = "" { didSet {
		read()
	} }
	
	let db: QBESQLiteDatabase?
	
	init(url: NSURL) {
		self.url = url.absoluteString ?? ""
		super.init()
		
		if let url = NSURL(string: self.url) {
			self.db = QBESQLiteDatabase(path: url.path!, readOnly: true)
			if let first = self.db?.tableNames?.first {
				self.tableName = first
			}
		}
	}
	
	override func explain(locale: QBELocale) -> String {
		return String(format: NSLocalizedString("Load table %@ from SQLite-database '%@'", comment: ""), self.tableName, url)
	}
	
	private func read() {
		if let db = self.db {
			super.staticFullData = QBESQLiteData(db: db, tableName: self.tableName)
			super.staticExampleData = QBERasterData(raster: super.staticFullData!.random(100).raster())
		}
	}
	
	required init(coder aDecoder: NSCoder) {
		self.url = aDecoder.decodeObjectForKey("url") as? String ?? ""
		if let url = NSURL(string: self.url) {
			self.db = QBESQLiteDatabase(path: url.path!, readOnly: true)
		}
		self.tableName = aDecoder.decodeObjectForKey("tableName") as? String ?? ""
		super.init(coder: aDecoder)
		read()
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		super.encodeWithCoder(coder)
		coder.encodeObject(url, forKey: "url")
		coder.encodeObject(tableName, forKey: "tableName")
	}
}