import AppKit
import SentinelCore

/// The menus at the top of the screen.
///
/// Network Sentinel is an `LSUIElement` app whose only SwiftUI scene is the menu
/// bar icon, so SwiftUI writes no menus of its own: this file builds
/// `NSApp.mainMenu` with AppKit. The app switches to `.regular` while a window is
/// open (`WindowCoordinator.showDockIcon`), and these are the menus it shows.
///
/// Every title comes from `T()`, so 界面 → 语言 changes the menus at once.
/// `install` runs at launch, on every visit to `.regular` and on a language
/// change: AppKit writes its default menu back while the app activates, and the
/// app's own menu has to be in place after that.
@MainActor
final class MainMenu: NSObject {
    /// The one menu of the app, kept for the selectors of its items.
    static let shared = MainMenu()

    /// The windows 「设置…」 opens, owned by `AppState`.
    ///
    /// Weak: the app state owns the coordinator, and the menu lives as long as
    /// the app.
    weak var windows: WindowCoordinator?

    /// Builds every menu again and hands it to `NSApp`.
    ///
    /// The whole menu is rebuilt rather than retitled, so a language change can
    /// never leave one item behind in the old language.
    func install() {
        let windowMenu = makeWindowMenu()
        let helpMenu = makeHelpMenu()

        let mainMenu = NSMenu()
        mainMenu.addItem(submenuItem(title: T(.menuApplication), submenu: makeAppMenu()))
        mainMenu.addItem(submenuItem(title: T(.menuEdit), submenu: makeEditMenu()))
        mainMenu.addItem(submenuItem(title: T(.menuWindow), submenu: windowMenu))
        mainMenu.addItem(submenuItem(title: T(.menuHelp), submenu: helpMenu))

        NSApp.mainMenu = mainMenu
        // The system adds the list of windows to `windowsMenu` and the search
        // field to `helpMenu`, which is why both are handed over separately.
        NSApp.windowsMenu = windowMenu
        NSApp.helpMenu = helpMenu
    }

    // MARK: - Menus

    /// Network Sentinel: 关于, 设置…, 隐藏, 退出.
    private func makeAppMenu() -> NSMenu {
        let menu = NSMenu(title: T(.menuApplication))
        menu.addItem(item(
            title: T(.menuAbout),
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            target: NSApp
        ))
        menu.addItem(.separator())
        menu.addItem(item(
            title: T(.menuSettings),
            action: #selector(openSettings(_:)),
            keyEquivalent: ",",
            target: self
        ))
        menu.addItem(.separator())
        menu.addItem(item(
            title: T(.menuHide),
            action: #selector(NSApplication.hide(_:)),
            keyEquivalent: "h",
            target: NSApp
        ))
        menu.addItem(item(
            title: T(.menuHideOthers),
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h",
            modifiers: [.command, .option],
            target: NSApp
        ))
        menu.addItem(item(
            title: T(.menuShowAll),
            action: #selector(NSApplication.unhideAllApplications(_:)),
            target: NSApp
        ))
        menu.addItem(.separator())
        menu.addItem(item(
            title: T(.menuQuit),
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q",
            target: NSApp
        ))
        return menu
    }

    /// 编辑: the standard text actions, so the fields of the app keep cut, copy
    /// and paste. `nil` targets send them down the responder chain to the field
    /// editor of the focused text field.
    private func makeEditMenu() -> NSMenu {
        let menu = NSMenu(title: T(.menuEdit))
        // `undo:` and `redo:` have no Swift declaration, so the selector is
        // written out; the four text actions below use theirs.
        menu.addItem(item(title: T(.menuUndo), action: Selector(("undo:")), keyEquivalent: "z"))
        menu.addItem(item(
            title: T(.menuRedo),
            action: Selector(("redo:")),
            keyEquivalent: "z",
            modifiers: [.command, .shift]
        ))
        menu.addItem(.separator())
        menu.addItem(item(title: T(.menuCut), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(item(title: T(.menuCopy), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(item(title: T(.menuPaste), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(item(
            title: T(.menuSelectAll),
            action: #selector(NSText.selectAll(_:)),
            keyEquivalent: "a"
        ))
        return menu
    }

    /// 窗口: the standard window actions and the window list AppKit appends.
    private func makeWindowMenu() -> NSMenu {
        let menu = NSMenu(title: T(.menuWindow))
        menu.addItem(item(
            title: T(.menuMinimize),
            action: #selector(NSWindow.performMiniaturize(_:)),
            keyEquivalent: "m"
        ))
        menu.addItem(item(title: T(.menuZoom), action: #selector(NSWindow.performZoom(_:))))
        menu.addItem(item(
            title: T(.menuCloseWindow),
            action: #selector(NSWindow.performClose(_:)),
            keyEquivalent: "w"
        ))
        menu.addItem(.separator())
        menu.addItem(item(
            title: T(.menuBringAllToFront),
            action: #selector(NSApplication.arrangeInFront(_:)),
            target: NSApp
        ))
        return menu
    }

    /// 帮助: the one link to the GitHub repository.
    private func makeHelpMenu() -> NSMenu {
        let menu = NSMenu(title: T(.menuHelp))
        menu.addItem(item(
            title: T(.menuGitHub),
            action: #selector(openRepository(_:)),
            target: self
        ))
        return menu
    }

    // MARK: - Actions

    /// 「设置…」: shows the 主窗口 on 设置.
    @objc private func openSettings(_ sender: Any?) {
        windows?.showMainWindow(selecting: .settings)
    }

    /// The same address as the GitHub row of the sidebar.
    @objc private func openRepository(_ sender: Any?) {
        NSWorkspace.shared.open(AppInfo.repositoryURL)
    }

    // MARK: - Pieces

    /// One menu item.
    ///
    /// A `nil` target leaves the action to the responder chain, which is what
    /// the standard text and window actions need.
    private func item(
        title: String,
        action: Selector,
        keyEquivalent: String = "",
        modifiers: NSEvent.ModifierFlags = .command,
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }

    /// The top-level item of a menu: the item carries the title, the submenu the
    /// rows.
    private func submenuItem(title: String, submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
}
