import UIKit

class GradientBackdropController: UIViewController {
    private let backdrop = CosmicBackdropView()

    override func viewDidLoad() {
        super.viewDidLoad()
        backdrop.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(backdrop)
        NSLayoutConstraint.activate([
            backdrop.topAnchor.constraint(equalTo: view.topAnchor),
            backdrop.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdrop.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        updateAccent()
    }

    func updateAccent() {
        let tier = UniverseTier.all[PlayerData.shared.selectedTier]
        backdrop.accentTint = tier.accent
    }

    func titleLabel(_ text: String, size: CGFloat = 34) -> UILabel {
        CosmicTypography.screenTitle(text)
    }

    func actionButton(_ text: String, symbol: String? = nil, prominent: Bool = false) -> UIButton {
        CosmicControls.glassButton(text, symbol: symbol, prominent: prominent)
    }

    func animateEntrance(for views: [UIView], delay: TimeInterval = 0) {
        for (index, item) in views.enumerated() {
            item.alpha = 0
            item.transform = CGAffineTransform(translationX: 0, y: 24)
            UIView.animate(
                withDuration: 0.55,
                delay: delay + Double(index) * 0.07,
                usingSpringWithDamping: 0.82,
                initialSpringVelocity: 0.4
            ) {
                item.alpha = 1
                item.transform = .identity
            }
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
}

final class MenuViewController: GradientBackdropController {
    private let scrollView = UIScrollView()
    private let contentStack = UIStackView()
    private let portraitView = OrbitalPortraitView()
    private let statsPanel = UIView()
    private let statsLabel = UILabel()
    private let titleLabelView = UILabel()
    private let tierSelector = SectorTierSelector()
    private let levelInfoLabel = UILabel()
    private weak var playButton: UIButton?
    private var didStartPortraitOrbit = false

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
        refresh()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .playerProfileDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: .playerSettingsDidChange, object: nil)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refresh()
        updateAccent()
        navigationController?.setNavigationBarHidden(true, animated: false)
        OrientationController.shared.lockToPortrait()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateEntrance(for: contentStack.arrangedSubviews)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didStartPortraitOrbit, portraitView.bounds.width > 0 else { return }
        didStartPortraitOrbit = true
        portraitView.startOrbitAnimation()
    }

    private func buildInterface() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.showsVerticalScrollIndicator = false
        contentStack.axis = .vertical
        contentStack.spacing = 18
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(contentStack)

        titleLabelView.attributedText = CosmicTypography.heroTitle("POCKET\nUNIVERSE")
        titleLabelView.numberOfLines = 0
        titleLabelView.textAlignment = .left
        titleLabelView.translatesAutoresizingMaskIntoConstraints = false

        portraitView.widthAnchor.constraint(equalToConstant: 58).isActive = true
        portraitView.heightAnchor.constraint(equalToConstant: 58).isActive = true
        let portraitTap = UITapGestureRecognizer(target: self, action: #selector(openProfile))
        portraitView.addGestureRecognizer(portraitTap)
        portraitView.isUserInteractionEnabled = true

        statsLabel.textColor = .white
        statsLabel.font = .monospacedDigitSystemFont(ofSize: 14, weight: .bold)
        statsLabel.numberOfLines = 2
        statsLabel.textAlignment = .right
        statsLabel.translatesAutoresizingMaskIntoConstraints = false
        statsPanel.translatesAutoresizingMaskIntoConstraints = false
        statsPanel.addSubview(statsLabel)
        NSLayoutConstraint.activate([
            statsLabel.topAnchor.constraint(equalTo: statsPanel.topAnchor, constant: 10),
            statsLabel.trailingAnchor.constraint(equalTo: statsPanel.trailingAnchor, constant: -14),
            statsLabel.leadingAnchor.constraint(equalTo: statsPanel.leadingAnchor, constant: 14),
            statsLabel.bottomAnchor.constraint(equalTo: statsPanel.bottomAnchor, constant: -10)
        ])
        let statsGlass = CosmicControls.wrapGlass(statsPanel, cornerRadius: 16)

        let header = UIStackView(arrangedSubviews: [titleLabelView, UIView()])
        header.axis = .horizontal
        header.alignment = .top
        header.translatesAutoresizingMaskIntoConstraints = false

        let profileRow = UIStackView(arrangedSubviews: [UIView(), portraitView, statsGlass])
        profileRow.axis = .horizontal
        profileRow.alignment = .center
        profileRow.spacing = 12
        profileRow.translatesAutoresizingMaskIntoConstraints = false

        let play = actionButton("ENTER COSMOS", symbol: "sparkles", prominent: true)
        play.addTarget(self, action: #selector(startGame), for: .touchUpInside)
        playButton = play

        let tierCaption = CosmicTypography.captionLabel("SECTOR SELECTOR")
        levelInfoLabel.textColor = .white
        levelInfoLabel.font = .systemFont(ofSize: 15, weight: .bold)
        levelInfoLabel.numberOfLines = 2
        levelInfoLabel.translatesAutoresizingMaskIntoConstraints = false
        tierSelector.onSelect = { [weak self] index in
            self?.selectTierIndex(index)
        }
        let tierPanel = UIView()
        tierPanel.translatesAutoresizingMaskIntoConstraints = false
        tierPanel.addSubview(tierCaption)
        tierPanel.addSubview(tierSelector)
        tierPanel.addSubview(levelInfoLabel)
        NSLayoutConstraint.activate([
            tierCaption.topAnchor.constraint(equalTo: tierPanel.topAnchor, constant: 16),
            tierCaption.leadingAnchor.constraint(equalTo: tierPanel.leadingAnchor, constant: 18),
            tierSelector.topAnchor.constraint(equalTo: tierCaption.bottomAnchor, constant: 10),
            tierSelector.leadingAnchor.constraint(equalTo: tierPanel.leadingAnchor, constant: 14),
            tierSelector.trailingAnchor.constraint(equalTo: tierPanel.trailingAnchor, constant: -14),
            levelInfoLabel.topAnchor.constraint(equalTo: tierSelector.bottomAnchor, constant: 12),
            levelInfoLabel.leadingAnchor.constraint(equalTo: tierPanel.leadingAnchor, constant: 18),
            levelInfoLabel.trailingAnchor.constraint(equalTo: tierPanel.trailingAnchor, constant: -18),
            levelInfoLabel.bottomAnchor.constraint(equalTo: tierPanel.bottomAnchor, constant: -16)
        ])
        let tierGlass = CosmicControls.wrapGlass(tierPanel, cornerRadius: 24)

        let profile = actionButton("OBSERVER", symbol: "person.crop.circle")
        profile.addTarget(self, action: #selector(openProfile), for: .touchUpInside)
        let cards = actionButton("SNAPSHOTS", symbol: "rectangle.stack")
        cards.addTarget(self, action: #selector(openCards), for: .touchUpInside)
        let guide = actionButton("GUIDE", symbol: "book.closed")
        guide.addTarget(self, action: #selector(openGuide), for: .touchUpInside)
        let settings = actionButton("SETTINGS", symbol: "slider.horizontal.3")
        settings.addTarget(self, action: #selector(openSettings), for: .touchUpInside)

        let navGrid = UIStackView(arrangedSubviews: [
            navRow(profile, cards),
            navRow(guide, settings)
        ])
        navGrid.axis = .vertical
        navGrid.spacing = 12
        navGrid.translatesAutoresizingMaskIntoConstraints = false

        contentStack.addArrangedSubview(header)
        contentStack.addArrangedSubview(profileRow)
        contentStack.addArrangedSubview(play)
        contentStack.addArrangedSubview(tierGlass)
        contentStack.addArrangedSubview(navGrid)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            contentStack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.leadingAnchor, constant: 24),
            contentStack.trailingAnchor.constraint(equalTo: scrollView.frameLayoutGuide.trailingAnchor, constant: -24),
            contentStack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -24),
            play.heightAnchor.constraint(equalToConstant: 64)
        ])
        pulseTitle()
    }

    private func navRow(_ first: UIView, _ second: UIView) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: [first, second])
        stack.axis = .horizontal
        stack.spacing = 12
        stack.distribution = .fillEqually
        return stack
    }

    private func pulseTitle() {
        let animation = CABasicAnimation(keyPath: "shadowOpacity")
        animation.fromValue = 0.3
        animation.toValue = 1
        animation.duration = 1.6
        animation.autoreverses = true
        animation.repeatCount = .infinity
        titleLabelView.layer.shadowColor = CosmicPalette.starGlow.cgColor
        titleLabelView.layer.shadowRadius = 16
        titleLabelView.layer.shadowOffset = .zero
        titleLabelView.layer.shadowOpacity = 0.8
        titleLabelView.layer.add(animation, forKey: "pulse")
    }

    @objc private func refresh() {
        let data = PlayerData.shared
        statsLabel.text = "SAVED \(data.systemsSaved)\nPEAK ⭐\(data.peakStars)  🪐\(data.peakPlanets)"
        let tier = UniverseTier.all[data.selectedTier]
        tierSelector.refresh(selected: data.selectedTier)
        levelInfoLabel.text = "\(tier.name)\n\(nextUnlockText())"
        var playConfig = playButton?.configuration
        playConfig?.background.backgroundColor = tier.accent.withAlphaComponent(0.42)
        playButton?.configuration = playConfig
        playButton?.layer.shadowColor = tier.glow.cgColor
        portraitView.configure(
            portrait: ProfileManager.shared.portrait(),
            initials: ProfileManager.shared.initials,
            accent: tier.accent
        )
        updateAccent()
    }

    private func nextUnlockText() -> String {
        for (index, tier) in UniverseTier.all.enumerated() where !PlayerData.shared.isTierUnlocked(index) {
            return "Unlock: \(tier.unlockGoal)"
        }
        return "All sectors unlocked"
    }

    private func selectTierIndex(_ index: Int) {
        guard PlayerData.shared.isTierUnlocked(index) else {
            presentNotice(UniverseTier.all[index].unlockGoal)
            return
        }
        PlayerData.shared.selectedTier = index
        refresh()
        GameFeedback.selectionChanged()
    }

    @objc private func startGame() {
        let index = PlayerData.shared.selectedTier
        guard PlayerData.shared.isTierUnlocked(index) else {
            presentNotice("This sector is still locked. Complete the previous goal first.")
            return
        }
        navigationController?.pushViewController(UniverseViewController(tierIndex: index), animated: true)
    }

    @objc private func openProfile() {
        navigationController?.pushViewController(ProfileViewController(), animated: true)
    }

    @objc private func openCards() {
        navigationController?.pushViewController(SystemCardsViewController(), animated: true)
    }

    @objc private func openGuide() {
        navigationController?.pushViewController(GuideViewController(), animated: true)
    }

    @objc private func openSettings() {
        navigationController?.pushViewController(SettingsViewController(), animated: true)
    }

    private func presentNotice(_ text: String) {
        let alert = UIAlertController(title: "Notice", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}

final class ProfileViewController: GradientBackdropController, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UITextFieldDelegate {
    private let portrait = OrbitalPortraitView()
    private let nameField = UITextField()
    private let badgeLabel = UILabel()
    private var didStartPortraitOrbit = false

    override func viewDidLoad() {
        super.viewDidLoad()
        let title = titleLabel("OBSERVER PROFILE")
        let back = actionButton("BACK", symbol: "chevron.left")
        back.addTarget(self, action: #selector(close), for: .touchUpInside)

        portrait.widthAnchor.constraint(equalToConstant: 156).isActive = true
        portrait.heightAnchor.constraint(equalToConstant: 156).isActive = true

        nameField.text = ProfileManager.shared.displayName
        nameField.textColor = .white
        nameField.font = .systemFont(ofSize: 22, weight: .bold)
        nameField.textAlignment = .center
        nameField.backgroundColor = CosmicPalette.glassFill
        nameField.layer.cornerRadius = 16
        nameField.layer.borderWidth = 1
        nameField.layer.borderColor = CosmicPalette.glassStroke.cgColor
        nameField.placeholder = "Observer name"
        nameField.attributedPlaceholder = NSAttributedString(
            string: "Observer name",
            attributes: [.foregroundColor: UIColor.white.withAlphaComponent(0.35)]
        )
        nameField.returnKeyType = .done
        nameField.delegate = self
        nameField.translatesAutoresizingMaskIntoConstraints = false

        badgeLabel.textColor = CosmicPalette.starGlow
        badgeLabel.font = .systemFont(ofSize: 13, weight: .heavy)
        badgeLabel.textAlignment = .center
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false

        let camera = actionButton("TAKE PHOTO", symbol: "camera.fill")
        camera.addTarget(self, action: #selector(useCamera), for: .touchUpInside)
        let library = actionButton("CHOOSE PHOTO", symbol: "photo.on.rectangle")
        library.addTarget(self, action: #selector(useLibrary), for: .touchUpInside)
        let remove = actionButton("REMOVE PHOTO", symbol: "trash")
        remove.addTarget(self, action: #selector(removePhoto), for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [camera, library, remove])
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(title)
        view.addSubview(back)
        view.addSubview(portrait)
        view.addSubview(badgeLabel)
        view.addSubview(nameField)
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            back.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            back.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            portrait.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            portrait.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 28),
            badgeLabel.topAnchor.constraint(equalTo: portrait.bottomAnchor, constant: 14),
            badgeLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            nameField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 28),
            nameField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -28),
            nameField.topAnchor.constraint(equalTo: badgeLabel.bottomAnchor, constant: 18),
            nameField.heightAnchor.constraint(equalToConstant: 54),
            stack.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: nameField.trailingAnchor),
            stack.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 22)
        ])
        updatePortrait()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateEntrance(for: [portrait, nameField, badgeLabel])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        guard !didStartPortraitOrbit, portrait.bounds.width > 0 else { return }
        didStartPortraitOrbit = true
        portrait.startOrbitAnimation()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        saveName()
        textField.resignFirstResponder()
        return true
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        saveName()
    }

