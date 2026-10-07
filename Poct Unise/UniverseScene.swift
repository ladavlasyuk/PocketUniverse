import SpriteKit
import UIKit

enum BodyKind {
    case seedStar
    case newbornStar
    case matter
    case planet
    case blackHole
}

final class UniverseScene: SKScene, SKPhysicsContactDelegate {
    var onExit: (() -> Void)?

    private let tier: UniverseTier
    private let worldNode = SKNode()
    private let hudNode = SKNode()
    private let topPanel = SKShapeNode()
    private let bottomPanel = SKShapeNode()
    private let backButton = SKShapeNode()
    private let saveButton = SKShapeNode()
    private let tierLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private let infoLabel = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
    private let hintPrimaryLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let hintSecondaryLabel = SKLabelNode(fontNamed: "AvenirNext-Medium")
    private let gravityLabel = SKLabelNode(fontNamed: "AvenirNext-Bold")
    private var backdropGradient: SKSpriteNode?

    private var gravityStrength: CGFloat = 0.35
    private var flowDirection = CGVector(dx: 0, dy: 0)
    private var matterCount = 0
    private var starCount = 1
    private var planetCount = 0
    private var collisionCount = 0
    private var sessionStart = CACurrentMediaTime()
    private var longPressTimer: Timer?
    private var longPressPoint: CGPoint?
    private var pinchStartGravity: CGFloat = 0.35
    private var backgroundStars: [SKShapeNode] = []
    private var lastShakeTimestamp: TimeInterval = 0

    private let seedCategory: UInt32 = 1
    private let matterCategory: UInt32 = 2
    private let starCategory: UInt32 = 4
    private let planetCategory: UInt32 = 8

    init(size: CGSize, tier: UniverseTier) {
        self.tier = tier
        self.gravityStrength = tier.gravityScale
        super.init(size: size)
        scaleMode = .resizeFill
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMove(to view: SKView) {
        backgroundColor = UIColor(red: 0.01, green: 0.02, blue: 0.07, alpha: 1)
        physicsWorld.gravity = .zero
        physicsWorld.contactDelegate = self
        anchorPoint = CGPoint(x: 0.5, y: 0.5)

        addChild(worldNode)
        addChild(hudNode)
        buildBackdrop()
        buildSeedStar()
        buildHUD()
        layoutHUD()
        refreshHUD()
        showIntroGuide()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        layoutHUD()
        if let backdropGradient {
            backdropGradient.size = size
            backdropGradient.texture = makeGradientTexture()
        }
    }

    private func buildBackdrop() {
        let gradient = SKSpriteNode(texture: makeGradientTexture(), size: size)
        gradient.zPosition = -30
        backdropGradient = gradient
        addChild(gradient)

        for _ in 0..<80 {
            let star = SKShapeNode(circleOfRadius: CGFloat.random(in: 0.6...1.8))
            star.fillColor = tier.glow.withAlphaComponent(CGFloat.random(in: 0.2...0.8))
            star.strokeColor = .clear
            star.position = CGPoint(x: CGFloat.random(in: -size.width / 2...size.width / 2), y: CGFloat.random(in: -size.height / 2...size.height / 2))
            star.zPosition = -20
            worldNode.addChild(star)
            backgroundStars.append(star)
        }
    }

    private func makeGradientTexture() -> SKTexture {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            let colors = [tier.glow.withAlphaComponent(0.35).cgColor, UIColor(red: 0.01, green: 0.02, blue: 0.08, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [])
            }
        }
        return SKTexture(image: image)
    }

