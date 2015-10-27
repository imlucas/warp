import Cocoa
import WarpCore

@objc protocol QBEDocumentViewDelegate: NSObjectProtocol {
	func documentView(view: QBEDocumentView, didSelectTablet: QBEChainViewController?)
	func documentView(view: QBEDocumentView, didSelectArrow: QBEArrow?)
	func documentView(view: QBEDocumentView, wantsZoomToView: NSView)
}

class QBETabletArrow: NSObject, QBEArrow {
	private(set) weak var from: QBETablet?
	private(set) weak var to: QBETablet?
	private(set) weak var fromStep: QBEStep?
	
	init(from: QBETablet, to: QBETablet, fromStep: QBEStep) {
		self.from = from
		self.to = to
		self.fromStep = fromStep
	}
	
	var sourceFrame: CGRect { get {
		return from?.frame ?? CGRectZero
	} }
	
	var targetFrame: CGRect { get {
		return to?.frame ?? CGRectZero
	} }
}

internal class QBEDocumentView: NSView, QBEResizableDelegate, QBEFlowchartViewDelegate {
	@IBOutlet weak var delegate: QBEDocumentViewDelegate?
	var flowchartView: QBEFlowchartView!
	private var draggingOver: Bool = false
	
	override init(frame frameRect: NSRect) {
		flowchartView = QBEFlowchartView(frame: frameRect)
		super.init(frame: frameRect)
		flowchartView.frame = self.bounds
		flowchartView.delegate = self
		addSubview(flowchartView)
	}
	
	override func prepareForDragOperation(sender: NSDraggingInfo) -> Bool {
		return true
	}
	
	func removeAllTablets() {
		subviews.forEach { ($0 as? QBEResizableTabletView)?.removeFromSuperview() }
	}
	
	func selectTablet(tablet: QBETablet?, notifyDelegate: Bool = true) {
		if let t = tablet {
			for sv in subviews {
				if let tv = sv as? QBEResizableTabletView {
					if tv.tabletController.chain?.tablet == t {
						selectView(tv, notifyDelegate: notifyDelegate)
						return
					}
				}
			}
		}
		else {
			selectView(nil)
		}
	}
	
	func flowchartView(view: QBEFlowchartView, didSelectArrow: QBEArrow?) {
		selectView(nil)
		delegate?.documentView(self, didSelectArrow: didSelectArrow)
	}
	
	private func selectView(view: QBEResizableTabletView?, notifyDelegate: Bool = true) {
		// Deselect other views
		for sv in subviews {
			if let tv = sv as? QBEResizableTabletView {
				tv.selected = (tv == view)
				if tv == view {
					self.window?.makeFirstResponder(tv.tabletController.view)
					if notifyDelegate {
						delegate?.documentView(self, didSelectTablet: tv.tabletController)
					}
					self.window?.update()
				}
			}
		}
		
		if view == nil {
			if notifyDelegate {
				delegate?.documentView(self, didSelectTablet: nil)
			}
		}
	}
	
	private func zoomToView(view: QBEResizableTabletView) {
		delegate?.documentView(self, wantsZoomToView: view)
	}
	
	func resizableViewWasSelected(view: QBEResizableView) {
		flowchartView.selectedArrow = nil
		selectView(view as? QBEResizableTabletView)
	}
	
	func resizableViewWasDoubleClicked(view: QBEResizableView) {
		zoomToView(view as! QBEResizableTabletView)
	}
	
	func resizableView(view: QBEResizableView, changedFrameTo frame: CGRect) {
		if let tv = view as? QBEResizableTabletView {
			if let tablet = tv.tabletController.chain?.tablet {
				let sizeChanged = tablet.frame == nil || tablet.frame!.size.width != frame.size.width || tablet.frame!.size.height != frame.size.height
				tablet.frame = frame
				tabletsChanged()
				if tv.selected && sizeChanged {
					tv.scrollRectToVisible(tv.bounds)
				}
			}
		}
		setNeedsDisplayInRect(self.bounds)
	}
	
	var boundsOfAllTablets: CGRect? { get {
		// Find out the bounds of all tablets combined
		var allBounds: CGRect? = nil
		for vw in subviews {
			if vw !== flowchartView {
				allBounds = allBounds == nil ? vw.frame : CGRectUnion(allBounds!, vw.frame)
			}
		}
		return allBounds
	} }
	
	func reloadData() {
		tabletsChanged()
	}
	
