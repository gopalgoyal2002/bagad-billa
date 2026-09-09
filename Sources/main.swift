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
        ["success","failure","attention","milestone"].contains(kind) && duration >= 0 && duration < 31536000 &&
        session.count <= 32 && session.allSatisfy { $0.isLetter || $0.isNumber } &&
        ["terminal","iterm","vscode","jetbrains","unknown"].contains(app)
    }
    var message: String {
        let label = session == "terminal" ? "Terminal" : session
        switch kind {
        case "success": return duration >= 10 ? "\(label): done after \(duration)s. Finally." : "\(label): command finished"
        case "failure": return "\(label): failed (\(code)). That's on you."
        case "milestone": return "\(label): git milestone. Dance time."
        default: return "\(label): needs your help"
        }
    }
}

struct WalkReminder {
    var next = 0.0
    var interval = 1200.0
    mutating func due(at now: Double, enabled: Bool) -> Bool {
        guard enabled, now >= next else { return false }
        next = now + interval
        return true
    }
}

struct WorkStreak {
    var count = 0
    /// Returns the run length at every fifth consecutive success; any failure resets it.
    mutating func record(success: Bool) -> Int? { count = success ? count+1 : 0; return success && count % 5 == 0 ? count : nil }
}

struct Mood {
    var value = 60.0
    mutating func add(_ amount: Double) { value = min(100,max(0,value+amount)) }
    mutating func decay(minutes: Double) { add(-minutes/10) }
    var label: String { value >= 80 ? "delighted" : value >= 60 ? "content" : value >= 40 ? "meh" : value >= 20 ? "grumpy" : "neglected" }
    var chaseGap: Double { value >= 80 ? 45 : value >= 40 ? 75 : 150 }
}

struct YarnBall {
    var position: NSPoint
    var velocity: NSPoint
    var spin = 0.0
    mutating func step(_ dt: Double, in area: NSRect) {
        position.x += velocity.x*dt; position.y += velocity.y*dt; spin += velocity.x*dt/14
        if position.x < area.minX { position.x = area.minX; velocity.x = abs(velocity.x)*0.7 }
        if position.x > area.maxX { position.x = area.maxX; velocity.x = -abs(velocity.x)*0.7 }
        if position.y < area.minY { position.y = area.minY; velocity.y = abs(velocity.y)*0.6 }
        if position.y > area.maxY { position.y = area.maxY; velocity.y = -abs(velocity.y)*0.6 }
        let friction = pow(0.5,dt); velocity.x *= friction; velocity.y *= friction
    }
    var resting: Bool { hypot(velocity.x,velocity.y) < 12 }
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
    enum Kind { case treat, chase, laser, yarn, patrol }
    var kind: Kind
    var origin: NSPoint
    var target: NSPoint
    var start: Double
    var duration: Double
    /// Treats and chases come back to the origin; laser, yarn, and patrol trips end at the target.
    var returns: Bool { kind == .treat || kind == .chase }
    func position(at now: Double) -> NSPoint {
        let progress = min(1, max(0, (now-start)/duration))
        let travel = !returns ? progress : progress < 0.4 ? progress/0.4 : progress < 0.6 ? 1 : (1-progress)/0.4
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

final class PetRootView: NSView {
    override func resizeSubviews(withOldSize oldSize: NSSize) {
        super.resizeSubviews(withOldSize: oldSize)
        for button in subviews where (900...902).contains(button.tag) {
            button.frame = NSRect(x: Double(button.tag-900)*bounds.width/3, y: 1, width: bounds.width/3, height: 24)
        }
    }
}
final class PetControlButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedWhite: isHighlighted ? 0.32 : 0.17, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1,dy: 1), xRadius: 6,yRadius: 6).fill()
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        (title as NSString).draw(in: NSRect(x: 0,y: 4,width: bounds.width,height: 16),withAttributes: [.font: NSFont.systemFont(ofSize: 10,weight: .medium),.foregroundColor: NSColor.white,.paragraphStyle: paragraph])
    }
}
final class PetVoiceButton: NSButton {
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.12, green: 0.24, blue: 0.26, alpha: isHighlighted ? 1 : 0.94).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 12, yRadius: 12).fill()
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .center
        (title as NSString).draw(in: NSRect(x: 23, y: 5, width: 53, height: 17), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold), .foregroundColor: NSColor.white, .paragraphStyle: paragraph])
        NSColor.white.setFill()
        NSBezierPath(roundedRect: NSRect(x: 17, y: 11, width: 4, height: 8), xRadius: 2, yRadius: 2).fill()
        let mic = NSBezierPath(); mic.move(to: NSPoint(x: 14, y: 13)); mic.curve(to: NSPoint(x: 24, y: 13), controlPoint1: NSPoint(x: 14, y: 5), controlPoint2: NSPoint(x: 24, y: 5)); mic.move(to: NSPoint(x: 19, y: 8)); mic.line(to: NSPoint(x: 19, y: 5)); mic.lineWidth = 1.4; NSColor.white.setStroke(); mic.stroke()
    }
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
    var outfit: Set<Outfit> = []
    var pose = "0-0"
    var clock = 0.0
    var caption: String? = nil
    var sprite: NSImage? { didSet { needsDisplay = true } }
    var downPoint = NSPoint.zero
    var downOrigin = NSPoint.zero
    var moved = false
    weak var owner: Companion?
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill()
        // The view is 192x256 sprite units: the 208-unit sprite sits at the bottom and the 48 units above leave room for hats.
        let sx = bounds.width / 192, sy = bounds.height / 256
        if home == .cushion {
            NSColor(calibratedRed: 0.35, green: 0.52, blue: 0.48, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 7*sx,y: 0,width: 178*sx,height: 30*sy)).fill()
            NSColor(calibratedRed: 0.53, green: 0.68, blue: 0.62, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 14*sx,y: 7*sy,width: 164*sx,height: 22*sy)).fill()
        } else if home == .box {
            NSColor(calibratedRed: 0.58, green: 0.36, blue: 0.19, alpha: 1).setFill()
            NSBezierPath(roundedRect: NSRect(x: 12*sx,y: 2*sy,width: 168*sx,height: 67*sy), xRadius: 4*sx, yRadius: 4*sy).fill()
        }
        var body = NSRect(x: 0, y: 0, width: bounds.width, height: 208 * sy)
        body.origin.y -= homeDepth * 17 * sy
        if snoozing { body.size.height -= (1 + sin(clock*1.8))*1.5*sy }
        if headphones && !snoozing { body.origin.y += sin(clock*4)*2*sy }
        if happy { body.origin.y += sin(clock*5)*1.2*sy }
        if stretching {
            let lift = max(0, sin(clock*2.5))
            body.size.height -= 8*sy; body.origin.y += lift*6*sy
        }
        sprite?.draw(in: body, from: .zero, operation: .sourceOver, fraction: 1)
        drawOutfit(in: body)
        if headphones && headphonesFitAvailable {
            // Ear-cup centers come from the wardrobe table; the far cup is hidden for profile poses and both share the body transform.
            let f = earFit, bx = body.width/192, by = body.height/208
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
        drawHat(in: body)
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
            let sx = bounds.width / 192, sy = bounds.height / 256
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
    enum Kind { case fish, water }
    weak var owner: Companion?
    var kind = Kind.fish { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill()
        if kind == .water {
            NSColor(calibratedRed: 0.25,green: 0.45,blue: 0.8,alpha: 1).setFill(); NSBezierPath(ovalIn: NSRect(x: 3,y: 6,width: 36,height: 20)).fill()
            NSColor(calibratedRed: 0.2,green: 0.35,blue: 0.65,alpha: 1).setFill(); NSBezierPath(ovalIn: NSRect(x: 3,y: 14,width: 36,height: 14)).fill()
            NSColor(calibratedRed: 0.6,green: 0.85,blue: 0.98,alpha: 1).setFill(); NSBezierPath(ovalIn: NSRect(x: 7,y: 16,width: 28,height: 10)).fill()
            NSColor(calibratedWhite: 1,alpha: 0.7).setFill(); NSBezierPath(ovalIn: NSRect(x: 12,y: 20,width: 8,height: 3)).fill()
            return
        }
        NSColor(calibratedRed: 0.93,green: 0.63,blue: 0.35,alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 9,y: 9,width: 29,height: 20)).fill()
        let tail = NSBezierPath(); tail.move(to: NSPoint(x: 11,y: 19)); tail.line(to: NSPoint(x: 1,y: 8));tail.line(to: NSPoint(x: 1,y: 30));tail.close();tail.fill()
        NSColor.black.setFill(); NSBezierPath(ovalIn: NSRect(x: 29,y: 20,width: 3,height: 3)).fill()
    }
    override func mouseDown(with event: NSEvent) { owner?.eatTreat() }
}