    private func saveName() {
        ProfileManager.shared.displayName = nameField.text ?? ""
        updatePortrait()
    }

    @objc private func useCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            presentMessage("Camera is not available on this device.")
            return
        }
        showPicker(.camera)
    }

    @objc private func useLibrary() {
        showPicker(.photoLibrary)
    }

    private func showPicker(_ source: UIImagePickerController.SourceType) {
        let picker = UIImagePickerController()
        picker.sourceType = source
        picker.delegate = self
        picker.allowsEditing = true
        present(picker, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        if let image = (info[.editedImage] ?? info[.originalImage]) as? UIImage {
            _ = ProfileManager.shared.savePortrait(image)
        }
        picker.dismiss(animated: true)
        updatePortrait()
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }

    @objc private func removePhoto() {
        ProfileManager.shared.removePortrait()
        updatePortrait()
    }

    private func updatePortrait() {
        let tier = UniverseTier.all[PlayerData.shared.selectedTier]
        portrait.configure(
            portrait: ProfileManager.shared.portrait(),
            initials: ProfileManager.shared.initials,
            accent: tier.accent
        )
        badgeLabel.text = "RANK · \(tier.name.uppercased())"
    }

    private func presentMessage(_ text: String) {
        let alert = UIAlertController(title: "Notice", message: text, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    @objc private func close() {
        saveName()
        navigationController?.popViewController(animated: true)
    }
}

final class SystemCardsViewController: GradientBackdropController, UITableViewDataSource, UITableViewDelegate {
    private let table = UITableView(frame: .zero, style: .plain)
    private var systems: [SavedSystem] = []

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        systems = SystemArchive.shared.fetchAll()
        table.reloadData()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        systems = SystemArchive.shared.fetchAll()
        let title = titleLabel("UNIVERSE SNAPSHOTS")
        let back = actionButton("BACK", symbol: "chevron.left")
        back.addTarget(self, action: #selector(close), for: .touchUpInside)

        table.backgroundColor = .clear
        table.separatorStyle = .none
        table.dataSource = self
        table.delegate = self
        table.register(SystemSnapshotCell.self, forCellReuseIdentifier: SystemSnapshotCell.reuseID)
        table.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(title)
        view.addSubview(back)
        view.addSubview(table)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            back.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 22),
            back.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            table.topAnchor.constraint(equalTo: back.bottomAnchor, constant: 12),
            table.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            table.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            table.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        max(systems.count, 1)
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: SystemSnapshotCell.reuseID, for: indexPath) as? SystemSnapshotCell else {
            return UITableViewCell()
        }
        if systems.isEmpty {
            cell.configureEmpty()
        } else {
            cell.configure(with: systems[indexPath.row])
        }
        return cell
    }

    @objc private func close() {
        navigationController?.popViewController(animated: true)
    }
}

