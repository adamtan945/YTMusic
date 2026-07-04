import Cocoa
import SwiftUI

/// Menu Bar 常駐圖示服務
class MenuBarService: NSObject, NSMenuDelegate {
    static let shared = MenuBarService()

    private var statusItem: NSStatusItem?
    private var isPlaying = false
    private var currentTrack: TrackInfo?
    private var currentArtwork: NSImage?
    private var volume: Float = 1.0
    private var repeatState: String = "none"
    private var shuffleEnabled: Bool = false
    private var queueItems: [QueueItem] = []
    private var currentTime: Double = 0
    private var duration: Double = 0
    private var queueThumbnails: [String: NSImage] = [:]
    private var artworkRequestTracker = ArtworkRequestTracker()

    // 即時更新的 UI 元素引用
    private weak var playButton: NSButton?
    private weak var progressSlider: NSSlider?
    private weak var elapsedLabel: NSTextField?
    private weak var remainLabel: NSTextField?
    private weak var artworkView: NSImageView?
    private weak var titleLabel: NSTextField?
    private weak var artistLabel: NSTextField?

    // 播放清單滾動位置追蹤
    private weak var queueScrollView: NSScrollView?
    private weak var topIndicator: NSView?
    private weak var bottomIndicator: NSView?
    private var lastQueueScrollOffset: CGFloat = 0

    private let menuWidth: CGFloat = 320
    private let cardMargin: CGFloat = 10
    private var isMenuOpen = false
    private var queueRefreshWorkItem: DispatchWorkItem?

    private override init() {
        super.init()
        setupStatusItem()
        setupCallbacks()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = makeStatusIcon()
        }

