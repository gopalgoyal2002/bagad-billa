import AppKit
import AVFoundation

struct VoiceTerminalAction {
    let name: String
    let terminalID: Int?
    let text: String
    let submit: Bool
    let key: String
    static func parse(_ name: String,_ args: [String:Any]) -> VoiceTerminalAction? {
        guard ["list_terminals","create_terminal","send_terminal","interrupt_terminal"].contains(name) else { return nil }
        var id: Int? = nil
        if let number = args["terminal_id"] as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID(),number.doubleValue == Double(number.intValue),number.intValue > 0 else { return nil }
            id = number.intValue
        }
        if name == "send_terminal" || name == "interrupt_terminal" { guard id != nil else { return nil } }
        let text = args["text"] as? String ?? ""
        if name == "send_terminal" {
            guard !text.isEmpty,text.utf8.count <= 16000,!text.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }),let flag = args["submit"] as? NSNumber,CFGetTypeID(flag) == CFBooleanGetTypeID() else { return nil }
        }
        let key = args["key"] as? String ?? "ctrl_c"
        guard ["ctrl_c","escape"].contains(key) else { return nil }
        return VoiceTerminalAction(name: name,terminalID: id,text: text,submit: args["submit"] as? Bool ?? false,key: key)
    }
}

// Mutable UI/session state is accessed on the main queue; audio/network callbacks dispatch back to it.
final class GeminiVoice: NSObject, NSWindowDelegate, @unchecked Sendable {
    weak var desk: TerminalDesk?
    let window = NSWindow(contentRect: NSRect(x: 0,y: 0,width: 600,height: 420),styleMask: [.titled,.closable],backing: .buffered,defer: false)
    let apiKey = NSSecureTextField()
    let model = NSTextField(string: "gemini-3.1-flash-live-preview")
    let status = NSTextField(labelWithString: "Disconnected · microphone off")
    let actions = NSButton(checkboxWithTitle: "Allow voice to control this pet’s terminals",target: nil,action: nil)
    let log = NSTextView()
    let micButton = NSButton(title: "Mute",target: nil,action: nil)
    var socket: URLSessionWebSocketTask?
    var network: URLSession?
    var generation = UUID()
    var connected = false
    var muted = true
    var starting = false
    var engine: AVAudioEngine?
    var player: AVAudioPlayerNode?
    var tapInstalled = false
    var pendingAudio = 0
    var playbackCount = 0
    var seenCalls: Set<String> = []
    var replies: [String:[String:Any]] = [:]
    var outgoing: Task<Void,Never>?
    var cancelledCalls: Set<String> = []
    var playbackGeneration = UUID()

