import ImageIO
import UIKit
import UniformTypeIdentifiers

final class ImageViewerController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    private let url: URL
    private let name: String
    private let session: URLSession
    private let scrollView = UIScrollView()
    private let imageView = UIImageView()
    private let spinner = UIActivityIndicatorView(style: .large)
    private let shareButton = UIButton(type: .system)
    private var data: Data?

    init(url: URL, name: String, session: URLSession) {
        self.url = url
        self.name = name
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

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.accessibilityIdentifier = "gomuks-image-viewer"

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

        let closeButton = makeButton(symbol: "xmark", label: "Close", action: #selector(close))
        closeButton.accessibilityIdentifier = "gomuks-image-viewer-close"
        shareButton.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        shareButton.tintColor = .white
        shareButton.accessibilityLabel = "Share"
        shareButton.isEnabled = false
        shareButton.addTarget(self, action: #selector(share), for: .touchUpInside)
        shareButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(shareButton)
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 8),
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            closeButton.widthAnchor.constraint(equalToConstant: 44),
            closeButton.heightAnchor.constraint(equalToConstant: 44),
            shareButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -8),
            shareButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            shareButton.widthAnchor.constraint(equalToConstant: 44),
            shareButton.heightAnchor.constraint(equalToConstant: 44),
        ])

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(dismissPan(_:)))
        pan.delegate = self
        view.addGestureRecognizer(pan)

        Task { await load() }
    }

    private func makeButton(symbol: String, label: String, action: Selector) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: symbol), for: .normal)
        button.tintColor = .white
        button.accessibilityLabel = label
        button.addTarget(self, action: action, for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(button)
        return button
    }

    private func load() async {
        guard let result = try? await session.data(from: url),
              (result.1 as? HTTPURLResponse)?.statusCode == 200
        else {
            spinner.stopAnimating()
            return
        }
        let data = result.0
        session.finishTasksAndInvalidate()
        let image = await Task.detached { Self.decode(data) }.value
        spinner.stopAnimating()
        guard let image else { return }
        self.data = data
        imageView.image = image
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = name
        shareButton.isEnabled = true
    }

    private nonisolated static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return UIImage(data: data) }
        var frames: [UIImage] = []
        var duration = 0.0
        for index in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
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

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        return scrollView.zoomScale <= scrollView.minimumZoomScale && abs(velocity.y) > abs(velocity.x)
    }

    @objc private func dismissPan(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: view)
        switch pan.state {
        case .changed:
            scrollView.transform = CGAffineTransform(translationX: 0, y: translation.y)
            view.backgroundColor = UIColor.black.withAlphaComponent(max(0.2, 1 - abs(translation.y) / 400))
        case .ended, .cancelled:
            if abs(translation.y) > 120 || abs(pan.velocity(in: view).y) > 1000 {
                close()
            } else {
                UIView.animate(withDuration: 0.2) {
                    self.scrollView.transform = .identity
                    self.view.backgroundColor = .black
                }
            }
        default:
            break
        }
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    @objc private func share() {
        guard let data else { return }
        let type = CGImageSourceCreateWithData(data as CFData, nil).flatMap { CGImageSourceGetType($0) as String? }
        let fileExtension = type.flatMap { UTType($0)?.preferredFilenameExtension } ?? "jpg"
        var base = (name as NSString).deletingPathExtension
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
