import UIKit

final class NoInternetViewController: UIViewController {
    private let backgroundImageView: UIImageView = {
        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        return imageView
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.addSubview(backgroundImageView)
        let title = UILabel()
        title.translatesAutoresizingMaskIntoConstraints = false
        title.text = "NO CONNECTION"
        title.textColor = .white
        title.textAlignment = .center
        title.font = .systemFont(ofSize: 30, weight: .black)
        let message = UILabel()
        message.translatesAutoresizingMaskIntoConstraints = false
        message.text = "Connect to the internet, then open the app again."
        message.textColor = UIColor.white.withAlphaComponent(0.8)
        message.textAlignment = .center
        message.numberOfLines = 0
        message.font = .systemFont(ofSize: 18, weight: .semibold)
        view.addSubview(title)
        view.addSubview(message)

        NSLayoutConstraint.activate([
            backgroundImageView.topAnchor.constraint(equalTo: view.topAnchor),
            backgroundImageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            backgroundImageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backgroundImageView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            title.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            title.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -24),
            message.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),
            message.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 36),
            message.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -36)
        ])

        updateBackgroundImage(for: view.bounds.size)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        updateBackgroundImage(for: size)
    }

    private func updateBackgroundImage(for size: CGSize) {
        let name = size.width > size.height ? "NoInternetBackgroundLandscape" : "NoInternetBackground"
        backgroundImageView.image = UIImage(named: name)
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return UIDevice.current.userInterfaceIdiom == .pad ? .all : .allButUpsideDown
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }
}
