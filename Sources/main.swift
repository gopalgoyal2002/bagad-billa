import AppKit
import WebKit
import ApplicationServices
import CoreAudio

struct TypingActivity {
    var until = 0.0
    var presses: [Double] = []
    mutating func pulse(at time: Double) {
        until = time + 0.7
        presses = Array(presses.filter { time - $0 < 2 }.suffix(39)); presses.append(time)
    }
    func active(at time: Double) -> Bool { time < until }
    func cadence(at time: Double) -> Double {
        let rate = Double(presses.filter { time - $0 < 2 }.count) / 2
        return rate >= 6 ? 0.065 : rate >= 2.5 ? 0.12 : 0.22
    }
}

struct TerminalEvent: Decodable {
    let kind: String
    let code: Int
    let duration: Int
    let time: Double
    let session: String
    let app: String
    var valid: Bool {
        ["success","failure","attention"].contains(kind) && duration >= 0 && duration < 31536000 &&
        session.count <= 32 && session.allSatisfy { $0.isLetter || $0.isNumber } &&
        ["terminal","iterm","vscode","jetbrains","unknown"].contains(app)
    }
    var message: String {
        let label = session == "terminal" ? "Terminal" : session
        switch kind {
        case "success": return "\(label): command finished"
        case "failure": return "\(label): failed (\(code))"
        default: return "\(label): needs your help"
        }
    }
}

struct WalkReminder {
    var next = 0.0
    mutating func due(at now: Double, enabled: Bool) -> Bool {
        guard enabled, now >= next else { return false }
        next = now + 1200
        return true
    }
}

enum PetHome: String { case none, cushion, box }

struct LifeState {
    var lastActivity = 0.0
    var sleepAfter = 180.0
    var forcedNap = false
    var focusEnd: Double? = nil
    var nextBreak = 0.0
    var breakInterval = 1800.0
    mutating func activity(at now: Double) { lastActivity = now; forcedNap = false }
    func sleeping(at now: Double, autoSleep: Bool) -> Bool {
        (focusEnd.map { now < $0 } ?? false) || forcedNap || (autoSleep && now - lastActivity >= sleepAfter)
    }
    mutating func completeFocus(at now: Double) -> Bool {
        guard let end = focusEnd, now >= end else { return false }
        focusEnd = nil; activity(at: now); nextBreak = now + breakInterval; return true
    }
    mutating func breakDue(at now: Double, enabled: Bool, sleeping: Bool) -> Bool {
        guard enabled, focusEnd == nil, !sleeping, now >= nextBreak else { return false }
        nextBreak = now + breakInterval; return true
    }
}

struct Excursion {
    enum Kind { case treat, chase }
    var kind: Kind
    var origin: NSPoint
    var target: NSPoint
    var start: Double
    var duration: Double
    func position(at now: Double) -> NSPoint {
        let progress = min(1, max(0, (now-start)/duration))
        let travel = progress < 0.4 ? progress/0.4 : progress < 0.6 ? 1 : (1-progress)/0.4
        let eased = travel * travel * (3 - 2 * travel)
        return NSPoint(x: origin.x + (target.x-origin.x)*eased, y: origin.y + (target.y-origin.y)*eased)
    }
}

func direction(_ dx: Double, _ dy: Double) -> Int? {
    guard hypot(dx, dy) > 22 else { return nil }
    let degrees = atan2(dx, dy) * 180 / .pi
    return Int((degrees + 360).truncatingRemainder(dividingBy: 360) / 22.5 + 0.5) % 16
}

final class PetPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class PetView: NSView {
    var typingPhase: Int? = nil
    var home: PetHome = .none
    var homeDepth = 0.0
    var snoozing = false
    var happy = false
    var stretching = false
    var headphones = false
    var gazeDirection: Int? = nil
    var headphonesFitAvailable = true
    var clock = 0.0
    var caption: String? = nil
    var sprite: NSImage? { didSet { needsDisplay = true } }
    var downPoint = NSPoint.zero
    var downOrigin = NSPoint.zero
    var moved = false
    weak var owner: Companion?
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill()
        let sx = bounds.width / 192, sy = bounds.height / 208
        if home == .cushion {
            NSColor(calibratedRed: 0.35, green: 0.52, blue: 0.48, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 7*sx,y: 0,width: 178*sx,height: 30*sy)).fill()
            NSColor(calibratedRed: 0.53, green: 0.68, blue: 0.62, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 14*sx,y: 7*sy,width: 164*sx,height: 22*sy)).fill()
        } else if home == .box {
            NSColor(calibratedRed: 0.58, green: 0.36, blue: 0.19, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 12*sx,y: 2*sy,width: 168*sx,height: 67*sy), xRadius: 4*sx, yRadius: 4*sy).fill()
        }
        var body = bounds
        body.origin.y -= homeDepth * 17 * sy
        if snoozing { body.size.height -= (1 + sin(clock*1.8))*1.5*sy }
        if headphones && !snoozing { body.origin.y += sin(clock*4)*2*sy }
        if happy { body.origin.y += sin(clock*5)*1.2*sy }
        if stretching {
            let lift = max(0, sin(clock*2.5))
            body.size.height -= 8*sy; body.origin.y += lift*6*sy
        }
        sprite?.draw(in: body, from: .zero, operation: .sourceOver, fraction: 1)
        if headphones && headphonesFitAvailable {
            // Ear-cup centers in each original 192x208 sprite, bottom-left coordinates.
            // The far cup is hidden for profile poses; both cups share the body transform.
            let fits: [(Double,Double,Double,Double,Bool)] = [
                (43,183,125,183,false), (48,184,106,194,true),
                (49,180,113,193,true), (57,180,119,193,true),
                (96,183,119,181,true), (82,147,137,179,true),
                (63,144,135,171,true), (73,133,148,158,false),
                (39,158,125,158,false), (33,152,107,141,false),
                (38,185,108,157,true), (60,184,111,160,true),
                (43,183,94,166,true), (62,184,113,176,true),
                (65,187,121,179,true), (68,188,135,181,true)
            ]
            let f = gazeDirection.map { fits[$0] } ?? (43,181,128,181,false)
            let bx = body.width/192, by = body.height/208
            func point(_ x: Double,_ y: Double) -> NSPoint { NSPoint(x: body.minX+x*bx,y: body.minY+y*by) }
            let band = NSBezierPath()
            band.move(to: point(f.0,f.1))
            band.curve(to: point(f.2,f.3),controlPoint1: point(f.0-3,max(f.1,f.3)+(f.4 ? 10 : 22)),controlPoint2: point(f.2+3,max(f.1,f.3)+(f.4 ? 10 : 22)))
            NSColor(calibratedWhite: 0.19,alpha: 1).setStroke(); band.lineWidth = 6*bx; band.stroke()
            let visible = f.4 ? [(gazeDirection! < 8 ? f.0 : f.2,gazeDirection! < 8 ? f.1 : f.3)] : [(f.0,f.1),(f.2,f.3)]
            for (x,y) in visible {
                let center = point(x,y)
                let cup = NSRect(x: center.x-9*bx,y: center.y-13*by,width: 18*bx,height: 26*by)
                NSColor(calibratedWhite: 0.16,alpha: 1).setFill()
                NSBezierPath(roundedRect: cup,xRadius: 6*bx,yRadius: 6*by).fill()
                NSColor.systemTeal.setFill()
                NSBezierPath(roundedRect: cup.insetBy(dx: 4*bx,dy: 4*by),xRadius: 3*bx,yRadius: 3*by).fill()
            }
        }
        if home == .box {
            NSColor(calibratedRed: 0.76, green: 0.54, blue: 0.32, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 10*sx,y: 0,width: 172*sx,height: 39*sy),xRadius: 3*sx,yRadius: 3*sy).fill()
            NSColor(calibratedRed: 0.90, green: 0.73, blue: 0.48, alpha: 1).setFill()
            NSRect(x: 88*sx,y: 0,width: 16*sx,height: 39*sy).fill()
        }
        if snoozing { label("z z z", at: NSRect(x: 140*sx,y: 150*sy,width: 45*sx,height: 20*sy),size: 12*sx) }
        if happy { label("♡", at: NSRect(x: 140*sx,y: 155*sy,width: 36*sx,height: 25*sy),size: 22*sx) }
        if let phase = typingPhase {
            // Runtime vector keyboard; no typed characters are displayed or stored.
            let sx = bounds.width / 192, sy = bounds.height / 208
            let board = NSRect(x: 33*sx, y: 9*sy, width: 126*sx, height: 35*sy)
            NSColor(calibratedWhite: 0.22, alpha: 1).setFill()
            NSBezierPath(roundedRect: board, xRadius: 5*sx, yRadius: 5*sy).fill()
            for r in 0..<3 { for c in 0..<10 {
                let key = NSRect(x: (39+Double(c)*11.5)*sx, y: (14+Double(r)*8)*sy, width: 8.5*sx, height: 5.5*sy)
                (c == (phase % 2 == 0 ? 2 : 7) && r == 1 ? NSColor.systemTeal : NSColor(calibratedWhite: 0.68, alpha: 1)).setFill()
                NSBezierPath(roundedRect: key, xRadius: sx, yRadius: sy).fill()
            } }
            for side in 0..<2 {
                let lift = phase % 2 == side ? 0.0 : 7.0
                let paw = NSRect(x: (57+Double(side)*52)*sx, y: (28+lift)*sy, width: 24*sx, height: 18*sy)
                NSColor(calibratedRed: 0.95, green: 0.80, blue: 0.56, alpha: 1).setFill()
                let shape = NSBezierPath(ovalIn: paw); shape.fill()
                NSColor(calibratedRed: 0.62, green: 0.44, blue: 0.26, alpha: 1).setStroke()
                shape.lineWidth = 0.8*sx; shape.stroke()
            }
        }
        if let text = caption {
            let area = NSRect(x: 3*sx,y: bounds.height-22*sy,width: bounds.width-6*sx,height: 21*sy)
            NSColor(calibratedWhite: 0.12, alpha: 0.93).setFill()
            NSBezierPath(roundedRect: area, xRadius: 7*sx,yRadius: 7*sy).fill()
            label(text,at: area.insetBy(dx: 2*sx,dy: 3*sy),size: 10*sx,color: .white)
        }
    }
    func label(_ text: String, at rect: NSRect, size: Double, color: NSColor = .darkGray) {
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        (text as NSString).draw(in: rect,withAttributes: [.font: NSFont.systemFont(ofSize: size,weight: .medium),.foregroundColor: color,.paragraphStyle: paragraph])
    }
    override func mouseDown(with event: NSEvent) {
        owner?.beginDrag()
        downPoint = NSEvent.mouseLocation
        downOrigin = window?.frame.origin ?? .zero
        moved = false
    }
    override func mouseDragged(with event: NSEvent) {
        let point = NSEvent.mouseLocation
        let dx = point.x - downPoint.x, dy = point.y - downPoint.y
        guard hypot(dx, dy) > 3 else { return }
        moved = true
        window?.setFrameOrigin(NSPoint(x: downOrigin.x + dx, y: downOrigin.y + dy))
        owner?.play(dx < 0 ? 2 : 1, duration: 0.2)
    }
    override func mouseUp(with event: NSEvent) {
        if moved { owner?.screenChanged(); owner?.savePosition() }
        else if event.clickCount > 1 { owner?.play(4, duration: 0.9) }
        else { owner?.openTerminals() }
    }
    override func rightMouseDown(with event: NSEvent) {
        if let menu = owner?.menu { NSMenu.popUpContextMenu(menu, with: event, for: self) }
    }
}

