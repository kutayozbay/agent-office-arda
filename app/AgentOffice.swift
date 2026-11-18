// Agent Office — a small macOS window showing the agents at work.
//
// The window hosts web/office.html (bundled as a resource) and hands it a snapshot every
// couple of seconds: the Claude sessions the hook records (hook/agent-office-hook.sh), and,
// when configured, a PR-review queue (a pr-watch layout: running/, queue, a log file).
// Nothing runs while the app is closed except the hook itself; there is no server and no port.
//
// Configuration: ~/.config/agent-office/config.json, every key optional:
//   { "officeState": "~/.local/state/agent-office",
//     "reviews": { "state": "~/.local/state/pr-watch", "log": "~/Library/Logs/pr-watch.log",
//                  "slots": 5, "overdueMinutes": 45, "bitbucketWorkspace": "<workspace>" },
//     "roomLabels": { "others": "MAIN OFFICE", "review": "REVIEW ROOM", "lounge": "LOUNGE" } }
// Without a "reviews" block the review room is shown empty.
// Settings (⌘,): "Keep on top", "Play a sound" and "Energy saver", all off unless turned on.
//
// Cost: the app runs at background priority (it yields to everything you do), reads its state
// files only while the window is actually visible on screen (not minimised, hidden or covered),
// and the page redraws at most 6 times a second (2 with Energy saver), never while hidden.
// Agent Office → Check Setup… says whether the hook is registered and reporting.

import Cocoa
import WebKit
import ServiceManagement

let home = FileManager.default.homeDirectoryForCurrentUser.path
/// "agent-office", or "agent-office-dev" in the dev app (scripts/build-app.sh --dev): its own config
/// folder, so a build being tried never touches the installed app's room, name or picture.
let APP_SLUG = Bundle.main.object(forInfoDictionaryKey: "AgentOfficeSlug") as? String ?? "agent-office"
let CONFIG_DIR = home + "/.config/" + APP_SLUG
let CONFIG_SHOWN = "~/.config/" + APP_SLUG
func expand(_ p: String) -> String { p.hasPrefix("~/") ? home + p.dropFirst(1) : p }

struct Config {
    var officeState = home + "/.local/state/agent-office"
    var reviewState: String? = nil
    var reviewLog: String? = nil
    var slots = 5
    var overdueMinutes = 45                               // a review desk running longer is flagged; 0: never
    var workspace = ""
    var managerName = ""
    var managerImage = ""
    var room = RoomConfig()
    var roomOff = false                                   // "enabled": false in the room block
    var roomLabels: [String: String] = [:]                // "roomLabels": the plaques on the walls

