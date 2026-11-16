// AVPlayer never posts didPlayToEndTime after the legible option is deselected and the
// player seeks (HLS with a one-segment WebVTT subtitle playlist).
//
// Launch with `-mode bug` (deselect subtitles, then seek) or `-mode subon` (seek only).
// Prints "RESULT <mode> ended|stalled" and exits 0 (ended) or 1 (stalled).
// The bundled HLS content is served from a loopback HTTP server, so no network is used.

import AVFoundation
import Network
import SwiftUI

@main
struct AppleHLSEOSStallRepro: App {
    init() {
        #if os(macOS)
        NSApplication.shared.setActivationPolicy(.accessory)  // run from Terminal without taking focus
        #endif
        Repro.shared.start()
    }
    var body: some Scene { WindowGroup { Text("HLS legible stall repro: see stdout") } }
}

final class Repro {
    static let shared = Repro()
    let mode = UserDefaults.standard.string(forKey: "mode") ?? "bug"
    let server = Server(root: Bundle.main.url(forResource: "content", withExtension: nil)!)
    var player: AVPlayer!
    var item: AVPlayerItem!
    var statusObservation: NSKeyValueObservation?
    var ended = false

    func start() {
        server.start { port in self.play(URL(string: "http://127.0.0.1:\(port)/master.m3u8")!) }
    }

    func play(_ url: URL) {
        item = AVPlayerItem(url: url)
        // Keeps video and audio short of end of stream at the time of the seek.
        item.preferredForwardBufferDuration = 10
        player = AVPlayer(playerItem: item)
        player.isMuted = true
        NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { _ in
            self.ended = true
            self.finish()
        }
        statusObservation = item.observe(\.status) { item, _ in
            guard item.status == .readyToPlay else { return }
            self.statusObservation = nil
            DispatchQueue.main.async { self.run() }
        }
    }

    func run() {
        let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: .legible)!
        item.select(group.options.first, in: group)  // its one-segment playlist ends at once
        player.play()
        let seekTo = item.duration.seconds - 20
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if self.mode == "bug" { self.item.select(nil, in: group) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self.player.seek(to: CMTime(seconds: seekTo, preferredTimescale: 600),
                                 toleranceBefore: .zero, toleranceAfter: .zero)
                DispatchQueue.main.asyncAfter(deadline: .now() + 35) { self.finish() }
            }
        }
    }

    func finish() {
        print("RESULT \(mode) \(ended ? "ended" : "stalled") currentTime=\(item.currentTime().seconds)")
        fflush(stdout)
        exit(ended ? 0 : 1)
    }
}

/// Minimal HTTP/1.1 GET server on 127.0.0.1 for the bundled files.
final class Server {
    let root: URL
    var listener: NWListener?
    init(root: URL) { self.root = root }

    func start(_ ready: @escaping (UInt16) -> Void) {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try! NWListener(using: params)
        self.listener = listener
        listener.newConnectionHandler = { conn in
            conn.start(queue: .global())
            conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
                let request = String(decoding: data ?? Data(), as: UTF8.self)
                let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                let body = try? Data(contentsOf: self.root.appendingPathComponent(path))
                var response = Data("HTTP/1.1 \(body == nil ? "404 Not Found" : "200 OK")\r\nContent-Length: \(body?.count ?? 0)\r\nConnection: close\r\n\r\n".utf8)
                response.append(body ?? Data())
                conn.send(content: response, completion: .contentProcessed { _ in conn.cancel() })
            }
        }
        listener.stateUpdateHandler = { state in
            if case .ready = state { DispatchQueue.main.async { ready(listener.port!.rawValue) } }
        }
        listener.start(queue: .global())
    }
}
