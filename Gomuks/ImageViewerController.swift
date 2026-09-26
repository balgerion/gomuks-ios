import ImageIO
import UIKit
import UniformTypeIdentifiers

struct ViewerImage {
    let url: URL
    let name: String
}

final class ImageViewerController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate,
    UIGestureRecognizerDelegate {
    private let images: [ViewerImage]
    private let startIndex: Int
    private let session: URLSession
    private let pager = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .vertical,
        options: [.interPageSpacing: 16]
    )
    private let shareButton = UIButton(type: .system)
    private let counter = UILabel()

    init(images: [ViewerImage], startIndex: Int, session: URLSession) {
        self.images = images
        self.startIndex = startIndex
        self.session = session
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
        modalPresentationCapturesStatusBarAppearance = true
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var prefersStatusBarHidden: Bool {
        true
    }

    private var currentPage: ImagePageController? {
        pager.viewControllers?.first as? ImagePageController
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.accessibilityIdentifier = "gomuks-image-viewer"

        pager.dataSource = self
        pager.delegate = self
        addChild(pager)
        pager.view.frame = view.bounds
        pager.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(pager.view)
        pager.didMove(toParent: self)
        pager.setViewControllers([page(at: startIndex)], direction: .forward, animated: false)

        let closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = .white
        closeButton.accessibilityLabel = "Close"
        closeButton.accessibilityIdentifier = "gomuks-image-viewer-close"
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

        shareButton.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        shareButton.tintColor = .white
        shareButton.accessibilityLabel = "Share"
        shareButton.addTarget(self, action: #selector(share), for: .touchUpInside)
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shareButton)

        counter.textColor = .white
        counter.font = .monospacedDigitSystemFont(ofSize: 15, weight: .medium)
        counter.accessibilityIdentifier = "gomuks-image-viewer-counter"
        counter.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(counter)

        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            shareButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            shareButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            shareButton.widthAnchor.constraint(equalToConstant: 44),
            shareButton.heightAnchor.constraint(equalToConstant: 44),
            counter.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            counter.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
        ])
        let pan = UIPanGestureRecognizer(target: self, action: #selector(dismissPan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)

        updateChrome()
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        return !(currentPage?.isZoomed ?? false) && abs(velocity.x) > abs(velocity.y)
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func dismissPan(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: view)
        switch pan.state {
        case .changed:
            pager.view.transform = CGAffineTransform(translationX: translation.x, y: 0)
            view.backgroundColor = UIColor.black.withAlphaComponent(max(0.2, 1 - abs(translation.x) / 400))
        case .ended, .cancelled:
            if abs(translation.x) > 100 || abs(pan.velocity(in: view).x) > 800 {
                close()
            } else {
                UIView.animate(withDuration: 0.2) {
                    self.pager.view.transform = .identity
                    self.view.backgroundColor = .black
                }
            }
        default:
            break
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isBeingDismissed {
            session.invalidateAndCancel()
        }
    }

    private func page(at index: Int) -> ImagePageController {
        let image = images[index]
        let page = ImagePageController(index: index, url: image.url, name: image.name, session: session)
        page.onLoad = { [weak self] in self?.updateChrome() }
        return page
    }

    private func updateChrome() {
        let index = currentPage?.index ?? startIndex
        counter.text = images.count > 1 ? "\(index + 1) / \(images.count)" : nil
        shareButton.isEnabled = currentPage?.data != nil
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let index = (viewController as? ImagePageController)?.index, index > 0 else { return nil }
        return page(at: index - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let index = (viewController as? ImagePageController)?.index, index + 1 < images.count else { return nil }
        return page(at: index + 1)
    }

    func pageViewController(
        _ pageViewController: UIPageViewController,
        didFinishAnimating finished: Bool,
        previousViewControllers: [UIViewController],
        transitionCompleted completed: Bool
    ) {
        updateChrome()
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func share() {
        guard let page = currentPage, let data = page.data else { return }
        let type = CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceGetType($0) as String? }
        let fileExtension = type.flatMap { UTType($0)?.preferredFilenameExtension } ?? "jpg"
        var base = (page.name as NSString).deletingPathExtension
        if base.isEmpty {
            base = "image"
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(base).appendingPathExtension(fileExtension)
        guard (try? data.write(to: file)) != nil else { return }
        let controller = UIActivityViewController(activityItems: [file], applicationActivities: nil)
        controller.popoverPresentationController?.sourceView = shareButton
        present(controller, animated: true)
    }
}