final class YarnView: NSView {
    weak var owner: Companion?
    var spin = 0.0 { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); bounds.fill()
        let r = bounds.insetBy(dx: 2,dy: 2), ball = NSBezierPath(ovalIn: r), c = NSPoint(x: r.midX,y: r.midY)
        NSColor(calibratedRed: 0.86,green: 0.33,blue: 0.4,alpha: 1).setFill(); ball.fill()
        NSGraphicsContext.saveGraphicsState(); ball.addClip()
        NSColor(calibratedRed: 0.6,green: 0.16,blue: 0.24,alpha: 1).setStroke()
        for i in 0..<4 {
            let a = spin+Double(i)*0.8, w = r.width, strand = NSBezierPath()
            strand.move(to: NSPoint(x: c.x+cos(a)*w,y: c.y+sin(a)*w))
            strand.curve(to: NSPoint(x: c.x-cos(a)*w,y: c.y-sin(a)*w),controlPoint1: NSPoint(x: c.x+sin(a)*w*0.7,y: c.y-cos(a)*w*0.7),controlPoint2: NSPoint(x: c.x-sin(a)*w*0.7,y: c.y+cos(a)*w*0.7))
            strand.lineWidth = 1.5; strand.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
        NSColor(calibratedRed: 0.6,green: 0.16,blue: 0.24,alpha: 1).setStroke(); ball.lineWidth = 1; ball.stroke()
    }
    override func mouseDown(with event: NSEvent) { owner?.kickYarn() }
}

