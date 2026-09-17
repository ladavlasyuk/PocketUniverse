import UIKit

enum CosmicPalette {
    static let void = UIColor(red: 0.02, green: 0.03, blue: 0.10, alpha: 1)
    static let nebulaViolet = UIColor(red: 0.22, green: 0.06, blue: 0.38, alpha: 1)
    static let nebulaTeal = UIColor(red: 0.04, green: 0.18, blue: 0.32, alpha: 1)
    static let starGlow = UIColor(red: 0.55, green: 0.82, blue: 1, alpha: 1)
    static let glassStroke = UIColor.white.withAlphaComponent(0.28)
    static let glassFill = UIColor.white.withAlphaComponent(0.09)
}

final class CosmicBackdropView: UIView {
    private let gradientA = CAGradientLayer()
    private let gradientB = CAGradientLayer()
    private let starContainer = CALayer()
    private var starLayers: [CALayer] = []
    private var dustLayers: [CALayer] = []
    private var displayLink: CADisplayLink?
    private var phase: CGFloat = 0
    var accentTint: UIColor = CosmicPalette.starGlow {
        didSet { refreshAccent() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        layer.addSublayer(gradientA)
        layer.addSublayer(gradientB)
        layer.addSublayer(starContainer)
        gradientA.colors = [
            CosmicPalette.void.cgColor,
            CosmicPalette.nebulaViolet.cgColor,
            CosmicPalette.nebulaTeal.cgColor
        ]
        gradientA.locations = [0, 0.55, 1]
        gradientA.startPoint = CGPoint(x: 0.05, y: 0)
        gradientA.endPoint = CGPoint(x: 0.95, y: 1)
        gradientB.type = .radial
        gradientB.colors = [
            UIColor(red: 0.45, green: 0.25, blue: 0.75, alpha: 0.35).cgColor,
            UIColor.clear.cgColor
        ]
        gradientB.startPoint = CGPoint(x: 0.75, y: 0.15)
        gradientB.endPoint = CGPoint(x: 1.2, y: 0.65)
        buildStars(count: 90)
        buildDust(count: 24)
        startAnimation()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        displayLink?.invalidate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        gradientA.frame = bounds
        gradientB.frame = bounds.insetBy(dx: -bounds.width * 0.2, dy: -bounds.height * 0.2)
        starContainer.frame = bounds
        if starLayers.allSatisfy({ $0.position == .zero }) {
            for star in starLayers {
                star.position = randomPoint(in: bounds)
                star.opacity = Float.random(in: 0.25...0.95)
            }
        }
        if dustLayers.allSatisfy({ $0.position == .zero }) {
            for dust in dustLayers {
                dust.position = CGPoint(
                    x: bounds.width * CGFloat.random(in: 0.08...0.92),
                    y: bounds.height * CGFloat.random(in: 0.08...0.92)
                )
            }
        }
    }

    private func buildStars(count: Int) {
        for _ in 0..<count {
            let star = CALayer()
            let size = CGFloat.random(in: 1...2.8)
            star.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            star.cornerRadius = size / 2
            star.backgroundColor = UIColor.white.withAlphaComponent(CGFloat.random(in: 0.35...0.9)).cgColor
            star.opacity = Float.random(in: 0.2...1)
            starContainer.addSublayer(star)
            starLayers.append(star)
        }
    }

    private func buildDust(count: Int) {
        for _ in 0..<count {
            let dust = CALayer()
            let size = CGFloat.random(in: 40...120)
            dust.bounds = CGRect(x: 0, y: 0, width: size, height: size)
            dust.cornerRadius = size / 2
            dust.backgroundColor = accentTint.withAlphaComponent(0.08).cgColor
            layer.insertSublayer(dust, above: gradientB)
            dustLayers.append(dust)
        }
    }

    private func refreshAccent() {
        for dust in dustLayers {
            dust.backgroundColor = accentTint.withAlphaComponent(0.08).cgColor
        }
        gradientB.colors = [
            accentTint.withAlphaComponent(0.22).cgColor,
            UIColor.clear.cgColor
        ]
    }

    private func startAnimation() {
        displayLink = CADisplayLink(target: self, selector: #selector(tick))
        displayLink?.add(to: .main, forMode: .common)
    }

    @objc private func tick() {
        phase += 0.004
        let shift = sin(phase)
        gradientA.startPoint = CGPoint(x: 0.05 + shift * 0.08, y: 0.02)
        gradientA.endPoint = CGPoint(x: 0.95 - shift * 0.06, y: 0.98)
        gradientB.opacity = Float(0.75 + sin(phase * 1.3) * 0.15)
        for (index, star) in starLayers.enumerated() {
            let twinkle = sin(phase * 3 + CGFloat(index) * 0.4)
            star.opacity = Float(0.25 + (twinkle + 1) * 0.35)
        }
        for (index, dust) in dustLayers.enumerated() {
            let drift = sin(phase * 0.6 + CGFloat(index))
            dust.transform = CATransform3DMakeTranslation(drift * 12, cos(phase + CGFloat(index)) * 8, 0)
        }
    }

    private func randomPoint(in rect: CGRect) -> CGPoint {
        CGPoint(x: CGFloat.random(in: 0...rect.width), y: CGFloat.random(in: 0...rect.height))
    }
}

enum CosmicTypography {
    static func heroTitle(_ text: String) -> NSAttributedString {
        let shadow = NSShadow()
        shadow.shadowColor = CosmicPalette.starGlow.withAlphaComponent(0.85)
        shadow.shadowBlurRadius = 18
        shadow.shadowOffset = .zero
        return NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 42, weight: .black),
                .foregroundColor: UIColor.white,
                .kern: 4,
                .shadow: shadow
            ]
        )
    }

    static func screenTitle(_ text: String) -> UILabel {
        let label = UILabel()
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [
                .font: UIFont.systemFont(ofSize: 30, weight: .heavy),
                .foregroundColor: UIColor.white,
                .kern: 2.5
            ]
        )
        label.textAlignment = .center
        label.numberOfLines = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    static func captionLabel(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.textColor = UIColor.white.withAlphaComponent(0.62)
        label.font = .systemFont(ofSize: 12, weight: .heavy)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
}

