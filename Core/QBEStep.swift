import Foundation

/** Represents a data manipulation step. Steps usually connect to (at least) one previous step and (sometimes) a next step.
The step transforms a data manipulation on the data produced by the previous step; the results are in turn used by the 
next. Steps work on two datasets: the 'example' data set (which is used to let the user design the data manipulation) and
the 'full' data (which is the full dataset on which the final data operations are run). 

Subclasses of QBEStep implement the data manipulation in the apply function, and should implement the description method
as well as coding methods. The explanation variable contains a user-defined comment to an instance of the step. */
public class QBEStep: NSObject, NSCoding {
	public static let dragType = "nl.pixelspark.Warp.Step"
	
	/** Creates a data object representing the result of an 'example' calculation of the result of this QBEStep. The
	maxInputRows parameter defines the maximum number of input rows a source step should generate. The maxOutputRows
	parameter defines the maximum number of rows a step should strive to produce. */
	public func exampleData(job: QBEJob, maxInputRows: Int, maxOutputRows: Int, callback: (QBEFallible<QBEData>) -> ()) {
		if let p = self.previous {
			p.exampleData(job, maxInputRows: maxInputRows, maxOutputRows: maxOutputRows, callback: {(data) in
				switch data {
					case .Success(let d):
						self.apply(d, job: job, callback: callback)
					
					case .Failure(let error):
						callback(.Failure(error))
				}
			})
		}
		else {
			callback(.Failure(QBEText("This step requires a previous step, but none was found.")))
		}
	}
	
	public func fullData(job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		if let p = self.previous {
			p.fullData(job, callback: {(data) in
				switch data {
					case .Success(let d):
						self.apply(d, job: job, callback: callback)
					
					case .Failure(let error):
						callback(.Failure(error))
				}
			})
		}
		else {
			callback(.Failure(QBEText("This step requires a previous step, but none was found.")))
		}
	}
	
	public var previous: QBEStep? { didSet {
		assert(previous != self, "A step cannot be its own previous step")
		previous?.next = self
	} }
	
	public var alternatives: [QBEStep]?
	public weak var next: QBEStep?
	
	override private init() {
	}
	
	public init(previous: QBEStep?) {
		self.previous = previous
	}
	
	public required init(coder aDecoder: NSCoder) {
		previous = aDecoder.decodeObjectForKey("previousStep") as? QBEStep
		next = aDecoder.decodeObjectForKey("nextStep") as? QBEStep
		alternatives = aDecoder.decodeObjectForKey("alternatives") as? [QBEStep]
	}
	
	public func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(previous, forKey: "previousStep")
		coder.encodeObject(next, forKey: "nextStep")
		coder.encodeObject(alternatives, forKey: "alternatives")
	}
	
	/** Description returns a locale-dependent explanation of the step. It can (should) depend on the specific
	configuration of the step. */
	public final func explain(locale: QBELocale) -> String {
		return sentence(locale).stringValue
	}

	public func sentence(locale: QBELocale) -> QBESentence {
		return QBESentence([])
	}
	
	public func apply(data: QBEData, job: QBEJob, callback: (QBEFallible<QBEData>) -> ()) {
		fatalError("Child class of QBEStep should implement apply()")
	}
	
	/** This method is called right before a document is saved to disk using encodeWithCoder. Steps that reference 
	external files should take the opportunity to create security bookmarks to these files (as required by Apple's
	App Sandbox) and store them. */
	public func willSaveToDocument(atURL: NSURL) {
	}
	
	/** This method is called right after a document has been loaded from disk. */
	public func didLoadFromDocument(atURL: NSURL) {
	}

	/** Returns whether this step can be merged with the specified previous step. */
	public func mergeWith(prior: QBEStep) -> QBEStepMerge {
		return QBEStepMerge.Impossible
	}
}

public enum QBEStepMerge {
	case Impossible
	case Advised(QBEStep)
	case Possible(QBEStep)
	case Cancels
}

/** QBEFileReference is the class to be used by steps that need to reference auxiliary files. It employs Apple's App
Sandbox API to create 'secure bookmarks' to these files, so that they can be referenced when opening the Warp document
again later. Steps should call bookmark() on all their references from the willSavetoDocument method, and call resolve()
on all file references inside didLoadFromDocument. In addition they should store both the 'url' as well as the 'bookmark'
property when serializing a file reference (in encodeWithCoder).

On non-sandbox builds, QBEFileReference will not be able to resolve bookmarks to URLs, and it will return the original URL
(which will allow regular unlimited access). */
public enum QBEFileReference: Equatable {
	case Bookmark(NSData)
	case ResolvedBookmark(NSData, NSURL)
	case URL(NSURL)
	
	public static func create(url: NSURL?, _ bookmark: NSData?) -> QBEFileReference? {
		if bookmark == nil {
			if url != nil {
				return QBEFileReference.URL(url!)
			}
			else {
				return nil
			}
		}
		else {
			if url == nil {
				return QBEFileReference.Bookmark(bookmark!)
			}
			else {
				return QBEFileReference.ResolvedBookmark(bookmark!, url!)
			}
		}
	}
	