    /// KEY=VALUE lines from ~/.config/agent-office/env, then the process environment on top. An app
    /// opened from the Finder or the Dock does not see a shell's exports, so the file is the way
    /// to set these for it.
    static func env() -> [String: String] {
        var e: [String: String] = [:]
        if let t = try? String(contentsOfFile: CONFIG_DIR + "/env", encoding: .utf8) {
            for line in t.split(separator: "\n") {
                let l = line.trimmingCharacters(in: .whitespaces)
                guard !l.hasPrefix("#"), let eq = l.firstIndex(of: "=") else { continue }
                var k = String(l[..<eq]).trimmingCharacters(in: .whitespaces)
                if k.hasPrefix("export ") { k = String(k.dropFirst(7)).trimmingCharacters(in: .whitespaces) }
                var v = String(l[l.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                if v.count >= 2, (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) { v = String(v.dropFirst().dropLast()) }
                e[k] = v
            }
        }
        for (k, v) in ProcessInfo.processInfo.environment where k.hasPrefix("AGENT_OFFICE_") { e[k] = v }
        return e
    }

    /// config.json, then the env file and the process environment on top of it. The env is
    /// applied by a plain call on the way out: changes made in a `defer` after `return c` would be
    /// made to a copy and lost.
    static func load() -> Config {
        var c = Config.fromJSON()
        let env = Config.env()
        if let s = env["AGENT_OFFICE_MANAGER_NAME"], !s.isEmpty { c.managerName = s }
        if let s = env["AGENT_OFFICE_MANAGER_IMAGE"], !s.isEmpty { c.managerImage = expand(s) }
        if let s = env["AGENT_OFFICE_ROOM_NAME"], !s.isEmpty { c.room.name = s }
        if let s = env["AGENT_OFFICE_ROOM_PASSWORD"], !s.isEmpty { c.room.password = s }
        if let s = env["AGENT_OFFICE_ROOM_HOST"] { c.room.host = ["1", "true", "yes"].contains(s.lowercased()) }
        if let s = env["AGENT_OFFICE_ROOM_ALWAYS_JOIN"] { c.room.alwaysJoin = !["0", "false", "no"].contains(s.lowercased()) }
        if let s = env["AGENT_OFFICE_ROOM_ENABLED"] { c.roomOff = ["0", "false", "no"].contains(s.lowercased()) }
        if let s = env["AGENT_OFFICE_ROOM_ADDRESS"], !s.isEmpty { c.room.address = s }
        if let s = env["AGENT_OFFICE_ROOM_PORT"], let p = UInt16(s) { c.room.port = p }
        return c
    }

    private static func fromJSON() -> Config {
        var c = Config()
        let url = URL(fileURLWithPath: CONFIG_DIR + "/config.json")
        guard let data = try? Data(contentsOf: url),
              let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return c }
        if let s = j["officeState"] as? String { c.officeState = expand(s) }
        if let r = j["reviews"] as? [String: Any] {
            if let s = r["state"] as? String { c.reviewState = expand(s) }
            if let s = r["log"] as? String { c.reviewLog = expand(s) }
            if let n = r["slots"] as? Int { c.slots = n }
            if let n = r["overdueMinutes"] as? Int { c.overdueMinutes = max(0, n) }
            if let w = r["bitbucketWorkspace"] as? String { c.workspace = w }
        }
        if let m = j["manager"] as? [String: Any] {
            if let s = m["name"] as? String { c.managerName = s }
            if let s = m["image"] as? String { c.managerImage = expand(s) }
        }
        if let l = j["roomLabels"] as? [String: Any] {
            // only the three rooms, a short line each: anything else is ignored
            for k in ["others", "review", "lounge"] {
                if let s = l[k] as? String {
                    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { c.roomLabels[k] = t.count > 24 ? String(t.prefix(23)) + "…" : t }   // cut: it says so
                }
            }
        }
        if let r = j["room"] as? [String: Any] {
            if let s = r["name"] as? String { c.room.name = s }
            if let s = r["password"] as? String { c.room.password = s }
            if let b = r["host"] as? Bool { c.room.host = b }
            if let b = r["alwaysJoin"] as? Bool { c.room.alwaysJoin = b }
            if let b = r["enabled"] as? Bool { c.roomOff = !b }
            if let s = r["address"] as? String { c.room.address = s }
            if let n = r["port"] as? Int, n > 0, n < 65536 { c.room.port = UInt16(n) }
        }
        return c
    }
}

/// Is that process alive? (EPERM means it exists but belongs to someone else.)
func alive(_ pid: Int) -> Bool { pid > 0 && (kill(pid_t(pid), 0) == 0 || errno == EPERM) }

func lines(_ path: String, tailBytes: Int = 0) -> [String] {
    guard let fh = FileHandle(forReadingAtPath: path) else { return [] }
    defer { try? fh.close() }
    if tailBytes > 0, let end = try? fh.seekToEnd(), end > UInt64(tailBytes) {
        try? fh.seek(toOffset: end - UInt64(tailBytes))
    }
    let data = (try? fh.readToEnd()) ?? Data()
    var out = String(decoding: data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    if tailBytes > 0, !out.isEmpty { out.removeFirst() }   // the first line may be cut in half
    return out
}

/// The manager's picture as a small PNG data URL: scaled to at most `maxH` px high (160 for the
/// manager's room, less for the shared room), so it costs a few KB however large the file is.
/// Cached by path, size and modification time.
var imageCache: [String: String] = [:]
func managerImageURL(_ path: String, maxH: Int = 160) -> String {
    guard !path.isEmpty, let attrs = try? FileManager.default.attributesOfItem(atPath: path),
          let m = attrs[.modificationDate] as? Date else { return "" }
    let key = path + "@" + String(m.timeIntervalSince1970) + "@" + String(maxH)
    if let hit = imageCache[key] { return hit }
    var url = ""
    if let img = NSImage(contentsOfFile: path),
       let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil), cg.height > 0 {
        let h = min(maxH, cg.height), w = max(1, cg.width * h / cg.height)
        if let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.interpolationQuality = .high
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            if let small = ctx.makeImage(),
               let png = NSBitmapImageRep(cgImage: small).representation(using: .png, properties: [:]) {
                url = "data:image/png;base64," + png.base64EncodedString()
            }
        }
    }
    imageCache = imageCache.filter { !$0.key.hasSuffix("@" + String(maxH)) }   // one picture per size: an old one is dropped
    imageCache[key] = url
    return url
}