	func resizeDocument() {
		let parentSize = self.superview?.bounds ?? CGRectMake(0,0,500,500)
		let contentMinSize = boundsOfAllTablets ?? parentSize
		
		// Determine new size of the document
		let margin: CGFloat = 500
		var newBounds = contentMinSize.insetBy(dx: -margin, dy: -margin)
		let offset = CGPointMake(-newBounds.origin.x, -newBounds.origin.y)
		newBounds.offsetInPlace(dx: offset.x, dy: offset.y)
		
		// Translate the 'visible rect' (just like we will translate tablets)
		let newVisible = self.visibleRect.offsetBy(dx: offset.x, dy: offset.y)
		
		// Move all tablets
		for vw in subviews {
			if let tv = vw as? QBEResizableTabletView {
				if let tablet = tv.tabletController.chain?.tablet {
					if let tabletFrame = tablet.frame {
						tablet.frame = tabletFrame.offsetBy(dx: offset.x, dy: offset.y)
						tv.frame = tablet.frame!
					}
				}
			}
		}
		
		// Set new document bounds and scroll to the 'old' location in the new coordinate system
		self.frame = CGRectMake(0, 0, newBounds.size.width, newBounds.size.height)
		self.scrollRectToVisible(newVisible)
	}
	
	// Call whenever tablets are added/removed or resized
	private func tabletsChanged() {
		self.flowchartView.frame = self.bounds
		// Update flowchart
		var arrows: [QBEArrow] = []
		for va in subviews {
			if let sourceChain = (va as? QBEResizableTabletView)?.tabletController.chain {
				for dep in sourceChain.dependencies {
					if let s = sourceChain.tablet, let t = dep.dependsOn.tablet {
						arrows.append(QBETabletArrow(from: s, to: t, fromStep: dep.step))
					}
				}
			}
		}
		flowchartView.arrows = arrows
	}
	
	private var selectedView: QBEResizableTabletView? { get {
		for vw in subviews {
			if let tv = vw as? QBEResizableTabletView {
				if tv.selected {
					return tv
				}
			}
		}
		return nil
	}}
	
	var selectedTablet: QBETablet? { get {
		return selectedView?.tabletController.chain?.tablet
	} }
	
	var selectedTabletController: QBEChainViewController? { get {
		return selectedView?.tabletController
	} }
	
	override func mouseDown(theEvent: NSEvent) {
		selectView(nil)
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	func removeTablet(tablet: QBETablet) {
		for subview in subviews {
			if let rv = subview as? QBEResizableTabletView {
				if let ct = rv.tabletController.chain?.tablet where ct == tablet {
					subview.removeFromSuperview()
				}
			}
		}
		tabletsChanged()
	}
	
	func addTablet(tabletController: QBEChainViewController, animated: Bool = true, completion: (() -> ())? = nil) {
		if let tablet = tabletController.chain?.tablet {
			let resizer = QBEResizableTabletView(frame: tablet.frame!, controller: tabletController)
			resizer.contentView = tabletController.view
			resizer.delegate = self
		
			self.addSubview(resizer, animated: animated, completion: completion)
			tabletsChanged()
		}
	}
	
	/** This view needs to be able to be first responder, so that QBEDocumentViewCOntroller can respond to first 
	responder actions even when there are no children selected. */
	override var acceptsFirstResponder: Bool { get { return true } }
}

private class QBEResizableTabletView: QBEResizableView {
	let tabletController: QBEChainViewController
	
	init(frame: CGRect, controller: QBEChainViewController) {
		tabletController = controller
		super.init(frame: frame)
	}
	
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}

class QBEScrollView: NSScrollView {
	private var oldZoomedRect: NSRect? = nil
	private(set) var magnifiedView: NSView? = nil
	
	func zoomView(view: NSView, completion: (() -> ())? = nil) {
		// First just try to magnify to the tablet
		if self.magnification < 1.0 {
			NSAnimationContext.runAnimationGroup({ (ac) -> Void in
				ac.duration = 0.3
				self.animator().magnifyToFitRect(view.frame)
			}, completionHandler: {
				// If the tablet is too large, we are still zoomed out a bit. Force zoom in by zooming in on a part of the tablet
				if self.magnification < 1.0 {
					NSAnimationContext.runAnimationGroup({ (ac) -> Void in
						ac.duration = 0.3
						let maxSize = self.bounds
						let frame = view.frame
						let zoomedHeight = min(maxSize.size.height, frame.size.height)
						let zoom = CGRectMake(frame.origin.x, frame.origin.y + (frame.size.height - zoomedHeight), min(maxSize.size.width, frame.size.width), zoomedHeight)
						self.animator().magnifyToFitRect(zoom)
					}, completionHandler: completion)
				}
			})
		}
		else {
			self.magnifyView(view, completion: completion)
		}
	}
	