final class TreatView: NSView {
    weak var owner: Companion?
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill()
        NSColor(calibratedRed: 0.93,green: 0.63,blue: 0.35,alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 9,y: 9,width: 29,height: 20)).fill()
        let tail = NSBezierPath(); tail.move(to: NSPoint(x: 11,y: 19)); tail.line(to: NSPoint(x: 1,y: 8));tail.line(to: NSPoint(x: 1,y: 30));tail.close();tail.fill()
        NSColor.black.setFill(); NSBezierPath(ovalIn: NSRect(x: 29,y: 20,width: 3,height: 3)).fill()
    }
    override func mouseDown(with event: NSEvent) { owner?.eatTreat() }
}

final class EmbeddedTerminal: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var web: WKWebView!
    var process: Process?
    let input = Pipe()
    let output = Pipe()
    let directory: URL
    let writer = DispatchQueue(label: "bagad.terminal.input")
    var closed = false
    var started = false
    var ready = false
    init(directory: URL) {
        self.directory = directory; super.init()
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        config.userContentController.add(self,name: "terminal")
        web = WKWebView(frame: .zero,configuration: config); web.navigationDelegate = self
        let folder = Bundle.main.resourceURL!.appendingPathComponent("terminal")
        web.loadFileURL(folder.appendingPathComponent("index.html"),allowingReadAccessTo: folder)
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let expected = Bundle.main.resourceURL!.appendingPathComponent("terminal/index.html").standardizedFileURL
        decisionHandler(navigationAction.request.url?.standardizedFileURL == expected ? .allow : .cancel)
    }
    func userContentController(_ userContentController: WKUserContentController,didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, !closed, let data = message.body as? [String:Any],let kind = data["kind"] as? String else { return }
        if kind == "ready" && !started { ready = true; start(); send(["kind":"resize","cols":data["cols"] ?? 80,"rows":data["rows"] ?? 24]) }
        else if kind == "input", let text = data["data"] as? String, text.utf8.count <= 1000000 { send(["kind":"input","data":Data(text.utf8).base64EncodedString()]) }
        else if kind == "resize" { send(["kind":"resize","cols":data["cols"] ?? 80,"rows":data["rows"] ?? 24]) }
    }
    func start() {
        guard !closed,!started else { return }; started = true
        let task = Process(); process = task
        task.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        task.arguments = [Bundle.main.resourceURL!.appendingPathComponent("terminal/pty_host.py").path]
        task.currentDirectoryURL = directory; task.standardInput = input; task.standardOutput = output; task.standardError = output
        do { try task.run() } catch { display(Data("Could not open shell: \(error.localizedDescription)".utf8)); return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let owner = self else { return }
            while true {
                let data = owner.output.fileHandleForReading.availableData
                if data.isEmpty { break }
                let done = DispatchSemaphore(value: 0)
                DispatchQueue.main.async {
                    guard !owner.closed else { done.signal(); return }
                    owner.web.callAsyncJavaScript("await window.feed(data)",arguments: ["data":data.base64EncodedString()],in: nil,in: .page) { _ in done.signal() }
                }
                // Limit outstanding renderer work. A closed/unresponsive web view must not block cleanup.
                _ = done.wait(timeout: .now()+5)
            }
            task.waitUntilExit()
            DispatchQueue.main.async { if !owner.closed { owner.display(Data("\r\n[Terminal ended · exit \(task.terminationStatus)]\r\n".utf8)) } }
        }
    }
    func display(_ data: Data) { web.callAsyncJavaScript("await window.feed(data)",arguments: ["data":data.base64EncodedString()],in: nil,in: .page,completionHandler: nil) }
    func send(_ object: [String:Any]) {
        guard !closed,let process = process,process.isRunning,let data = try? JSONSerialization.data(withJSONObject: object) else { return }
        writer.async { [weak self] in
            guard let self = self else { return }
            do { try self.input.fileHandleForWriting.write(contentsOf: data+Data([10])) } catch { }
        }
    }
    func focus() { web.evaluateJavaScript("window.focusTerminal()",completionHandler: nil) }
    func stop() {
        guard !closed else { return }; closed = true
        web.configuration.userContentController.removeScriptMessageHandler(forName: "terminal")
        if let process = process,process.isRunning { process.terminate() }
        writer.async { [weak self] in try? self?.input.fileHandleForWriting.close() }
    }
}
final class TerminalDesk: NSObject, NSWindowDelegate, NSTabViewDelegate {
    let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 720,height: 440),styleMask: [.titled,.closable,.miniaturizable,.resizable],backing: .buffered,defer: false)
    let tabs = NSTabView()
    var terminals: [EmbeddedTerminal] = []
    var counter = 0
    override init() {
        super.init(); window.title = "Bagad Billa · Terminals"; window.isReleasedWhenClosed = false; window.delegate = self
        window.minSize = NSSize(width: 520,height: 280); window.level = .floating
        let root = window.contentView!
        tabs.frame = NSRect(x: 8,y: 8,width: 704,height: 382); tabs.autoresizingMask = [.width,.height]; tabs.delegate = self; root.addSubview(tabs)
        for (title,selector,x,width) in [("+ Terminal",#selector(addDefault),8.0,100.0),("+ In folder…",#selector(addFolder),112.0,110.0),("End tab",#selector(closeTab),226.0,85.0),("Expand",#selector(expand),315.0,80.0),("Paste",#selector(paste),399.0,70.0),("Copy",#selector(copyText),473.0,70.0)] {
            let b = NSButton(title: title,target: self,action: selector); b.bezelStyle = .rounded; b.frame = NSRect(x: x,y: 402,width: width,height: 28); b.autoresizingMask = [.minYMargin]; root.addSubview(b)
        }
        addDefault()
    }
    @objc func addDefault() { add(FileManager.default.homeDirectoryForCurrentUser) }
    @objc func addFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { add(url) }
    }
    func add(_ directory: URL) {
        counter += 1
        let terminal = EmbeddedTerminal(directory: directory); terminals.append(terminal)
        let tab = NSTabViewItem(identifier: terminal); tab.label = "\(counter) · \(directory.lastPathComponent)"; tab.view = terminal.web
        tabs.addTabViewItem(tab); tabs.selectTabViewItem(tab)
    }
    var selected: EmbeddedTerminal? { tabs.selectedTabViewItem?.identifier as? EmbeddedTerminal }
    @objc func closeTab() {
        guard let tab = tabs.selectedTabViewItem,let terminal = selected else { return }
        if terminal.process?.isRunning == true {
            let alert = NSAlert(); alert.messageText = "End this terminal?"; alert.informativeText = "This closes its shell and may interrupt commands running in this tab."; alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "End terminal")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        terminal.stop(); terminals.removeAll { $0 === terminal }; tabs.removeTabViewItem(tab)
    }
    @objc func expand() { window.zoom(nil) }
    @objc func paste() {
        guard let text = NSPasteboard.general.string(forType: .string),text.utf8.count <= 1000000 else { return }
        selected?.web.callAsyncJavaScript("window.pasteText(text)",arguments: ["text":text],in: nil,in: .page,completionHandler: nil)
    }
    @objc func copyText() {
        selected?.web.evaluateJavaScript("window.copySelection()") { result,_ in
            if let text = result as? String,!text.isEmpty { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text,forType: .string) }
        }
    }
    func tabView(_ tabView: NSTabView,didSelect tabViewItem: NSTabViewItem?) { selected?.focus() }
    func show(above pet: NSRect) {
        if !window.isVisible {
            let screen = NSScreen.screens.first { $0.frame.contains(pet.center) } ?? NSScreen.main
            if let area = screen?.visibleFrame {
                window.setFrameOrigin(NSPoint(x: max(area.minX,min(pet.midX-window.frame.width/2,area.maxX-window.frame.width)),y: max(area.minY,min(pet.maxY+8,area.maxY-window.frame.height))))
            }
        }
        NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); selected?.focus()
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool { window.orderOut(nil); return false }
    func shutdown() { terminals.forEach { $0.stop() } }
}

