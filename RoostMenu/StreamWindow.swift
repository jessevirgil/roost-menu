import SwiftUI
import AppKit

/// A separate, resizable window that hosts a live stream's web view. The stream itself (and its
/// 5-minute extension timer) keeps living in StreamSession; this only changes where it is shown.
@MainActor
final class StreamWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let onUserClose: () -> Void
    private static var nextTopLeft: NSPoint?

    init(session: StreamSession, onUserClose: @escaping () -> Void) {
        self.onUserClose = onUserClose
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 450),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = session.device.displayName
        w.isReleasedWhenClosed = false
        w.backgroundColor = .black
        self.window = w
        super.init()

        let host = NSHostingController(rootView: StreamWindowView(
            session: session,
            setOnTop: { [weak w] on in w?.level = on ? .floating : .normal }))
        host.sizingOptions = []          // let the window, not SwiftUI, decide the size
        w.contentViewController = host
        w.setContentSize(NSSize(width: 800, height: 450))
        w.contentAspectRatio = NSSize(width: 16, height: 9)
        w.contentMinSize = NSSize(width: 320, height: 180)
        // Stagger new windows so several streams don't open exactly on top of each other.
        if Self.nextTopLeft == nil { w.center(); Self.nextTopLeft = NSPoint(x: w.frame.minX, y: w.frame.maxY) }
        else { w.setFrameTopLeftPoint(Self.nextTopLeft!) }
        Self.nextTopLeft = w.cascadeTopLeft(from: NSPoint(x: w.frame.minX, y: w.frame.maxY))
        w.delegate = self
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Programmatic close (stream already being stopped): don't report it as a user close.
    func close() {
        window.delegate = nil
        window.close()
    }

    func windowWillClose(_ notification: Notification) { onUserClose() }
}

struct StreamWindowView: View {
    @ObservedObject var session: StreamSession
    let setOnTop: (Bool) -> Void
    @State private var onTop = false

    var body: some View {
        ZStack {
            Color.black
            WebViewHost(webView: session.webView)
            StreamStatusOverlay(state: session.state)
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                OverlayButton(symbol: onTop ? "pin.fill" : "pin", help: "Keep on top of other windows") {
                    onTop.toggle(); setOnTop(onTop)
                }
                if session.state == .live {
                    OverlayButton(symbol: session.muted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                                  help: session.muted ? "Unmute" : "Mute") {
                        session.setMuted(!session.muted)
                    }
                }
            }
            .padding(10)
        }
        .onAppear { session.resumePlayback() }
    }
}

struct StreamStatusOverlay: View {
    let state: StreamSession.State
    var body: some View {
        switch state {
        case .connecting: ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let msg):
            Text(msg).font(.caption).foregroundStyle(.white).padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .live: EmptyView()
        }
    }
}

struct OverlayButton: View {
    let symbol: String
    let help: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .foregroundStyle(.white)
                .padding(7)
                .background(.black.opacity(0.55), in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
