import Cocoa

internal class QBEChainTabletViewController: QBETabletViewController, QBEChainViewDelegate {
	var chainViewController: QBEChainViewController? = nil { didSet { bind() } }

	override func tabletWasDeselected() {
		self.chainViewController?.selected = false
	}

	override func tabletWasSelected() {
		self.chainViewController?.selected = true
	}

	private func bind() {
		self.chainViewController?.chain = (self.tablet as! QBEChainTablet).chain
		self.chainViewController?.delegate = self
	}

	override func prepareForSegue(segue: NSStoryboardSegue, sender: AnyObject?) {
		if segue.identifier == "chain" {
			self.chainViewController = segue.destinationController as? QBEChainViewController
		}
	}

	override func selectArrow(arrow: QBETabletArrow) {
		if let s = arrow.fromStep {
			self.chainViewController?.currentStep = s
			self.chainViewController?.calculate()
		}
	}

	override func startEditing() {
		self.chainViewController?.startEditing(self)
	}

	/** Chain view delegate implementation */
	func chainViewDidClose(view: QBEChainViewController) -> Bool {
		return self.delegate?.tabletViewDidClose(self) ?? true
	}

	func chainView(view: QBEChainViewController, configureStep step: QBEStep?, delegate: QBESentenceViewDelegate) {
		self.delegate?.tabletView(self, didSelectConfigurable:step, delegate: delegate)
	}

	func chainViewDidChangeChain(view: QBEChainViewController) {
		self.delegate?.tabletViewDidChangeContents(self)
	}
}