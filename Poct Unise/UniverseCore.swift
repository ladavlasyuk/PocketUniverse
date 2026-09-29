import UIKit
import SpriteKit
import AudioToolbox

struct UniverseTier {
    let name: String
    let gravityScale: CGFloat
    let matterCap: Int
    let accent: UIColor
    let glow: UIColor
    let unlockGoal: String
    let requiredStars: Int
    let requiredPlanets: Int
    let requiredCollisions: Int
    let requiredMinutes: Int

    static let all: [UniverseTier] = [
        UniverseTier(name: "Stellar Nursery", gravityScale: 0.35, matterCap: 24, accent: UIColor(red: 0.95, green: 0.82, blue: 0.35, alpha: 1), glow: UIColor(red: 0.55, green: 0.35, blue: 1, alpha: 1), unlockGoal: "Always available", requiredStars: 0, requiredPlanets: 0, requiredCollisions: 0, requiredMinutes: 0),
        UniverseTier(name: "Binary Dawn", gravityScale: 0.48, matterCap: 36, accent: UIColor(red: 1, green: 0.55, blue: 0.28, alpha: 1), glow: UIColor(red: 1, green: 0.25, blue: 0.45, alpha: 1), unlockGoal: "Birth 1 star in any run", requiredStars: 1, requiredPlanets: 0, requiredCollisions: 0, requiredMinutes: 0),
        UniverseTier(name: "Planet Forge", gravityScale: 0.62, matterCap: 52, accent: UIColor(red: 0.35, green: 0.95, blue: 0.78, alpha: 1), glow: UIColor(red: 0.15, green: 0.55, blue: 0.95, alpha: 1), unlockGoal: "Reach 2 stars and 3 planets", requiredStars: 2, requiredPlanets: 3, requiredCollisions: 0, requiredMinutes: 0),
        UniverseTier(name: "Collision Course", gravityScale: 0.78, matterCap: 72, accent: UIColor(red: 0.92, green: 0.42, blue: 1, alpha: 1), glow: UIColor(red: 0.45, green: 0.35, blue: 1, alpha: 1), unlockGoal: "Trigger 5 collisions", requiredStars: 0, requiredPlanets: 0, requiredCollisions: 5, requiredMinutes: 0),
        UniverseTier(name: "Event Horizon", gravityScale: 1.0, matterCap: 96, accent: UIColor(red: 0.72, green: 0.78, blue: 1, alpha: 1), glow: UIColor(red: 0.2, green: 0.2, blue: 0.35, alpha: 1), unlockGoal: "Survive 8 minutes in one session", requiredStars: 0, requiredPlanets: 0, requiredCollisions: 0, requiredMinutes: 8)
    ]
}

final class PlayerData {
    static let shared = PlayerData()

    private let defaults = UserDefaults.standard
    private let tierKey = "universe_selected_tier"
    private let unlockedKey = "universe_unlocked_mask"
    private let soundKey = "universe_sound"
    private let hapticsKey = "universe_haptics"
    private let peakStarsKey = "universe_peak_stars"
    private let peakPlanetsKey = "universe_peak_planets"
    private let peakCollisionsKey = "universe_peak_collisions"
    private let peakMinutesKey = "universe_peak_minutes"
    private let systemsSavedKey = "universe_systems_saved"

    var selectedTier: Int {
        get { min(max(defaults.integer(forKey: tierKey), 0), UniverseTier.all.count - 1) }
        set {
            let clamped = min(max(newValue, 0), UniverseTier.all.count - 1)
            defaults.set(clamped, forKey: tierKey)
            notifySettingsChanged()
        }
    }

    var soundEnabled: Bool {
        get { defaults.object(forKey: soundKey) == nil ? true : defaults.bool(forKey: soundKey) }
        set {
            defaults.set(newValue, forKey: soundKey)
            notifySettingsChanged()
        }
    }

    var hapticsEnabled: Bool {
        get { defaults.object(forKey: hapticsKey) == nil ? true : defaults.bool(forKey: hapticsKey) }
        set {
            defaults.set(newValue, forKey: hapticsKey)
            notifySettingsChanged()
        }
    }

    var systemsSaved: Int { defaults.integer(forKey: systemsSavedKey) }
    var peakStars: Int { defaults.integer(forKey: peakStarsKey) }
    var peakPlanets: Int { defaults.integer(forKey: peakPlanetsKey) }
    var peakCollisions: Int { defaults.integer(forKey: peakCollisionsKey) }
    var peakMinutes: Int { defaults.integer(forKey: peakMinutesKey) }

