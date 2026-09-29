import ImageIO
import UIKit
import UniformTypeIdentifiers

struct ViewerImage {
    let url: URL
    let name: String
}

final class ImageViewerController: UIViewController, UIPageViewControllerDataSource, UIPageViewControllerDelegate {
    private let images: [ViewerImage]
    private let startIndex: Int
    private let session: URLSession
    private let pager = UIPageViewController(
        transitionStyle: .scroll,
        navigationOrientation: .vertical,
        options: [.interPageSpacing: 16]
    )
    private let shareButton = UIButton.overlay(systemName: "square.and.arrow.up")
    private let counter = UILabel()
    private var swipeToDismiss: SwipeToDismiss?

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

        let closeButton = UIButton.overlay(systemName: "xmark")
        closeButton.accessibilityLabel = "Close"
        closeButton.accessibilityIdentifier = "gomuks-image-viewer-close"
        closeButton.addTarget(self, action: #selector(close), for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(closeButton)

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

        swipeToDismiss = SwipeToDismiss(
            controller: self,
            movingView: pager.view,
            fadesBackground: true,
            canBegin: { [weak self] in !(self?.currentPage?.isZoomed ?? false) },
            onDismiss: { [weak self] in self?.close() }
        )

        updateChrome()
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
        var base = String((page.name as NSString).deletingPathExtension
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .drop { $0 == "." }
            .prefix(100))
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

final class ImagePageController: UIViewController, UIScrollViewDelegate {
    private nonisolated static let maxPixelSize = 4096

    let index: Int
    let name: String
    private(set) var data: Data?
    var onLoad: (() -> Void)?
    var isZoomed: Bool {
        scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
    }
    private let url: URL
    private let session: URLSession
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .large)

    init(index: Int, url: URL, name: String, session: URLSession) {
        self.index = index
        self.url = url
        self.name = name
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        scrollView.frame = view.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 6
        scrollView.showsVerticalScrollIndicator = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        view.addSubview(scrollView)

        imageView.frame = scrollView.bounds
        imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        imageView.contentMode = .scaleAspectFit
        imageView.accessibilityIdentifier = "gomuks-image-viewer-image"
        scrollView.addSubview(imageView)

        spinner.color = .white
        spinner.center = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
        spinner.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin, .flexibleLeftMargin, .flexibleRightMargin]
        spinner.startAnimating()
        view.addSubview(spinner)

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        Task { await load() }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
    }

    private func load() async {
        guard let result = try? await session.data(from: url),
              (result.1 as? HTTPURLResponse)?.statusCode == 200
        else {
            spinner.stopAnimating()
            return
        }
        let data = result.0
        let image = await Task.detached { Self.decode(data) }.value
        spinner.stopAnimating()
        guard let image else { return }
        self.data = data
        imageView.image = image
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = name
        onLoad?()
    }

    private nonisolated static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return decodeStill(data, source: source) }
        let frameOptions = [kCGImageSourceShouldCacheImmediately: true] as CFDictionary
        var frames: [UIImage] = []
        var duration = 0.0
        for index in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, frameOptions) else { continue }
            frames.append(UIImage(cgImage: frame))
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
            let gif = properties?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = gif?[kCGImagePropertyGIFUnclampedDelayTime] as? Double
                ?? gif?[kCGImagePropertyGIFDelayTime] as? Double
                ?? 0.1
            duration += delay < 0.02 ? 0.1 : delay
        }
        return UIImage.animatedImage(with: frames, duration: duration)
    }

    private nonisolated static func decodeStill(_ data: Data, source: CGImageSource) -> UIImage? {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = properties?[kCGImagePropertyPixelWidth] as? Int ?? 0
        let height = properties?[kCGImagePropertyPixelHeight] as? Int ?? 0
        guard max(width, height) > maxPixelSize else {
            return UIImage(data: data)?.preparingForDisplay()
        }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options).map { UIImage(cgImage: $0) }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            let size = CGSize(width: scrollView.bounds.width / 3, height: scrollView.bounds.height / 3)
            scrollView.zoom(to: CGRect(origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size), animated: true)
        }
    }
}

final class SwipeToDismiss: NSObject, UIGestureRecognizerDelegate {
    private weak var controller: UIViewController?
    private weak var movingView: UIView?
    private let fadesBackground: Bool
    private let canBegin: () -> Bool
    private let onDismiss: () -> Void

    init(
        controller: UIViewController,
        movingView: UIView,
        fadesBackground: Bool,
        canBegin: @escaping () -> Bool,
        onDismiss: @escaping () -> Void
    ) {
        self.controller = controller
        self.movingView = movingView
        self.fadesBackground = fadesBackground
        self.canBegin = canBegin
        self.onDismiss = onDismiss
        super.init()
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handle(_:)))
        pan.delegate = self
        controller.view.addGestureRecognizer(pan)
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, let view = controller?.view else { return true }
        let velocity = pan.velocity(in: view)
        return abs(velocity.x) > abs(velocity.y) && canBegin()
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    @objc private func handle(_ pan: UIPanGestureRecognizer) {
        guard let controller, let movingView else { return }
        let translation = pan.translation(in: controller.view)
        switch pan.state {
        case .changed:
            movingView.transform = CGAffineTransform(translationX: translation.x, y: 0)
            if fadesBackground {
                controller.view.backgroundColor = UIColor.black.withAlphaComponent(max(0.2, 1 - abs(translation.x) / 400))
            }
        case .ended, .cancelled:
            if abs(translation.x) > 100 || abs(pan.velocity(in: controller.view).x) > 800 {
                onDismiss()
            } else {
                UIView.animate(withDuration: 0.2) {
                    movingView.transform = .identity
                    if self.fadesBackground {
                        controller.view.backgroundColor = .black
                    }
                }
            }
        default:
            break
        }
    }
}

extension UIButton {
    static func overlay(systemName: String) -> UIButton {
        let image = UIImage(systemName: systemName)
        if #available(iOS 26, *) {
            var configuration = UIButton.Configuration.glass()
            configuration.image = image
            return UIButton(configuration: configuration)
        }
        let button = UIButton(type: .system)
        button.setImage(image, for: .normal)
        button.tintColor = .white
        return button
    }
}
