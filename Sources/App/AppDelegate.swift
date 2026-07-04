import Cocoa
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var menuBarService: MenuBarService?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 建立主視窗
        let window = makeMainWindow()
        window.makeKeyAndOrderFront(nil)
        self.window = window

        // 建立主選單
        setupMainMenu()

        // 啟動 Menu Bar 常駐圖示
        menuBarService = MenuBarService.shared

        // 讓 App 顯示在前景
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 關閉最後一個視窗時不結束 App，讓音樂在背景繼續播放
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// 點擊 Dock 圖示時重新顯示視窗
    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            showWindow()
        }
        return true
    }

    public func showWindow() {
        if let window = self.window {
            window.makeKeyAndOrderFront(nil)
        } else {
            // 視窗已被釋放，重新建立
            let newWindow = makeMainWindow()
            newWindow.makeKeyAndOrderFront(nil)
            self.window = newWindow
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeMainWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1024, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.styleMask.insert(.fullSizeContentView)
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(red: 0.07, green: 0.07, blue: 0.07, alpha: 1)
        window.minSize = NSSize(width: 800, height: 600)
        window.isReleasedWhenClosed = false

        // 標題列透明化後頂部整片都是 WKWebView，會吃掉滑鼠事件導致無法拖動視窗，
        // 疊一條透明拖曳區在最上方（紅綠燈在另一個圖層，不受影響）
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 1024, height: 700))
        let hostingView = NSHostingView(rootView: ContentView())
        hostingView.frame = container.bounds
        hostingView.autoresizingMask = [.width, .height]
        container.addSubview(hostingView)

        let dragStripHeight: CGFloat = 28
        let dragStrip = WindowDragStripView(frame: NSRect(
            x: 0,
            y: container.bounds.height - dragStripHeight,
            width: container.bounds.width,
            height: dragStripHeight
        ))
        dragStrip.autoresizingMask = [.width, .minYMargin]
        container.addSubview(dragStrip)

        window.contentView = container
        window.center()
        return window
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        // App 選單
        let appMenu = NSMenu()
        appMenu.addItem(NSMenuItem(title: "關於 YTMusic", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(NSMenuItem(title: "隱藏 YTMusic", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        appMenu.addItem(NSMenuItem(title: "結束 YTMusic", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let appMenuItem = NSMenuItem()
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        // Edit 選單（支援 WebView 文字輸入的 ⌘C/V/X/A）
        let editMenu = NSMenu(title: "編輯")
        editMenu.addItem(NSMenuItem(title: "剪下", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(NSMenuItem(title: "拷貝", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(NSMenuItem(title: "貼上", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem(title: "全選", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        let editMenuItem = NSMenuItem()
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        // Window 選單
        let windowMenu = NSMenu(title: "視窗")
        windowMenu.addItem(NSMenuItem(title: "關閉視窗", action: #selector(NSWindow.close), keyEquivalent: "w"))
        windowMenu.addItem(NSMenuItem(title: "縮小", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"))

        let windowMenuItem = NSMenuItem()
        windowMenuItem.submenu = windowMenu
        mainMenu.addItem(windowMenuItem)

        NSApp.mainMenu = mainMenu
    }
}

/// 透明拖曳區：mouseDown 直接啟動視窗拖曳
final class WindowDragStripView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}