    private init() {
        if defaults.object(forKey: unlockedKey) == nil {
            defaults.set(1, forKey: unlockedKey)
        }
    }

    func isTierUnlocked(_ index: Int) -> Bool {
        guard index >= 0, index < UniverseTier.all.count else { return false }
        if index == 0 { return true }
        let mask = defaults.integer(forKey: unlockedKey)
        return (mask & (1 << index)) != 0
    }

    func recordSession(stars: Int, planets: Int, collisions: Int, minutes: Int) {
        defaults.set(max(peakStars, stars), forKey: peakStarsKey)
        defaults.set(max(peakPlanets, planets), forKey: peakPlanetsKey)
        defaults.set(max(peakCollisions, collisions), forKey: peakCollisionsKey)
        defaults.set(max(peakMinutes, minutes), forKey: peakMinutesKey)
        evaluateUnlocks()
    }

    func recordSavedSystem() {
        defaults.set(systemsSaved + 1, forKey: systemsSavedKey)
        notifySettingsChanged()
    }

    private func notifySettingsChanged() {
        NotificationCenter.default.post(name: .playerSettingsDidChange, object: nil)
    }

    private func evaluateUnlocks() {
        var mask = defaults.integer(forKey: unlockedKey)
        var didUnlock = false
        for (index, tier) in UniverseTier.all.enumerated() where index > 0 {
            let unlocked = peakStars >= tier.requiredStars
                && peakPlanets >= tier.requiredPlanets
                && peakCollisions >= tier.requiredCollisions
                && peakMinutes >= tier.requiredMinutes
            if unlocked && (mask & (1 << index)) == 0 {
                didUnlock = true
            }
            if unlocked {
                mask |= (1 << index)
            }
        }
        defaults.set(mask, forKey: unlockedKey)
        if didUnlock {
            notifySettingsChanged()
        }
    }
}

enum GameFeedback {
    static func lightImpact() {
        guard PlayerData.shared.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func successNotice() {
        guard PlayerData.shared.hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func heavyImpact() {
        guard PlayerData.shared.hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    }

    static func selectionChanged() {
        guard PlayerData.shared.hapticsEnabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func playMatterTone() {
        guard PlayerData.shared.soundEnabled else { return }
        AudioServicesPlaySystemSound(1104)
    }

    static func playStarTone() {
        guard PlayerData.shared.soundEnabled else { return }
        AudioServicesPlaySystemSound(1057)
    }

    static func playEventTone() {
        guard PlayerData.shared.soundEnabled else { return }
        AudioServicesPlaySystemSound(1013)
    }

    static func playSaveTone() {
        guard PlayerData.shared.soundEnabled else { return }
        AudioServicesPlaySystemSound(1001)
    }
}

struct SessionSnapshot {
    let stars: Int
    let planets: Int
    let collisions: Int
    let lifetimeMinutes: Int
    let levelName: String
}

final class UniverseViewController: UIViewController, UIGestureRecognizerDelegate {
    private let tierIndex: Int
    private weak var activeScene: UniverseScene?
    private var scenePresented = false

    init(tierIndex: Int) {
        self.tierIndex = tierIndex
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        self.tierIndex = 0
        super.init(coder: coder)
    }

    override func loadView() {
        view = SKView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        guard let skView = view as? SKView else { return }
        skView.ignoresSiblingOrder = true
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        skView.addGestureRecognizer(pinch)
        becomeFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard let skView = view as? SKView else { return }
        let bounds = skView.bounds.size
        guard bounds.width > 1, bounds.height > 1 else { return }
        if !scenePresented {
            let scene = UniverseScene(size: bounds, tier: UniverseTier.all[tierIndex])
            scene.scaleMode = .resizeFill
            scene.onExit = { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
            skView.presentScene(scene)
            activeScene = scene
            scenePresented = true
        } else if let scene = activeScene, scene.size != bounds {
            scene.size = bounds
        }
    }

    override var canBecomeFirstResponder: Bool { true }

    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            activeScene?.handleShake()
        }
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        guard let scene = activeScene else { return }
        switch recognizer.state {
        case .began:
            scene.beginPinch()
        case .changed:
            scene.handlePinch(scale: recognizer.scale)
        case .ended, .cancelled:
            scene.endPinch()
            recognizer.scale = 1
        default:
            break
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
        OrientationController.shared.lockToPortrait()
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        .portrait
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