final class GuideViewController: GradientBackdropController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let title = titleLabel("MISSION BRIEFING")
        let panel = UIView()
        panel.translatesAutoresizingMaskIntoConstraints = false
        let guide = UILabel()
        guide.text = "Start in empty space with one seed star.\n\nTap to drop matter. Hold to birth a new star. Swipe to set drift direction. Pinch to tune gravity. Shake for a cosmic event.\n\nCollisions can forge planets or collapse into voids. Save any result as a universe snapshot."
        guide.textColor = UIColor.white.withAlphaComponent(0.88)
        guide.font = .systemFont(ofSize: 18, weight: .semibold)
        guide.numberOfLines = 0
        guide.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(guide)
        NSLayoutConstraint.activate([
            guide.topAnchor.constraint(equalTo: panel.topAnchor, constant: 22),
            guide.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: 22),
            guide.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -22),
            guide.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -22)
        ])
        let guideGlass = CosmicControls.wrapGlass(panel, cornerRadius: 24)
        let back = actionButton("GOT IT", symbol: "checkmark", prominent: true)
        back.addTarget(self, action: #selector(close), for: .touchUpInside)
        view.addSubview(title)
        view.addSubview(guideGlass)
        view.addSubview(back)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            guideGlass.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            guideGlass.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            guideGlass.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            back.leadingAnchor.constraint(equalTo: guideGlass.leadingAnchor),
            back.trailingAnchor.constraint(equalTo: guideGlass.trailingAnchor),
            back.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    @objc private func close() { navigationController?.popViewController(animated: true) }
}