final class EmbeddedTerminal: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    var web: WKWebView!
    var process: Process?
    let input = Pipe()
    let output = Pipe()
    let directory: URL
    let writer = DispatchQueue(label: "bagad.terminal.input")
    var number = 0
    var closed = false
    var started = false
    var ready = false
    var onBell: (() -> Void)?
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
                // The terminal bell (BEL) is the only byte inspected; it lets the pet flag a tab that wants attention.
                if data.contains(7) { DispatchQueue.main.async { if !owner.closed { owner.onBell?() } } }
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
    var voice: GeminiVoice?
    var bell: ((EmbeddedTerminal) -> Void)?
    override init() {
        super.init(); window.title = "Bagad Billa · Terminal Desk"; window.isReleasedWhenClosed = false; window.delegate = self
        window.minSize = NSSize(width: 650,height: 280); window.level = .floating
        let root = window.contentView!
        tabs.frame = NSRect(x: 8,y: 8,width: 704,height: 382); tabs.autoresizingMask = [.width,.height]; tabs.delegate = self; root.addSubview(tabs)
        for (title,selector,x,width) in [("+ Terminal",#selector(addDefault),8.0,100.0),("+ In folder…",#selector(addFolder),112.0,110.0),("End tab",#selector(closeTab),226.0,85.0),("Expand",#selector(expand),315.0,80.0),("Paste",#selector(paste),399.0,70.0),("Copy",#selector(copyText),473.0,70.0),("Voice",#selector(openVoice),547.0,75.0)] {
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
        let terminal = EmbeddedTerminal(directory: directory); terminal.number = counter; terminals.append(terminal)
        terminal.onBell = { [weak self,weak terminal] in if let terminal = terminal { self?.bell?(terminal) } }
        let tab = NSTabViewItem(identifier: terminal); tab.label = "\(counter) · \(directory.lastPathComponent)"; tab.view = terminal.web
        tabs.addTabViewItem(tab); tabs.selectTabViewItem(tab)
        window.title = "Bagad Billa · Terminal Desk · \(terminals.count) tabs"
    }
    var selected: EmbeddedTerminal? { tabs.selectedTabViewItem?.identifier as? EmbeddedTerminal }
    @objc func closeTab() {
        guard let tab = tabs.selectedTabViewItem,let terminal = selected else { return }
        if terminal.process?.isRunning == true {
            let alert = NSAlert(); alert.messageText = "End this terminal?"; alert.informativeText = "This closes its shell and may interrupt commands running in this tab."; alert.addButton(withTitle: "Cancel"); alert.addButton(withTitle: "End terminal")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        terminal.stop(); terminals.removeAll { $0 === terminal }; tabs.removeTabViewItem(tab)
        window.title = "Bagad Billa · Terminal Desk · \(terminals.count) tabs"
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
    @objc func openVoice() { if voice == nil { voice = GeminiVoice(desk: self) }; voice?.show() }
    func voiceContext(_ completion: @escaping (String) -> Void) {
        let items = Array(terminals.prefix(8))
        var snapshots: [Int: String] = [:]
        var remaining = items.count
        guard remaining > 0 else { completion("No pet terminals are open."); return }
        for terminal in items {
            let id = terminal.number
            terminal.web.evaluateJavaScript("window.voiceSnapshot()") { [weak self, weak terminal] result, _ in
                if let self = self, let terminal = terminal, self.terminals.contains(where: { $0 === terminal }) {
                    snapshots[id] = "Tab \(id), selected=\(self.selected === terminal), shellAlive=\(terminal.process?.isRunning == true):\n" + String((result as? String ?? "Screen unavailable").suffix(4000))
                }
                remaining -= 1
                if remaining == 0 { completion(snapshots.keys.sorted().compactMap { snapshots[$0] }.joined(separator: "\n---\n")) }
            }
        }
    }
    func voiceAction(_ action: VoiceTerminalAction) -> [String:Any] {
        if action.name == "list_terminals" {
            return ["terminals":terminals.map { ["id":$0.number,"folder":$0.directory.lastPathComponent,"ready":$0.ready && $0.process?.isRunning == true,"selected":$0 === selected] as [String:Any] }]
        }
        if action.name == "create_terminal" { addDefault(); return ["created_terminal_id":counter,"status":"starting; list terminals before sending"] }
        guard let id = action.terminalID,let terminal = terminals.first(where: { $0.number == id }),terminal.ready,terminal.process?.isRunning == true,!terminal.closed else { return ["error":"That pet terminal does not exist or is not ready."] }
        if let tab = tabs.tabViewItems.first(where: { ($0.identifier as? EmbeddedTerminal) === terminal }) { tabs.selectTabViewItem(tab) }
        if action.name == "send_terminal" {
            let data = Data((action.text+(action.submit ? "\r" : "")).utf8)
            terminal.send(["kind":"input","data":data.base64EncodedString()])
            return ["status":"queued input; command outcome unknown","terminal_id":id,"text":action.text,"submitted":action.submit]
        }
        terminal.send(["kind":"input","data":Data([action.key == "escape" ? 27 : 3]).base64EncodedString()])
        return ["status":"queued interrupt key; process outcome unknown","terminal_id":id,"key":action.key]
    }
    func shutdown() { voice?.stop(); terminals.forEach { $0.stop() } }
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
    var outfit = Set((UserDefaults.standard.stringArray(forKey: "wardrobe") ?? (UserDefaults.standard.bool(forKey: "sunglasses") ? ["sunglasses"] : [])).compactMap { Outfit(rawValue: $0) })
    var outfitItems: [Outfit: NSMenuItem] = [:]
    var seasonal = UserDefaults.standard.object(forKey: "seasonal") as? Bool ?? true
    var seasonalItem: NSMenuItem!
    var bedtime = UserDefaults.standard.object(forKey: "bedtime") as? Int ?? -1
    var bedtimeItems: [Int: NSMenuItem] = [:]
    var lastBedtimeNag = 0.0
    var clockCheck = 0.0
    var hour = 12, month = 1, day = 1
    var streak = WorkStreak()
    var danceUntil = 0.0
    var lastBell = 0.0
    var laserUntil = 0.0
    var strolls = UserDefaults.standard.bool(forKey: "strolls")
    var strollItem: NSMenuItem!
    var nextStroll = 0.0
    var yarnPanel: PetPanel?
    var yarn: YarnBall?
    var yarnBats = 0
    var yarnFade = 0.0
    var waterReminders = UserDefaults.standard.bool(forKey: "waterReminders")
    var water = WalkReminder(interval: 2700)
    var waterItem: NSMenuItem!
    var eyeRest = UserDefaults.standard.bool(forKey: "eyeRest")
    var eyeRestItem: NSMenuItem!
    var nextEyeRest = 0.0
    var eyeRestUntil = 0.0
    var focusLength = 0.0
    var focusStatsItem: NSMenuItem!
    var mood = Mood()
    var moodItem: NSMenuItem!
    var lastMoodTick = 0.0
    var lastMoodPet = 0.0
    var lastGrumble = 0.0
    var lastTick = 0.0
    var terminalEnabled = UserDefaults.standard.object(forKey: "terminalEnabled") as? Bool ?? true
    var terminalCheck = 0.0
    var terminalSince = Date().timeIntervalSince1970
    var terminalUntil = 0.0
    var terminalMessage: String?
    var terminalItem: NSMenuItem!
    var terminalHistory = NSMenu(title: "Terminal activity")
    var terminalDesk: TerminalDesk?
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
        panel = PetPanel(contentRect: NSRect(x: 0, y: 0, width: 154, height: 277), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        let root = PetRootView(frame: NSRect(origin: .zero, size: panel.frame.size))
        pet.owner = self; pet.frame = NSRect(x: 0, y: 72, width: 154, height: 205)
        pet.autoresizingMask = [.width, .height]
        root.addSubview(pet)
        let voiceButton = PetVoiceButton(title: "Voice", target: self, action: #selector(openPetVoice))
        voiceButton.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Voice")
        voiceButton.imagePosition = .imageLeading
        voiceButton.bezelStyle = .rounded
        voiceButton.frame = NSRect(x: 33, y: 41, width: 88, height: 26)
        voiceButton.autoresizingMask = [.minXMargin, .maxXMargin]
        voiceButton.toolTip = "Open Gemini voice controls"
        root.addSubview(voiceButton)
        let activity = NSTextField(labelWithString: "Voice ready")
        activity.alignment = .center; activity.font = .systemFont(ofSize: 10, weight: .medium)
        activity.textColor = .white; activity.backgroundColor = NSColor(calibratedWhite: 0.1, alpha: 0.9); activity.drawsBackground = true
        activity.frame = NSRect(x: 0,y: 27,width: 154,height: 14); activity.autoresizingMask = [.width]; root.addSubview(activity)
        for (title, selector, x) in [("Mute", #selector(mutePetVoice), 0.0), ("End", #selector(endPetVoice), 49.0), ("⚙", #selector(voiceSettings), 98.0)] {
            let button = PetControlButton(title: title,target: self,action: selector); button.bezelStyle = .rounded
            button.tag = 900 + Int(x / 49)
            button.frame = NSRect(x: x,y: 1,width: 48,height: 24); button.autoresizingMask = [.minXMargin,.maxXMargin]; root.addSubview(button)
        }
        Timer.scheduledTimer(withTimeInterval: 0.15,repeats: true) { [weak self, weak activity, weak voiceButton] _ in
            let voice = self?.terminalDesk?.voice
            let now = ProcessInfo.processInfo.systemUptime
            activity?.stringValue = voice?.starting == true ? "Connecting…" : voice?.connected == true ? (voice?.muted == true ? "Muted" : now - (voice?.outputPulse ?? 0) < 0.5 ? "▂▆█▅▂ Speaking" : now - (voice?.inputPulse ?? 0) < 0.5 ? "▂▄▆▄▂ Listening" : "Live") : "Voice ready"
            voiceButton?.title = voice?.connected == true || voice?.starting == true ? "Stop" : "Voice"
            voiceButton?.needsDisplay = true
            activity?.toolTip = voice?.status.stringValue
        }
        panel.contentView = root
        if let index = CommandLine.arguments.firstIndex(of: "--render-pet-controls"), CommandLine.arguments.count > index+1 {
            pet.sprite = images["0-0"]
            if let bitmap = root.bitmapImageRepForCachingDisplay(in: root.bounds) {
                root.cacheDisplay(in: root.bounds, to: bitmap)
                try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: CommandLine.arguments[index+1]))
            }
            NSApp.terminate(nil); return
        }
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
        walk.next = start + 1200; water.next = start + water.interval; nextEyeRest = start + 1200; nextStroll = start + 1500
        // Mood carries over between launches and decays while the cat was away, capped at a grumpy but recoverable level.
        mood.value = prefs.object(forKey: "mood") as? Double ?? 60
        mood.decay(minutes: min(400,max(0,(Date().timeIntervalSince1970-(prefs.object(forKey: "moodAt") as? Double ?? Date().timeIntervalSince1970))/60)))
        lastMoodTick = start
        buildMenu(); refreshFocusStats()
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
        if CommandLine.arguments.contains("--voice-tool-smoke") {
            openTerminals(); let desk = terminalDesk!; desk.openVoice(); let voice = desk.voice!
            voice.connected = true; voice.actions.state = .off
            func call(_ id: String,_ name: String,_ args: [String:Any]) { voice.handle(["toolCall":["functionCalls":[["id":id,"name":name,"args":args]]]]) }
            let initial = desk.terminals.count
            call("blocked","create_terminal",[:]); precondition(desk.terminals.count == initial)
            voice.actions.state = .on
            call("new","create_terminal",[:]); call("new","create_terminal",[:]); precondition(desk.terminals.count == initial+1)
            call("missing","send_terminal",["terminal_id":99999,"text":"bad","submit":true]); precondition(voice.replies["missing"]?["response"] as? [String:String] != nil)
            let target = desk.terminals.last!
            var tries = 0
            Timer.scheduledTimer(withTimeInterval: 0.5,repeats: true) { timer in
                tries += 1
                if target.ready {
                    timer.invalidate()
                    call("send","send_terminal",["terminal_id":target.number,"text":"printf 'VOICE_%s\\n' 'ROUTE_OK'","submit":true])
                    DispatchQueue.main.asyncAfter(deadline: .now()+2) {
                        target.web.evaluateJavaScript("Array.from({length:term.buffer.active.length},(_,i)=>term.buffer.active.getLine(i).translateToString()).join('\\n')") { result,_ in
                            guard (result as? String)?.contains("VOICE_ROUTE_OK") == true else { print("FAIL voice terminal input"); voice.stop(); desk.shutdown(); exit(1) }
                            call("interrupt","interrupt_terminal",["terminal_id":target.number,"key":"ctrl_c"])
                            voice.handle(["toolCallCancellation":["ids":["cancelled"]]])
                            call("cancelled","create_terminal",[:]); precondition(desk.terminals.count == initial+1)
                            voice.actions.state = .off; call("hangup", "hang_up", [:]); precondition(!voice.connected); call("after-stop","create_terminal",[:]); precondition(desk.terminals.count == initial+1)
                            print("PASS: voice tool toggle, stable target IDs, duplicate suppression, shell delivery, cancellation, and stop gate")
                            desk.voiceContext { text in
                                precondition(text.contains("VOICE_ROUTE_OK") && text.contains("Tab \(target.number)"))
                                print("PASS: bounded rendered terminal context and hang-up with controls disabled")
                                NSApp.terminate(nil)
                            }
                        }
                    }
                } else if tries > 30 { timer.invalidate(); desk.shutdown(); exit(1) }
            }
            return
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
        openTerminals()
        if typingEnabled { requestTypingAccess() }
    }
    func buildMenu() {
        add("Open terminals", #selector(openTerminals))
        terminalItem = add("Terminal notifications", #selector(toggleTerminal))
        let history = NSMenuItem(title: "Recent terminal activity",action: nil,keyEquivalent: "")
        history.submenu = terminalHistory; menu.addItem(history)
        let title = NSMenuItem(title: "Bagad Billi", action: nil, keyEquivalent: ""); menu.addItem(title)
        menu.addItem(.separator())
        add("Wave", #selector(wave)); add("Jump", #selector(jump)); add("Thinking", #selector(think))
        add("Pet Bagad Billa", #selector(petNow)); add("Give a fish treat", #selector(giveTreat))
        add("Nap now", #selector(nap)); add("Stretch now", #selector(stretch))
        add("Play with cursor", #selector(playCursor))
        add("Laser pointer for 30 seconds", #selector(startLaser)); add("Toss a yarn ball", #selector(tossYarn))
        strollItem = add("Occasional strolls along the screen", #selector(toggleStrolls))
        menu.addItem(.separator())
        focusItem = add("Focus timer: off", #selector(startFocus))
        add("Start 5-minute focus", #selector(shortFocus))
        add("Try a 10-second focus", #selector(testFocus))
        add("Cancel focus", #selector(cancelFocus))
        focusStatsItem = add("Focus sessions today: 0", nil); moodItem = add("Mood: content (60)", nil)
        menu.addItem(.separator())
        sleepItem = add("Auto nap after 3 minutes", #selector(toggleSleep))
        mischiefItem = add("Occasional cursor play", #selector(toggleMischief))
        walkItem = add("Walk reminders every 20 minutes", #selector(toggleWalk))
        add("Preview walk reminder", #selector(remindWalk))
        breakItem = add("Stretch reminders every 30 minutes", #selector(toggleBreaks))
        waterItem = add("Water reminders every 45 minutes", #selector(toggleWater)); add("Preview water break", #selector(offerWater))
        eyeRestItem = add("Eye rest every 20 minutes", #selector(toggleEyeRest)); add("Preview eye rest", #selector(startEyeRest))
        let bedtimeMenu = NSMenu(title: "Bedtime")
        for (title,hour) in [("Off",-1),("10 PM",22),("11 PM",23),("Midnight",0),("1 AM",1)] {
            let entry = add(title,#selector(selectBedtime(_:)),in: bedtimeMenu); entry.representedObject = hour; bedtimeItems[hour] = entry
        }
        let bedtimeItem = NSMenuItem(title: "Bedtime nightcap and nudge",action: nil,keyEquivalent: ""); bedtimeItem.submenu = bedtimeMenu; menu.addItem(bedtimeItem)
        musicItem = add("Headphones — manual music mode", #selector(toggleMusic))
        audioItem = add("Auto headphones when audio output is active", #selector(toggleAudio))
        let wardrobe = NSMenu(title: "Wardrobe")
        for item in Outfit.allCases {
            if item == .partyHat { wardrobe.addItem(.separator()) }
            let entry = add(item.title,#selector(toggleOutfit(_:)),in: wardrobe); entry.representedObject = item.rawValue; outfitItems[item] = entry
        }
        wardrobe.addItem(.separator()); seasonalItem = add("Seasonal hats (Santa in December, witch at Halloween)",#selector(toggleSeasonal),in: wardrobe)
        let wardrobeItem = NSMenuItem(title: "Wardrobe",action: nil,keyEquivalent: ""); wardrobeItem.submenu = wardrobe; menu.addItem(wardrobeItem)
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
    @discardableResult func add(_ title: String, _ action: Selector?, _ key: String = "", in target: NSMenu? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; (target ?? menu).addItem(item); return item
    }
    func play(_ row: Int, duration: Double) {
        actionRow = row; actionStart = ProcessInfo.processInfo.systemUptime; actionUntil = actionStart + duration
    }
    func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = lastTick > 0 ? min(0.2,now-lastTick) : 0; lastTick = now
        if now >= terminalCheck { terminalCheck = now+1; checkTerminals() }
        if now >= clockCheck {
            clockCheck = now+30; refreshFocusStats()
            let parts = Calendar.current.dateComponents([.hour,.month,.day],from: Date()); hour = parts.hour ?? 12; month = parts.month ?? 1; day = parts.day ?? 1
        }
        if now >= permissionCheck { permissionCheck = now + 1; refreshTypingMonitor() }
        if now >= audioCheck { audioCheck = now+2; audioActive = autoAudio && outputActive() }
        let point = NSEvent.mouseLocation
        let distance = hypot(point.x-lastMouse.x,point.y-lastMouse.y)
        if distance > 0.5 { life.activity(at: now) }
        let face = NSRect(x: panel.frame.minX+panel.frame.width*0.2,y: panel.frame.minY+pet.frame.minY+pet.frame.height*0.45,width: panel.frame.width*0.6,height: pet.frame.height*0.28)
        if face.contains(point) && NSEvent.pressedMouseButtons == 0 && distance > 0.5 {
            if now-pettingWindow > 1.5 { pettingWindow = now; pettingTravel = 0 }
            pettingTravel += min(distance,30)
            if pettingTravel > 55 { petNow(); pettingTravel = 0 }
        } else if !face.contains(point) { pettingTravel = 0 }
        lastMouse = point
        if life.completeFocus(at: now) { announce("Focus finished. Nice work!",for: 6); play(4,duration: 1.5); playSound(purr: false); mood.add(10); if focusLength >= 300 { recordFocus() } }
        if walk.due(at: now,enabled: walkReminders) { remindWalk() }
        if water.due(at: now,enabled: waterReminders) { offerWater() }
        let sleeping = life.sleeping(at: now,autoSleep: autoSleep && !musicMode && !audioActive)
        if life.breakDue(at: now,enabled: breakReminders,sleeping: sleeping) { stretch() }
        if eyeRest && life.focusEnd == nil && !sleeping && !typing.active(at: now) && now >= nextEyeRest && now >= eyeRestUntil { startEyeRest() }
        if pastBedtime(hour: hour,bedtime: bedtime) && !sleeping && now-lastBedtimeNag > 1200 { lastBedtimeNag = now; announce("It's late. Go to bed.",for: 8); stretchUntil = now+2.5 }
        if now-lastMoodTick >= 60 { mood.decay(minutes: (now-lastMoodTick)/60); lastMoodTick = now; saveMood() }
        moodItem.title = "Mood: \(mood.label) (\(Int(mood.value)))"
        if mood.value < 20 && !sleeping && excursion == nil && now > noticeUntil && now-lastGrumble > 600 { lastGrumble = now; announce("Hmph.",for: 2.5) }
        if let end = life.focusEnd {
            let seconds = max(0,Int(ceil(end-now)))
            focusItem.title = String(format: "Focus %02d:%02d — click to cancel",seconds/60,seconds%60)
        } else { focusItem.title = "Start 25-minute focus" }
        if now > treatExpires { treatPanel?.orderOut(nil) }
        if var ball = yarn, let ballPanel = yarnPanel {
            let screen = NSScreen.screens.first { $0.frame.contains(ball.position) } ?? NSScreen.main
            ball.step(dt,in: (screen?.visibleFrame ?? panel.frame).insetBy(dx: 18,dy: 18)); yarn = ball
            ballPanel.setFrameOrigin(NSPoint(x: ball.position.x-16,y: ball.position.y-16)); (ballPanel.contentView as? YarnView)?.spin = ball.spin
            if yarnBats >= 4 { if now > yarnFade { yarn = nil; ballPanel.orderOut(nil) } }
            else if ball.resting && excursion == nil && now > actionUntil && !pursue(toward: ball.position,kind: .yarn,speed: 220,stopShort: 30) { batYarn() }
        }
        if let trip = excursion {
            if now >= trip.start+trip.duration {
                panel.setFrameOrigin(trip.returns ? trip.origin : trip.target); excursion = nil
                switch trip.kind {
                case .treat:
                    treatPanel?.orderOut(nil); play(0,duration: 1); playSound(purr: true); mood.add(12)
                    announce((treatPanel?.contentView as? TreatView)?.kind == .water ? "Slurp. Hydrated." : "Nom. Acceptable.",for: 2.5)
                case .chase: announce("I meant to miss.",for: 2.5); play(5,duration: 1.2)
                case .yarn: batYarn()
                case .patrol: announce("New spot.",for: 2); savePosition()
                case .laser: break
                }
            } else {
                panel.setFrameOrigin(trip.position(at: now))
                if trip.kind == .treat && now-trip.start > trip.duration*0.45 { treatPanel?.orderOut(nil) }
            }
        }
        if laserUntil > 0 && excursion == nil && now > actionUntil {
            if now >= laserUntil { laserUntil = 0; announce("Got it. Wait, no.",for: 2.5); play(5,duration: 1); mood.add(8); savePosition() }
            else { let cursor = NSEvent.mouseLocation; if hypot(cursor.x-petCenter.x,cursor.y-petCenter.y) > 70 { pursue(toward: cursor,kind: .laser,speed: 280,stopShort: 40) } }
        }
        if strolls && !sleeping && life.focusEnd == nil && !typing.active(at: now) && excursion == nil && yarn == nil && laserUntil == 0 && now > actionUntil && now >= nextStroll && NSEvent.pressedMouseButtons == 0 {
            nextStroll = now+1500+Double(Int.random(in: 0...600)); startStroll()
        }
        if mischief && !sleeping && life.focusEnd == nil && !typing.active(at: now) && excursion == nil && now > actionUntil && now > pettingUntil && now-lastChase > mood.chaseGap && distance > 1 && NSEvent.pressedMouseButtons == 0 {
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
            else { row = trip.target.x < trip.origin.x ? 2 : 1; if trip.returns && now-trip.start > trip.duration*0.6 { row = row == 1 ? 2 : 1 }; col = Int(now/0.1)%8 }
        } else if now < danceUntil {
            row = Int(now/0.35)%2 == 0 ? 1 : 2; col = Int(now/0.1)%8; pet.happy = true
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
        } else if now < eyeRestUntil {
            row = 9; col = 2; pet.caption = "Look far away · \(max(0,Int(ceil(eyeRestUntil-now)))) s"
        } else if !paused {
            // AppKit mouse and window coordinates both use a bottom-left origin,
            // including negative coordinates on secondary displays.
            let point = NSEvent.mouseLocation
            let face = NSPoint(x: panel.frame.midX, y: panel.frame.minY + pet.frame.minY + pet.frame.height * 0.55)
            if let d = direction(point.x - face.x, point.y - face.y) { row = 9 + d / 8; col = d % 8 }
        }
        if now < terminalUntil { pet.caption = terminalMessage }
        if now < walkUntil { pet.caption = "Stand up & take a short walk" }
        pet.gazeDirection = row >= 9 ? (row-9)*8+col : nil
        pet.headphonesFitAvailable = row == 0 || row >= 9
        pet.outfit = currentOutfit(); pet.pose = "\(row)-\(col)"
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
            terminalMessage = event.message; terminalUntil = ProcessInfo.processInfo.systemUptime+12
            let item = NSMenuItem(title: event.message,action: nil,keyEquivalent: "")
            terminalHistory.insertItem(item,at: 0)
            if terminalHistory.items.count > 12 { terminalHistory.removeItem(at: 12) }
            let now = ProcessInfo.processInfo.systemUptime
            switch event.kind {
            case "attention": playSound(purr: false)
            case "milestone": danceUntil = now+2.6; playSound(purr: false); mood.add(4)
            case "failure": _ = streak.record(success: false); play(7,duration: 2)
            default:
                if let run = streak.record(success: true) { terminalMessage = "\(run) in a row. Show-off."; danceUntil = now+2 }
                else if event.duration >= 10 { play(4,duration: 1.2) }
            }
        }
    }
    var seenTerminalEvents: [String] = []
    func terminalBell(_ terminal: EmbeddedTerminal) {
        let now = ProcessInfo.processInfo.systemUptime
        guard terminalEnabled, now-lastBell > 8, let desk = terminalDesk else { return }
        // Ignore bells from the tab you are already looking at.
        if desk.window.isKeyWindow && desk.window.isVisible && desk.selected === terminal { return }
        lastBell = now; terminalMessage = "Terminal \(terminal.number) needs you"; terminalUntil = now+10
        play(3,duration: 2); playSound(purr: false)
    }
    @objc func mutePetVoice() { terminalDesk?.voice?.toggleMic() }
    @objc func endPetVoice() { terminalDesk?.voice?.stop() }
    func desk() -> TerminalDesk {
        if let desk = terminalDesk { return desk }
        let desk = TerminalDesk(); desk.bell = { [weak self] terminal in self?.terminalBell(terminal) }; terminalDesk = desk; return desk
    }
    @objc func voiceSettings() { desk().openVoice() }
    @objc func openPetVoice() {
        let desk = desk()
        if desk.voice == nil { desk.voice = GeminiVoice(desk: desk) }; desk.voice?.quickStart()
    }
    @objc func openTerminals() { desk().show(above: panel.frame) }
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
        if now-lastMoodPet > 3 { lastMoodPet = now; if mood.value < 20 { announce("Took you long enough.",for: 2.5) }; mood.add(6) }
    }
    @objc func nap() { life.forcedNap = true; actionUntil = 0; pettingUntil = 0; stretchUntil = 0; typing.until = 0; laserUntil = 0; announce("Nap time",for: 2) }
    @objc func stretch() {
        let now = ProcessInfo.processInfo.systemUptime
        stretchUntil = now+3; life.nextBreak = now+life.breakInterval
        announce("Time for a little stretch",for: 5)
    }
    func startTimer(_ seconds: Double) {
        beginDrag(); life.focusEnd = ProcessInfo.processInfo.systemUptime+seconds; focusLength = seconds
        actionUntil = 0; typing.until = 0; treatPanel?.orderOut(nil); laserUntil = 0; yarn = nil; yarnPanel?.orderOut(nil); eyeRestUntil = 0
        announce("Focus together",for: 2)
    }
    func recordFocus() {
        let today = ISO8601DateFormatter.string(from: Date(),timeZone: .current,formatOptions: [.withFullDate])
        let count = (UserDefaults.standard.string(forKey: "focusDate") == today ? UserDefaults.standard.integer(forKey: "focusCount") : 0)+1
        UserDefaults.standard.set(today,forKey: "focusDate"); UserDefaults.standard.set(count,forKey: "focusCount"); refreshFocusStats()
    }
    func refreshFocusStats() {
        let today = ISO8601DateFormatter.string(from: Date(),timeZone: .current,formatOptions: [.withFullDate])
        focusStatsItem?.title = "Focus sessions today: \(UserDefaults.standard.string(forKey: "focusDate") == today ? UserDefaults.standard.integer(forKey: "focusCount") : 0)"
    }
    func saveMood() { UserDefaults.standard.set(mood.value,forKey: "mood"); UserDefaults.standard.set(Date().timeIntervalSince1970,forKey: "moodAt") }
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
    @objc func toggleOutfit(_ sender: NSMenuItem) {
        guard let item = Outfit(rawValue: sender.representedObject as? String ?? "") else { return }
        if outfit.contains(item) { outfit.remove(item) } else { if item.isHat { outfit = outfit.filter { !$0.isHat } }; outfit.insert(item); announce(item.quip,for: 2) }
        UserDefaults.standard.set(outfit.map { $0.rawValue }.sorted(),forKey: "wardrobe"); syncOptions()
    }
    @objc func toggleSeasonal() { seasonal.toggle(); UserDefaults.standard.set(seasonal,forKey: "seasonal"); syncOptions() }
    @objc func selectBedtime(_ sender: NSMenuItem) { bedtime = sender.representedObject as? Int ?? -1; UserDefaults.standard.set(bedtime,forKey: "bedtime"); lastBedtimeNag = 0; syncOptions() }
    func currentOutfit() -> Set<Outfit> {
        var worn = outfit
        if pastBedtime(hour: hour,bedtime: bedtime) { worn = worn.filter { !$0.isHat }; worn.insert(.nightcap) }
        else if seasonal, !worn.contains(where: { $0.isHat }), let hat = Outfit.seasonal(month: month,day: day) { worn.insert(hat) }
        return worn
    }
    @objc func toggleStrolls() { strolls.toggle(); UserDefaults.standard.set(strolls,forKey: "strolls"); nextStroll = ProcessInfo.processInfo.systemUptime+1500; syncOptions() }
    @objc func toggleWater() { waterReminders.toggle(); water.next = ProcessInfo.processInfo.systemUptime+water.interval; UserDefaults.standard.set(waterReminders,forKey: "waterReminders"); syncOptions() }
    @objc func toggleEyeRest() { eyeRest.toggle(); nextEyeRest = ProcessInfo.processInfo.systemUptime+1200; if !eyeRest { eyeRestUntil = 0 }; UserDefaults.standard.set(eyeRest,forKey: "eyeRest"); syncOptions() }
    @objc func startEyeRest() {
        let now = ProcessInfo.processInfo.systemUptime
        eyeRestUntil = now+20; nextEyeRest = now+1200; life.activity(at: now); playSound(purr: false)
    }
    @objc func startLaser() {
        let now = ProcessInfo.processInfo.systemUptime
        laserUntil = now+30; life.activity(at: now); excursion = nil; announce("Red dot. Mine.",for: 2)
    }
    /// Screen position of the sprite's middle (the view keeps hat headroom above the sprite).
    var petCenter: NSPoint { NSPoint(x: panel.frame.midX,y: panel.frame.minY+pet.frame.minY+pet.frame.height*0.41) }
    /// Walk toward a point and stay there. Returns false when the cat is already there.
    @discardableResult func pursue(toward point: NSPoint,kind: Excursion.Kind,speed: Double,stopShort: Double = 0) -> Bool {
        let center = petCenter
        let dx = point.x-center.x, dy = point.y-center.y, distance = max(1,hypot(dx,dy)), reach = max(0,distance-stopShort)
        let target = clampedOrigin(NSPoint(x: panel.frame.minX+dx/distance*reach,y: panel.frame.minY+dy/distance*reach))
        let travel = hypot(target.x-panel.frame.minX,target.y-panel.frame.minY)
        guard travel > 6 else { return false }
        let now = ProcessInfo.processInfo.systemUptime; life.activity(at: now)
        excursion = Excursion(kind: kind,origin: panel.frame.origin,target: target,start: now,duration: min(kind == .patrol ? 8 : 2.5,max(0.35,travel/speed)))
        return true
    }
    func startStroll() {
        let screen = NSScreen.screens.first { $0.frame.contains(panel.frame.center) } ?? NSScreen.main
        guard let f = screen?.visibleFrame else { return }
        let x = f.minX+24+Double(Int.random(in: 0...max(1,Int(f.width-panel.frame.width-48))))
        pursue(toward: NSPoint(x: x+panel.frame.width/2,y: petCenter.y),kind: .patrol,speed: 110)
    }
    @objc func tossYarn() {
        if yarnPanel == nil {
            let window = PetPanel(contentRect: NSRect(x: 0,y: 0,width: 32,height: 32),styleMask: [.borderless,.nonactivatingPanel],backing: .buffered,defer: false)
            window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false; window.level = .floating
            window.hidesOnDeactivate = false; window.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]; window.isReleasedWhenClosed = false
            let view = YarnView(frame: NSRect(x: 0,y: 0,width: 32,height: 32)); view.owner = self; window.contentView = view; yarnPanel = window
        }
        let side = panel.frame.midX > (NSScreen.main?.visibleFrame.midX ?? 0) ? -1.0 : 1.0
        let ball = YarnBall(position: NSPoint(x: panel.frame.midX+side*60,y: panel.frame.minY+30),velocity: NSPoint(x: side*320,y: 90))
        yarn = ball; yarnBats = 0; yarnFade = 0; beginDrag(); laserUntil = 0
        yarnPanel?.setFrameOrigin(NSPoint(x: ball.position.x-16,y: ball.position.y-16)); yarnPanel?.orderFrontRegardless()
        announce("Yarn!",for: 1.5)
    }
    func batYarn() {
        guard var ball = yarn else { return }
        let now = ProcessInfo.processInfo.systemUptime, away = ball.position.x >= panel.frame.midX ? 1.0 : -1.0
        ball.velocity = NSPoint(x: away*Double(Int.random(in: 300...460)),y: Double(Int.random(in: -40...130))); yarn = ball
        yarnBats += 1; play(3,duration: 0.6); mood.add(4)
        if yarnBats >= 4 { yarnFade = now+3; announce("Bored now.",for: 2.5) } else { announce("Whap.",for: 1.2) }
    }
    func kickYarn() {
        guard var ball = yarn else { return }
        let cursor = NSEvent.mouseLocation, dx = ball.position.x-cursor.x, dy = ball.position.y-cursor.y, d = max(1,hypot(dx,dy))
        ball.velocity = NSPoint(x: dx/d*380,y: dy/d*380); yarn = ball; yarnBats = min(yarnBats,3); yarnFade = 0; life.activity(at: ProcessInfo.processInfo.systemUptime)
    }
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
        terminalItem?.state = terminalEnabled ? .on : .off
        walkItem?.state = walkReminders ? .on : .off
        musicItem?.state = musicMode ? .on : .off; audioItem?.state = autoAudio ? .on : .off
        strollItem?.state = strolls ? .on : .off; waterItem?.state = waterReminders ? .on : .off; eyeRestItem?.state = eyeRest ? .on : .off
        seasonalItem?.state = seasonal ? .on : .off
        for (item,entry) in outfitItems { entry.state = outfit.contains(item) ? .on : .off }
        for (hour,entry) in bedtimeItems { entry.state = hour == bedtime ? .on : .off }
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
    @objc func giveTreat() { offerTreat(.fish) }
    @objc func offerWater() { offerTreat(.water) }
    func offerTreat(_ kind: TreatView.Kind) {
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
        (window.contentView as? TreatView)?.kind = kind
        window.orderFrontRegardless(); treatExpires = ProcessInfo.processInfo.systemUptime+(kind == .water ? 45 : 20)
        announce(kind == .water ? "Water break? Click the bowl" : "Click the fish",for: 4)
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
        panel.setContentSize(NSSize(width: width, height: width * 256 / 192 + 72)); screenChanged()
    }
    @objc func small() { resize(115) }
    @objc func large() { resize(192) }
    @objc func wave() { play(3, duration: 1.0) }
    @objc func jump() { play(4, duration: 0.85) }
    @objc func think() { play(7, duration: 2.0) }
    @objc func togglePause() { paused.toggle(); pauseItem.title = paused ? "Resume cursor following" : "Pause cursor following" }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationWillTerminate(_ notification: Notification) {
        terminalDesk?.shutdown(); timer?.invalidate(); removeKeyMonitors(); sound?.stop(); saveMood(); yarnPanel?.orderOut(nil)
        if let trip = excursion { panel.setFrameOrigin(trip.origin) }
        savePosition()
    }
}

extension NSRect { var center: NSPoint { NSPoint(x: midX,y: midY) } }

if CommandLine.arguments.contains("--self-test") {
    precondition(VoiceTerminalAction.parse("send_terminal",["terminal_id":1,"text":"claude","submit":true]) != nil)
    precondition(VoiceTerminalAction.parse("send_terminal",["terminal_id":true,"text":"claude","submit":true]) == nil)
    precondition(VoiceTerminalAction.parse("send_terminal",["terminal_id":1,"text":"a\nb","submit":true]) == nil)
    precondition(VoiceTerminalAction.parse("send_terminal",["terminal_id":1,"text":"ok"]) == nil)
    precondition(VoiceTerminalAction.parse("delete_files",[:]) == nil)
    precondition(VoiceTerminalAction.parse("interrupt_terminal",["terminal_id":2,"key":"escape"]) != nil)
    precondition(VoiceTerminalAction.parse("interrupt_terminal",["terminal_id":-1]) == nil)
    let terminal = TerminalEvent(kind: "failure",code: 1,duration: 4,time: 1,session: "ttys001",app: "vscode")
    precondition(terminal.valid && terminal.message == "ttys001: failed (1). That's on you.")
    precondition(TerminalEvent(kind: "milestone",code: 0,duration: 2,time: 1,session: "ttys002",app: "iterm").valid)
    precondition(TerminalEvent(kind: "success",code: 0,duration: 42,time: 1,session: "ttys002",app: "iterm").message == "ttys002: done after 42s. Finally.")
    var streak = WorkStreak()
    for _ in 0..<4 { precondition(streak.record(success: true) == nil) }
    precondition(streak.record(success: true) == 5 && streak.record(success: false) == nil && streak.count == 0)
    var mood = Mood(); mood.add(50); precondition(mood.value == 100 && mood.label == "delighted" && mood.chaseGap == 45)
    mood.decay(minutes: 900); precondition(mood.value == 10 && mood.label == "neglected" && mood.chaseGap == 150)
    precondition(pastBedtime(hour: 23,bedtime: 22) && pastBedtime(hour: 3,bedtime: 22) && !pastBedtime(hour: 12,bedtime: 22) && !pastBedtime(hour: 23,bedtime: 0) && pastBedtime(hour: 0,bedtime: 0) && !pastBedtime(hour: 23,bedtime: -1))
    precondition(Outfit.seasonal(month: 12,day: 10) == .santaHat && Outfit.seasonal(month: 10,day: 28) == .witchHat && Outfit.seasonal(month: 6,day: 1) == nil && Outfit.seasonal(month: 12,day: 30) == nil)
    var ball = YarnBall(position: NSPoint(x: 10,y: 10),velocity: NSPoint(x: -400,y: 0))
    ball.step(0.1,in: NSRect(x: 0,y: 0,width: 100,height: 100)); precondition(ball.position.x == 0 && ball.velocity.x > 0 && !ball.resting)
    for _ in 0..<200 { ball.step(0.1,in: NSRect(x: 0,y: 0,width: 100,height: 100)) }
    precondition(ball.resting && ball.position.x >= 0 && ball.position.x <= 100)
    let stroll = Excursion(kind: .patrol,origin: .zero,target: NSPoint(x: 100,y: 0),start: 0,duration: 2)
    precondition(!stroll.returns && stroll.position(at: 0) == .zero && stroll.position(at: 2) == stroll.target && stroll.position(at: 1).x == 50)
    precondition(PetView.ears.count == 16 && Outfit.allCases.filter { $0.isHat }.count == 5)
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
    // Every idle and gaze pose has fitted sunglasses; the far lens is hidden exactly when a profile temple arm is drawn.
    for (r,n) in [(0,6),(9,8),(10,8)] { for c in 0..<n { precondition(PetView.shades["\(r)-\(c)"] != nil) } }
    precondition(PetView.shades.count == 22 && PetView.shades.values.allSatisfy { $0.2 > 0 && ($0.5 > 0) == ($0.6 == 0) && $0.0 > 0 && $0.0 < 192 && $0.1 > 0 && $0.1 < 208 })
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
    print("PASS: life/focus/break transitions, excursion return and pursuit, typing speed/storage; 16 cursor directions, compass cases, deadzone, typing renewal/expiry, sprite resources, wardrobe anchors, terminal reactions, streaks, mood, bedtime, seasonal hats, and yarn physics")
} else if CommandLine.arguments.contains("--audio-startup-smoke") {
    _ = NSApplication.shared
    let desk = TerminalDesk(); let voice = GeminiVoice(desk: desk)
    do { try voice.startAudio(); print("PASS: audio engine started; no network session or audio storage") }
    catch { let e = error as NSError; print("FAIL: \(e.domain) \(e.code)") }
    voice.stop(); desk.shutdown()
} else if let index = CommandLine.arguments.firstIndex(of: "--render-voice"), CommandLine.arguments.count > index+1 {
    _ = NSApplication.shared
    let desk = TerminalDesk(); let voice = GeminiVoice(desk: desk)
    let view = voice.window.contentView!; view.wantsLayer = true; view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
    let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
    view.cacheDisplay(in: view.bounds,to: rep)
    try! rep.representation(using: .png,properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index+1]))
    desk.shutdown()
} else if let index = CommandLine.arguments.firstIndex(of: "--render-wardrobe"), CommandLine.arguments.count > index+1 {
    _ = NSApplication.shared
    // Optional third argument: comma-separated outfit names (default sunglasses). Idle frames also wear headphones.
    let worn = Set((CommandLine.arguments.count > index+2 ? CommandLine.arguments[index+2] : "sunglasses").split(separator: ",").compactMap { Outfit(rawValue: String($0)) })
    let poses = (0..<16).map { "\(9+$0/8)-\($0%8)" } + (0..<6).map { "0-\($0)" }
    let canvas = NSImage(size: NSSize(width: 1152,height: 1024))
    canvas.lockFocus()
    NSColor(calibratedWhite: 0.9,alpha: 1).setFill(); NSRect(x: 0,y: 0,width: 1152,height: 1024).fill()
    for (i,pose) in poses.enumerated() {
        let view = PetView(frame: NSRect(x: 0,y: 0,width: 192,height: 256))
        view.sprite = NSImage(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("frames/\(pose).png"))
        view.clock = 1; view.home = .cushion; view.pose = pose; view.outfit = worn
        view.gazeDirection = i < 16 ? i : nil; view.headphones = i >= 16
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform(); transform.translateX(by: Double(i%6)*192,yBy: Double(3-i/6)*256); transform.concat()
        view.draw(view.bounds)
        NSGraphicsContext.restoreGraphicsState()
    }
    canvas.unlockFocus()
    let rep = NSBitmapImageRep(data: canvas.tiffRepresentation!)!
    try! rep.representation(using: .png,properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[index+1]))
} else if let index = CommandLine.arguments.firstIndex(of: "--render-gallery"), CommandLine.arguments.count > index+1 {
    _ = NSApplication.shared
    let canvas = NSImage(size: NSSize(width: 768,height: 1024))
    canvas.lockFocus()
    NSColor(calibratedWhite: 0.9,alpha: 1).setFill(); NSRect(x: 0,y: 0,width: 768,height: 1024).fill()
    for i in 0..<16 {
        let view = PetView(frame: NSRect(x: 0,y: 0,width: 192,height: 256))
        view.sprite = NSImage(contentsOf: Bundle.main.resourceURL!.appendingPathComponent("frames/\(9+i/8)-\(i%8).png"))
        view.clock = 1; view.home = .cushion; view.gazeDirection = i
        view.headphones = true; view.typingPhase = nil
        view.snoozing = false; view.happy = false
        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform(); transform.translateX(by: Double(i%4)*192,yBy: Double(3-i/4)*256); transform.concat()
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