struct ClaudeSnapshot: Decodable {
    let id: String
    let pid: Int
    let project: String
    let updated: Double
    let state: String
    let output: String
}

final class ClaudeControl: NSObject {
    let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 560,height: 440),styleMask: [.titled,.closable,.resizable],backing: .buffered,defer: false)
    let transcript = NSTextView()
    let input = NSTextField()
    let status = NSTextField(labelWithString: "")
    var session: ClaudeSnapshot
    init(_ session: ClaudeSnapshot) {
        self.session = session; super.init()
        window.title = "Claude · " + session.project; window.isReleasedWhenClosed = false
        let root = window.contentView!
        let scroll = NSScrollView(frame: NSRect(x: 12,y: 105,width: 536,height: 320))
        scroll.autoresizingMask = [.width,.height]; scroll.hasVerticalScroller = true
        transcript.isEditable = false; transcript.isSelectable = true; transcript.font = .monospacedSystemFont(ofSize: 11,weight: .regular)
        transcript.autoresizingMask = [.width]; transcript.textContainer?.widthTracksTextView = true
        scroll.documentView = transcript; root.addSubview(scroll)
        input.frame = NSRect(x: 12,y: 58,width: 536,height: 30); input.autoresizingMask = [.width]; input.placeholderString = "Message or response to Claude…"; root.addSubview(input)
        for (title,selector,x) in [("Send",#selector(send),12.0),("Interrupt (Esc)",#selector(interrupt),100.0)] {
            let button = NSButton(title: title,target: self,action: selector); button.bezelStyle = .rounded; button.contentTintColor = .black; button.bezelColor = .lightGray; button.frame = NSRect(x: x,y: 18,width: title == "Send" ? 80 : 135,height: 30); root.addSubview(button)
        }
        status.frame = NSRect(x: 245,y: 21,width: 300,height: 22); status.font = .systemFont(ofSize: 10); root.addSubview(status)
        update(session); window.center()
    }
    func update(_ value: ClaudeSnapshot) {
        session = value
        if transcript.string != value.output { transcript.string = value.output; transcript.scrollToEndOfDocument(nil) }
    }
    func show() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil); window.makeFirstResponder(input) }
    @objc func send() { let text = input.stringValue; guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }; command("send",text: text) }
    @objc func interrupt() { command("interrupt",text: "") }
    func command(_ action: String,text: String) {
        guard Date().timeIntervalSince1970-session.updated < 5 else { status.stringValue = "Disconnected; reconnect from terminal"; return }
        guard let script = Bundle.main.resourceURL?.appendingPathComponent("claude-bridge.py") else { return }
        let id = session.id
        status.stringValue = "Sending…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let task = Process(); task.executableURL = URL(fileURLWithPath: "/usr/bin/python3"); task.arguments = [script.path,"control"]
            let pipe = Pipe(); task.standardInput = pipe; task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
            var success = false
            do {
                try task.run()
                let data = try JSONSerialization.data(withJSONObject: ["id":id,"action":action,"text":text])
                try pipe.fileHandleForWriting.write(contentsOf: data); try pipe.fileHandleForWriting.close(); task.waitUntilExit(); success = task.terminationStatus == 0
            } catch { }
            DispatchQueue.main.async {
                self?.status.stringValue = success ? (action == "send" ? "Sent to Claude terminal" : "Escape sent") : "Not sent — connection unavailable"
                if success && action == "send" && self?.input.stringValue == text { self?.input.stringValue = "" }
            }
        }
    }
}

