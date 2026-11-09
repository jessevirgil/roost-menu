import Foundation
import WebKit

/// One live WebRTC viewing session for one camera. The page inside the WKWebView owns the
/// RTCPeerConnection; this class owns the SDM side (generate / extend / stop) and talks to the page
/// through a script-message bridge that can reply asynchronously.
@MainActor
final class StreamSession: NSObject, ObservableObject, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    enum State: Equatable { case connecting, live, failed(String) }

    let device: SDMDevice
    let webView: WKWebView
    @Published var state: State = .connecting
    @Published var muted = true
    /// True while the video is shown in its own window instead of the popover.
    @Published var detached = false

    private let client: SDMClient
    private var currentID: String?
    private var currentExpiry: Date?
    private var pendingID: String?
    private var pendingExpiry: Date?
    private var extendTask: Task<Void, Never>?
    private var stopped = false
    private var autoRetries = 0

    init(device: SDMDevice, client: SDMClient) {
        self.device = device
        self.client = client
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        #if DEBUG
        web.isInspectable = true
        #endif
        self.webView = web
        super.init()
        config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "nest")
        web.navigationDelegate = self
    }

    func start() {
        webView.loadHTMLString(StreamHTML.page, baseURL: URL(string: "https://roost-menu.invalid/"))
    }

    func stop() {
        guard !stopped else { return }
        stopped = true
        extendTask?.cancel()
        webView.evaluateJavaScript("teardown()", completionHandler: nil)
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "nest", contentWorld: .page)
        let name = device.id
        let ids = [currentID, pendingID].compactMap { $0 }
        let client = self.client
        Task { for id in ids { await client.stopWebRtc(deviceName: name, mediaSessionId: id) } }
        currentID = nil; pendingID = nil
    }

    /// Moving the web view between windows can pause the <video>; nudge it to keep playing.
    func resumePlayback() {
        webView.evaluateJavaScript("document.getElementById('v').play().catch(function(){})", completionHandler: nil)
    }

    func setMuted(_ m: Bool) {
        muted = m
        webView.evaluateJavaScript("setMuted(\(m))", completionHandler: nil)
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("connect()", completionHandler: nil)
    }

    // MARK: JS bridge

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return (nil, nil) }
        switch type {
        case "generate":
            guard let offer = body["offerSdp"] as? String else { return (nil, "missing offer") }
            do {
                let r = try await client.generateWebRtc(deviceName: device.id, offerSdp: offer)
                pendingID = r.mediaSessionId
                pendingExpiry = r.expiresAt
                return (["answerSdp": r.answerSdp], nil)
            } catch {
                let text = error.localizedDescription
                state = .failed(text)
                return (nil, text)
            }
        case "connected":
            promotePending()
        case "status":
            let s = body["state"] as? String ?? ""
            let detail = body["detail"] as? String ?? ""
            if s == "failed", !stopped {
                if state == .live, autoRetries < 2 {
                    autoRetries += 1
                    state = .connecting
                    webView.evaluateJavaScript("connect()", completionHandler: nil)
                } else if case .failed = state {} else {
                    state = .failed(detail.isEmpty ? "Stream failed" : detail)
                }
            } else if s == "connecting", state != .live {
                state = .connecting
            }
        default: break
        }
        return (nil, nil)
    }

    // MARK: Extension

    private func promotePending() {
        guard !stopped, let newID = pendingID else { return }
        let old = currentID
        currentID = newID
        currentExpiry = pendingExpiry
        pendingID = nil
        state = .live
        autoRetries = 0
        if let old {
            let name = device.id, client = self.client
            Task { await client.stopWebRtc(deviceName: name, mediaSessionId: old) }
        }
        scheduleExtension()
    }

    private func scheduleExtension() {
        extendTask?.cancel()
        extendTask = Task { [weak self] in
            var canExtend = true
            while let self, !Task.isCancelled, !self.stopped {
                guard let expiry = self.currentExpiry, let id = self.currentID else { return }
                // Streams last 5 minutes; extend with a minute to spare.
                try? await Task.sleep(for: .seconds(max(1, expiry.addingTimeInterval(-60).timeIntervalSinceNow)))
                if Task.isCancelled || self.stopped { return }

                if canExtend {
                    do {
                        let newExpiry = try await self.client.extendWebRtc(deviceName: self.device.id, mediaSessionId: id)
                        // Battery cameras on battery (and battery doorbells) can't extend: the request
                        // is ignored or rejected, so the expiry doesn't actually move.
                        if newExpiry > expiry.addingTimeInterval(30) {
                            self.currentExpiry = newExpiry
                            continue
                        }
                    } catch {}
                    canExtend = false
                }

                // Fallback: start a replacement stream shortly before the old one dies. The page swaps
                // video over once the new connection is up, so there is no visible gap.
                try? await Task.sleep(for: .seconds(max(0, expiry.addingTimeInterval(-25).timeIntervalSinceNow)))
                if Task.isCancelled || self.stopped { return }
                self.webView.evaluateJavaScript("connect()", completionHandler: nil)
                return // promotePending() will schedule the next cycle
            }
        }
    }
}