enum CosmicControls {
    static func glassButton(_ title: String, symbol: String? = nil, prominent: Bool = false) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.image = symbol.flatMap { UIImage(systemName: $0) }
        configuration.imagePadding = 10
        configuration.imagePlacement = .leading
        configuration.baseForegroundColor = .white
        configuration.background.backgroundColor = prominent
            ? CosmicPalette.starGlow.withAlphaComponent(0.28)
            : CosmicPalette.glassFill
        configuration.background.cornerRadius = 18
        configuration.background.strokeColor = CosmicPalette.glassStroke
        configuration.background.strokeWidth = 1
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 16, leading: 18, bottom: 16, trailing: 18)
        let button = UIButton(configuration: configuration)
        button.titleLabel?.font = .systemFont(ofSize: 16, weight: .bold)
        button.translatesAutoresizingMaskIntoConstraints = false
        if prominent {
            button.layer.shadowColor = CosmicPalette.starGlow.cgColor
            button.layer.shadowRadius = 18
            button.layer.shadowOpacity = 0.45
            button.layer.shadowOffset = CGSize(width: 0, height: 8)
        }
        return button
    }

    static func wrapGlass(_ view: UIView, cornerRadius: CGFloat = 22) -> UIView {
        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.backgroundColor = CosmicPalette.glassFill
        container.layer.cornerRadius = cornerRadius
        container.layer.borderWidth = 1
        container.layer.borderColor = CosmicPalette.glassStroke.cgColor
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .systemUltraThinMaterialDark))
        blur.translatesAutoresizingMaskIntoConstraints = false
        blur.layer.cornerRadius = cornerRadius
        blur.clipsToBounds = true
        blur.isUserInteractionEnabled = false
        container.addSubview(blur)
        container.addSubview(view)
        NSLayoutConstraint.activate([
            blur.topAnchor.constraint(equalTo: container.topAnchor),
            blur.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            blur.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            blur.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            view.topAnchor.constraint(equalTo: container.topAnchor),
            view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        return container
    }
}