final class AgentListView: NSView {
    var lines: [String] = [] { didSet { needsDisplay = true } }
    var collapsed = false
    var page = 0
    var activity: String? = nil
    var attention = false
    var changed: (() -> Void)?
    var select: ((String) -> Void)?
    var rows: [String] { Array(lines.dropFirst()) }
    var pageCount: Int { max(1,(rows.count+2)/3) }
    var cardCount: Int { min(3,max(0,rows.count-page*3)) }
    var desiredHeight: Double { collapsed ? 46 : 100+Double(cardCount)*72 }
    func label(_ text: String,_ x: Double,_ y: Double,_ size: Double,_ color: NSColor = .white,_ bold: Bool = false) {
        let style = NSMutableParagraphStyle(); style.lineBreakMode = .byTruncatingTail
        (text as NSString).draw(in: NSRect(x: x,y: y,width: bounds.width-x-14,height: 19),withAttributes: [.font: NSFont.systemFont(ofSize: size,weight: bold ? .semibold : .regular),.foregroundColor: color,.paragraphStyle: style])
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: 0.075,alpha: 0.97).setFill()
        NSBezierPath(roundedRect: bounds,xRadius: 15,yRadius: 15).fill()
        label("AGENT DESK",14,bounds.height-29,12,.white,true)
        label(collapsed ? "+" : "−",bounds.width-30,bounds.height-29,15,.systemTeal,true)
        guard !collapsed else { return }
        label(lines.first ?? "Checking…",14,bounds.height-50,10,.lightGray)
        for (index,line) in rows.dropFirst(page*3).prefix(3).enumerated() {
            let y = bounds.height-124-Double(index)*72
            let card = NSRect(x: 10,y: y,width: bounds.width-20,height: 65)
            NSColor(calibratedWhite: 0.14,alpha: 1).setFill()
            NSBezierPath(roundedRect: card,xRadius: 9,yRadius: 9).fill()
            label(line.replacingOccurrences(of: "● ",with: ""),20,y+41,11,.white,true)
            let live = line.hasPrefix("Live Claude")
            let isAgent = line.contains("PID")
            label(live ? "● Connected · click to view and control" : isAgent ? "● Running · activity unknown" : "No live task information",20,y+22,10,isAgent ? .systemTeal : .lightGray)
            label(live ? "Live terminal output · input · interrupt" : isAgent ? "Local process · refreshed every 5s" : "Supported CLI processes only",20,y+6,9,.lightGray)
        }
        label(activity ?? "No recent terminal alerts",14,25,10,attention ? .systemOrange : .lightGray)
        label("‹   Page \(page+1)/\(pageCount)   ›",14,6,10,.systemTeal)
    }
    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow,from: nil)
        if p.y > bounds.height-44 { collapsed.toggle() }
        else if !collapsed && p.y < 24 { page = (page + (p.x < bounds.width/2 ? pageCount-1 : 1)) % pageCount }
        else if !collapsed {
            let index = Int((bounds.height-59-p.y)/72)
            if p.y <= bounds.height-59 && index >= 0 && index < cardCount { select?(rows[page*3+index]) }
        }
        changed?(); needsDisplay = true
    }
}