        let menu = NSMenu()
        menu.delegate = self
        statusItem?.menu = menu
    }

    /// YouTube Music 風格圖示：實心圓形中央挖空播放三角（template 圖，自動配合深淺色 menu bar）
    private func makeStatusIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

            let circle = NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5))
            NSColor.black.setFill()
            circle.fill()

            ctx.setBlendMode(.destinationOut)
            let triangle = NSBezierPath()
            triangle.move(to: NSPoint(x: 7.2, y: 5.9))
            triangle.line(to: NSPoint(x: 7.2, y: 12.1))
            triangle.line(to: NSPoint(x: 12.8, y: 9))
            triangle.close()
            NSColor.black.setFill()
            triangle.fill()
            ctx.setBlendMode(.normal)

            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - NSMenuDelegate — 每次開啟時重建 menu 內容

    func menuNeedsUpdate(_ menu: NSMenu) {
        if let contentView = queueScrollView?.contentView {
            lastQueueScrollOffset = contentView.bounds.origin.y
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.boundsDidChangeNotification,
                object: contentView
            )
        }

        playButton = nil
        progressSlider = nil
        elapsedLabel = nil
        remainLabel = nil
        artworkView = nil
        titleLabel = nil
        artistLabel = nil
        queueScrollView = nil
        topIndicator = nil
        bottomIndicator = nil

        menu.removeAllItems()
        menu.minimumWidth = menuWidth

        // Now Playing 玻璃卡片
        let playerItem = NSMenuItem()
        if let track = currentTrack, !track.title.isEmpty {
            playerItem.view = createPlayerCardView(track: track)
        } else {
            playerItem.view = createEmptyPlayerView()
        }
        menu.addItem(playerItem)
        menu.addItem(NSMenuItem.separator())

        // 待播清單區
        let queueHeaderItem = NSMenuItem()
        queueHeaderItem.view = createQueueHeaderView()
        menu.addItem(queueHeaderItem)

        if queueItems.isEmpty {
            JavaScriptBridge.executeCommand(.fetchQueue)
        } else {
            let queueViewItem = NSMenuItem()
            queueViewItem.view = createQueueView()
            menu.addItem(queueViewItem)
        }

        menu.addItem(NSMenuItem.separator())

        let showItem = NSMenuItem(title: "顯示視窗", action: #selector(showWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "結束 YTMusic", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        debugConsole("[MenuBar] menuWillOpen")
        scheduleQueueRefresh(delay: 0)
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        debugConsole("[MenuBar] menuDidClose")
    }

    private func setupCallbacks() {
        JavaScriptBridge.shared.onPlaybackStateChanged = { [weak self] playing in
            DispatchQueue.main.async {
                self?.isPlaying = playing
                self?.updatePlayButtonIcon()
                if playing {
                    self?.scheduleQueueRefresh()
                }
                self?.refreshMenuContentsIfVisible()
            }
        }

        JavaScriptBridge.shared.onTrackChanged = { [weak self] track in
            DispatchQueue.main.async {
                debugConsole("[MenuBar] onTrackChanged title=\(track.title) artist=\(track.artist)")
                self?.currentTrack = track
                self?.currentArtwork = nil
                self?.artworkView?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
                self?.titleLabel?.stringValue = track.title
                self?.artistLabel?.stringValue = track.artist
                NowPlayingService.shared.showNotification(track: track)
                self?.scheduleQueueRefresh()

                if let urlString = track.artworkURL {
                    self?.loadArtwork(urlString: urlString)
                } else {
                    self?.artworkRequestTracker.clear()
                }
                self?.refreshMenuContentsIfVisible()
            }
        }

        JavaScriptBridge.shared.onVolumeChanged = { [weak self] vol in
            DispatchQueue.main.async {
                self?.volume = vol
            }
        }

        JavaScriptBridge.shared.onRepeatStateChanged = { [weak self] state in
            DispatchQueue.main.async {
                self?.repeatState = state
                self?.refreshMenuContentsIfVisible()
            }
        }

        JavaScriptBridge.shared.onShuffleStateChanged = { [weak self] enabled in
            DispatchQueue.main.async {
                self?.shuffleEnabled = enabled
                self?.refreshMenuContentsIfVisible()
            }
        }

        JavaScriptBridge.shared.onQueueUpdated = { [weak self] items in
            DispatchQueue.main.async {
                debugConsole("[MenuBar] onQueueUpdated count=\(items.count)")
                self?.queueItems = items
                self?.loadQueueThumbnails(items)
                self?.refreshMenuContentsIfVisible()
            }
        }

        JavaScriptBridge.shared.onTimeUpdated = { [weak self] current, total in
            DispatchQueue.main.async {
                self?.currentTime = current
                self?.duration = total
                self?.updateProgressUI()
            }
        }
    }

    // MARK: - 即時 UI 更新（不重建 menu）

    private func updatePlayButtonIcon() {
        guard let button = playButton else { return }
        let symbolName = isPlaying ? "pause.fill" : "play.fill"
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 17, weight: .semibold)
            button.image = image.withSymbolConfiguration(config)
        }
    }

    private func updateProgressUI() {
        progressSlider?.maxValue = max(duration, 1)
        progressSlider?.doubleValue = currentTime
        elapsedLabel?.stringValue = formatTime(currentTime)
        let remaining = max(0, duration - currentTime)
        remainLabel?.stringValue = "-\(formatTime(remaining))"
    }

    private func refreshMenuContentsIfVisible() {
        guard isMenuOpen,
              let menu = statusItem?.menu else { return }
        menuNeedsUpdate(menu)
        menu.update()
    }

    private func scheduleQueueRefresh(delay: TimeInterval = 0.35) {
        queueRefreshWorkItem?.cancel()

        let workItem = DispatchWorkItem {
            JavaScriptBridge.executeCommand(.fetchQueue)
        }
        queueRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func loadArtwork(urlString: String) {
        let requestID = artworkRequestTracker.start()

        // 嘗試取得較大尺寸的封面圖
        let highResURL = urlString
            .replacingOccurrences(of: "w60-h60", with: "w300-h300")
            .replacingOccurrences(of: "w120-h120", with: "w300-h300")
            .replacingOccurrences(of: "=w60", with: "=w300")
            .replacingOccurrences(of: "=w120", with: "=w300")

        let urls = [highResURL, urlString].compactMap { URL(string: $0) }
        loadArtworkFromURLs(urls, requestID: requestID)
    }

    private func loadArtworkFromURLs(_ urls: [URL], requestID: UUID) {
        guard let url = urls.first else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            if let data = data, let image = NSImage(data: data) {
                DispatchQueue.main.async {
                    guard self?.artworkRequestTracker.accepts(requestID) == true else { return }
                    self?.currentArtwork = image
                    self?.artworkView?.image = image
                }
            } else {
                // fallback 到下一個 URL
                let remaining = Array(urls.dropFirst())
                if !remaining.isEmpty {
                    self?.loadArtworkFromURLs(remaining, requestID: requestID)
                }
            }
        }.resume()
    }

    // MARK: - Now Playing 玻璃卡片

    private func createGlassCard(height: CGFloat) -> (container: NSView, card: NSView) {
        let cardWidth = menuWidth - cardMargin * 2
        let container = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: height + 12))

        let card = NSVisualEffectView(frame: NSRect(x: cardMargin, y: 6, width: cardWidth, height: height))
        card.material = .hudWindow
        card.blendingMode = .withinWindow
        card.state = .active
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.cornerCurve = .continuous
        card.layer?.masksToBounds = true
        card.layer?.borderWidth = 0.5
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        container.addSubview(card)

        return (container, card)
    }

    private func createEmptyPlayerView() -> NSView {
        let (container, card) = createGlassCard(height: 56)

        let icon = NSImageView(frame: NSRect(x: 16, y: 16, width: 24, height: 24))
        icon.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 18, weight: .regular))
        icon.contentTintColor = .tertiaryLabelColor
        card.addSubview(icon)

        let label = NSTextField(labelWithString: "尚未播放任何內容")
        label.frame = NSRect(x: 52, y: 20, width: 200, height: 16)
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        card.addSubview(label)

        return container
    }

    private func createPlayerCardView(track: TrackInfo) -> NSView {
        let cardHeight: CGFloat = 208
        let (container, card) = createGlassCard(height: cardHeight)
        let cardWidth = card.frame.width
        let padding: CGFloat = 14
        let artSize: CGFloat = 88

        // 封面圖（左上）
        let imageView = NSImageView(frame: NSRect(x: padding, y: cardHeight - padding - artSize, width: artSize, height: artSize))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 8
        imageView.layer?.cornerCurve = .continuous
        imageView.layer?.masksToBounds = true
        imageView.image = currentArtwork ?? NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)
        card.addSubview(imageView)
        self.artworkView = imageView

        // 歌名 / 歌手（封面右側）
        let textX = padding + artSize + 12
        let textWidth = cardWidth - textX - padding

        let titleLabel = NSTextField(labelWithString: track.title)
        titleLabel.frame = NSRect(x: textX, y: cardHeight - padding - 22, width: textWidth, height: 18)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        card.addSubview(titleLabel)
        self.titleLabel = titleLabel

        let artistLabel = NSTextField(labelWithString: track.artist)
        artistLabel.frame = NSRect(x: textX, y: cardHeight - padding - 40, width: textWidth, height: 15)
        artistLabel.font = NSFont.systemFont(ofSize: 11)
        artistLabel.textColor = .secondaryLabelColor
        artistLabel.lineBreakMode = .byTruncatingTail
        card.addSubview(artistLabel)
        self.artistLabel = artistLabel

        // 進度條 + 時間
        let timeWidth: CGFloat = 34
        let progressY: CGFloat = 82

        let elapsed = NSTextField(labelWithString: formatTime(currentTime))
        elapsed.frame = NSRect(x: padding, y: progressY, width: timeWidth, height: 12)
        elapsed.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        elapsed.textColor = .secondaryLabelColor
        elapsed.alignment = .left
        card.addSubview(elapsed)
        self.elapsedLabel = elapsed

        let sliderX = padding + timeWidth + 4
        let slider = NSSlider(frame: NSRect(x: sliderX, y: progressY - 3, width: cardWidth - sliderX - padding - timeWidth - 4, height: 16))
        slider.controlSize = .mini
        slider.minValue = 0
        slider.maxValue = max(duration, 1)
        slider.doubleValue = currentTime
        slider.target = self
        slider.action = #selector(progressSliderChanged(_:))
        slider.isContinuous = true
        card.addSubview(slider)
        self.progressSlider = slider

        let remaining = max(0, duration - currentTime)
        let remain = NSTextField(labelWithString: "-\(formatTime(remaining))")
        remain.frame = NSRect(x: cardWidth - padding - timeWidth, y: progressY, width: timeWidth, height: 12)
        remain.font = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular)
        remain.textColor = .secondaryLabelColor
        remain.alignment = .right
        card.addSubview(remain)
        self.remainLabel = remain

        // 控制列：shuffle / 上一首 / 播放 / 下一首 / repeat
        let controlsCenterY: CGFloat = 56
        let sizes: [CGFloat] = [28, 30, 40, 30, 28]
        let spacing: CGFloat = 16
        let totalWidth = sizes.reduce(0, +) + spacing * CGFloat(sizes.count - 1)
        var x = (cardWidth - totalWidth) / 2

        let shuffleButton = HoverSymbolButton(
            symbolName: "shuffle", pointSize: 12,
            frame: NSRect(x: x, y: controlsCenterY - sizes[0] / 2, width: sizes[0], height: sizes[0]),
            target: self, action: #selector(shuffleClicked)
        )
        if shuffleEnabled {
            shuffleButton.contentTintColor = .controlAccentColor
        }
        card.addSubview(shuffleButton)
        x += sizes[0] + spacing

        let prevButton = HoverSymbolButton(
            symbolName: "backward.fill", pointSize: 13,
            frame: NSRect(x: x, y: controlsCenterY - sizes[1] / 2, width: sizes[1], height: sizes[1]),
            target: self, action: #selector(previousClicked)
        )
        card.addSubview(prevButton)
        x += sizes[1] + spacing

        let playBtn = HoverSymbolButton(
            symbolName: isPlaying ? "pause.fill" : "play.fill", pointSize: 17,
            frame: NSRect(x: x, y: controlsCenterY - sizes[2] / 2, width: sizes[2], height: sizes[2]),
            target: self, action: #selector(playPauseClicked)
        )
        playBtn.normalBackgroundColor = NSColor.labelColor.withAlphaComponent(0.1)
        playBtn.hoverBackgroundColor = NSColor.labelColor.withAlphaComponent(0.18)
        card.addSubview(playBtn)
        self.playButton = playBtn
        x += sizes[2] + spacing

        let nextButton = HoverSymbolButton(
            symbolName: "forward.fill", pointSize: 13,
            frame: NSRect(x: x, y: controlsCenterY - sizes[3] / 2, width: sizes[3], height: sizes[3]),
            target: self, action: #selector(nextClicked)
        )
        card.addSubview(nextButton)
        x += sizes[3] + spacing

        let repeatButton = HoverSymbolButton(
            symbolName: repeatState == "one" ? "repeat.1" : "repeat", pointSize: 12,
            frame: NSRect(x: x, y: controlsCenterY - sizes[4] / 2, width: sizes[4], height: sizes[4]),
            target: self, action: #selector(repeatClicked)
        )
        if repeatState != "none" {
            repeatButton.contentTintColor = .controlAccentColor
        }
        card.addSubview(repeatButton)

        // 音量列
        let volumeIconSize: CGFloat = 14
        let volumeY: CGFloat = 14

        let smallIcon = NSImageView(frame: NSRect(x: padding, y: volumeY, width: volumeIconSize, height: volumeIconSize))
        smallIcon.image = NSImage(systemSymbolName: "speaker.fill", accessibilityDescription: "音量小")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))
        smallIcon.contentTintColor = .secondaryLabelColor
        card.addSubview(smallIcon)

        let volSliderX = padding + volumeIconSize + 8
        let volSliderWidth = cardWidth - volSliderX - padding - volumeIconSize - 8
        let volSlider = NSSlider(frame: NSRect(x: volSliderX, y: volumeY - 2, width: volSliderWidth, height: 16))
        volSlider.controlSize = .small
        volSlider.minValue = 0
        volSlider.maxValue = 1
        volSlider.doubleValue = Double(volume)
        volSlider.target = self
        volSlider.action = #selector(volumeSliderChanged(_:))
        volSlider.isContinuous = true
        card.addSubview(volSlider)

        let largeIcon = NSImageView(frame: NSRect(x: cardWidth - padding - volumeIconSize, y: volumeY, width: volumeIconSize, height: volumeIconSize))
        largeIcon.image = NSImage(systemSymbolName: "speaker.wave.3.fill", accessibilityDescription: "音量大")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .medium))
        largeIcon.contentTintColor = .secondaryLabelColor
        card.addSubview(largeIcon)

        return container
    }

    // MARK: - 待播清單區

    private func createQueueHeaderView() -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: 24))

        let label = NSTextField(labelWithString: "待播清單")
        label.frame = NSRect(x: 16, y: 3, width: 200, height: 18)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        view.addSubview(label)

        return view
    }

    private func createQueueView() -> NSView {
        let rowHeight: CGFloat = 52
        let maxVisible = 6
        let visibleHeight = min(CGFloat(queueItems.count), CGFloat(maxVisible)) * rowHeight
        let indicatorHeight: CGFloat = 16

        let containerHeight = visibleHeight
        let container = NSView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: containerHeight))

        let scrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: containerHeight))
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.scrollerStyle = .overlay
        scrollView.drawsBackground = false

        let totalHeight = CGFloat(queueItems.count) * rowHeight
        let documentView = FlippedView(frame: NSRect(x: 0, y: 0, width: menuWidth, height: totalHeight))

        for (index, item) in queueItems.enumerated() {
            let rowView = QueueRowView(frame: NSRect(x: 0, y: CGFloat(index) * rowHeight, width: menuWidth, height: rowHeight))
            rowView.configure(
                item: item,
                thumbnail: queueThumbnail(for: item),
                isCurrent: item.isPlaying,
                isPlayerPlaying: isPlaying
            )
            rowView.onActivate = { [weak self] in
                if item.isPlaying {
                    JavaScriptBridge.executeCommand(.playPause)
                } else {
                    self?.playQueueItem(at: index)
                }
            }
            documentView.addSubview(rowView)
        }

        scrollView.documentView = documentView
        container.addSubview(scrollView)

        // ▲▼ 指示器（無半透明圖層，只有 chevron 圖示）
        if queueItems.count > maxVisible {
            let topInd = createScrollIndicator(
                frame: NSRect(x: 0, y: containerHeight - indicatorHeight, width: menuWidth, height: indicatorHeight),
                chevronName: "chevron.up"
            )
            container.addSubview(topInd)
            topInd.isHidden = true
            self.topIndicator = topInd

            let bottomInd = createScrollIndicator(
                frame: NSRect(x: 0, y: 0, width: menuWidth, height: indicatorHeight),
                chevronName: "chevron.down"
            )
            container.addSubview(bottomInd)
            self.bottomIndicator = bottomInd

            self.queueScrollView = scrollView
            if let documentView = scrollView.documentView {
                let maxOffset = max(0, documentView.frame.height - scrollView.frame.height)
                let restoredOffset = min(lastQueueScrollOffset, maxOffset)
                scrollView.contentView.scroll(to: NSPoint(x: 0, y: restoredOffset))
                scrollView.reflectScrolledClipView(scrollView.contentView)
            }

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(queueDidScroll(_:)),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
            scrollView.contentView.postsBoundsChangedNotifications = true
        }

        return container
    }

    // MARK: - ▲▼ 指示器（純圖示，無漸層）

    private func createScrollIndicator(frame: NSRect, chevronName: String) -> NSView {
        let view = NSView(frame: frame)

        let iconSize: CGFloat = 10
        let iconView = NSImageView(frame: NSRect(
            x: (frame.width - iconSize) / 2,
            y: (frame.height - iconSize) / 2,
            width: iconSize,
            height: iconSize
        ))
        if let img = NSImage(systemSymbolName: chevronName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 8, weight: .medium)
            iconView.image = img.withSymbolConfiguration(config)
        }
        iconView.contentTintColor = .tertiaryLabelColor
        view.addSubview(iconView)

        return view
    }

    @objc private func queueDidScroll(_ notification: Notification) {
        guard let scrollView = queueScrollView,
              let documentView = scrollView.documentView else { return }

        let clipBounds = scrollView.contentView.bounds
        lastQueueScrollOffset = clipBounds.origin.y
        let contentHeight = documentView.frame.height
        let viewHeight = scrollView.frame.height

        let atTop = clipBounds.origin.y <= 0
        let atBottom = clipBounds.origin.y + viewHeight >= contentHeight - 1

        topIndicator?.isHidden = atTop
        bottomIndicator?.isHidden = atBottom

        // 捲動時列在動、滑鼠沒動，NSTrackingArea 不會送 mouseExited，
        // 用實際滑鼠位置同步每一列的 hover 狀態，避免殘留高亮
        if let window = scrollView.window {
            let mouse = window.mouseLocationOutsideOfEventStream
            for case let row as QueueRowView in documentView.subviews {
                row.syncHover(mouseLocationInWindow: mouse)
            }
        }
    }

    // MARK: - 輔助方法

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "0:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return "\(mins):\(String(format: "%02d", secs))"
    }

    private func queueThumbnail(for item: QueueItem) -> NSImage? {
        if let urlStr = item.thumbnailURL, let cached = queueThumbnails[urlStr] {
            return cached
        }
        return nil
    }

    private func loadQueueThumbnails(_ items: [QueueItem]) {
        for item in items {
            guard let urlStr = item.thumbnailURL,
                  queueThumbnails[urlStr] == nil,
                  let url = URL(string: urlStr) else { continue }

            URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
                guard let data = data, let image = NSImage(data: data) else { return }
                DispatchQueue.main.async {
                    self?.queueThumbnails[urlStr] = image
                    self?.refreshMenuContentsIfVisible()
                }
            }.resume()
        }
    }

    // MARK: - 選單動作

    @objc private func playPauseClicked() {
        JavaScriptBridge.executeCommand(.playPause)
    }

    @objc private func nextClicked() {
        JavaScriptBridge.executeCommand(.next)
    }

    @objc private func previousClicked() {
        JavaScriptBridge.executeCommand(.previous)
    }

    @objc private func volumeSliderChanged(_ sender: NSSlider) {
        let value = Float(sender.doubleValue)
        volume = value
        JavaScriptBridge.executeCommand(.setVolume(value))
    }

    @objc private func progressSliderChanged(_ sender: NSSlider) {
        let time = sender.doubleValue
        currentTime = time
        JavaScriptBridge.executeCommand(.seekTo(time))
    }

    @objc private func repeatClicked() {
        JavaScriptBridge.executeCommand(.toggleRepeat)
    }

    @objc private func shuffleClicked() {
        JavaScriptBridge.executeCommand(.toggleShuffle)
    }

    private func playQueueItem(at index: Int) {
        JavaScriptBridge.executeCommand(.playQueueItem(index))
    }

    @objc private func showWindow() {
        if let appDelegate = NSApp.delegate as? AppDelegate {
            appDelegate.showWindow()
        }
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}

