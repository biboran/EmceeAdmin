import AppKit

public final class StatusBarController: NSObject, NSMenuDelegate {
    private var item: NSStatusItem?
    
    public var title: String {
        didSet { updateItem() }
    }
    public var image: NSImage? {
        didSet { updateItem() }
    }
    public var willOpenMenu: () -> () = {}
    public var didCloseMenu: () -> () = {}
    public var menuItems: () -> [NSMenuItem] = {[]} {
        didSet { updateMenuItems() }
    }
    
    public init(
        title: String = "",
        image: NSImage? = nil
    ) {
        self.title = title
        self.image = image
    }
    
    public func showStatusBarItem() {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateItem()
    }
    
    public func hideStatusBarItem() {
        item = nil
    }
    
    public func updateMenuItems() {
        item?.menu?.items = menuItems()
    }
    
    public func closeMenu(animated: Bool) {
        if animated {
            currentlyPresentedMenu?.cancelTracking()
        } else {
            currentlyPresentedMenu?.cancelTrackingWithoutAnimation()
        }
        currentlyPresentedMenu = nil
    }
    
    public var isMenuOpen: Bool { currentlyPresentedMenu != nil }
    
    private func updateItem() {
        guard let item = item else { return }
        item.button?.title = title
        item.button?.image = image
        
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        menu.delegate = self
        item.menu = menu
    }
    
    private var currentlyPresentedMenu: NSMenu?
    
    public func menuWillOpen(_ menu: NSMenu) {
        currentlyPresentedMenu = menu
        willOpenMenu()
    }
    
    public func menuDidClose(_ menu: NSMenu) {
        currentlyPresentedMenu = nil
        didCloseMenu()
    }
    
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items = menuItems()
    }
}
