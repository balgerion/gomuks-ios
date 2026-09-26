enum ImageViewerScript {
    static let messageName = "gomuksImage"

    static let script = """
    (() => {
        const style = document.createElement("style");
        style.textContent = "html.ios-native-lightbox div.lightbox { display: none !important; }";
        document.head.appendChild(style);
        const root = document.documentElement;
        const closeLightbox = (attempt) => {
            const close = document.querySelector("div.lightbox .controls > button:last-of-type");
            if (close) {
                close.click();
                root.classList.remove("ios-native-lightbox");
            } else if (attempt < 30) {
                requestAnimationFrame(() => closeLightbox(attempt + 1));
            } else {
                root.classList.remove("ios-native-lightbox");
            }
        };
        const pushState = history.pushState.bind(history);
        history.pushState = (state, unused, url) => {
            const lightbox = state && state.lightbox;
            if (lightbox && typeof lightbox.src === "string") {
                const src = new URL(lightbox.src, location.href);
                if (src.protocol === "https:" || src.protocol === "http:") {
                    root.classList.add("ios-native-lightbox");
                    const images = [...document.querySelectorAll("div.timeline-view .image-container img")]
                        .map((img) => ({
                            src: new URL(img.getAttribute("data-full-src") || img.src, location.href).href,
                            alt: img.alt || "",
                        }))
                        .filter((image) => image.src.startsWith("http"));
                    let index = images.findIndex((image) => image.src === src.href);
                    if (index < 0) {
                        images.splice(0, images.length, { src: src.href, alt: String(lightbox.alt || "") });
                        index = 0;
                    }
                    window.webkit.messageHandlers.\(messageName).postMessage({ images, index });
                    requestAnimationFrame(() => closeLightbox(0));
                    return;
                }
            }
            pushState(state, unused, url);
        };
    })();
    """
}