// MARK: - 翻轉座標 NSView（從上往下排列）

class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

// MARK: - 圓形 hover 背景的符號按鈕

final class HoverSymbolButton: NSButton {
    var normalBackgroundColor: NSColor = .clear {
        didSet { layer?.backgroundColor = normalBackgroundColor.cgColor }
    }
    var hoverBackgroundColor: NSColor = NSColor.labelColor.withAlphaComponent(0.12)
    private var hoverTracking: NSTrackingArea?

    convenience init(symbolName: String, pointSize: CGFloat, frame: NSRect, target: AnyObject?, action: Selector?) {
        self.init(frame: frame)
        isBordered = false
        bezelStyle = .regularSquare
        imagePosition = .imageOnly
        wantsLayer = true
        layer?.cornerRadius = frame.height / 2
        layer?.masksToBounds = true
        contentTintColor = .labelColor
        self.target = target
        self.action = action

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            self.image = image.withSymbolConfiguration(config)
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverTracking {
            removeTrackingArea(hoverTracking)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        hoverTracking = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = hoverBackgroundColor.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = normalBackgroundColor.cgColor
    }
}

// MARK: - 播放清單列（整列 hover / 點擊跳播）

final class QueueRowView: NSView {
    private let highlightView = NSView()
    private let thumbView = NSImageView()
    private let thumbOverlay = NSView()
    private let stateIconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let artistLabel = NSTextField(labelWithString: "")
    private let timeLabel = NSTextField(labelWithString: "")
    private var rowTracking: NSTrackingArea?
    private var isHovering = false
    private var isCurrent = false
    private var isPlayerPlaying = false
    var onActivate: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        let rowHeight = bounds.height
        let width = bounds.width
        let padding: CGFloat = 16
        let thumbSize: CGFloat = 36
        let timeWidth: CGFloat = 40