final class Companion: NSObject, NSApplicationDelegate {
    var panel: PetPanel!
    var pet = PetView()
    var status: NSStatusItem!
    let menu = NSMenu()
    var images: [String: NSImage] = [:]
    var timer: Timer?
    var paused = false
    var pauseItem: NSMenuItem!
    var actionRow = 0
    var actionStart = 0.0
    var actionUntil = 0.0
    var typing = TypingActivity()
    var typingEnabled = UserDefaults.standard.object(forKey: "typingEnabled") as? Bool ?? true
    var globalKeys: Any?
    var localKeys: Any?
    var permissionCheck = 0.0
    var typingItem: NSMenuItem!
    var typingStatus: NSMenuItem!
    var lastKeyActivity = 0.0
    var permissionItem: NSMenuItem!
    var life = LifeState()
    var autoSleep = true
    var mischief = true
    var breakReminders = true
    var walkReminders = true
    var walk = WalkReminder()
    var walkUntil = 0.0
    var walkItem: NSMenuItem!
    var sounds = false
    var home: PetHome = .cushion
    var lastMouse = NSPoint.zero
    var pettingTravel = 0.0
    var pettingWindow = 0.0
    var pettingUntil = 0.0
    var lastPetSound = 0.0
    var lastChase = 0.0
    var excursion: Excursion?
    var treatPanel: PetPanel?
    var treatExpires = 0.0
    var notice: String?
    var noticeUntil = 0.0
    var stretchUntil = 0.0
    var focusItem: NSMenuItem!
    var sleepItem: NSMenuItem!
    var mischiefItem: NSMenuItem!
    var breakItem: NSMenuItem!
    var soundItem: NSMenuItem!
    var homeItems: [PetHome: NSMenuItem] = [:]
    var sound: NSSound?
    var musicMode = false
    var autoAudio = UserDefaults.standard.object(forKey: "autoAudio") as? Bool ?? true
    var audioActive = false
    var audioCheck = 0.0
    var musicItem: NSMenuItem!
    var audioItem: NSMenuItem!
    var terminalEnabled = UserDefaults.standard.object(forKey: "terminalEnabled") as? Bool ?? true
    var terminalCheck = 0.0
    var terminalSince = Date().timeIntervalSince1970
    var terminalUntil = 0.0
    var terminalMessage: String?
    var terminalItem: NSMenuItem!
    var terminalHistory = NSMenu(title: "Terminal activity")
    var terminalDesk: TerminalDesk?
    var claudeSessions: [String: ClaudeSnapshot] = [:]
    var claudeControls: [String: ClaudeControl] = [:]
    var processAgentLines: [String] = []
    var agentPanel: PetPanel?
    let agentView = AgentListView()
    var agentLines = ["Running agents", "Checking…"]
    var agentCheck = 0.0
    var agentScanning = false
    var showAgents = UserDefaults.standard.object(forKey: "showAgents") as? Bool ?? true
    var agentItem: NSMenuItem!
    let counts = [6,8,8,4,5,8,6,6,6,8,8]

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let resources = Bundle.main.resourceURL else { NSApp.terminate(nil); return }
        for row in 0..<11 {
            for col in 0..<counts[row] {
                let key = "\(row)-\(col)"
                guard let image = NSImage(contentsOf: resources.appendingPathComponent("frames/\(key).png")) else {
                    let alert = NSAlert(); alert.messageText = "Bagad Billi’s artwork is missing."
                    alert.informativeText = "Keep the complete app bundle together."; alert.runModal()
                    NSApp.terminate(nil); return
                }
                images[key] = image
            }
        }
        panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 154, height: 167), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        pet.owner = self; pet.frame = NSRect(origin: .zero, size: panel.frame.size)
        panel.contentView = pet
        let prefs = UserDefaults.standard
        autoSleep = prefs.object(forKey: "autoSleep") as? Bool ?? true
        mischief = prefs.object(forKey: "mischief") as? Bool ?? true
        breakReminders = prefs.object(forKey: "breakReminders") as? Bool ?? true
        walkReminders = prefs.object(forKey: "walkReminders") as? Bool ?? true
        sounds = prefs.bool(forKey: "sounds")
        home = PetHome(rawValue: prefs.string(forKey: "home") ?? "cushion") ?? .cushion
        let start = ProcessInfo.processInfo.systemUptime
        life.lastActivity = start; life.nextBreak = start + life.breakInterval; lastChase = start
        lastMouse = NSEvent.mouseLocation
        walk.next = start + 1200
        buildMenu()
        status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Bagad Billi")
        status.menu = menu
        // Read the saved position before defaults can overwrite it.
        var restored = false
        if let x = prefs.object(forKey: "petX") as? Double, let y = prefs.object(forKey: "petY") as? Double {
            let candidate = NSRect(x: x, y: y, width: panel.frame.width, height: panel.frame.height)
            if NSScreen.screens.contains(where: { $0.visibleFrame.contains(candidate) }) { panel.setFrameOrigin(candidate.origin); restored = true }
        }
        if !restored { resetPosition() }
        panel.orderFrontRegardless()
        tick()
        timer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged), name: NSApplication.didChangeScreenParametersNotification, object: nil)
        if let index = CommandLine.arguments.firstIndex(of: "--diagnostics"), CommandLine.arguments.count > index+1 {
            let report = "accessibilityTrusted=\(AXIsProcessTrusted())\ntypingEnabled=\(typingEnabled)\nglobalMonitor=\(globalKeys != nil)\n"
            try? report.write(toFile: CommandLine.arguments[index+1],atomically: true,encoding: .utf8)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--terminal-smoke"), CommandLine.arguments.count > index+1 {
            openTerminals()
            let destination = CommandLine.arguments[index+1]
            var attempts = 0
            Timer.scheduledTimer(withTimeInterval: 0.5,repeats: true) { [weak self] timer in
                attempts += 1
                guard let terminal = self?.terminalDesk?.selected else { return }
                if terminal.ready {
                    timer.invalidate()
                    terminal.send(["kind":"input","data":Data("printf 'BAGAD_%s\\n' 'TERMINAL_OK'\n".utf8).base64EncodedString()])
                    DispatchQueue.main.asyncAfter(deadline: .now()+2) {
                        terminal.web.evaluateJavaScript("Array.from({length:term.buffer.active.length},(_,i)=>term.buffer.active.getLine(i).translateToString()).join('\\n')") { value,error in
                            guard let text = value as? String,text.contains("BAGAD_TERMINAL_OK") else { print("FAIL terminal renderer: \(String(describing: error))"); self?.terminalDesk?.shutdown(); exit(1) }
                            terminal.web.takeSnapshot(with: nil) { image,error in
                                if let image = image,let tiff = image.tiffRepresentation,let rep = NSBitmapImageRep(data: tiff),let png = rep.representation(using: .png,properties: [:]) { try? png.write(to: URL(fileURLWithPath: destination)) }
                                print("PASS: embedded terminal renders real shell output")
                                NSApp.terminate(nil)
                            }
                        }
                    }
                } else if attempts > 30 { print("FAIL: terminal did not load"); timer.invalidate(); NSApp.terminate(nil) }
            }
            return
        }
        if typingEnabled { requestTypingAccess() }
    }
    func buildMenu() {
        add("Open terminals", #selector(openTerminals))
        agentItem = add("Show running agents above cat", #selector(toggleAgents))
        terminalItem = add("Terminal notifications", #selector(toggleTerminal))
        let history = NSMenuItem(title: "Recent terminal activity",action: nil,keyEquivalent: "")
        history.submenu = terminalHistory; menu.addItem(history)
        let title = NSMenuItem(title: "Bagad Billi", action: nil, keyEquivalent: ""); menu.addItem(title)
        menu.addItem(.separator())
        add("Wave", #selector(wave)); add("Jump", #selector(jump)); add("Thinking", #selector(think))
        add("Pet Bagad Billa", #selector(petNow)); add("Give a fish treat", #selector(giveTreat))
        add("Nap now", #selector(nap)); add("Stretch now", #selector(stretch))
        add("Play with cursor", #selector(playCursor))
        menu.addItem(.separator())
        focusItem = add("Focus timer: off", #selector(startFocus))
        add("Start 5-minute focus", #selector(shortFocus))
        add("Try a 10-second focus", #selector(testFocus))
        add("Cancel focus", #selector(cancelFocus))
        menu.addItem(.separator())
        sleepItem = add("Auto nap after 3 minutes", #selector(toggleSleep))
        mischiefItem = add("Occasional cursor play", #selector(toggleMischief))
        walkItem = add("Walk reminders every 20 minutes", #selector(toggleWalk))
        add("Preview walk reminder", #selector(remindWalk))
        breakItem = add("Stretch reminders every 30 minutes", #selector(toggleBreaks))
        musicItem = add("Headphones — manual music mode", #selector(toggleMusic))
        audioItem = add("Auto headphones when audio output is active", #selector(toggleAudio))
        soundItem = add("Sounds and purring", #selector(toggleSounds))
        for (name, style) in [("No home",PetHome.none),("Cushion",PetHome.cushion),("Cardboard box",PetHome.box)] {
            let item = add(name,#selector(selectHome(_:))); item.representedObject = style.rawValue; homeItems[style] = item
        }
        menu.addItem(.separator())
        pauseItem = add("Pause cursor following", #selector(togglePause))
        typingItem = add("Typing reactions", #selector(toggleTyping))
        typingStatus = NSMenuItem(title: "Typing detection: checking…",action: nil,keyEquivalent: ""); menu.addItem(typingStatus)
        add("Open keyboard permission settings…", #selector(openTypingSettings))
        permissionItem = add("Allow typing detection…", #selector(requestTypingAccess))
        add("Preview typing", #selector(previewTyping))
        add("Reset position", #selector(resetPosition))
        add("Small", #selector(small)); add("Large", #selector(large))
        menu.addItem(.separator()); add("Quit Bagad Billi", #selector(quit), "q")
    }
    @discardableResult func add(_ title: String, _ action: Selector, _ key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item); return item
    }
    func play(_ row: Int, duration: Double) {
        actionRow = row; actionStart = ProcessInfo.processInfo.systemUptime; actionUntil = actionStart + duration
    }
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        updateAgentPanel()
        if showAgents && now >= agentCheck && !agentScanning { agentCheck = now+5; scanAgents() }
        if now >= terminalCheck { terminalCheck = now+1; checkTerminals(); readClaudeSessions() }
        if now >= permissionCheck { permissionCheck = now + 1; refreshTypingMonitor() }
        if now >= audioCheck { audioCheck = now+2; audioActive = autoAudio && outputActive() }
        let point = NSEvent.mouseLocation
        let distance = hypot(point.x-lastMouse.x,point.y-lastMouse.y)
        if distance > 0.5 { life.activity(at: now) }
        let face = NSRect(x: panel.frame.minX+panel.frame.width*0.2,y: panel.frame.minY+panel.frame.height*0.55,width: panel.frame.width*0.6,height: panel.frame.height*0.35)
        if face.contains(point) && NSEvent.pressedMouseButtons == 0 && distance > 0.5 {
            if now-pettingWindow > 1.5 { pettingWindow = now; pettingTravel = 0 }
            pettingTravel += min(distance,30)
            if pettingTravel > 55 { petNow(); pettingTravel = 0 }
        } else if !face.contains(point) { pettingTravel = 0 }
        lastMouse = point
        if life.completeFocus(at: now) { announce("Focus finished. Nice work!",for: 6); play(4,duration: 1.5); playSound(purr: false) }
        if walk.due(at: now,enabled: walkReminders) { remindWalk() }
        let sleeping = life.sleeping(at: now,autoSleep: autoSleep && !musicMode && !audioActive)
        if life.breakDue(at: now,enabled: breakReminders,sleeping: sleeping) { stretch() }
        if let end = life.focusEnd {
            let seconds = max(0,Int(ceil(end-now)))
            focusItem.title = String(format: "Focus %02d:%02d — click to cancel",seconds/60,seconds%60)
        } else { focusItem.title = "Start 25-minute focus" }
        if now > treatExpires { treatPanel?.orderOut(nil) }
        if let trip = excursion {
            if now >= trip.start+trip.duration {
                panel.setFrameOrigin(trip.origin); excursion = nil
                if trip.kind == .treat { treatPanel?.orderOut(nil); announce("Nom. Acceptable.",for: 2.5); play(0,duration: 1); playSound(purr: true) }
                else { announce("I meant to miss.",for: 2.5); play(5,duration: 1.2) }
            } else {
                panel.setFrameOrigin(trip.position(at: now))
                if trip.kind == .treat && now-trip.start > trip.duration*0.45 { treatPanel?.orderOut(nil) }
            }
        }
        if mischief && !sleeping && life.focusEnd == nil && !typing.active(at: now) && excursion == nil && now > actionUntil && now > pettingUntil && now-lastChase > 75 && distance > 1 && NSEvent.pressedMouseButtons == 0 {
            let range = hypot(point.x-panel.frame.midX,point.y-panel.frame.midY)
            if range > 65 && range < 240 { startChase() }
        }
        pet.typingPhase = nil
        pet.snoozing = false; pet.happy = false; pet.stretching = false; pet.clock = now
        pet.home = home
        pet.headphones = musicMode || audioActive
        let goal = home == .box && (sleeping || now < pettingUntil) ? 1.0 : 0.0
        pet.homeDepth += (goal-pet.homeDepth)*0.12
        pet.caption = now < noticeUntil ? notice : nil
        var row = 0, col = Int(now / 0.2) % 6
        if let trip = excursion {
            if trip.kind == .treat { row = 4; col = min(4,Int((now-trip.start)/trip.duration*5)) }
            else { row = trip.target.x < trip.origin.x ? 2 : 1; if now-trip.start > trip.duration*0.6 { row = row == 1 ? 2 : 1 }; col = Int(now/0.1)%8 }
        } else if now < pettingUntil {
            row = 0; col = 1; pet.happy = true
        } else if now < stretchUntil {
            row = 7; col = 3; pet.stretching = true
        } else if now < actionUntil {
            row = actionRow; col = Int((now - actionStart) / 0.14) % counts[row]
        } else if typing.active(at: now) {
            row = 10; col = 0
            let cadence = typing.cadence(at: now)
            pet.typingPhase = Int(now / cadence)
            if cadence < 0.1 { pet.caption = "Turbo paws" }
        } else if sleeping {
            row = 0; col = 1; pet.snoozing = true
            if let end = life.focusEnd { pet.caption = "Focus · \(max(0,Int(ceil((end-now)/60)))) min" }
        } else if !paused {
            // AppKit mouse and window coordinates both use a bottom-left origin,
            // including negative coordinates on secondary displays.
            let point = NSEvent.mouseLocation
            let face = NSPoint(x: panel.frame.midX, y: panel.frame.minY + panel.frame.height * 0.68)
            if let d = direction(point.x - face.x, point.y - face.y) { row = 9 + d / 8; col = d % 8 }
        }
        if now < terminalUntil { pet.caption = terminalMessage }
        if now < walkUntil { pet.caption = "Stand up & take a short walk" }
        pet.gazeDirection = row >= 9 ? (row-9)*8+col : nil
        pet.headphonesFitAvailable = row == 0 || row >= 9
        pet.sprite = images["\(row)-\(col)"]
    }
    @objc func toggleTerminal() {
        terminalEnabled.toggle(); UserDefaults.standard.set(terminalEnabled,forKey: "terminalEnabled")
        terminalUntil = 0; terminalSince = Date().timeIntervalSince1970; syncOptions()
    }
    func checkTerminals() {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BagadBilli/events")
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory,includingPropertiesForKeys: [.fileSizeKey,.isSymbolicLinkKey]) else { return }
        var events: [TerminalEvent] = []
        let wall = Date().timeIntervalSince1970
        for file in files.prefix(256) where file.pathExtension == "json" {
            guard let info = try? file.resourceValues(forKeys: [.fileSizeKey,.isSymbolicLinkKey]), info.isSymbolicLink != true,
                  (info.fileSize ?? 9999) <= 1024,
                  let data = try? Data(contentsOf: file), let event = try? JSONDecoder().decode(TerminalEvent.self,from: data),
                  event.valid, event.time >= terminalSince, event.time <= wall+5, wall-event.time < 120 else { continue }
            events.append(event)
        }
        terminalSince = floor(wall)-1
        guard terminalEnabled else { return }
        for event in events.sorted(by: { $0.time < $1.time }) {
            // One event per session per second; ignore repeated polling of the same file.
            let identity = "\(event.session)-\(event.time)-\(event.kind)-\(event.code)"
            guard !seenTerminalEvents.contains(identity) else { continue }
            seenTerminalEvents.append(identity); if seenTerminalEvents.count > 256 { seenTerminalEvents.removeFirst() }
            agentView.attention = event.kind == "attention" || event.kind == "failure"
            if agentView.attention { agentView.collapsed = false }
            terminalMessage = event.message; terminalUntil = ProcessInfo.processInfo.systemUptime+12
            let item = NSMenuItem(title: event.message,action: nil,keyEquivalent: "")
            terminalHistory.insertItem(item,at: 0)
            if terminalHistory.items.count > 12 { terminalHistory.removeItem(at: 12) }
            if event.kind == "attention" { playSound(purr: false) }
        }
    }
    var seenTerminalEvents: [String] = []
    @objc func toggleAgents() {
        showAgents.toggle(); UserDefaults.standard.set(showAgents,forKey: "showAgents"); syncOptions(); updateAgentPanel()
    }
    func scanAgents() {
        agentScanning = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let task = Process(); task.executableURL = URL(fileURLWithPath: "/bin/ps")
            // Executable names only, never command arguments or agent conversation text.
            task.arguments = ["-U",String(getuid()),"-o","pid=,comm="]
            let pipe = Pipe(); task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
            var lines: [String] = []
            do {
                try task.run()
                let data = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
                let names = ["codex":"Codex CLI","claude":"Claude CLI","aider":"Aider","gemini":"Gemini CLI","opencode":"OpenCode","goose":"Goose"]
                for row in (String(data: data,encoding: .utf8) ?? "").split(separator: "\n") {
                    let parts = row.split(maxSplits: 1,whereSeparator: { $0.isWhitespace })
                    guard parts.count == 2, let pid = Int(parts[0]) else { continue }
                    let executable = URL(fileURLWithPath: String(parts[1]).trimmingCharacters(in: .whitespaces)).lastPathComponent
                    if let name = names[executable] { lines.append("● \(name) · PID \(pid)") }
                }
                if task.terminationStatus != 0 { lines = ["Process status unavailable"] }
            } catch { lines = ["Process status unavailable"] }
            let result = lines.sorted()
            DispatchQueue.main.async {
                guard let owner = self else { return }
                owner.agentScanning = false
                owner.processAgentLines = result
                owner.readClaudeSessions()
                owner.updateAgentPanel()
            }
        }
    }
    @objc func openTerminals() {
        if terminalDesk == nil { terminalDesk = TerminalDesk() }
        terminalDesk?.show(above: panel.frame)
    }
    func readClaudeSessions() {
        let directory = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/BagadBilli/claude")
        claudeSessions = [:]
        let files = (try? FileManager.default.contentsOfDirectory(at: directory,includingPropertiesForKeys: [.fileSizeKey,.isSymbolicLinkKey])) ?? []
        for file in files.prefix(128) where file.pathExtension == "json" {
            guard let info = try? file.resourceValues(forKeys: [.fileSizeKey,.isSymbolicLinkKey]), info.isSymbolicLink != true, (info.fileSize ?? 999999)>0, (info.fileSize ?? 999999)<64000,
                  let data = try? Data(contentsOf: file),let item = try? JSONDecoder().decode(ClaudeSnapshot.self,from: data),
                  item.id.count == 32,item.id.allSatisfy({ $0.isHexDigit }),Date().timeIntervalSince1970-item.updated < 5, item.updated <= Date().timeIntervalSince1970+2 else { continue }
            let key = "Live Claude · \(item.project.prefix(25)) · \(item.pid)"
            claudeSessions[key] = item; claudeControls[item.id]?.update(item)
        }
        let controlledPIDs = Set(claudeSessions.values.map { String($0.pid) })
        let remaining = processAgentLines.filter { !controlledPIDs.contains($0.components(separatedBy: "PID ").last ?? "") }
        let rows = claudeSessions.keys.sorted()+remaining
        agentLines = ["Agents · \(rows.count)"] + (rows.isEmpty ? ["No supported CLI agents found"] : rows)
        updateAgentPanel()
    }
    func updateAgentPanel() {
        guard showAgents else { agentPanel?.orderOut(nil); return }
        if agentPanel == nil {
            let p = PetPanel(contentRect: NSRect(x: 0,y: 0,width: 235,height: 60),styleMask: [.borderless,.nonactivatingPanel],backing: .buffered,defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.hasShadow = false; p.level = .floating
            p.hidesOnDeactivate = false; p.ignoresMouseEvents = false
            p.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; p.isReleasedWhenClosed = false
            agentView.select = { [weak self] line in
                guard let owner = self, let snapshot = owner.claudeSessions[line] else { return }
                let control = owner.claudeControls[snapshot.id] ?? ClaudeControl(snapshot)
                owner.claudeControls[snapshot.id] = control; control.show()
            }
            agentView.changed = { [weak self] in self?.updateAgentPanel() }
            p.contentView = agentView; agentPanel = p
        }
        guard let p = agentPanel else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(panel.frame.center) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? panel.frame
        agentView.lines = agentLines
        agentView.page = min(agentView.page,agentView.pageCount-1)
        agentView.activity = terminalMessage
        let height = agentView.desiredHeight
        p.setContentSize(NSSize(width: 280,height: height))
        p.setFrameOrigin(NSPoint(x: max(area.minX,min(panel.frame.midX-140,area.maxX-280)),y: max(area.minY,min(panel.frame.maxY+6,area.maxY-height))))
        p.orderFrontRegardless()
    }
    func savePosition() { UserDefaults.standard.set(panel.frame.minX, forKey: "petX"); UserDefaults.standard.set(panel.frame.minY, forKey: "petY") }
    func announce(_ text: String, for duration: Double = 3) { notice = text; noticeUntil = ProcessInfo.processInfo.systemUptime+duration }
    func beginDrag() {
        excursion = nil; life.activity(at: ProcessInfo.processInfo.systemUptime)
        pettingUntil = 0; stretchUntil = 0
    }
    @objc func petNow() {
        let now = ProcessInfo.processInfo.systemUptime
        pettingUntil = now+2.2; life.activity(at: now)
        if now-lastPetSound > 3 { lastPetSound = now; playSound(purr: true) }
    }
    @objc func nap() { life.forcedNap = true; actionUntil = 0; pettingUntil = 0; stretchUntil = 0; typing.until = 0; announce("Nap time",for: 2) }
    @objc func stretch() {
        let now = ProcessInfo.processInfo.systemUptime
        stretchUntil = now+3; life.nextBreak = now+life.breakInterval
        announce("Time for a little stretch",for: 5)
    }
    func startTimer(_ seconds: Double) {
        beginDrag(); life.focusEnd = ProcessInfo.processInfo.systemUptime+seconds
        actionUntil = 0; typing.until = 0; treatPanel?.orderOut(nil)
        announce("Focus together",for: 2)
    }
    @objc func startFocus() { if life.focusEnd != nil { cancelFocus() } else { startTimer(25*60) } }
    @objc func shortFocus() { startTimer(5*60) }
    @objc func testFocus() { startTimer(10) }
    @objc func cancelFocus() { life.focusEnd = nil; life.activity(at: ProcessInfo.processInfo.systemUptime); announce("Focus cancelled") }
    @objc func remindWalk() {
        walkUntil = ProcessInfo.processInfo.systemUptime + 30
        play(3,duration: 3); playSound(purr: false)
    }
    @objc func toggleWalk() {
        walkReminders.toggle(); walk.next = ProcessInfo.processInfo.systemUptime + 1200
        if !walkReminders { walkUntil = 0 }
        UserDefaults.standard.set(walkReminders,forKey: "walkReminders"); syncOptions()
    }
    @objc func toggleSleep() { autoSleep.toggle(); UserDefaults.standard.set(autoSleep,forKey: "autoSleep"); syncOptions() }
    @objc func toggleMischief() { mischief.toggle(); UserDefaults.standard.set(mischief,forKey: "mischief"); syncOptions() }
    @objc func toggleBreaks() { breakReminders.toggle(); life.nextBreak = ProcessInfo.processInfo.systemUptime+life.breakInterval; UserDefaults.standard.set(breakReminders,forKey: "breakReminders"); syncOptions() }
    @objc func toggleSounds() { sounds.toggle(); UserDefaults.standard.set(sounds,forKey: "sounds"); if !sounds { sound?.stop() }; syncOptions() }
    @objc func selectHome(_ sender: NSMenuItem) {
        home = PetHome(rawValue: sender.representedObject as? String ?? "none") ?? .none
        UserDefaults.standard.set(home.rawValue,forKey: "home"); syncOptions()
        if home == .box { petNow(); announce("My box now.",for: 2) }
    }
    @objc func toggleMusic() { musicMode.toggle(); syncOptions() }
    @objc func toggleAudio() { autoAudio.toggle(); UserDefaults.standard.set(autoAudio,forKey: "autoAudio"); audioCheck = 0; if !autoAudio { audioActive = false }; syncOptions() }
    func outputActive() -> Bool {
        var device = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,mScope: kAudioObjectPropertyScopeGlobal,mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject),&address,0,nil,&size,&device) == noErr, device != 0 else { return false }
        var running: UInt32 = 0; size = UInt32(MemoryLayout<UInt32>.size)
        address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,mScope: kAudioObjectPropertyScopeGlobal,mElement: kAudioObjectPropertyElementMain)
        return AudioObjectGetPropertyData(device,&address,0,nil,&size,&running) == noErr && running != 0
    }
    func syncOptions() {
        agentItem?.state = showAgents ? .on : .off
        terminalItem?.state = terminalEnabled ? .on : .off
        walkItem?.state = walkReminders ? .on : .off
        musicItem?.state = musicMode ? .on : .off; audioItem?.state = autoAudio ? .on : .off
        sleepItem?.state = autoSleep ? .on : .off; mischiefItem?.state = mischief ? .on : .off
        breakItem?.state = breakReminders ? .on : .off; soundItem?.state = sounds ? .on : .off
        for (style,item) in homeItems { item.state = style == home ? .on : .off }
    }
    func clampedOrigin(_ point: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(panel.frame.center) } ?? NSScreen.main
        guard let f = screen?.visibleFrame else { return point }
        return NSPoint(x: min(max(point.x,f.minX),f.maxX-panel.frame.width), y: min(max(point.y,f.minY),f.maxY-panel.frame.height))
    }
    @objc func playCursor() { startChase() }
    func startChase() {
        guard excursion == nil else { return }
        let now = ProcessInfo.processInfo.systemUptime
        life.activity(at: now); lastChase = now
        let cursor = NSEvent.mouseLocation
        let dx = cursor.x-panel.frame.midX, dy = cursor.y-panel.frame.midY
        let distance = max(1,hypot(dx,dy)), amount = min(70,distance*0.5)
        let target = clampedOrigin(NSPoint(x: panel.frame.minX+dx/distance*amount,y: panel.frame.minY+dy/distance*amount))
        excursion = Excursion(kind: .chase,origin: panel.frame.origin,target: target,start: now,duration: 1.7)
    }
    @objc func giveTreat() {
        if treatPanel == nil {
            let window = PetPanel(contentRect: NSRect(x: 0,y: 0,width: 42,height: 38),styleMask: [.borderless,.nonactivatingPanel],backing: .buffered,defer: false)
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false; window.level = .floating
            window.hidesOnDeactivate = false; window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
            let view = TreatView(frame: NSRect(x: 0,y: 0,width: 42,height: 38)); view.owner = self; window.contentView = view
            window.isReleasedWhenClosed = false; treatPanel = window
        }
        guard let window = treatPanel else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(panel.frame.center) } ?? NSScreen.main
        let f = screen?.visibleFrame ?? panel.frame
        let x = panel.frame.minX-52 >= f.minX ? panel.frame.minX-52 : min(f.maxX-42,panel.frame.maxX+10)
        window.setFrameOrigin(NSPoint(x: x,y: max(f.minY,panel.frame.minY+10)))
        window.orderFrontRegardless(); treatExpires = ProcessInfo.processInfo.systemUptime+20
        announce("Click the fish",for: 3)
    }
    func eatTreat() {
        guard let treat = treatPanel, excursion == nil else { return }
        beginDrag(); let now = ProcessInfo.processInfo.systemUptime
        let target = clampedOrigin(NSPoint(x: treat.frame.midX-panel.frame.width/2,y: panel.frame.minY))
        excursion = Excursion(kind: .treat,origin: panel.frame.origin,target: target,start: now,duration: 1.5)
        treatExpires = now+2
    }
    func playSound(purr: Bool) {
        guard sounds else { return }
        let rate = 22050, length = Int(Double(rate)*(purr ? 0.8 : 0.35))
        var pcm = Data()
        for i in 0..<length {
            let t = Double(i)/Double(rate), fade = sin(.pi*Double(i)/Double(length))
            let base = purr ? (sin(2 * .pi * 95*t)+0.25*sin(2 * .pi * 190*t))*(0.55+0.45*sin(2 * .pi * 25*t)) : sin(2 * .pi * 660*t)
            var value = Int16(base*fade*2400).littleEndian
            withUnsafeBytes(of: &value) { pcm.append(contentsOf: $0) }
        }
        var data = Data()
        func text(_ s: String) { data.append(s.data(using: .ascii)!) }
        func number<T: FixedWidthInteger>(_ n: T) { var le = n.littleEndian; withUnsafeBytes(of: &le) { data.append(contentsOf: $0) } }
        text("RIFF"); number(UInt32(pcm.count+36)); text("WAVEfmt "); number(UInt32(16)); number(UInt16(1)); number(UInt16(1)); number(UInt32(rate)); number(UInt32(rate*2)); number(UInt16(2)); number(UInt16(16)); text("data"); number(UInt32(pcm.count)); data.append(pcm)
        sound?.stop(); sound = NSSound(data: data); sound?.volume = 0.35; sound?.play()
    }
    func removeKeyMonitors() {
        if let monitor = globalKeys { NSEvent.removeMonitor(monitor) }; globalKeys = nil
        if let monitor = localKeys { NSEvent.removeMonitor(monitor) }; localKeys = nil
    }
    func refreshTypingMonitor() {
        let allowed = AXIsProcessTrusted()
        syncOptions()
        typingItem?.state = typingEnabled ? .on : .off
        permissionItem?.isHidden = allowed || !typingEnabled
        typingStatus?.title = !typingEnabled ? "Typing detection: off" : !allowed ? "Typing detection: permission needed" : lastKeyActivity > 0 ? "Typing detection: receiving keys" : "Typing detection: waiting for keys"
        guard typingEnabled && allowed else { removeKeyMonitors(); return }
        if globalKeys == nil {
            globalKeys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] _ in
                let now = ProcessInfo.processInfo.systemUptime
                self?.receiveTyping(at: now)
            }
        }
        if localKeys == nil {
            localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                let now = ProcessInfo.processInfo.systemUptime
                self?.receiveTyping(at: now)
                return event
            }
        }
    }
    func receiveTyping(at now: Double) {
        typing.pulse(at: now); life.activity(at: now); lastKeyActivity = now
        actionUntil = 0; pettingUntil = 0; stretchUntil = 0
    }
    @objc func openTypingSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func requestTypingAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshTypingMonitor()
    }
    @objc func toggleTyping() {
        typingEnabled.toggle(); UserDefaults.standard.set(typingEnabled, forKey: "typingEnabled")
        if typingEnabled { requestTypingAccess() } else { typing.until = 0; removeKeyMonitors() }
        refreshTypingMonitor()
    }
    @objc func previewTyping() { let now = ProcessInfo.processInfo.systemUptime; receiveTyping(at: now); typing.until = now + 3; lastKeyActivity = 0 }
    @objc func resetPosition() {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        panel.setFrameOrigin(NSPoint(x: frame.maxX - panel.frame.width - 24, y: frame.minY + 24)); savePosition()
    }
    @objc func screenChanged() {
        if !NSScreen.screens.contains(where: { $0.visibleFrame.contains(panel.frame) }) { resetPosition() }
    }
    func resize(_ width: Double) {
        panel.setContentSize(NSSize(width: width, height: width * 208 / 192)); screenChanged()
    }
    @objc func small() { resize(115) }
    @objc func large() { resize(192) }
    @objc func wave() { play(3, duration: 1.0) }
    @objc func jump() { play(4, duration: 0.85) }
    @objc func think() { play(7, duration: 2.0) }
    @objc func togglePause() { paused.toggle(); pauseItem.title = paused ? "Resume cursor following" : "Pause cursor following" }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        terminalDesk?.shutdown(); timer?.invalidate(); removeKeyMonitors(); sound?.stop()
        if let trip = excursion { panel.setFrameOrigin(trip.origin) }
        savePosition()
    }
}

extension NSRect { var center: NSPoint { NSPoint(x: midX,y: midY) } }

if CommandLine.arguments.contains("--self-test") {
    let terminal = TerminalEvent(kind: "failure",code: 1,duration: 4,time: 1,session: "ttys001",app: "vscode")
    precondition(terminal.valid && terminal.message == "ttys001: failed (1)")
    precondition(!TerminalEvent(kind: "execute",code: 0,duration: 0,time: 1,session: "terminal",app: "unknown").valid)
    precondition(!TerminalEvent(kind: "success",code: 0,duration: 0,time: 1,session: "bad\nlabel",app: "unknown").valid)
    let cases: [(Double, Double, Int)] = [(0,100,0),(100,0,4),(0,-100,8),(-100,0,12),(100,100,2),(100,-100,6),(-100,-100,10),(-100,100,14)]
    for (x,y,want) in cases { precondition(direction(x,y) == want) }
    for i in 0..<16 {
        let a = Double(i) * 22.5 * .pi / 180
        precondition(direction(sin(a)*100,cos(a)*100) == i)
    }
    precondition(direction(0,0) == nil)
    var activity = TypingActivity()
    precondition(!activity.active(at: 10))
    activity.pulse(at: 10)
    precondition(activity.active(at: 10.5))
    activity.pulse(at: 10.6)
    precondition(activity.active(at: 11.2))
    precondition(!activity.active(at: 11.4))
    guard let resources = Bundle.main.resourceURL else { fatalError("Missing bundle resources") }
    for (r,n) in [6,8,8,4,5,8,6,6,6,8,8].enumerated() {
        for c in 0..<n { precondition(NSImage(contentsOf: resources.appendingPathComponent("frames/\(r)-\(c).png")) != nil) }
    }
    var reminder = WalkReminder(next: 1200)
    precondition(!reminder.due(at: 1199,enabled: true))
    precondition(!reminder.due(at: 1200,enabled: false))
    precondition(reminder.due(at: 1200,enabled: true))
    precondition(!reminder.due(at: 1201,enabled: true))
    precondition(reminder.due(at: 2400,enabled: true))
    precondition(reminder.due(at: 10000,enabled: true) && reminder.next == 11200)
    var life = LifeState(lastActivity: 10, nextBreak: 1800)
    precondition(!life.sleeping(at: 189,autoSleep: true))
    precondition(life.sleeping(at: 190,autoSleep: true))
    life.activity(at: 191); precondition(!life.sleeping(at: 191,autoSleep: true))
    life.focusEnd = 200; precondition(life.sleeping(at: 195,autoSleep: false))
    precondition(!life.completeFocus(at: 199)); precondition(life.completeFocus(at: 200)); precondition(!life.completeFocus(at: 201))
    precondition(!life.breakDue(at: 201,enabled: true,sleeping: false))
    precondition(life.breakDue(at: 2000,enabled: true,sleeping: false))
    let trip = Excursion(kind: .chase,origin: .zero,target: NSPoint(x: 100,y: 50),start: 10,duration: 2)
    precondition(trip.position(at: 10) == .zero && trip.position(at: 12) == .zero)
    precondition(trip.position(at: 11) == trip.target)
    for i in 0..<100 { activity.pulse(at: 20+Double(i)*0.01) }
    precondition(activity.presses.count == 40 && activity.cadence(at: 21) == 0.065)
    print("PASS: life/focus/break transitions, excursion return, typing speed/storage; 16 cursor directions, compass cases, deadzone, typing renewal/expiry, and sprite resources")
 } else if let index = CommandLine.arguments.firstIndex(of: "--render-control"), CommandLine.arguments.count > index+1 {
    _ = NSApplication.shared
    let control = ClaudeControl(ClaudeSnapshot(id: String(repeating: "a",count: 32),pid: 123,project: "Demo project",updated: Date().timeIntervalSince1970,state: "Connected",output: "Claude terminal preview\n\nReading project files…\nWaiting for your next instruction."))
    let view = control.window.contentView!
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds,to: rep)
    try! rep.representation(using: .png,properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index+1]))
 } else if let index = CommandLine.arguments.firstIndex(of: "--render-cards"), CommandLine.arguments.count > index+1 {
    _ = NSApplication.shared
    let view = AgentListView(frame: NSRect(x: 0,y: 0,width: 280,height: 244))
    view.lines = ["Running agents · 2", "● Codex CLI · PID 123", "● Claude CLI · PID 456"]
    view.activity = "ttys001: needs your help"; view.attention = true
    let preview = NSImage(size: view.frame.size); preview.lockFocus(); view.draw(view.bounds); preview.unlockFocus()
    let rep = NSBitmapImageRep(data: preview.tiffRepresentation!)!
    try! rep.representation(using: .png,properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index+1]))
} else if let index = CommandLine.arguments.firstIndex(of: "--render-gallery"), CommandLine.arguments.count > index+1 {
    _ = NSApplication.shared
    let canvas = NSImage(size: NSSize(width: 768,height: 832))
    canvas.lockFocus()
    NSColor(calibratedWhite: 0.9,alpha: 1).setFill(); NSRect(x: 0,y: 0,width: 768,height: 832).fill()
    for i in 0..<16 {
        let view = PetView(frame: NSRect(x: 0,y: 0,width: 192,height: 208))
        view.sprite = NSImage(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("frames/\(9+i/8)-\(i%8).png"))
        view.clock = 1; view.home = .cushion; view.gazeDirection = i
        view.headphones = true; view.typingPhase = nil
        view.snoozing = false; view.happy = false
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform(); transform.translateX(by: Double(i%4)*192,yBy: Double(3-i/4)*208); transform.concat()
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
    }
    canvas.unlockFocus()
    let rep = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
    try! rep.representation(using: .png,properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index+1]))
} else {
    let app = NSApplication.shared
    let delegate = Companion()
    app.setActivationPolicy(.accessory)
    app.delegate = delegate
    app.run()
}