	public func bookmark(relativeToDocument: NSURL) -> QBEFileReference? {
		switch self {
		case .URL(let u):
			do {
				let bookmark = try u.bookmarkDataWithOptions(NSURLBookmarkCreationOptions.WithSecurityScope, includingResourceValuesForKeys: nil, relativeToURL: nil)
				do {
					let resolved = try NSURL(byResolvingBookmarkData: bookmark, options: NSURLBookmarkResolutionOptions.WithSecurityScope, relativeToURL: nil, bookmarkDataIsStale: nil)
					return QBEFileReference.ResolvedBookmark(bookmark, resolved)
				}
				catch let error as NSError {
					QBELog("Failed to resolve just-created bookmark: \(error)")
				}
			}
			catch let error as NSError {
				QBELog("Could not create bookmark for url \(u): \(error)")
			}
			return self
			
		case .Bookmark(_):
			return self
			
		case .ResolvedBookmark(_,_):
			return self
		}
	}
	
	public func resolve(relativeToDocument: NSURL) -> QBEFileReference? {
		switch self {
		case .URL(_):
			return self
			
		case .ResolvedBookmark(let b, let oldURL):
			do {
				let u = try NSURL(byResolvingBookmarkData: b, options: NSURLBookmarkResolutionOptions.WithSecurityScope, relativeToURL: nil, bookmarkDataIsStale: nil)
				return QBEFileReference.ResolvedBookmark(b, u)
			}
			catch let error as NSError {
				QBELog("Could not re-resolve bookmark \(b) to \(oldURL) relative to \(relativeToDocument): \(error)")
			}
			
			return self
			
		case .Bookmark(let b):
			do {
				let u = try NSURL(byResolvingBookmarkData: b, options: NSURLBookmarkResolutionOptions.WithSecurityScope, relativeToURL: nil, bookmarkDataIsStale: nil)
				return QBEFileReference.ResolvedBookmark(b, u)
			}
			catch let error as NSError {
				QBELog("Could not resolve secure bookmark \(b): \(error)")
			}
			return self
		}
	}
	
	public var bookmark: NSData? { get {
		switch self {
			case .ResolvedBookmark(let d, _): return d
			case .Bookmark(let d): return d
			default: return nil
		}
	} }
	
	public var url: NSURL? { get {
		switch self {
			case .URL(let u): return u
			case .ResolvedBookmark(_, let u): return u
			default: return nil
		}
	} }
}

public func == (lhs: QBEFileReference, rhs: QBEFileReference) -> Bool {
	if let lu = lhs.url, ru = rhs.url {
		return lu == ru
	}
	else if let lb = lhs.bookmark, rb = rhs.bookmark {
		return lb == rb
	}
	return false
}

/** The transpose step implements a row-column switch. It has no configuration and relies on the QBEData transpose()
implementation to do the actual work. */
public class QBETransposeStep: QBEStep {
	public override func apply(data: QBEData, job: QBEJob? = nil, callback: (QBEFallible<QBEData>) -> ()) {
		callback(.Success(data.transpose()))
	}

	public override func sentence(locale: QBELocale) -> QBESentence {
		return QBESentence([QBESentenceText(QBEText("Switch rows/columns"))])
	}
	
	public override func mergeWith(prior: QBEStep) -> QBEStepMerge {
		if prior is QBETransposeStep {
			return QBEStepMerge.Cancels
		}
		return QBEStepMerge.Impossible
	}
}

/** A sentence is a string of tokens that describe the action performed by a step in natural language, and allow for the
configuration of that step. For example, a step that limits the number of rows in a result set may have a sentence like 
"limit to [x] rows". In this case, the sentence consists of three tokens: a constant text ('limit to'), a configurable
number token ('x') and another constant text ('rows'). */
public class QBESentence {
	public private(set) var tokens: [QBESentenceToken]

	public init(_ tokens: [QBESentenceToken]) {
		self.tokens = tokens
	}

	public static let formatStringTokenPlaceholder = "[#]"

	/** Create a sentence based on a formatting string and a set of tokens. This allows for flexible localization of 
	sentences. The format string may contain instances of '[#]' as placeholders for tokens. This is the preferred way
	of constructing sentences, since it allows for proper localization (word order may be different between languages).*/
	public init(format: String, _ tokens: QBESentenceToken...) {
		self.tokens = []

		var startIndex = format.startIndex
		for token in tokens {
			if let nextToken = format.rangeOfString(QBESentence.formatStringTokenPlaceholder, options: [], range: Range(start: startIndex, end: format.endIndex)) {
				let constantString = format.substringWithRange(Range(start: startIndex, end: nextToken.startIndex))
				self.tokens.append(QBESentenceText(constantString))
				self.tokens.append(token)
				startIndex = nextToken.endIndex
			}
			else {
				fatalError("There are more tokens than there can be placed in the format string '\(format)'")
			}
		}

		if startIndex.distanceTo(format.endIndex) > 0 {
			self.tokens.append(QBESentenceText(format.substringWithRange(Range(start: startIndex, end: format.endIndex))))
		}
	}