final class SettingsViewController: GradientBackdropController {
    private var soundSwitch: UISwitch?
    private var hapticsSwitch: UISwitch?

    override func viewDidLoad() {
        super.viewDidLoad()
        let title = titleLabel("SETTINGS")
        let soundRow = settingRow("Sound", initial: PlayerData.shared.soundEnabled, action: #selector(soundChanged(_:)))
        let hapticsRow = settingRow("Haptics", initial: PlayerData.shared.hapticsEnabled, action: #selector(hapticsChanged(_:)))
        soundSwitch = soundRow.switchControl
        hapticsSwitch = hapticsRow.switchControl
        let stack = UIStackView(arrangedSubviews: [soundRow.container, hapticsRow.container])
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        let back = actionButton("BACK", symbol: "chevron.left")
        back.addTarget(self, action: #selector(close), for: .touchUpInside)
        view.addSubview(title)
        view.addSubview(stack)
        view.addSubview(back)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 44),
            back.leadingAnchor.constraint(equalTo: stack.leadingAnchor),
            back.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
            back.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20)
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        syncControls()
        updateAccent()
    }

    private func syncControls() {
        soundSwitch?.isOn = PlayerData.shared.soundEnabled
        hapticsSwitch?.isOn = PlayerData.shared.hapticsEnabled
        let accent = UniverseTier.all[PlayerData.shared.selectedTier].accent
        soundSwitch?.onTintColor = accent
        hapticsSwitch?.onTintColor = accent
    }

    private struct SettingRow {
        let container: UIView
        let switchControl: UISwitch
    }

    private func settingRow(_ text: String, initial: Bool, action: Selector) -> SettingRow {
        let container = UIView()
        container.backgroundColor = CosmicPalette.glassFill
        container.layer.cornerRadius = 18
        container.layer.borderWidth = 1
        container.layer.borderColor = CosmicPalette.glassStroke.cgColor
        container.translatesAutoresizingMaskIntoConstraints = false
        let label = UILabel()
        label.text = text
        label.textColor = .white
        label.font = .systemFont(ofSize: 19, weight: .bold)
        label.translatesAutoresizingMaskIntoConstraints = false
        let control = UISwitch()
        control.isOn = initial
        control.onTintColor = UniverseTier.all[PlayerData.shared.selectedTier].accent
        control.addTarget(self, action: action, for: .valueChanged)
        control.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        container.addSubview(control)
        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: 68),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            control.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),
            control.centerYAnchor.constraint(equalTo: container.centerYAnchor)
        ])
        return SettingRow(container: container, switchControl: control)
    }

    @objc private func soundChanged(_ sender: UISwitch) {
        PlayerData.shared.soundEnabled = sender.isOn
        if sender.isOn {
            GameFeedback.playMatterTone()
        }
    }

    @objc private func hapticsChanged(_ sender: UISwitch) {
        PlayerData.shared.hapticsEnabled = sender.isOn
        if sender.isOn {
            GameFeedback.selectionChanged()
        }
    }
    @objc private func close() { navigationController?.popViewController(animated: true) }
}
