import AppKit

enum Outfit: String, CaseIterable {
    case sunglasses, monocle, bowtie, scarf, partyHat, crown, santaHat, witchHat, nightcap
    var isHat: Bool { self == .partyHat || self == .crown || self == .santaHat || self == .witchHat || self == .nightcap }
    var title: String {
        switch self {
        case .sunglasses: return "Sunglasses — cool mode"
        case .monocle: return "Monocle"
        case .bowtie: return "Bow tie"
        case .scarf: return "Knit scarf"
        case .partyHat: return "Party hat"
        case .crown: return "Crown"
        case .santaHat: return "Santa hat"
        case .witchHat: return "Witch hat"
        case .nightcap: return "Nightcap"
        }
    }
    var quip: String {
        switch self {
        case .sunglasses: return "Deal with it."
        case .monocle: return "Quite."
        case .bowtie: return "Fancy."
        case .scarf: return "Cozy. Acceptable."
        case .crown: return "Bow before me."
        default: return "Hat. Tolerable."
        }
    }
    /// Calendar auto-dress from the local clock only: Santa hat through most of December, witch hat for Halloween week.
    static func seasonal(month: Int, day: Int) -> Outfit? { month == 12 && day <= 26 ? .santaHat : month == 10 && day >= 24 ? .witchHat : nil }
}

/// Bedtime runs from the chosen hour until 5 AM; -1 disables it.
func pastBedtime(hour: Int, bedtime: Int) -> Bool {
    guard bedtime >= 0 else { return false }
    let h = hour < 5 ? hour+24 : hour, b = bedtime < 5 ? bedtime+24 : bedtime
    return h >= b && h < 29
}

extension PetView {
    // Ear-cup centers per gaze direction in the original 192x208 sprite, bottom-left coordinates; the flag marks profile poses.
    static let ears: [(Double,Double,Double,Double,Bool)] = [
        (43,183,125,183,false), (48,184,106,194,true),
        (49,180,113,193,true), (57,180,119,193,true),
        (96,183,119,181,true), (82,147,137,179,true),
        (63,144,135,171,true), (73,133,148,158,false),
        (39,158,125,158,false), (33,152,107,141,false),
        (38,185,108,157,true), (60,184,111,160,true),
        (43,183,94,166,true), (62,184,113,176,true),
        (65,187,121,179,true), (68,188,135,181,true)
    ]
    static let idleEars: (Double,Double,Double,Double,Bool) = (43,181,128,181,false)
    // Sunglasses lens centers per sprite (row-col), bottom-left coordinates: image-left lens x, y, width,
    // image-right lens x, y, width (0 hides it), then the temple-arm direction for profile poses (-1 left, 1 right, 0 none).
    static let shades: [String: (Double,Double,Double,Double,Double,Double,Double)] = [
        "0-0": (60,138,28,104,138,28,0), "0-1": (60,139,28,104,139,28,0), "0-2": (61,137,28,102,134,28,0),
        "0-3": (64,137,28,104,134,28,0), "0-4": (42,140,20,76,142,26,0), "0-5": (62,137,28,103,137,28,0),
        "9-0": (65,170,28,103,170,28,0), "9-1": (100,171,26,121,175,12,0), "9-2": (104,176,24,122,177,10,0),
        "9-3": (119,175,20,0,0,0,-1), "9-4": (130,153,18,0,0,0,-1), "9-5": (116,107,22,0,0,0,-1),
        "9-6": (101,94,22,131,107,12,0), "9-7": (102,80,22,127,84,10,0),
        "10-0": (60,103,28,104,103,28,0), "10-1": (55,96,22,88,89,20,0), "10-2": (38,112,12,63,100,22,0),
        "10-3": (48,108,20,0,0,0,1), "10-4": (41,111,18,0,0,0,1), "10-5": (33,132,12,49,123,22,0),
        "10-6": (40,156,12,56,150,24,0), "10-7": (47,163,14,76,163,26,0)
    ]
    var earFit: (Double,Double,Double,Double,Bool) { gazeDirection.map { PetView.ears[$0] } ?? PetView.idleEars }