        highlightView.frame = NSRect(x: 8, y: 2, width: width - 16, height: rowHeight - 4)
        highlightView.wantsLayer = true
        highlightView.layer?.cornerRadius = 8
        highlightView.layer?.cornerCurve = .continuous
        highlightView.isHidden = true
        addSubview(highlightView)

        thumbView.frame = NSRect(x: padding, y: (rowHeight - thumbSize) / 2, width: thumbSize, height: thumbSize)
        thumbView.imageScaling = .scaleProportionallyUpOrDown
        thumbView.wantsLayer = true
        thumbView.layer?.cornerRadius = 6
        thumbView.layer?.cornerCurve = .continuous
        thumbView.layer?.masksToBounds = true
        thumbView.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        addSubview(thumbView)

        thumbOverlay.frame = thumbView.frame
        thumbOverlay.wantsLayer = true
        thumbOverlay.layer?.cornerRadius = 6
        thumbOverlay.layer?.cornerCurve = .continuous
        thumbOverlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor
        thumbOverlay.isHidden = true
        addSubview(thumbOverlay)

        let iconSize: CGFloat = 16
        stateIconView.frame = NSRect(
            x: thumbView.frame.midX - iconSize / 2,
            y: thumbView.frame.midY - iconSize / 2,
            width: iconSize,
            height: iconSize
        )
        stateIconView.contentTintColor = .white
        stateIconView.isHidden = true
        addSubview(stateIconView)

