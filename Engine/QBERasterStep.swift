import Foundation

class QBERasterStep: QBEStep {
	var staticExampleData: QBERasterData?
	var staticFullData: QBEData?
	
	init() {
		super.init(previous: nil)
	}
	
	init(raster: QBERaster) {
		super.init(previous: nil)
		self.staticExampleData = QBERasterData()
		self.staticExampleData?.setRaster(raster)
		self.staticFullData = staticExampleData
	}
	
	required init(coder aDecoder: NSCoder) {
		staticExampleData = aDecoder.decodeObjectForKey("staticData") as? QBERasterData
		super.init(coder: aDecoder)
	}
	
	override func encodeWithCoder(coder: NSCoder) {
		coder.encodeObject(staticExampleData, forKey: "staticData")
		super.encodeWithCoder(coder)
	}
	
	override var fullData: QBEData? { get { return staticFullData }}
	
	override var exampleData: QBEData? { get { return staticExampleData }}
}