    init(desk: TerminalDesk) {
        self.desk = desk; super.init()
        window.title = "Bagad Billa · Gemini Live"; window.isReleasedWhenClosed = false; window.delegate = self
        let root = window.contentView!
        func label(_ text: String,_ y: Double) {
            let v = NSTextField(labelWithString: text); v.frame = NSRect(x: 14,y: y,width: 570,height: 20); v.font = .systemFont(ofSize: 11); root.addSubview(v)
        }
        label("Microphone audio goes to Google while live. API usage charges may apply.",388)
        apiKey.frame = NSRect(x: 14,y: 347,width: 570,height: 28); apiKey.placeholderString = "Gemini API key — kept in memory only"; root.addSubview(apiKey)
        model.frame = NSRect(x: 14,y: 310,width: 570,height: 28); root.addSubview(model)
        actions.frame = NSRect(x: 14,y: 276,width: 570,height: 24); actions.state = .off; root.addSubview(actions)
        label("Scope: list/create tabs, send a line, Ctrl-C/Escape. No terminal output upload.",251)
        for (title,action,x) in [("Start voice",#selector(start),14.0),("Stop",#selector(stop),130.0)] {
            let b = NSButton(title: title,target: self,action: action); b.bezelStyle = .rounded; b.frame = NSRect(x: x,y: 212,width: 110,height: 30); root.addSubview(b)
        }
        micButton.target = self; micButton.action = #selector(toggleMic); micButton.bezelStyle = .rounded; micButton.frame = NSRect(x: 246,y: 212,width: 100,height: 30); root.addSubview(micButton)
        status.frame = NSRect(x: 14,y: 184,width: 570,height: 22); status.font = .systemFont(ofSize: 11,weight: .medium); root.addSubview(status)
        let scroll = NSScrollView(frame: NSRect(x: 14,y: 14,width: 570,height: 164)); scroll.hasVerticalScroller = true
        log.isEditable = false; log.isSelectable = true; log.font = .systemFont(ofSize: 11); log.autoresizingMask = [.width]; log.textContainer?.widthTracksTextView = true
        scroll.documentView = log; root.addSubview(scroll)
        window.center()
    }
    func show() { NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil) }
    func note(_ text: String) {
        log.string += text+"\n"
        if log.string.count > 18000 { log.string = String(log.string.suffix(14000)) }
        log.scrollToEndOfDocument(nil)
    }
    @objc func start() {
        guard !starting,!connected else { return }
        let key = apiKey.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = model.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty,!name.isEmpty,name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "." }) else { note("Enter your Gemini API key and Live model name first."); return }
        starting = true; status.stringValue = "Requesting microphone access…"
        let token = UUID(); generation = token
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self = self,self.generation == token else { return }
                guard allowed else { self.starting = false; self.status.stringValue = "Microphone access denied — enable it in macOS Settings"; return }
                self.connect(key: key,model: name,token: token)
            }
        }
    }
    func connect(key: String,model: String,token: UUID) {
        var url = URLComponents(string: "wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContent")!
        url.queryItems = [URLQueryItem(name: "key",value: key)]
        let config = URLSessionConfiguration.ephemeral
        network = URLSession(configuration: config)
        let task = network!.webSocketTask(with: url.url!); task.maximumMessageSize = 2_000_000; socket = task
        seenCalls = []; replies = [:]; cancelledCalls = []; status.stringValue = "Connecting to Gemini…"; task.resume()
        send(["setup":["model":"models/"+model,"generationConfig":["responseModalities":["AUDIO"]],"inputAudioTranscription":[:],"outputAudioTranscription":[:],"systemInstruction":["parts":[["text":"You are Bagad Billa, a concise voice companion. Only act on the user's explicit spoken requests. You can control only the pet's own terminal tabs with the provided tools. List tabs to obtain stable IDs before targeting any tab; ask the user if the target or exact text is ambiguous. Before sending text, say the tab ID and text you will send. Set submit true only when the user asks to execute or submit. Use Ctrl-C to interrupt shell programs, Escape when explicitly requested for Claude. Tool results say queued, not command succeeded. Never claim you saw terminal output. You cannot access other apps, files, or terminals. Tool errors mean the action did not happen. Do not invent tab IDs or issue follow-up commands without user request."]]],"tools":[["functionDeclarations":Self.declarations]]]])
        receive(task,token: token)
        DispatchQueue.main.asyncAfter(deadline: .now()+20) { [weak self] in
            if let self = self,self.generation == token,!self.connected { self.fail("Connection timed out. Check the API key, model access, and network.") }
        }
    }
    static var declarations: [[String:Any]] {
        [
            ["name":"list_terminals","description":"List only terminals created by this pet, including their stable numeric IDs and readiness.","parameters":["type":"OBJECT","properties":[:]]],
            ["name":"create_terminal","description":"Create a new terminal tab in the user's home directory.","parameters":["type":"OBJECT","properties":[:]]],
            ["name":"send_terminal","description":"Queue exact user-requested single-line text into a pet terminal. submit true sends Enter. Never send commands not requested by the user.","parameters":["type":"OBJECT","properties":["terminal_id":["type":"INTEGER"],"text":["type":"STRING"],"submit":["type":"BOOLEAN"]],"required":["terminal_id","text","submit"]]],
            ["name":"interrupt_terminal","description":"Send Ctrl-C or Escape to the explicitly selected pet terminal. Does not force-kill processes.","parameters":["type":"OBJECT","properties":["terminal_id":["type":"INTEGER"],"key":["type":"STRING","enum":["ctrl_c","escape"]]],"required":["terminal_id","key"]]]
        ]
    }
    func send(_ object: [String:Any],audio: Bool = false) {
        guard let task = socket,let data = try? JSONSerialization.data(withJSONObject: object),let text = String(data: data,encoding: .utf8) else { return }
        if audio { guard pendingAudio < 6 else { return }; pendingAudio += 1 }
        let token = generation
        let previous = outgoing
        outgoing = Task { [weak self] in
            await previous?.value
            do { try await task.send(.string(text)) }
            catch { DispatchQueue.main.async { if self?.generation == token { self?.fail("Gemini connection failed. Check your key, model access, or network.") } } }
            if audio { DispatchQueue.main.async { if self?.generation == token { self?.pendingAudio = max(0,(self?.pendingAudio ?? 1)-1) } } }
        }
    }
    func receive(_ task: URLSessionWebSocketTask,token: UUID) {
        Task { [weak self] in
            do {
                let message = try await task.receive()
                let data: Data
                switch message { case .data(let bytes): data = bytes; case .string(let text): data = Data(text.utf8); @unknown default: return }
                let json = (try? JSONSerialization.jsonObject(with: data)) as? [String:Any]
                DispatchQueue.main.async {
                    guard let self = self,self.generation == token else { return }
                    if let json = json { self.handle(json) }
                    if self.generation == token { self.receive(task,token: token) }
                }
            } catch { DispatchQueue.main.async { if self?.generation == token { self?.fail("Gemini disconnected. Check API access, model availability, or reconnect.") } } }
        }
    }
    func handle(_ message: [String:Any]) {
        if message["error"] != nil { fail("Gemini rejected the session. Check API key, quota, and Live model access."); return }
        if message["setupComplete"] != nil {
            connected = true; starting = false
            do { try startAudio(); status.stringValue = "● LIVE — microphone audio is being sent to Gemini"; note("Connected. Terminal actions: "+(actions.state == .on ? "enabled" : "disabled")) }
            catch { fail("Could not start microphone/speakers. Check your audio devices.") }
        }
        if let cancellation = message["toolCallCancellation"] as? [String:Any],let ids = cancellation["ids"] as? [String] { cancelledCalls.formUnion(ids) }
        if let content = message["serverContent"] as? [String:Any] {
            if content["interrupted"] as? Bool == true { player?.stop(); player?.play(); playbackCount = 0; playbackGeneration = UUID() }
            if let transcript = content["inputTranscription"] as? [String:Any],let text = transcript["text"] as? String { note("You: "+text) }
            if let transcript = content["outputTranscription"] as? [String:Any],let text = transcript["text"] as? String { note("Gemini: "+text) }
            if let turn = content["modelTurn"] as? [String:Any],let parts = turn["parts"] as? [[String:Any]] {
                for part in parts {
                    if let inline = part["inlineData"] as? [String:Any],let mime = inline["mimeType"] as? String,mime.hasPrefix("audio/pcm"),let encoded = inline["data"] as? String,let audio = Data(base64Encoded: encoded) { playAudio(audio) }
                }
            }
        }
        if let tools = message["toolCall"] as? [String:Any],let calls = tools["functionCalls"] as? [[String:Any]] {
            for call in calls {
                guard connected,let id = call["id"] as? String,let name = call["name"] as? String,!cancelledCalls.contains(id) else { continue }
                if let cached = replies[id] { send(["toolResponse":["functionResponses":[cached]]]); continue }
                guard seenCalls.count < 1000 else { fail("Session action limit reached. Reconnect to continue."); return }
                seenCalls.insert(id)
                let result: [String:Any]
                if actions.state != .on { result = ["error":"Terminal control is disabled by the user."] }
                else if let parsed = VoiceTerminalAction.parse(name,call["args"] as? [String:Any] ?? [:]),let desk = desk { result = desk.voiceAction(parsed) }
                else { result = ["error":"Invalid action or terminal desk unavailable."] }
                note("Tool: "+name+" → "+String(describing: result))
                let reply: [String:Any] = ["id":id,"name":name,"response":result]
                replies[id] = reply
                send(["toolResponse":["functionResponses":[reply]]])
            }
        }
        if message["goAway"] != nil { note("Gemini session will expire soon. Stop and reconnect when ready.") }
    }
    func startAudio() throws {
        let engine = AVAudioEngine(); let player = AVAudioPlayerNode(); self.engine = engine; self.player = player
        let input = engine.inputNode
        try? input.setVoiceProcessingEnabled(true)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0,format.channelCount > 0,format.commonFormat == .pcmFormatFloat32 else { throw NSError(domain: "VoiceAudio",code: 1) }
        let output = AVAudioFormat(commonFormat: .pcmFormatFloat32,sampleRate: 24000,channels: 1,interleaved: false)!
        engine.attach(player); engine.connect(player,to: engine.mainMixerNode,format: output)
        let token = generation
        input.installTap(onBus: 0,bufferSize: 4096,format: format) { [weak self] buffer,_ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
            var data = Data(capacity: Int(buffer.frameLength)*2)
            for i in 0..<Int(buffer.frameLength) {
                let sample = samples[i*stride]
                var value = Int16(max(-32767,min(32767,(sample.isFinite ? sample : 0)*32767))).littleEndian
                withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
            }
            let rate = Int(buffer.format.sampleRate)
            DispatchQueue.main.async {
                guard let self = self,self.generation == token,self.connected,!self.muted else { return }
                self.send(["realtimeInput":["audio":["data":data.base64EncodedString(),"mimeType":"audio/pcm;rate=\(rate)"]]],audio: true)
            }
        }
        tapInstalled = true; engine.prepare(); try engine.start(); player.play(); muted = false; micButton.title = "Mute"
    }
    func playAudio(_ data: Data) {
        guard connected,data.count > 0,data.count % 2 == 0,data.count <= 480000,playbackCount < 100,let player = player,let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,sampleRate: 24000,channels: 1,interleaved: false),let buffer = AVAudioPCMBuffer(pcmFormat: format,frameCapacity: AVAudioFrameCount(data.count/2)),let samples = buffer.floatChannelData?[0] else { return }
        buffer.frameLength = buffer.frameCapacity
        for i in 0..<Int(buffer.frameLength) {
            let value = UInt16(data[2*i]) | (UInt16(data[2*i+1]) << 8)
            samples[i] = Float(Int16(bitPattern: value))/32768
        }
        playbackCount += 1; let token = playbackGeneration
        player.scheduleBuffer(buffer) { [weak self] in DispatchQueue.main.async { if self?.playbackGeneration == token { self?.playbackCount = max(0,(self?.playbackCount ?? 1)-1) } } }
    }
    @objc func toggleMic() {
        guard connected else { return }; muted.toggle(); micButton.title = muted ? "Unmute" : "Mute"
        status.stringValue = muted ? "Connected · microphone muted" : "● LIVE — microphone audio is being sent to Gemini"
        if muted { send(["realtimeInput":["audioStreamEnd":true]]) }
    }
    @objc func stop() {
        generation = UUID(); connected = false; starting = false; muted = true
        if tapInstalled { engine?.inputNode.removeTap(onBus: 0); tapInstalled = false }
        player?.stop(); engine?.stop(); player = nil; engine = nil; playbackCount = 0; pendingAudio = 0; playbackGeneration = UUID()
        socket?.cancel(with: .normalClosure,reason: nil); socket = nil; network?.invalidateAndCancel(); network = nil; outgoing?.cancel(); outgoing = nil
        status.stringValue = "Disconnected · microphone off"; micButton.title = "Mute"
    }
    func fail(_ text: String) { stop(); status.stringValue = text; note(text) }
    func windowShouldClose(_ sender: NSWindow) -> Bool { stop(); window.orderOut(nil); return false }
}