    /// Face and neck accessories, drawn between the sprite and the headphones.
    func drawOutfit(in body: NSRect) {
        guard !outfit.isEmpty, let f = PetView.shades[pose] else { return }
        let bx = body.width/192, by = body.height/208
        func point(_ x: Double,_ y: Double) -> NSPoint { NSPoint(x: body.minX+x*bx,y: body.minY+y*by) }
        // The neck sits a fixed distance under the eyes and drifts toward the body's center line as the head turns.
        let mid = f.5 > 0 ? ((f.0+f.3)/2,(f.1+f.4)/2) : (f.0,f.1)
        let neck = point(mid.0+(96-mid.0)*0.35,mid.1-40)
        if outfit.contains(.scarf) { drawScarf(at: neck,bx: bx,by: by) }
        if outfit.contains(.bowtie) { drawBowTie(at: neck,bx: bx,by: by) }
        if outfit.contains(.sunglasses) { drawSunglasses(f,body: body,bx: bx,by: by,point: point) }
        if outfit.contains(.monocle) { drawMonocle(at: f.5 > 0 ? point(f.3,f.4) : point(f.0,f.1),bx: bx,by: by) }
    }

    /// Hats sit on the crown between the ear anchors and draw above the headphones.
    func drawHat(in body: NSRect) {
        guard headphonesFitAvailable, let hat = outfit.first(where: { $0.isHat }) else { return }
        let bx = body.width/192, by = body.height/208, e = earFit
        // The crown sits midway between the ear anchors; averaging their heights keeps hats seated on turned heads.
        let top = NSPoint(x: body.minX+(e.0+e.2)/2*bx,y: body.minY+((e.1+e.3)/2+4)*by)
        func p(_ dx: Double,_ dy: Double) -> NSPoint { NSPoint(x: top.x+dx*bx,y: top.y+dy*by) }
        func box(_ x: Double,_ y: Double,_ w: Double,_ h: Double) -> NSRect { NSRect(x: top.x+x*bx,y: top.y+y*by,width: w*bx,height: h*by) }
        func outline(_ path: NSBezierPath,_ color: NSColor,_ width: Double) { color.setStroke(); path.lineWidth = width*bx; path.stroke() }
        switch hat {
        case .partyHat:
            let cone = NSBezierPath(); cone.move(to: p(-20,0)); cone.line(to: p(0,44)); cone.line(to: p(20,0)); cone.close()
            NSColor(calibratedRed: 0.95,green: 0.55,blue: 0.3,alpha: 1).setFill(); cone.fill()
            NSGraphicsContext.saveGraphicsState(); cone.addClip()
            NSColor(calibratedRed: 1,green: 0.86,blue: 0.4,alpha: 1).setFill()
            for i in 0..<4 { let y = Double(i)*12, band = NSBezierPath(); band.move(to: p(-24,y-6)); band.line(to: p(24,y+4)); band.line(to: p(24,y+9)); band.line(to: p(-24,y-1)); band.close(); band.fill() }
            NSGraphicsContext.restoreGraphicsState()
            outline(cone,NSColor(calibratedRed: 0.6,green: 0.3,blue: 0.15,alpha: 1),1.2)
            NSColor(calibratedRed: 0.3,green: 0.75,blue: 0.8,alpha: 1).setFill(); NSBezierPath(ovalIn: box(-5,40,10,10)).fill()
        case .crown:
            let crown = NSBezierPath(); crown.move(to: p(-20,0))
            for (x,y) in [(-20.0,22.0),(-13,12),(-7,24),(0,13),(7,24),(13,12),(20,22),(20,0)] { crown.line(to: p(x,y)) }
            crown.close()
            NSColor(calibratedRed: 0.96,green: 0.78,blue: 0.2,alpha: 1).setFill(); crown.fill()
            outline(crown,NSColor(calibratedRed: 0.6,green: 0.45,blue: 0.05,alpha: 1),1.2)
            for (x,color) in [(-11.0,NSColor.systemRed),(0,NSColor.systemBlue),(11,NSColor.systemGreen)] { color.setFill(); NSBezierPath(ovalIn: box(x-3,4,6,6)).fill() }
        case .santaHat:
            let cone = NSBezierPath(); cone.move(to: p(-22,2)); cone.curve(to: p(26,40),controlPoint1: p(-14,34),controlPoint2: p(6,44)); cone.curve(to: p(22,2),controlPoint1: p(20,30),controlPoint2: p(22,16)); cone.close()
            NSColor(calibratedRed: 0.82,green: 0.12,blue: 0.15,alpha: 1).setFill(); cone.fill()
            outline(cone,NSColor(calibratedRed: 0.5,green: 0.05,blue: 0.08,alpha: 1),1)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: box(-25,-3,50,10),xRadius: 5*bx,yRadius: 5*by).fill()
            NSBezierPath(ovalIn: box(20,34,12,12)).fill()
        case .witchHat:
            NSColor(calibratedWhite: 0.12,alpha: 1).setFill()
            NSBezierPath(ovalIn: box(-32,-4,64,12)).fill()
            let cone = NSBezierPath(); cone.move(to: p(-19,3)); cone.curve(to: p(8,48),controlPoint1: p(-10,30),controlPoint2: p(-4,46)); cone.curve(to: p(19,3),controlPoint1: p(14,36),controlPoint2: p(18,18)); cone.close(); cone.fill()
            NSColor(calibratedRed: 0.5,green: 0.25,blue: 0.65,alpha: 1).setFill(); box(-17,6,34,5).fill()
            NSColor(calibratedRed: 0.95,green: 0.78,blue: 0.25,alpha: 1).setFill(); box(-3,5,6,7).fill()
        default:
            // Nightcap: a soft striped cone that droops to one side, with a pompom.
            let cap = NSBezierPath(); cap.move(to: p(-22,2)); cap.curve(to: p(34,18),controlPoint1: p(-16,36),controlPoint2: p(14,40)); cap.curve(to: p(22,2),controlPoint1: p(26,14),controlPoint2: p(22,10)); cap.close()
            NSColor(calibratedRed: 0.55,green: 0.7,blue: 0.9,alpha: 1).setFill(); cap.fill()
            NSGraphicsContext.saveGraphicsState(); cap.addClip()
            NSColor(calibratedWhite: 1,alpha: 0.55).setFill()
            for i in 0..<3 { box(-24,9+Double(i)*11,60,4).fill() }
            NSGraphicsContext.restoreGraphicsState()
            outline(cap,NSColor(calibratedRed: 0.3,green: 0.42,blue: 0.62,alpha: 1),1)
            NSColor.white.setFill()
            NSBezierPath(roundedRect: box(-25,-3,50,9),xRadius: 4*bx,yRadius: 4*by).fill()
            NSBezierPath(ovalIn: box(29,12,11,11)).fill()
        }
    }

    func drawSunglasses(_ f: (Double,Double,Double,Double,Double,Double,Double),body: NSRect,bx: Double,by: Double,point: (Double,Double) -> NSPoint) {
        // Light frames with a translucent teal gradient; lenses are 20% wider than the eye anchors and share the body transform.
        // The narrower far lens on three-quarter poses tucks behind the near lens, and the bridge only spans a real gap.
        let h = 21.0, lenses = [(f.0,f.1,f.2*1.2),(f.3,f.4,f.5*1.2)].filter { $0.2 > 0 }.sorted { $0.2 > $1.2 }
        func frame(_ path: NSBezierPath,_ width: Double) {
            NSColor(calibratedWhite: 0.42,alpha: 0.9).setStroke(); path.lineWidth = (width+1.4)*bx; path.stroke()
            NSColor(calibratedWhite: 0.94,alpha: 1).setStroke(); path.lineWidth = width*bx; path.stroke()
        }
        func shape(_ lens: (Double,Double,Double)) -> NSBezierPath {
            let rect = NSRect(x: body.minX+(lens.0-lens.2/2)*bx,y: body.minY+(lens.1-h/2)*by,width: lens.2*bx,height: h*by)
            return NSBezierPath(roundedRect: rect,xRadius: min(lens.2,h)*0.35*bx,yRadius: min(lens.2,h)*0.35*by)
        }
        if lenses.count == 2 {
            let left = lenses[0].0 < lenses[1].0 ? lenses[0] : lenses[1], right = lenses[0].0 < lenses[1].0 ? lenses[1] : lenses[0]
            if right.0-right.2/2 > left.0+left.2/2+1 {
                let bridge = NSBezierPath(); bridge.move(to: point(left.0+left.2/2-1,left.1+2)); bridge.line(to: point(right.0-right.2/2+1,right.1+2)); frame(bridge,2.5)
            }
        } else if let lens = lenses.first, f.6 != 0 {
            let arm = NSBezierPath(); arm.move(to: point(lens.0+f.6*(lens.2/2-1),lens.1+1)); arm.line(to: point(lens.0+f.6*(lens.2/2+20),lens.1+6)); arm.lineCapStyle = .round; frame(arm,2.5)
        }
        for lens in lenses.reversed() {
            let glass = shape(lens)
            NSGraphicsContext.saveGraphicsState()
            if lens.2 < lenses[0].2 { let mask = NSBezierPath(rect: bounds); mask.append(shape(lenses[0])); mask.windingRule = .evenOdd; mask.addClip() }
            NSGradient(starting: NSColor(calibratedRed: 0.50,green: 0.78,blue: 0.86,alpha: 0.72),ending: NSColor(calibratedRed: 0.80,green: 0.92,blue: 0.96,alpha: 0.42))!.draw(in: glass,angle: -90)
            NSGraphicsContext.saveGraphicsState(); glass.addClip()
            NSColor(calibratedWhite: 1,alpha: 0.4).setFill()
            let r = glass.bounds, gloss = NSBezierPath()
            gloss.move(to: NSPoint(x: r.minX+r.width*0.12,y: r.maxY)); gloss.line(to: NSPoint(x: r.minX+r.width*0.42,y: r.maxY)); gloss.line(to: NSPoint(x: r.minX+r.width*0.22,y: r.minY)); gloss.line(to: NSPoint(x: r.minX,y: r.minY)); gloss.close(); gloss.fill()
            NSGraphicsContext.restoreGraphicsState()
            frame(glass,2)
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    func drawMonocle(at center: NSPoint,bx: Double,by: Double) {
        let r = 11.0, ring = NSBezierPath(ovalIn: NSRect(x: center.x-r*bx,y: center.y-r*by,width: 2*r*bx,height: 2*r*by))
        NSGradient(starting: NSColor(calibratedWhite: 1,alpha: 0.45),ending: NSColor(calibratedRed: 0.7,green: 0.85,blue: 0.95,alpha: 0.25))!.draw(in: ring,angle: -60)
        NSColor(calibratedRed: 0.82,green: 0.64,blue: 0.2,alpha: 1).setStroke(); ring.lineWidth = 2.2*bx; ring.stroke()
        let chain = NSBezierPath(); chain.move(to: NSPoint(x: center.x+r*0.7*bx,y: center.y-r*0.7*by))
        chain.curve(to: NSPoint(x: center.x+(r+14)*bx,y: center.y-(r+22)*by),controlPoint1: NSPoint(x: center.x+(r+2)*bx,y: center.y-(r+8)*by),controlPoint2: NSPoint(x: center.x+(r+14)*bx,y: center.y-(r+10)*by))
        chain.lineWidth = 1.2*bx; chain.setLineDash([1.5*bx,1.5*bx],count: 2,phase: 0); chain.stroke()
    }

    func drawBowTie(at n: NSPoint,bx: Double,by: Double) {
        let tie = NSBezierPath()
        for side in [-1.0,1.0] {
            tie.move(to: NSPoint(x: n.x+side*14*bx,y: n.y+8*by)); tie.line(to: NSPoint(x: n.x+side*2*bx,y: n.y+2*by))
            tie.line(to: NSPoint(x: n.x+side*2*bx,y: n.y-2*by)); tie.line(to: NSPoint(x: n.x+side*14*bx,y: n.y-8*by)); tie.close()
        }
        NSColor(calibratedRed: 0.85,green: 0.15,blue: 0.22,alpha: 1).setFill(); tie.fill()
        NSColor(calibratedRed: 0.55,green: 0.05,blue: 0.1,alpha: 1).setStroke(); tie.lineWidth = 1*bx; tie.stroke()
        NSColor(calibratedRed: 0.65,green: 0.08,blue: 0.14,alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: n.x-3.5*bx,y: n.y-4*by,width: 7*bx,height: 8*by),xRadius: 2*bx,yRadius: 2*by).fill()
    }

    func drawScarf(at n: NSPoint,bx: Double,by: Double) {
        let band = NSBezierPath(roundedRect: NSRect(x: n.x-27*bx,y: n.y-3*by,width: 54*bx,height: 13*by),xRadius: 6*bx,yRadius: 6*by)
        let tail = NSBezierPath(roundedRect: NSRect(x: n.x-19*bx,y: n.y-26*by,width: 12*bx,height: 26*by),xRadius: 3*bx,yRadius: 3*by)
        let wool = NSColor(calibratedRed: 0.84,green: 0.3,blue: 0.26,alpha: 1), stripe = NSColor(calibratedRed: 0.98,green: 0.72,blue: 0.35,alpha: 1), edge = NSColor(calibratedRed: 0.5,green: 0.15,blue: 0.12,alpha: 1)
        for shape in [tail,band] {
            wool.setFill(); shape.fill()
            NSGraphicsContext.saveGraphicsState(); shape.addClip(); stripe.setFill()
            var x = n.x-30*bx
            while x < n.x+30*bx { NSRect(x: x,y: n.y-30*by,width: 4*bx,height: 50*by).fill(); x += 9*bx }
            NSGraphicsContext.restoreGraphicsState()
            edge.setStroke(); shape.lineWidth = 1*bx; shape.stroke()
        }
        edge.setStroke()
        for i in 0..<3 {
            let fringe = NSBezierPath(); fringe.move(to: NSPoint(x: n.x+(-17+Double(i)*4)*bx,y: n.y-26*by)); fringe.line(to: NSPoint(x: n.x+(-18+Double(i)*4)*bx,y: n.y-31*by))
            fringe.lineWidth = 1.2*bx; fringe.stroke()
        }
    }
}