enum StreamHTML {
    static let page = #"""
    <!doctype html><html><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <style>
      html,body{margin:0;height:100%;background:#000;overflow:hidden}
      video{width:100%;height:100%;object-fit:contain;background:#000}
    </style></head>
    <body><video id="v" autoplay playsinline muted></video>
    <script>
    const bridge = window.webkit.messageHandlers.nest;
    const v = document.getElementById('v');
    let current = null;

    function status(state, detail) { bridge.postMessage({type:'status', state:state, detail:detail||''}); }
    function setMuted(m) { v.muted = m; }

    async function gathered(pc, ms) {
      if (pc.iceGatheringState === 'complete') return;
      await new Promise(res => {
        const t = setTimeout(res, ms);
        pc.addEventListener('icegatheringstatechange', () => {
          if (pc.iceGatheringState === 'complete') { clearTimeout(t); res(); }
        });
      });
    }

    function adopt(pc, stream) {
      if (current === pc) return;
      const old = current;
      current = pc;
      v.srcObject = stream;
      v.play().catch(() => {});
      if (old) { try { old.close(); } catch (e) {} }
      bridge.postMessage({type:'connected'});
    }

    async function connect() {
      status('connecting');
      try {
        const pc = new RTCPeerConnection({iceServers:[{urls:'stun:stun.l.google.com:19302'}]});
        // Google requires m-lines in this order: audio (recvonly, Opus only), video, application.
        const at = pc.addTransceiver('audio', {direction:'recvonly'});
        try {
          const opus = RTCRtpReceiver.getCapabilities('audio').codecs
            .filter(c => c.mimeType.toLowerCase() === 'audio/opus');
          if (opus.length) at.setCodecPreferences(opus);
        } catch (e) {}
        pc.addTransceiver('video', {direction:'recvonly'});
        pc.createDataChannel('dataSendChannel');

        const stream = new MediaStream();
        pc.ontrack = e => {
          stream.addTrack(e.track);
          if (e.track.kind === 'video' && pc.connectionState === 'connected') adopt(pc, stream);
        };
        pc.onconnectionstatechange = () => {
          if (pc.connectionState === 'connected' && stream.getVideoTracks().length) adopt(pc, stream);
          if ((pc.connectionState === 'failed' || pc.connectionState === 'closed') && pc === current) {
            status('failed', 'Connection ' + pc.connectionState);
          }
        };

        const offer = await pc.createOffer();
        await pc.setLocalDescription(offer);
        await gathered(pc, 3000);
        const reply = await bridge.postMessage({type:'generate', offerSdp: pc.localDescription.sdp});
        await pc.setRemoteDescription({type:'answer', sdp: reply.answerSdp});
      } catch (err) {
        status('failed', String(err && err.message ? err.message : err));
      }
    }

    function teardown() {
      try { if (current) current.close(); } catch (e) {}
      current = null; v.srcObject = null;
    }
    </script></body></html>
    """#
}