final class OrbitalPortraitView: UIView {
    private let imageView = UIImageView()
    private let initialsLabel = UILabel()
    private let orbitRing = CAShapeLayer()
    private let orbitDot = CALayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        initialsLabel.textAlignment = .center
        initialsLabel.font = .systemFont(ofSize: 20, weight: .black)
        initialsLabel.textColor = .black
        initialsLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        addSubview(initialsLabel)
        layer.addSublayer(orbitRing)
        layer.addSublayer(orbitDot)
        orbitRing.fillColor = UIColor.clear.cgColor
        orbitRing.lineWidth = 1.5
        orbitRing.strokeColor = UIColor.white.withAlphaComponent(0.35).cgColor
        orbitDot.backgroundColor = CosmicPalette.starGlow.cgColor
        orbitDot.cornerRadius = 4
        orbitDot.bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            imageView.widthAnchor.constraint(equalTo: widthAnchor, multiplier: 0.78),
            imageView.heightAnchor.constraint(equalTo: imageView.widthAnchor),
            initialsLabel.centerXAnchor.constraint(equalTo: imageView.centerXAnchor),
            initialsLabel.centerYAnchor.constraint(equalTo: imageView.centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let inset: CGFloat = 4
        imageView.layer.cornerRadius = imageView.bounds.width / 2
        layer.cornerRadius = bounds.width / 2
        let orbitRect = bounds.insetBy(dx: inset, dy: inset)
        orbitRing.path = UIBezierPath(ovalIn: orbitRect).cgPath
        orbitRing.frame = bounds
    }

    func configure(portrait: UIImage?, initials: String, accent: UIColor) {
        if let portrait {
            imageView.image = portrait
            imageView.backgroundColor = .clear
            initialsLabel.isHidden = true
        } else {
            imageView.image = nil
            imageView.backgroundColor = accent
            initialsLabel.text = initials
            initialsLabel.isHidden = false
        }
        layer.borderWidth = 2
        layer.borderColor = UIColor.white.withAlphaComponent(0.65).cgColor
        clipsToBounds = false
    }

    func startOrbitAnimation() {
        orbitDot.removeAllAnimations()
        let orbit = CAKeyframeAnimation(keyPath: "position")
        let inset: CGFloat = 4
        let orbitRect = bounds.insetBy(dx: inset, dy: inset)
        orbit.path = UIBezierPath(ovalIn: orbitRect).cgPath
        orbit.duration = 8
        orbit.repeatCount = .infinity
        orbit.calculationMode = .paced
        orbitDot.position = CGPoint(x: orbitRect.midX, y: orbitRect.minY)
        orbitDot.add(orbit, forKey: "orbit")
    }
}