	public func append(sentence: QBESentence) {
		self.tokens.appendContentsOf(sentence.tokens)
	}

	public func append(token: QBESentenceToken) {
		self.tokens.append(token)
	}

	public var stringValue: String { get {
		return self.tokens.map({ return $0.label }).joinWithSeparator(" ")
	} }
}

public protocol QBESentenceToken: NSObjectProtocol {
	var label: String { get }
	var isToken: Bool { get }
}

public class QBESentenceList: NSObject, QBESentenceToken {
	public typealias Callback = (String) -> ()
	public typealias ProviderCallback = (QBEFallible<[String]>) -> ()
	public typealias Provider = (ProviderCallback) -> ()
	public private(set) var optionsProvider: Provider
	private(set) var value: String
	public let callback: Callback

	public var label: String { get {
		return value
	} }

	public init(value: String, provider: Provider, callback: Callback) {
		self.optionsProvider = provider
		self.value = value
		self.callback = callback
	}

	public var isToken: Bool { get { return true } }

	public func select(key: String) {
		if key != value {
			callback(key)
		}
	}
}

public class QBESentenceOptions: NSObject, QBESentenceToken {
	public typealias Callback = (String) -> ()
	public private(set) var options: [String: String]
	public private(set) var value: String
	public let callback: Callback

	public var label: String { get {
		return options[value] ?? ""
	} }

	public init(options: [String: String], value: String, callback: Callback) {
		self.options = options
		self.value = value
		self.callback = callback
	}

	public var isToken: Bool { get { return true } }

	public func select(key: String) {
		assert(options[key] != nil, "Selecting an invalid option")
		if key != value {
			callback(key)
		}
	}
}

public class QBESentenceText: NSObject, QBESentenceToken {
	public let label: String

	public init(_ label: String) {
		self.label = label
	}

	public var isToken: Bool { get { return false } }
}

public class QBESentenceTextInput: NSObject, QBESentenceToken {
	public typealias Callback = (String) -> (Bool)
	public let label: String
	public let callback: Callback

	public init(value: String, callback: Callback) {
		self.label = value
		self.callback = callback
	}

	public func change(newValue: String) -> Bool {
		if label != newValue {
			return callback(newValue)
		}
		return true
	}

	public var isToken: Bool { get { return true } }
}

public class QBESentenceFormula: NSObject, QBESentenceToken {
	public typealias Callback = (QBEExpression) -> ()
	public let expression: QBEExpression
	public let locale: QBELocale
	public let callback: Callback

	public init(expression: QBEExpression, locale: QBELocale, callback: Callback) {
		self.expression = expression
		self.locale = locale
		self.callback = callback
	}

	public func change(newValue: QBEExpression) {
		callback(newValue)
	}

	public var label: String {
		get {
			return expression.explain(self.locale, topLevel: true)
		}
	}

	public var isToken: Bool { get { return true } }
}

public class QBESentenceFile: NSObject, QBESentenceToken {
	public typealias Callback = (QBEFileReference) -> ()
	public let file: QBEFileReference?
	public let allowedFileTypes: [String]
	public let callback: Callback
	public let isDirectory: Bool
	public let mustExist: Bool

	public init(directory: QBEFileReference?, callback: Callback) {
		self.allowedFileTypes = []
		self.file = directory
		self.callback = callback
		self.isDirectory = true
		self.mustExist = true
	}

	public init(saveFile file: QBEFileReference?, allowedFileTypes: [String], callback: Callback) {
		self.file = file
		self.callback = callback
		self.allowedFileTypes = allowedFileTypes
		self.isDirectory = false
		self.mustExist = false
	}

	public init(file: QBEFileReference?, allowedFileTypes: [String], callback: Callback) {
		self.file = file
		self.callback = callback
		self.allowedFileTypes = allowedFileTypes
		self.isDirectory = false
		self.mustExist = true
	}

	public func change(newValue: QBEFileReference) {
		callback(newValue)
	}

	public var label: String {
		get {
			return file?.url?.lastPathComponent ?? QBEText("(no file)")
		}
	}

	public var isToken: Bool { get { return true } }
}

/** Component that can write a data set to a file in a particular format. */
public protocol QBEFileWriter: NSObjectProtocol, NSCoding {
	/** A description of the type of file exported by instances of this file writer, e.g. "XML file". */
	static func explain(fileExtension: String, locale: QBELocale) -> String

	/** The UTIs and file extensions supported by this type of file writer. */
	static var fileTypes: Set<String> { get }

	/** Create a file writer with default settings for the given locale. */
	init(locale: QBELocale, title: String?)

	/** Write data to the given URL. The file writer calls back once after success or failure. */
	func writeData(data: QBEData, toFile file: NSURL, locale: QBELocale, job: QBEJob, callback: (QBEFallible<Void>) -> ())

	/** Returns a sentence for configuring this writer */
	func sentence(locale: QBELocale) -> QBESentence?
}