    private func buildSeedStar() {
        let radius: CGFloat = 10
        let node = SKShapeNode(circleOfRadius: radius)
        node.fillColor = tier.accent
        node.strokeColor = UIColor.white.withAlphaComponent(0.5)
        node.lineWidth = 1.5
        node.glowWidth = 4
        node.position = .zero
        node.name = "seed"
        node.zPosition = 5
        node.physicsBody = SKPhysicsBody(circleOfRadius: radius)
        node.physicsBody?.isDynamic = false
        node.physicsBody?.categoryBitMask = seedCategory
        node.physicsBody?.collisionBitMask = matterCategory | starCategory | planetCategory
        node.physicsBody?.contactTestBitMask = matterCategory | starCategory | planetCategory
        worldNode.addChild(node)

        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.08, duration: 1.1),
            SKAction.scale(to: 1.0, duration: 1.1)
        ])
        node.run(SKAction.repeatForever(pulse))
    }

    private func buildHUD() {
        topPanel.fillColor = UIColor.black.withAlphaComponent(0.42)
        topPanel.strokeColor = UIColor.white.withAlphaComponent(0.08)
        topPanel.zPosition = 18
        hudNode.addChild(topPanel)

        bottomPanel.fillColor = UIColor.black.withAlphaComponent(0.42)
        bottomPanel.strokeColor = UIColor.white.withAlphaComponent(0.08)
        bottomPanel.zPosition = 18
        hudNode.addChild(bottomPanel)

        backButton.path = CGPath(roundedRect: CGRect(x: -46, y: -16, width: 92, height: 32), cornerWidth: 10, cornerHeight: 10, transform: nil)
        backButton.fillColor = UIColor.white.withAlphaComponent(0.14)
        backButton.strokeColor = UIColor.white.withAlphaComponent(0.28)
        backButton.zPosition = 20
        backButton.name = "back"
        hudNode.addChild(backButton)

        let backText = SKLabelNode(text: "EXIT")
        backText.fontName = "AvenirNext-Bold"
        backText.fontSize = 13
        backText.verticalAlignmentMode = .center
        backText.name = "back"
        backButton.addChild(backText)

        saveButton.path = CGPath(roundedRect: CGRect(x: -58, y: -16, width: 116, height: 32), cornerWidth: 10, cornerHeight: 10, transform: nil)
        saveButton.fillColor = tier.accent.withAlphaComponent(0.32)
        saveButton.strokeColor = tier.accent
        saveButton.zPosition = 20
        saveButton.name = "save"
        hudNode.addChild(saveButton)

        let saveText = SKLabelNode(text: "SAVE")
        saveText.fontName = "AvenirNext-Bold"
        saveText.fontSize = 13
        saveText.verticalAlignmentMode = .center
        saveText.name = "save"
        saveButton.addChild(saveText)

        tierLabel.fontSize = 13
        tierLabel.fontColor = tier.accent
        tierLabel.zPosition = 20
        tierLabel.text = tier.name.uppercased()
        hudNode.addChild(tierLabel)

        infoLabel.fontSize = 13
        infoLabel.fontColor = UIColor.white.withAlphaComponent(0.92)
        infoLabel.zPosition = 20
        hudNode.addChild(infoLabel)

        gravityLabel.fontSize = 13
        gravityLabel.fontColor = tier.accent
        gravityLabel.zPosition = 20
        hudNode.addChild(gravityLabel)

        hintPrimaryLabel.fontSize = 11
        hintPrimaryLabel.fontColor = UIColor.white.withAlphaComponent(0.62)
        hintPrimaryLabel.text = "Tap — matter   ·   Hold — star   ·   Swipe — drift"
        hintPrimaryLabel.zPosition = 20
        hudNode.addChild(hintPrimaryLabel)

        hintSecondaryLabel.fontSize = 11
        hintSecondaryLabel.fontColor = UIColor.white.withAlphaComponent(0.62)
        hintSecondaryLabel.text = "Pinch — gravity   ·   Shake — cosmic event"
        hintSecondaryLabel.zPosition = 20
        hudNode.addChild(hintSecondaryLabel)
    }

    private func layoutHUD() {
        let topInset: CGFloat = 52
        let bottomInset: CGFloat = 58
        let sideInset: CGFloat = 18
        let topBandHeight: CGFloat = 108
        let bottomBandHeight: CGFloat = 72

        topPanel.path = CGPath(roundedRect: CGRect(x: -size.width / 2, y: size.height / 2 - topBandHeight, width: size.width, height: topBandHeight), cornerWidth: 0, cornerHeight: 0, transform: nil)
        bottomPanel.path = CGPath(roundedRect: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: bottomBandHeight), cornerWidth: 0, cornerHeight: 0, transform: nil)

        let buttonRowY = size.height / 2 - topInset
        backButton.position = CGPoint(x: -size.width / 2 + sideInset + 46, y: buttonRowY)
        saveButton.position = CGPoint(x: size.width / 2 - sideInset - 58, y: buttonRowY)

        tierLabel.position = CGPoint(x: 0, y: buttonRowY - 30)
        infoLabel.position = CGPoint(x: 0, y: buttonRowY - 54)

        gravityLabel.position = CGPoint(x: 0, y: -size.height / 2 + bottomInset)
        hintPrimaryLabel.position = CGPoint(x: 0, y: -size.height / 2 + bottomInset - 22)
        hintSecondaryLabel.position = CGPoint(x: 0, y: -size.height / 2 + bottomInset - 40)
    }

    private func showIntroGuide() {
        let guide = SKNode()
        guide.zPosition = 40
        guide.name = "introGuide"

        let panel = SKShapeNode(rectOf: CGSize(width: min(size.width - 48, 320), height: 168), cornerRadius: 18)
        panel.fillColor = UIColor.black.withAlphaComponent(0.72)
        panel.strokeColor = tier.accent.withAlphaComponent(0.55)
        panel.lineWidth = 1.5
        guide.addChild(panel)

        let title = SKLabelNode(text: "Shape Your Cosmos")
        title.fontName = "AvenirNext-Bold"
        title.fontSize = 18
        title.fontColor = tier.accent
        title.position = CGPoint(x: 0, y: 44)
        guide.addChild(title)

        let body = SKLabelNode(text: "Tap empty space to add matter.\nHold to birth a star.\nSwipe to set cosmic drift.")
        body.fontName = "AvenirNext-Medium"
        body.fontSize = 13
        body.fontColor = UIColor.white.withAlphaComponent(0.88)
        body.numberOfLines = 0
        body.preferredMaxLayoutWidth = min(size.width - 72, 280)
        body.verticalAlignmentMode = .center
        body.position = CGPoint(x: 0, y: -6)
        guide.addChild(body)

        let dismiss = SKLabelNode(text: "Tap anywhere to begin")
        dismiss.fontName = "AvenirNext-DemiBold"
        dismiss.fontSize = 12
        dismiss.fontColor = UIColor.white.withAlphaComponent(0.45)
        dismiss.position = CGPoint(x: 0, y: -58)
        guide.addChild(dismiss)

        hudNode.addChild(guide)
        guide.run(SKAction.sequence([
            SKAction.wait(forDuration: 5.0),
            SKAction.fadeOut(withDuration: 0.5),
            SKAction.removeFromParent()
        ]))
    }

    private func refreshHUD() {
        let minutes = max(0, Int((CACurrentMediaTime() - sessionStart) / 60))
        infoLabel.text = "⭐ \(starCount)  🪐 \(planetCount)  ☄️ \(collisionCount)  ⏱ \(minutes)m"
        gravityLabel.text = String(format: "Gravity %.2f", gravityStrength)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first else { return }
        let point = touch.location(in: self)
        if let intro = hudNode.childNode(withName: "introGuide") {
            intro.removeAllActions()
            intro.run(SKAction.sequence([SKAction.fadeOut(withDuration: 0.25), SKAction.removeFromParent()]))
        }
        let nodes = nodes(at: point)
        if nodes.contains(where: { $0.name == "back" }) {
            onExit?()
            return
        }
        if nodes.contains(where: { $0.name == "save" }) {
            saveCurrentSystem()
            return
        }
        longPressPoint = point
        longPressTimer?.invalidate()
        longPressTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: false) { [weak self] _ in
            self?.birthStar(at: self?.longPressPoint ?? .zero)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressTimer?.invalidate()
        longPressTimer = nil
        guard let touch = touches.first else { return }
        let began = touch.location(in: self)
        let ended = touch.location(in: self)
        let distance = hypot(ended.x - began.x, ended.y - began.y)
        if distance > 36 {
            let vector = CGVector(dx: ended.x - began.x, dy: ended.y - began.y)
            let length = max(hypot(vector.dx, vector.dy), 1)
            flowDirection = CGVector(dx: vector.dx / length, dy: vector.dy / length)
            flashDirectionIndicator()
            return
        }
        if distance < 8 {
            spawnMatter(at: began)
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        longPressTimer?.invalidate()
        longPressTimer = nil
    }

    func handlePinch(scale: CGFloat) {
        let delta = (scale - 1) * 0.35
        gravityStrength = min(1.4, max(0.1, pinchStartGravity + delta))
        refreshHUD()
    }

    func beginPinch() {
        pinchStartGravity = gravityStrength
    }

    func endPinch() {
        pinchStartGravity = gravityStrength
    }

    func handleShake() {
        let now = CACurrentMediaTime()
        guard now - lastShakeTimestamp > 2.5 else { return }
        lastShakeTimestamp = now
        triggerCosmicEvent()
    }

    private func spawnMatter(at point: CGPoint) {
        guard matterCount < tier.matterCap else { return }
        matterCount += 1
        let radius = CGFloat.random(in: 3...6)
        let node = SKShapeNode(circleOfRadius: radius)
        node.fillColor = UIColor.white.withAlphaComponent(0.85)
        node.strokeColor = tier.accent.withAlphaComponent(0.6)
        node.position = point
        node.zPosition = 3
        node.name = "matter"
        node.physicsBody = SKPhysicsBody(circleOfRadius: radius)
        node.physicsBody?.mass = 0.2
        node.physicsBody?.linearDamping = 0.2
        node.physicsBody?.categoryBitMask = matterCategory
        node.physicsBody?.collisionBitMask = seedCategory | matterCategory | starCategory | planetCategory
        node.physicsBody?.contactTestBitMask = seedCategory | matterCategory | starCategory | planetCategory
        worldNode.addChild(node)
        GameFeedback.lightImpact()
        GameFeedback.playMatterTone()
    }

    private func birthStar(at point: CGPoint) {
        guard matterCount < tier.matterCap else { return }
        starCount += 1
        matterCount += 1
        let radius: CGFloat = 14
        let node = SKShapeNode(circleOfRadius: radius)
        node.fillColor = tier.accent
        node.strokeColor = .white
        node.lineWidth = 1
        node.glowWidth = 6
        node.position = point
        node.zPosition = 6
        node.name = "star"
        node.physicsBody = SKPhysicsBody(circleOfRadius: radius)
        node.physicsBody?.mass = 2.4
        node.physicsBody?.linearDamping = 0.15
        node.physicsBody?.categoryBitMask = starCategory
        node.physicsBody?.collisionBitMask = seedCategory | matterCategory | starCategory | planetCategory
        node.physicsBody?.contactTestBitMask = matterCategory | starCategory | planetCategory
        worldNode.addChild(node)
        emitBurst(at: point, color: tier.accent)
        GameFeedback.successNotice()
        GameFeedback.playStarTone()
        refreshHUD()
    }

    private func promoteToPlanet(_ node: SKShapeNode) {
        guard node.name == "matter" else { return }
        node.name = "planet"
        planetCount += 1
        node.fillColor = tier.glow
        node.strokeColor = UIColor.white.withAlphaComponent(0.7)
        node.glowWidth = 2
        node.physicsBody?.mass = 1.2
        node.physicsBody?.categoryBitMask = planetCategory
        refreshHUD()
    }

    private func collapseToBlackHole(_ node: SKShapeNode) {
        collisionCount += 1
        node.name = "void"
        node.fillColor = .black
        node.strokeColor = tier.accent
        node.glowWidth = 8
        node.physicsBody?.mass = 8
        node.physicsBody?.fieldBitMask = 0
        let field = SKFieldNode.radialGravityField()
        field.strength = -3
        field.falloff = 1.2
        field.region = SKRegion(radius: 120)
        node.addChild(field)
        refreshHUD()
    }

    private func triggerCosmicEvent() {
        collisionCount += 1
        for _ in 0..<6 {
            let point = CGPoint(x: CGFloat.random(in: -size.width / 3...size.width / 3), y: CGFloat.random(in: -size.height / 3...size.height / 3))
            spawnMatter(at: point)
        }
        let wave = SKShapeNode(circleOfRadius: 12)
        wave.strokeColor = tier.accent
        wave.fillColor = .clear
        wave.lineWidth = 2
        wave.glowWidth = 5
        wave.zPosition = 15
        worldNode.addChild(wave)
        wave.run(SKAction.sequence([
            SKAction.group([
                SKAction.scale(to: 18, duration: 0.8),
                SKAction.fadeOut(withDuration: 0.8)
            ]),
            SKAction.removeFromParent()
        ]))
        GameFeedback.heavyImpact()
        GameFeedback.playEventTone()
        refreshHUD()
    }

    private func flashDirectionIndicator() {
        let arrow = SKShapeNode()
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -10, y: -6))
        path.addLine(to: CGPoint(x: 18, y: 0))
        path.addLine(to: CGPoint(x: -10, y: 6))
        path.closeSubpath()
        arrow.path = path
        arrow.fillColor = tier.accent.withAlphaComponent(0.8)
        arrow.strokeColor = .clear
        arrow.zPosition = 12
        arrow.zRotation = atan2(flowDirection.dy, flowDirection.dx)
        arrow.position = .zero
        hudNode.addChild(arrow)
        arrow.run(SKAction.sequence([SKAction.fadeOut(withDuration: 0.5), SKAction.removeFromParent()]))
    }

    private func emitBurst(at point: CGPoint, color: UIColor) {
        for _ in 0..<10 {
            let spark = SKShapeNode(circleOfRadius: 2)
            spark.fillColor = color
            spark.strokeColor = .clear
            spark.position = point
            spark.zPosition = 8
            worldNode.addChild(spark)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let impulse = CGVector(dx: cos(angle) * 80, dy: sin(angle) * 80)
            spark.run(SKAction.sequence([
                SKAction.group([
                    SKAction.move(by: impulse, duration: 0.35),
                    SKAction.fadeOut(withDuration: 0.35)
                ]),
                SKAction.removeFromParent()
            ]))
        }
    }

    func didBegin(_ contact: SKPhysicsContact) {
        let bodies = [contact.bodyA.node, contact.bodyB.node].compactMap { $0 as? SKShapeNode }
        guard bodies.count == 2 else { return }
        let names = Set(bodies.compactMap { $0.name })
        if names.contains("matter"), names.contains("star") || names.contains("seed") {
            if let matter = bodies.first(where: { $0.name == "matter" }) {
                promoteToPlanet(matter)
            }
        }
        if names.contains("star") && names.filter({ $0 == "star" }).count == 2 {
            collisionCount += 1
            if let node = bodies.first {
                collapseToBlackHole(node)
            }
            refreshHUD()
        }
    }

    override func update(_ currentTime: TimeInterval) {
        applyForces()
        animateBackground()
        refreshHUD()
        let minutes = Int((CACurrentMediaTime() - sessionStart) / 60)
        PlayerData.shared.recordSession(stars: starCount, planets: planetCount, collisions: collisionCount, minutes: minutes)
    }

    private func applyForces() {
        let centerStrength = gravityStrength * 0.8
        for node in worldNode.children {
            guard let body = node.physicsBody, body.isDynamic else { continue }
            let offset = CGVector(dx: -node.position.x, dy: -node.position.y)
            let distance = max(hypot(offset.dx, offset.dy), 12)
            let pull = centerStrength * 140 / distance
            body.applyForce(CGVector(dx: offset.dx / distance * pull, dy: offset.dy / distance * pull))
            if self.flowDirection.dx != 0 || self.flowDirection.dy != 0 {
                body.applyForce(CGVector(dx: self.flowDirection.dx * 6, dy: self.flowDirection.dy * 6))
            }
        }
    }

    private func animateBackground() {
        for star in backgroundStars {
            star.alpha -= 0.002
            if star.alpha < 0.15 {
                star.alpha = CGFloat.random(in: 0.35...0.9)
                star.position = CGPoint(x: CGFloat.random(in: -size.width / 2...size.width / 2), y: CGFloat.random(in: -size.height / 2...size.height / 2))
            }
        }
    }

    private func saveCurrentSystem() {
        let minutes = max(1, Int((CACurrentMediaTime() - sessionStart) / 60))
        let snapshot = SessionSnapshot(stars: starCount, planets: planetCount, collisions: collisionCount, lifetimeMinutes: minutes, levelName: tier.name)
        SystemArchive.shared.save(snapshot)
        PlayerData.shared.recordSavedSystem()
        GameFeedback.playSaveTone()
        let banner = SKLabelNode(text: "System card saved")
        banner.fontName = "AvenirNext-Bold"
        banner.fontSize = 16
        banner.fontColor = tier.accent
        banner.position = CGPoint(x: 0, y: size.height / 2 - 130)
        banner.zPosition = 30
        hudNode.addChild(banner)
        banner.run(SKAction.sequence([SKAction.wait(forDuration: 1.2), SKAction.fadeOut(withDuration: 0.4), SKAction.removeFromParent()]))
    }
}

final class SystemArchive {
    static let shared = SystemArchive()

    private init() {}

    func save(_ snapshot: SessionSnapshot) {
        SystemStore.shared.save(snapshot)
    }

    func fetchAll() -> [SavedSystem] {
        SystemStore.shared.fetchAll()
    }
}