final class SectorTierSelector: UIView {
    var onSelect: ((Int) -> Void)?
    private let track = UIView()
    private let stack = UIStackView()
    private var nodes: [UIButton] = []
    private let connector = CAShapeLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        track.translatesAutoresizingMaskIntoConstraints = false
        track.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        track.layer.cornerRadius = 16
        stack.axis = .horizontal
        stack.spacing = 8
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false
        layer.insertSublayer(connector, at: 0)
        addSubview(track)
        track.addSubview(stack)
        NSLayoutConstraint.activate([
            track.topAnchor.constraint(equalTo: topAnchor),
            track.leadingAnchor.constraint(equalTo: leadingAnchor),
            track.trailingAnchor.constraint(equalTo: trailingAnchor),
            track.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.topAnchor.constraint(equalTo: track.topAnchor, constant: 14),
            stack.leadingAnchor.constraint(equalTo: track.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(equalTo: track.trailingAnchor, constant: -14),
            stack.bottomAnchor.constraint(equalTo: track.bottomAnchor, constant: -14)
        ])
        for (index, tier) in UniverseTier.all.enumerated() {
            let node = UIButton(type: .custom)
            node.tag = index
            node.layer.cornerRadius = 22
            node.titleLabel?.font = .systemFont(ofSize: 13, weight: .black)
            node.addTarget(self, action: #selector(tapped(_:)), for: .touchUpInside)
            node.translatesAutoresizingMaskIntoConstraints = false
            node.heightAnchor.constraint(equalToConstant: 44).isActive = true
            nodes.append(node)
            stack.addArrangedSubview(node)
            _ = tier
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func refresh(selected: Int) {
        for (index, node) in nodes.enumerated() {
            let unlocked = PlayerData.shared.isTierUnlocked(index)
            let tier = UniverseTier.all[index]
            let isSelected = index == selected
            node.setTitle(unlocked ? "\(index + 1)" : "🔒", for: .normal)
            node.setTitleColor(unlocked ? .black : .white, for: .normal)
            node.backgroundColor = unlocked ? tier.accent : UIColor.white.withAlphaComponent(0.1)
            node.layer.borderWidth = isSelected ? 2.5 : 0
            node.layer.borderColor = isSelected ? UIColor.white.cgColor : UIColor.clear.cgColor
            node.transform = isSelected ? CGAffineTransform(scaleX: 1.1, y: 1.1) : .identity
            node.layer.shadowColor = isSelected ? tier.glow.cgColor : UIColor.clear.cgColor
            node.layer.shadowRadius = isSelected ? 10 : 0
            node.layer.shadowOpacity = isSelected ? 0.7 : 0
            node.layer.shadowOffset = .zero
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let path = UIBezierPath()
        let centers = nodes.map { convert($0.center, from: stack) }
        if let first = centers.first {
            path.move(to: first)
            for point in centers.dropFirst() {
                path.addLine(to: point)
            }
        }
        connector.path = path.cgPath
        connector.strokeColor = UIColor.white.withAlphaComponent(0.15).cgColor
        connector.lineWidth = 1
        connector.fillColor = UIColor.clear.cgColor
    }

    @objc private func tapped(_ sender: UIButton) {
        onSelect?(sender.tag)
    }
}

final class SystemSnapshotCell: UITableViewCell {
    static let reuseID = "SystemSnapshotCell"
    private let card = UIView()
    private let nebula = CAGradientLayer()
    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let sectorLabel = UILabel()
    private let stampLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .clear
        selectionStyle = .none
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 20
        card.clipsToBounds = true
        card.layer.borderWidth = 1
        card.layer.borderColor = CosmicPalette.glassStroke.cgColor
        nebula.startPoint = CGPoint(x: 0, y: 0)
        nebula.endPoint = CGPoint(x: 1, y: 1)
        card.layer.insertSublayer(nebula, at: 0)
        titleLabel.font = .systemFont(ofSize: 20, weight: .black)
        titleLabel.textColor = .white
        detailLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.82)
        detailLabel.numberOfLines = 0
        sectorLabel.font = .systemFont(ofSize: 12, weight: .heavy)
        sectorLabel.textColor = CosmicPalette.starGlow
        stampLabel.font = .systemFont(ofSize: 11, weight: .bold)
        stampLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        stampLabel.textAlignment = .right
        for label in [titleLabel, detailLabel, sectorLabel, stampLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(label)
        }
        contentView.addSubview(card)
        NSLayoutConstraint.activate([
            card.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            card.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            card.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            card.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            stampLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            stampLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            detailLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            detailLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            sectorLabel.topAnchor.constraint(equalTo: detailLabel.bottomAnchor, constant: 10),
            sectorLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            sectorLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        nebula.frame = card.bounds
    }

    func configure(with system: SavedSystem) {
        let palette = UniverseTier.all.first(where: { $0.name == system.levelName }) ?? UniverseTier.all[0]
        nebula.colors = [
            palette.accent.withAlphaComponent(0.35).cgColor,
            palette.glow.withAlphaComponent(0.18).cgColor,
            CosmicPalette.void.withAlphaComponent(0.85).cgColor
        ]
        titleLabel.text = system.cardTitle
        detailLabel.text = system.summaryLine
        sectorLabel.text = "SECTOR · \(system.levelName.uppercased())"
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        stampLabel.text = formatter.string(from: system.createdAt)
    }

    func configureEmpty() {
        nebula.colors = [
            UIColor.white.withAlphaComponent(0.08).cgColor,
            CosmicPalette.void.withAlphaComponent(0.9).cgColor
        ]
        titleLabel.text = "No snapshots yet"
        detailLabel.text = "Play a session and tap SAVE CARD to collect universe snapshots."
        sectorLabel.text = ""
        stampLabel.text = ""
    }
}