        let textX = padding + thumbSize + 10
        let textWidth = width - textX - padding - timeWidth - 4

        titleLabel.frame = NSRect(x: textX, y: rowHeight / 2 + 2, width: textWidth, height: 16)
        titleLabel.font = NSFont.systemFont(ofSize: 12)
        titleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)

        artistLabel.frame = NSRect(x: textX, y: rowHeight / 2 - 15, width: textWidth, height: 14)
        artistLabel.font = NSFont.systemFont(ofSize: 10)
        artistLabel.textColor = .secondaryLabelColor
        artistLabel.lineBreakMode = .byTruncatingTail
        addSubview(artistLabel)

        timeLabel.frame = NSRect(x: width - padding - timeWidth, y: (rowHeight - 14) / 2, width: timeWidth, height: 14)
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.alignment = .right
        addSubview(timeLabel)
    }

    func configure(item: QueueItem, thumbnail: NSImage?, isCurrent: Bool, isPlayerPlaying: Bool) {
        self.isCurrent = isCurrent
        self.isPlayerPlaying = isPlayerPlaying

        titleLabel.stringValue = item.title
        titleLabel.font = isCurrent
            ? NSFont.systemFont(ofSize: 12, weight: .semibold)
            : NSFont.systemFont(ofSize: 12)
        artistLabel.stringValue = item.artist
        timeLabel.stringValue = item.duration

        if let thumbnail {
            thumbView.image = thumbnail
            thumbView.contentTintColor = nil
        } else {
            thumbView.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .regular))
            thumbView.contentTintColor = .tertiaryLabelColor
        }

        refreshState()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let rowTracking {
            removeTrackingArea(rowTracking)
        }
        let tracking = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(tracking)
        rowTracking = tracking
    }

    override func mouseEntered(with event: NSEvent) {
        isHovering = true
        refreshState()
    }

    override func mouseExited(with event: NSEvent) {
        isHovering = false
        refreshState()
    }

    /// 依實際滑鼠位置校正 hover 狀態（捲動時 tracking area 不可靠）
    func syncHover(mouseLocationInWindow point: NSPoint) {
        let local = convert(point, from: nil)
        let inside = bounds.contains(local) && visibleRect.contains(local)
        if inside != isHovering {
            isHovering = inside
            refreshState()
        }
    }

    override func mouseUp(with event: NSEvent) {
        let location = convert(event.locationInWindow, from: nil)
        guard bounds.contains(location) else { return }
        onActivate?()
    }

    private func refreshState() {
        // 整列 highlight：hover 較亮，正在播放持續淡色
        if isHovering {
            highlightView.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.1).cgColor
            highlightView.isHidden = false
        } else if isCurrent {
            highlightView.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.06).cgColor
            highlightView.isHidden = false
        } else {
            highlightView.isHidden = true
        }

        // 縮圖 overlay：正在播放顯示喇叭；hover 其他列顯示播放鍵
        let symbolName: String?
        if isCurrent {
            symbolName = isPlayerPlaying ? "speaker.wave.2.fill" : "speaker.fill"
        } else if isHovering {
            symbolName = "play.fill"
        } else {
            symbolName = nil
        }

        if let symbolName,
           let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) {
            let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
            stateIconView.image = image.withSymbolConfiguration(config)
            stateIconView.isHidden = false
            thumbOverlay.isHidden = false
        } else {
            stateIconView.isHidden = true
            thumbOverlay.isHidden = true
        }
    }
}

public struct ArtworkRequestTracker {
    private var currentRequestID: UUID?

    public init() {}

    public mutating func start() -> UUID {
        let requestID = UUID()
        currentRequestID = requestID
        return requestID
    }

    public mutating func clear() {
        currentRequestID = nil
    }

    public func accepts(_ requestID: UUID) -> Bool {
        currentRequestID == requestID
    }
}