func snapshot(_ cfg: Config) -> [String: Any] {
    let fm = FileManager.default
    var sessions: [[String: Any]] = []
    let sdir = cfg.officeState + "/sessions"
    let now = Date().timeIntervalSince1970
    for name in (try? fm.contentsOfDirectory(atPath: sdir)) ?? [] where name.hasSuffix(".json") {
        let path = sdir + "/" + name
        guard let data = fm.contents(atPath: path),
              let s = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
        let pid = (s["pid"] as? Int) ?? 0
        let updated = (s["updated"] as? Double) ?? (s["updated"] as? Int).map(Double.init) ?? 0
        // A session whose Claude process is gone ended without saying so: forget it.
        if pid > 0 ? !alive(pid) : now - updated > 12 * 3600 {
            try? fm.removeItem(atPath: path); continue
        }
        // the file's mtime is the session's heartbeat (the hook touches it on every event)
        var s2 = s
        if let m = (try? fm.attributesOfItem(atPath: path))?[.modificationDate] as? Date { s2["beat"] = m.timeIntervalSince1970 }
        // what the optional companion mod reports from inside the session (context, cost, plan
        // usage, exact subagent states); absent without the mod
        let livePath = cfg.officeState + "/live/" + name
        if let d = fm.contents(atPath: livePath), let live = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
            s2["live"] = live
        }
        sessions.append(s2)
    }
    // live files of sessions that are gone
    let liveIds = Set(sessions.compactMap { ($0["id"] as? String).map { $0 + ".json" } })
    for name in (try? fm.contentsOfDirectory(atPath: cfg.officeState + "/live")) ?? [] where !liveIds.contains(name) {
        let p = cfg.officeState + "/live/" + name
        if let m = (try? fm.attributesOfItem(atPath: p))?[.modificationDate] as? Date, now - m.timeIntervalSince1970 > 120 {
            try? fm.removeItem(atPath: p)
        }
    }
    var reviews: [String] = [], queue: [String] = [], reviewLog: [String] = []
    if let rs = cfg.reviewState {
        for name in (try? fm.contentsOfDirectory(atPath: rs + "/running")) ?? [] {
            guard let l = lines(rs + "/running/" + name).first else { continue }
            let f = l.split(separator: "\t", omittingEmptySubsequences: false)
            if f.count >= 7, let pid = Int(f[6]), alive(pid) { reviews.append(l) }
        }
        queue = lines(rs + "/queue")
    }
    if let rl = cfg.reviewLog {
        // the last 120 lines, or more when today has more (as far as the tail goes): the whiteboard counts the day
        reviewLog = lines(rl, tailBytes: 24_000)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let day = f.string(from: Date()), todays = reviewLog.reversed().prefix { $0.hasPrefix(day) }.count
        reviewLog = Array(reviewLog.suffix(max(120, todays)))
    }
    return [
        "now": now, "slots": cfg.slots, "overdueMinutes": cfg.overdueMinutes, "workspace": cfg.workspace,
        "sessions": sessions, "reviews": reviews, "queue": queue,
        "officeEvents": Array(lines(cfg.officeState + "/events.log", tailBytes: 16_000).suffix(60)),
        "reviewLog": reviewLog,
        "manager": ["name": cfg.managerName, "image": managerImageURL(cfg.managerImage)],
        "roomLabels": cfg.roomLabels,
    ]
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, NSWindowDelegate {
    var window: NSWindow!
    var web: WKWebView!
    var settings: NSWindow?
    var timer: Timer?
    let defaults = UserDefaults.standard

    var keepOnTop: Bool {
        get { defaults.bool(forKey: "keepOnTop") }          // false until turned on in Settings
        set { defaults.set(newValue, forKey: "keepOnTop"); applyKeepOnTop() }
    }
    var sound: Bool {
        get { defaults.bool(forKey: "sound") }              // false until turned on in Settings
        set { defaults.set(newValue, forKey: "sound") }
    }
    var energySaver: Bool {
        get { defaults.bool(forKey: "energySaver") }        // false until turned on in Settings
        set { defaults.set(newValue, forKey: "energySaver"); push() }
    }
    // One exit watcher per session process: the window updates the moment a session's process
    // ends, instead of at the next poll.
    var exitWatch: [Int: DispatchSourceProcess] = [:]

    // ---- the shared room ----
    // On when the config names a room with a password, it is not turned off there ("enabled":
    // false), and "Join the shared room" is ticked in Settings (on by default).
    var roomHost: RoomHost?
    var roomClient: RoomClient?
    var roomRunning = RoomConfig()
    var roomMembersSent = -1
    var managerImageSent: String?
    var lastPoke: [String: Date] = [:]                   // who poked you last, and when (RoomSetup.swift)
    var shaking = false
    var settingsRoomLabel: NSTextField?
    var settingsSigningLabel: NSTextField?, settingsSigningButton: NSButton?
    // ---- updates ----
    let updater = Updater()
    let jukebox = Jukebox()                              // the lounge's jukebox (Jukebox.swift)
    var updateTimer: Timer?
    // ---- the terminal under the office (Terminal.swift) ----
    let terminal = TerminalPane()
    var split: OfficeSplit!
    var terminalShown: Bool {
        get { defaults.bool(forKey: "terminalShown") }      // false until turned on from the View menu
        set { defaults.set(newValue, forKey: "terminalShown") }
    }
    var manualCheck = false
    var checkUpdates: Bool {
        get { defaults.bool(forKey: "checkUpdates") }        // false until turned on in Settings
        set { defaults.set(newValue, forKey: "checkUpdates"); if newValue { updater.check() } else { pushUpdate() } }
    }
    var roomSharing: Bool {
        get { defaults.object(forKey: "roomSharing") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "roomSharing"); syncRoom() }
    }

    func applicationDidFinishLaunching(_ n: Notification) {
        setpriority(PRIO_PROCESS, 0, 10)                     // background priority: yield to real work
        buildMenu()
        let conf = WKWebViewConfiguration()
        conf.userContentController.add(self, name: "office")
        web = WKWebView(frame: .zero, configuration: conf)
        web.setValue(false, forKey: "drawsBackground")
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 480),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Agent Office"
        window.minSize = NSSize(width: 380, height: 300)
        split = OfficeSplit(office: web, terminal: terminal.view)
        split.autosaveName = "AgentOfficeTerminal"           // remembers where the divider was
        terminal.view.isHidden = !terminalShown
        window.contentView = split
        window.delegate = self
        if terminalShown { terminal.load() }
        // Catch up at once when the window comes back into view.
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main) { [weak self] _ in self?.push() }
        window.backgroundColor = NSColor(red: 0.11, green: 0.10, blue: 0.15, alpha: 1)
        window.center()
        window.setFrameAutosaveName("AgentOfficeMain")       // remembers size and position
        applyKeepOnTop()
        if let page = Bundle.main.url(forResource: "office", withExtension: "html") {
            web.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        decideWelcome()                                      // before the env import: it looks at what was set up before
        importEnvOnce()                                      // before the first look at the room (RoomSetup.swift)
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.syncRoom(); self?.push() }
        syncRoom()
        updater.onChange = { [weak self] in self?.pushUpdate() }
        jukebox.onChange = { [weak self] in self?.push() }
        // once a day, when turned on: at launch if the last look is a day old, then hourly re-checks of that
        let daily = { [weak self] in
            guard let self, self.checkUpdates else { return }
            let last = self.defaults.double(forKey: "updateLastCheck")
            if Date().timeIntervalSince1970 - last > 24 * 3600 || self.updater.status == "idle" { self.updater.check() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: daily)
        updateTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in daily() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.push() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ n: Notification) { terminal.stop() }

    /// Show or hide the terminal under the office. Hiding it leaves the shell running.
    @objc func toggleTerminal(_ sender: NSMenuItem) {
        terminalShown.toggle()
        sender.state = terminalShown ? .on : .off
        if terminalShown {
            terminal.view.isHidden = false
            split.adjustSubviews()
            // first time, or a remembered height that no longer fits: a third of the window
            let h = split.bounds.height, th = terminal.view.frame.height
            if th < OfficeSplit.terminalMin || h - th < OfficeSplit.officeMin {
                split.setPosition(h - max(OfficeSplit.terminalMin, (h / 3).rounded()), ofDividerAt: 0)
            }
            terminal.load()
            terminal.focus()
        } else {
            terminal.view.isHidden = true
            split.adjustSubviews()
            window.makeFirstResponder(web)
        }
    }

    func push() {
        // Nothing on screen (minimised, hidden, or covered by other windows): skip the work.
        guard window.isVisible, !window.isMiniaturized, window.occlusionState.contains(.visible) else { return }
        var snap = snapshot(Config.load())
        snap["settings"] = ["energySaver": energySaver, "welcome": !defaults.bool(forKey: "welcomed")]
        snap["jukebox"] = jukebox.snapshot
        snap["hidden"] = defaults.string(forKey: "hidden") ?? "{}"
        // the manager's picture only when it changed: it is most of a snapshot otherwise
        if var m = snap["manager"] as? [String: Any], let img = m["image"] as? String {
            m["hasImage"] = !img.isEmpty
            if img == managerImageSent { m.removeValue(forKey: "image") } else { managerImageSent = img }
            snap["manager"] = m
        }
        watchExits(snap)
        guard let data = try? JSONSerialization.data(withJSONObject: snap),
              let json = String(data: data, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.updateOffice && updateOffice(\(json))", completionHandler: nil)
    }

    /// Start, stop or restart the room host and the member connection to match the config.
    func syncRoom() {
        let cfg = Config.load()
        let want = cfg.room.enabled && !cfg.roomOff && roomSharing ? cfg.room : RoomConfig()
        guard want != roomRunning else { return }
        roomHost?.stop(); roomHost = nil
        roomClient?.stop(); roomClient = nil
        roomRunning = want
        roomMembersSent = -1
        if want.enabled {
            if want.host { let h = RoomHost(want); h.scoresFile = CONFIG_DIR + "/leaderboard.json"; h.start(); roomHost = h }
            let c = RoomClient(want) {
                let cfg = Config.load()
                return (cfg.managerName.isEmpty ? "Teammate" : cfg.managerName, managerImageURL(cfg.managerImage, maxH: 96))
            }
            c.onChange = { [weak self] in self?.pushRoom() }
            c.onPoked = { [weak self] name in self?.poked(by: name) }
            c.onGame = { [weak self] msg in self?.gameIn(msg) }            // Games.swift
            c.setBadge(defaults.string(forKey: "gameBadge") ?? "")
            // the host's own member waits a moment for its listener to be advertised
            DispatchQueue.main.asyncAfter(deadline: .now() + (want.host ? 1.5 : 0)) { c.start() }
            roomClient = c
        }
        pushRoom()
    }
    /// The room's state to the page; the members' pictures only when the member list changed.
    func pushRoom() {
        // off: say whether a room is set up at all, so the page offers Create / Join or only Join
        let r = Config.load().room
        var o: [String: Any] = ["status": "off", "name": r.enabled ? r.name : "", "sharing": roomSharing]
        if let c = roomClient {
            let fresh = c.membersVersion != roomMembersSent
            o = c.json(withMembers: fresh)
            roomMembersSent = c.membersVersion
        }
        guard let d = try? JSONSerialization.data(withJSONObject: o), let json = String(data: d, encoding: .utf8) else { return }
        web.evaluateJavaScript("window.updateRoom && updateRoom(\(json))", completionHandler: nil)
    }

    /// The update button's state, to the page. Nothing to show while checking is off and no
    /// check was asked for by hand.
    func pushUpdate() {
        var o = updater.json
        if !checkUpdates && !manualCheck && updater.status != "updating" { o["status"] = "idle" }
        guard let d = try? JSONSerialization.data(withJSONObject: o), let json = String(data: d, encoding: .utf8) else { return }
        web?.evaluateJavaScript("window.updateUpdate && updateUpdate(\(json))", completionHandler: nil)
    }
    @objc func checkForUpdates() {
        manualCheck = true
        updater.check { [weak self] in
            guard let self else { return }
            let a = NSAlert()
            switch self.updater.status {
            case "available":
                // asked for by hand, so offer to do it right here; the same update as the button
                let build = self.updater.json["canBuild"] as? Bool ?? false
                a.messageText = "Agent Office \(self.updater.latest) is available"
                a.informativeText = "You have \(self.updater.current). " + (build
                    ? "Update Now rebuilds Agent Office from the new release and reopens it."
                    : "This copy was not built from a checkout, so it cannot rebuild itself: open the release page to get it.")
                a.addButton(withTitle: build ? "Update Now" : "Open Release Page")
                a.addButton(withTitle: "Later")
                if a.runModal() == .alertFirstButtonReturn { self.offerSigning { self.updater.update() } }
                return
            case "current": a.messageText = "Agent Office is up to date"; a.informativeText = "You have \(self.updater.current), the latest release."
            default: a.messageText = "Could not check for updates"; a.informativeText = self.updater.detail
            }
            a.runModal()
        }
    }

    func watchExits(_ snap: [String: Any]) {
        let pids = Set(((snap["sessions"] as? [[String: Any]]) ?? []).compactMap { $0["pid"] as? Int }.filter { $0 > 0 })
        for (pid, src) in exitWatch where !pids.contains(pid) { src.cancel(); exitWatch[pid] = nil }
        for pid in pids where exitWatch[pid] == nil {
            let src = DispatchSource.makeProcessSource(identifier: pid_t(pid), eventMask: .exit, queue: .main)
            src.setEventHandler { [weak self] in self?.exitWatch[pid]?.cancel(); self?.exitWatch[pid] = nil; self?.push() }
            src.resume()
            exitWatch[pid] = src
        }
    }

    // office.html asks to open a PR (https only), reveal a session's folder, chime, or keep the
    // list of agents hidden from view (a small JSON object it reads back in every snapshot).
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {
        guard let body = m.body as? [String: String] else { return }
        if let h = body["hidden"], h.utf8.count < 64_000 { defaults.set(h, forKey: "hidden") }
        if let kind = body["chime"], sound {
            NSSound(named: kind == "waiting" ? "Glass" : "Pop")?.play()
        }
        if let u = body["open"], let url = URL(string: u), url.scheme == "https" { NSWorkspace.shared.open(url) }
        if let p = body["reveal"], FileManager.default.fileExists(atPath: p) {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
        }
        if let id = body["focus"], id.range(of: "^[A-Za-z0-9-]{1,80}$", options: .regularExpression) != nil { focusSession(id) }
        if let t = body["say"] { roomClient?.say(t) }
        if let mid = body["edit"], let t = body["text"] { roomClient?.edit(mid, t) }   // your own message only
        if let mid = body["unsay"] { roomClient?.unsay(mid) }
        if let sp = body["spot"] { roomClient?.setSpot(sp) }
        if let a = body["act"] {                                  // "kind|member id"
            let parts = a.split(separator: "|", maxSplits: 1).map(String.init)
            if parts.count == 2 { roomClient?.act(parts[0], to: parts[1]) }
        }
        gameMessage(body)                                                   // Games.swift
        if body["update"] == "go" { DispatchQueue.main.async { self.offerSigning { self.updater.update() } } }   // Signing.swift
        if body["welcome"] == "done" { defaults.set(true, forKey: "welcomed") }
        if let j = body["jukebox"] { jukebox.control(j) }   // previous | playpause | next
        if body["profile"] == "edit" { DispatchQueue.main.async { self.editProfile() } }   // after this message returns
        if let r = body["room"] {
            if r == "ready" { roomMembersSent = -1; managerImageSent = nil; pushRoom(); pushUpdate() }   // the page (re)loaded: send everything
            if r == "join" { roomClient?.join() }
            // the page's buttons; the dialogs run after this message returns
            if r == "create" { DispatchQueue.main.async { self.createRoom() } }
            if r == "setup" { DispatchQueue.main.async { self.joinRoom() } }
            if r == "leave" { DispatchQueue.main.async { self.leaveRoom() } }
            if r == "share" { roomSharing = true }
        }
        if let t = body["copy"], t.count < 200 {
            NSPasteboard.general.clearContents(); NSPasteboard.general.setString(t, forType: .string)
        }
    }

    // ---- bringing a session to the front, where it runs ----
    // The hook records where each session started (origin: app, bundle, tty). Terminal and iTerm
    // tabs are found by their terminal device; a VS Code panel session by the extension's own
    // link; a VS Code terminal and the Claude app can only be brought forward as a window.
    func focusSession(_ id: String) {
        let path = Config.load().officeState + "/sessions/" + id + ".json"
        guard let d = FileManager.default.contents(atPath: path),
              let s = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        let o = s["origin"] as? [String: Any] ?? [:]
        let app = o["app"] as? String ?? "", bundle = o["bundle"] as? String ?? ""
        let tty = o["tty"] as? String ?? "", cwd = s["cwd"] as? String ?? ""
        let safeTTY = tty.range(of: "^/dev/ttys[0-9]+$", options: .regularExpression) != nil ? tty : ""
        switch app {
        case "terminal" where !safeTTY.isEmpty:
            osascript("""
            tell application "Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is "\(safeTTY)" then
                    set selected tab of w to t
                    set index of w to 1
                    activate
                    return
                  end if
                end repeat
              end repeat
              activate
            end tell
            """)
        case "iterm" where !safeTTY.isEmpty:
            osascript("""
            tell application "iTerm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    if tty of s is "\(safeTTY)" then
                      select w
                      tell t to select
                      tell s to select
                      activate
                      return
                    end if
                  end repeat
                end repeat
              end repeat
              activate
            end tell
            """)
        case "vscode-panel":
            focusEditorWindow(bundle: bundle.isEmpty ? "com.microsoft.VSCode" : bundle, folder: cwd) {
                let scheme = bundle.lowercased().contains("todesktop") ? "cursor" : "vscode"
                if let u = URL(string: "\(scheme)://anthropic.claude-code/open?session=\(id)") { NSWorkspace.shared.open(u) }
            }
        case "vscode-terminal":
            focusEditorWindow(bundle: bundle.isEmpty ? "com.microsoft.VSCode" : bundle, folder: cwd) {}
        case "desktop":
            // The Claude app opens one of its sessions by the id it gave it (`local_…`), which the
            // hook records from CLAUDE_CODE_HOST_SESSION_ID.
            let host = o["host"] as? String ?? ""
            if host.range(of: "^local_[A-Za-z0-9-]{1,64}$", options: .regularExpression) != nil,
               let u = URL(string: "claude://code/continue?session=\(host)") {
                NSWorkspace.shared.open(u); return
            }
            if !bundle.isEmpty, activate(bundle: bundle) { return }
        default:
            if !bundle.isEmpty, activate(bundle: bundle) { return }
            if FileManager.default.fileExists(atPath: cwd) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: cwd)]) }
        }
    }

    @discardableResult func activate(bundle: String) -> Bool {
        guard let a = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first else { return false }
        return a.activate()
    }

    // Bring forward the editor window whose workspace folder holds `folder`. VS Code and its
    // forks list their open windows' folders in User/globalStorage/storage.json; opening the
    // deepest folder that contains the session's directory focuses that window instead of
    // starting a new one, and needs no permission. A folder no open window holds is never opened
    // (that would create a window): the title match below is the fallback. `then` runs once the
    // window is in front.
    func focusEditorWindow(bundle: String, folder: String, then: @escaping () -> Void) {
        if let root = editorWindowFolder(bundle: bundle, containing: folder) {
            DispatchQueue.global(qos: .userInitiated).async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = ["-b", bundle, root]
                p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
                try? p.run(); p.waitUntilExit()
                // the window has to be the last active one before a vscode:// link is opened,
                // because the editor hands such a link to its last active window
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: then)
            }
            return
        }
        raiseWindow(bundle: bundle, folder: folder, then: then)
    }

    func editorWindowFolder(bundle: String, containing folder: String) -> String? {
        let b = bundle.lowercased()
        let dir = b.contains("todesktop") ? "Cursor"
            : b.contains("insiders") ? "Code - Insiders"
            : b.contains("vscodium") ? "VSCodium"
            : b.contains("windsurf") ? "Windsurf"
            : "Code"
        let path = NSHomeDirectory() + "/Library/Application Support/\(dir)/User/globalStorage/storage.json"
        guard !folder.isEmpty, let d = FileManager.default.contents(atPath: path),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let ws = j["windowsState"] as? [String: Any] else { return nil }
        var wins = ws["openedWindows"] as? [[String: Any]] ?? []
        if let last = ws["lastActiveWindow"] as? [String: Any] { wins.append(last) }
        let target = URL(fileURLWithPath: folder).standardizedFileURL.path
        var best: String?
        for w in wins {
            guard let f = w["folder"] as? String, let u = URL(string: f), u.isFileURL else { continue }
            let root = u.standardizedFileURL.path
            guard target == root || target.hasPrefix(root.hasSuffix("/") ? root : root + "/") else { continue }
            if root.count > (best?.count ?? -1) { best = root }
        }
        return best
    }

    // Raise the app's window whose title names one of the session folder's names (the folder,
    // then its parents): VS Code titles end with the workspace name. Needs Accessibility for
    // System Events; without it the app is just brought forward. `then` runs afterwards.
    func raiseWindow(bundle: String, folder: String, then: @escaping () -> Void) {
        activate(bundle: bundle)
        let names = folder.split(separator: "/").suffix(4).reversed()
            .map { String($0).replacingOccurrences(of: "\"", with: "") }
            .filter { !$0.isEmpty }
            .map { "\"\($0)\"" }.joined(separator: ", ")
        let safeBundle = bundle.replacingOccurrences(of: "\"", with: "")
        osascript("""
        tell application "System Events"
          set p to first process whose bundle identifier is "\(safeBundle)"
          repeat with n in {\(names)}
            repeat with w in windows of p
              set t to name of w
              if t ends with (" — " & n) or t is n or t contains (" — " & n & " ") then
                perform action "AXRaise" of w
                set frontmost of p to true
                return
              end if
            end repeat
          end repeat
        end tell
        """, then: then)
    }

    func osascript(_ source: String, then: (() -> Void)? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            p.arguments = ["-e", source]
            p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
            try? p.run(); p.waitUntilExit()
            if let then { DispatchQueue.main.async(execute: then) }
        }
    }

    func applyKeepOnTop() {
        window?.level = keepOnTop ? .floating : .normal
        window?.collectionBehavior = keepOnTop ? [.canJoinAllSpaces, .fullScreenAuxiliary] : []
    }

    // ---- the welcome tour ----
    // The page shows it while "welcomed" is false: what the office is, then your name and picture,
    // then a room, each step skippable. Someone who used the app before this existed (an env
    // import already ran, or a name, picture or room is set up) is counted as welcomed and never
    // sees it; Agent Office → Welcome Tour… shows it to anyone.
    func decideWelcome() {
        guard defaults.object(forKey: "welcomed") == nil else { return }
        let cfg = Config.load()
        let before = defaults.object(forKey: "envImported") != nil || !cfg.managerName.isEmpty
            || !cfg.managerImage.isEmpty || !cfg.room.name.isEmpty
        defaults.set(before, forKey: "welcomed")
    }
    @objc func showWelcome() {
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        web.evaluateJavaScript("window.showWelcome && showWelcome()", completionHandler: nil)
    }

    // ---- menu and settings ----
    func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let app = NSMenu()
        app.addItem(withTitle: "About Agent Office", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        app.addItem(withTitle: "Your Name and Picture…", action: #selector(editProfile), keyEquivalent: "")
        app.addItem(withTitle: "Welcome Tour…", action: #selector(showWelcome), keyEquivalent: "")
        app.addItem(withTitle: "Check Setup…", action: #selector(checkSetup), keyEquivalent: "")
        app.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        app.addItem(.separator())
        app.addItem(withTitle: "Hide Agent Office", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        app.addItem(withTitle: "Quit Agent Office", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        // the text fields in the dialogs get their keyboard shortcuts (⌘V, ⌘C, ⌘X, ⌘A, ⌘Z) from
        // this menu: without it pasting into them does nothing
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        let viewItem = NSMenuItem(); main.addItem(viewItem)
        let view = NSMenu(title: "View")
        let term = view.addItem(withTitle: "Terminal", action: #selector(toggleTerminal(_:)), keyEquivalent: "`")
        term.keyEquivalentModifierMask = [.control]
        term.state = terminalShown ? .on : .off
        viewItem.submenu = view
        let roomItem = NSMenuItem(); main.addItem(roomItem)
        let rm = NSMenu(title: "Room")
        rm.addItem(withTitle: "Create a Room…", action: #selector(createRoom), keyEquivalent: "")
        rm.addItem(withTitle: "Join a Room…", action: #selector(joinRoom), keyEquivalent: "")
        rm.addItem(.separator())
        rm.addItem(withTitle: "Mini-Games…", action: #selector(showGames), keyEquivalent: "")
        rm.addItem(.separator())
        rm.addItem(withTitle: "Leave the Room", action: #selector(leaveRoom), keyEquivalent: "")
        roomItem.submenu = rm
        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winItem.submenu = win
        NSApp.mainMenu = main
        NSApp.windowsMenu = win
    }

    @objc func showSettings() {
        if settings == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 700),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Agent Office Settings"
            w.isReleasedWhenClosed = false
            let box = NSButton(checkboxWithTitle: "Keep the window on top of other windows", target: self, action: #selector(toggleTop(_:)))
            box.state = keepOnTop ? .on : .off
            box.frame = NSRect(x: 20, y: 270, width: 350, height: 22)
            let hint = NSTextField(wrappingLabelWithString: "Off by default. When on, the office floats above other apps and follows you across Spaces.")
            hint.frame = NSRect(x: 38, y: 234, width: 320, height: 32)
            let snd = NSButton(checkboxWithTitle: "Play a sound when an agent needs you or finishes", target: self, action: #selector(toggleSound(_:)))
            snd.state = sound ? .on : .off
            snd.frame = NSRect(x: 20, y: 198, width: 350, height: 22)
            let hint2 = NSTextField(wrappingLabelWithString: "Off by default. \u{201C}Glass\u{201D} when one waits for your permission, \u{201C}Pop\u{201D} when one finishes its turn.")
            hint2.frame = NSRect(x: 38, y: 162, width: 320, height: 32)
            let eco = NSButton(checkboxWithTitle: "Energy saver", target: self, action: #selector(toggleEnergy(_:)))
            eco.state = energySaver ? .on : .off
            eco.frame = NSRect(x: 20, y: 126, width: 350, height: 22)
            let hint3 = NSTextField(wrappingLabelWithString: "Off by default. Redraws 2 times a second instead of 6, with no walking or blinking.")
            hint3.frame = NSRect(x: 38, y: 90, width: 320, height: 32)
            let shr = NSButton(checkboxWithTitle: "Join the shared room", target: self, action: #selector(toggleRoom(_:)))
            shr.state = roomSharing ? .on : .off
            shr.frame = NSRect(x: 20, y: 342, width: 350, height: 22)
            let hint4 = NSTextField(wrappingLabelWithString: "On by default, when a room is set up in the config. Your lounge joins your teammates': names, pictures and chat. Nothing about your sessions is shared.")
            hint4.frame = NSRect(x: 38, y: 296, width: 320, height: 44)
            let lgn = NSButton(checkboxWithTitle: "Open at login", target: self, action: #selector(toggleLogin(_:)))
            lgn.state = SMAppService.mainApp.status == .enabled ? .on : .off
            lgn.frame = NSRect(x: 20, y: 414, width: 350, height: 22)
            let hint5 = NSTextField(wrappingLabelWithString: "Off by default. Starts Agent Office when you log in, so a room you host is there after a restart. macOS may ask you to allow it in Login Items.")
            hint5.frame = NSRect(x: 38, y: 368, width: 320, height: 44)
            let upd = NSButton(checkboxWithTitle: "Check for updates once a day", target: self, action: #selector(toggleUpdates(_:)))
            upd.state = checkUpdates ? .on : .off
            upd.frame = NSRect(x: 20, y: 486, width: 350, height: 22)
            let hint6 = NSTextField(wrappingLabelWithString: "Off by default. Asks GitHub for the latest release; a newer one shows an Update button that rebuilds the app from it and reopens it.")
            hint6.frame = NSRect(x: 38, y: 440, width: 320, height: 44)
            let roomLbl = NSTextField(labelWithString: "")
            roomLbl.frame = NSRect(x: 20, y: 554, width: 200, height: 20)
            roomLbl.lineBreakMode = .byTruncatingTail
            settingsRoomLabel = roomLbl
            let del = NSButton(title: "Delete Saved Room…", target: self, action: #selector(deleteSavedRoom))
            del.bezelStyle = .rounded
            del.frame = NSRect(x: 220, y: 548, width: 145, height: 30)
            let prof = NSButton(title: "Change…", target: self, action: #selector(editProfile))
            prof.bezelStyle = .rounded
            prof.frame = NSRect(x: 220, y: 620, width: 145, height: 30)
            let sigL = NSTextField(labelWithString: "Keep permissions")
            sigL.frame = NSRect(x: 20, y: 662, width: 200, height: 20); sigL.lineBreakMode = .byTruncatingTail
            settingsSigningLabel = sigL
            let sig = NSButton(title: "Set Up…", target: self, action: #selector(setUpSigning))
            sig.bezelStyle = .rounded
            sig.frame = NSRect(x: 220, y: 656, width: 145, height: 30)
            settingsSigningButton = sig
            let profL = NSTextField(labelWithString: "Your name and picture")
            profL.frame = NSRect(x: 20, y: 626, width: 200, height: 20)
            let imp = NSButton(title: "Import from env file…", target: self, action: #selector(importFromEnv))
            imp.bezelStyle = .rounded
            imp.frame = NSRect(x: 220, y: 582, width: 145, height: 30)
            let impL = NSTextField(labelWithString: "Set up with the env file?")
            impL.frame = NSRect(x: 20, y: 588, width: 200, height: 20)
            let jbx = NSButton(checkboxWithTitle: "Jukebox in the lounge", target: self, action: #selector(toggleJukebox(_:)))
            jbx.state = jukebox.enabled ? .on : .off
            jbx.frame = NSRect(x: 20, y: 54, width: 350, height: 22)
            let hint8 = NSTextField(wrappingLabelWithString: "On by default. Shows what plays on this Mac (Spotify, Music, a video in a browser) with previous, play/pause and next.")
            hint8.frame = NSRect(x: 38, y: 18, width: 320, height: 32)
            let hint7 = NSTextField(wrappingLabelWithString: "A room you create or join is saved and joined again at every launch, until you change it or delete it here.")
            hint7.frame = NSRect(x: 20, y: 516, width: 340, height: 30)
            for h in [hint, hint2, hint3, hint4, hint5, hint6, hint7, hint8] { h.textColor = .secondaryLabelColor; h.font = .systemFont(ofSize: 11) }
            for v in [sigL, sig, profL, prof, impL, imp, roomLbl, del, hint7, upd, hint6, lgn, hint5, shr, hint4, box, hint, snd, hint2, eco, hint3, jbx, hint8] { w.contentView?.addSubview(v) }
            w.center()
            settings = w
        }
        refreshSettingsRoom(); refreshSettingsSigning()
        settings?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refreshSettingsRoom() {
        let r = Config.load().room
        settingsRoomLabel?.stringValue = r.name.isEmpty ? "Saved room: none" : "Saved room: \(r.name)\(r.host ? " (you host)" : "")"
    }
    @objc func toggleTop(_ sender: NSButton) { keepOnTop = sender.state == .on }
    @objc func toggleSound(_ sender: NSButton) { sound = sender.state == .on }
    @objc func toggleEnergy(_ sender: NSButton) { energySaver = sender.state == .on }
    @objc func toggleJukebox(_ sender: NSButton) { jukebox.enabled = sender.state == .on }
    @objc func toggleRoom(_ sender: NSButton) { roomSharing = sender.state == .on }
    @objc func toggleUpdates(_ sender: NSButton) { checkUpdates = sender.state == .on }
    // Open at login: registers this app as a login item with macOS. When macOS wants the person
    // to approve it first, it opens Login Items in System Settings.
    @objc func toggleLogin(_ sender: NSButton) {
        let svc = SMAppService.mainApp
        do {
            if sender.state == .on { try svc.register() } else { try svc.unregister() }
        } catch {
            let a = NSAlert(); a.messageText = "Could not change Open at login"
            a.informativeText = error.localizedDescription + "\n\nYou can add Agent Office in System Settings → General → Login Items."
            a.runModal()
        }
        if svc.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
        sender.state = svc.status == .enabled ? .on : .off
    }

    // Is the hook registered for every event, executable, and actually reporting?
    @objc func checkSetup() {
        let cfg = Config.load(), fm = FileManager.default
        var lines: [String] = []
        let needed = ["SessionStart", "UserPromptSubmit", "PermissionRequest", "Notification", "PostToolUse",
                      "PreCompact", "Stop", "StopFailure", "SubagentStart", "SubagentStop", "SessionEnd"]
        var hookPath: String?
        if let data = fm.contents(atPath: home + "/.claude/settings.json"),
           let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let hooks = j["hooks"] as? [String: Any] {
            var missing: [String] = []
            for e in needed {
                let cmds = ((hooks[e] as? [[String: Any]]) ?? []).flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }
                    .compactMap { $0["command"] as? String }.filter { $0.hasSuffix("agent-office-hook.sh") }
                if let c = cmds.first { hookPath = c } else { missing.append(e) }
            }
            lines.append(missing.isEmpty ? "✅ Hook registered for all \(needed.count) events."
                                         : "❌ Hook missing for: \(missing.joined(separator: ", ")). Run scripts/install-hook.sh.")
        } else { lines.append("❌ Could not read ~/.claude/settings.json.") }
        if let h = hookPath { lines.append(fm.isExecutableFile(atPath: h) ? "✅ Hook script is executable." : "❌ Hook script not found or not executable: \(h)") }
        let sdir = cfg.officeState + "/sessions"
        let files = ((try? fm.contentsOfDirectory(atPath: sdir)) ?? []).filter { $0.hasSuffix(".json") }
        let newest = ([cfg.officeState + "/events.log"] + files.map { sdir + "/" + $0 })
            .compactMap { (try? fm.attributesOfItem(atPath: $0))?[.modificationDate] as? Date }.max()
        if let n = newest {
            let f = RelativeDateTimeFormatter(); f.unitsStyle = .full
            lines.append("✅ Last report from a session: \(f.localizedString(for: n, relativeTo: Date())). Sessions on file: \(files.count).")
        } else { lines.append("⚠️ No session has reported yet. Sessions started after the hook was installed appear here.") }
        if let rs = cfg.reviewState {
            lines.append(fm.fileExists(atPath: rs) ? "✅ Review room reads \(rs)." : "⚠️ Review state folder not found: \(rs)")
        } else { lines.append("ℹ️ No review room configured (\(CONFIG_SHOWN)/config.json).") }
        let a = NSAlert(); a.messageText = "Agent Office setup"; a.informativeText = lines.joined(separator: "\n\n")
        a.runModal()
    }
}

// `AgentOffice --dump-snapshot` prints what the window would be given, and exits (for debugging).
if CommandLine.arguments.contains("--dump-snapshot") {
    let data = try! JSONSerialization.data(withJSONObject: snapshot(Config.load()), options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self)); exit(0)
}

// `AgentOffice --check-room` prints the room settings the app sees (config.json, the env file
// and the environment together; the password only as its length), and exits.
if CommandLine.arguments.contains("--check-room") {
    let c = Config.load(), r = c.room
    let sharing = UserDefaults.standard.object(forKey: "roomSharing") as? Bool ?? true
    let verdict = r.enabled && !c.roomOff && sharing ? "the app joins this room"
        : "the app joins NO room: " + (r.name.isEmpty ? "no room name" : r.password.isEmpty ? "no password"
            : c.roomOff ? "turned off in the config" : "Settings → Join the shared room is off")
    print("""
    room name:     \(r.name.isEmpty ? "(none)" : r.name)
    password:      \(r.password.isEmpty ? "(none)" : "set, \(r.password.count) characters")
    host:          \(r.host ? "yes, on port \(r.port)" : "no")
    address:       \(r.address.isEmpty ? "(none: by name only)" : r.address + (r.addressEndpoint == nil ? "  <- not a valid address" : ""))
    always join:   \(r.alwaysJoin ? "yes" : "no")
    Settings tick: \(sharing ? "on" : "off")
    → \(verdict)
    """)
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