	func magnifyView(view: NSView?, completion: (() -> ())? = nil) {
		let zoom = {() -> () in
			if let zv = view {
				self.magnifiedView = zv
				self.oldZoomedRect = zv.frame
				self.hasHorizontalScroller = false
				self.hasVerticalScroller = false
				
				// Approximate the document visible rectangle at magnification 1.0, to smoothen the animation
				let oldMagnification = self.magnification
				self.magnification = 1.0
				let visibleRect = self.documentVisibleRect
				self.magnification = oldMagnification

				NSAnimationContext.runAnimationGroup({ (ac) -> Void in
					self.animator().magnification = 1.0
					ac.duration = 0.3
					zv.animator().frame = visibleRect
				}) {
					// Final adjustment
					zv.frame = self.documentVisibleRect
					NSAnimationContext.runAnimationGroup({ (ac) -> Void in
						ac.duration = 0.1
						zv.animator().frame = self.documentVisibleRect.inset(-11.0)
					}, completionHandler: completion)
				}
			}
			else {
				self.oldZoomedRect = nil
				self.hasHorizontalScroller = true
				self.hasVerticalScroller = true
				
				if let oldView = self.magnifiedView {
					self.magnifiedView = nil
					NSAnimationContext.runAnimationGroup({ (ac) -> Void in
						ac.duration = 0.3
						oldView.animator().scrollRectToVisible(oldView.bounds)
					}, completionHandler: completion)
				}
				else {
					completion?()
				}
			}
		}
		
		// Un-zoom the old view (if any)
		if let old = self.magnifiedView, oldRect = self.oldZoomedRect {
			old.autoresizingMask = NSAutoresizingMaskOptions.ViewNotSizable
			NSAnimationContext.runAnimationGroup({ (ac) -> Void in
				ac.duration = 0.3
				old.animator().frame = oldRect
			}, completionHandler: zoom)
			
		}
		else {
			zoom()
		}
	}
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	override func scrollWheel(theEvent: NSEvent) {
		if magnifiedView == nil {
			super.scrollWheel(theEvent)
		}
		else {
			self.magnifyView(nil)
		}
	}
}

protocol QBEWorkspaceViewDelegate: NSObjectProtocol {
	func workspaceView(view: QBEWorkspaceView, didReceiveFiles: [String], atLocation: CGPoint)
	func workspaceView(view: QBEWorkspaceView, didReceiveChain: QBEChain, atLocation: CGPoint)
}

class QBEWorkspaceView: QBEScrollView {
	private var draggingOver: Bool = false
	weak var delegate: QBEWorkspaceViewDelegate? = nil
	
	required init?(coder: NSCoder) {
		super.init(coder: coder)
	}
	
	override func awakeFromNib() {
		registerForDraggedTypes([NSFilenamesPboardType, QBEOutletView.dragType])
	}
	
	override func draggingEntered(sender: NSDraggingInfo) -> NSDragOperation {
		let pboard = sender.draggingPasteboard()
		
		if let _: [String] = pboard.propertyListForType(NSFilenamesPboardType) as? [String] {
			draggingOver = true
			setNeedsDisplayInRect(self.bounds)
			return NSDragOperation.Copy
		}
		else if let _ = pboard.dataForType(QBEOutletView.dragType) {
			draggingOver = true
			setNeedsDisplayInRect(self.bounds)
			return NSDragOperation.Link
		}
		return NSDragOperation.None
	}
	
	override func draggingUpdated(sender: NSDraggingInfo) -> NSDragOperation {
		return draggingEntered(sender)
	}
	
	override func draggingExited(sender: NSDraggingInfo?) {
		draggingOver = false
		setNeedsDisplayInRect(self.bounds)
	}
	
	override func draggingEnded(sender: NSDraggingInfo?) {
		draggingOver = false
		setNeedsDisplayInRect(self.bounds)
	}
	
	override func drawRect(dirtyRect: NSRect) {
		if draggingOver {
			NSColor.blueColor().colorWithAlphaComponent(0.15).set()
		}
		else {
			NSColor.clearColor().set()
		}
		NSRectFill(dirtyRect)
	}
	
	override func prepareForDragOperation(sender: NSDraggingInfo) -> Bool {
		return true
	}
	
	override func performDragOperation(draggingInfo: NSDraggingInfo) -> Bool {
		let pboard = draggingInfo.draggingPasteboard()
		let pointInWorkspace = self.convertPoint(draggingInfo.draggingLocation(), fromView: nil)
		let pointInDocument = self.convertPoint(pointInWorkspace, toView: self.documentView as? NSView)
		
		if let _ = pboard.dataForType(QBEOutletView.dragType) {
			if let ov = draggingInfo.draggingSource() as? QBEOutletView {
				if let draggedChain = ov.draggedObject as? QBEChain {
					delegate?.workspaceView(self, didReceiveChain: draggedChain, atLocation: pointInDocument)
					return true
				}
			}
		}
		else if let files: [String] = pboard.propertyListForType(NSFilenamesPboardType) as? [String] {
			delegate?.workspaceView(self, didReceiveFiles: files, atLocation: pointInDocument)
		}
		return true
	}
}