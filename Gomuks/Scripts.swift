enum SettingsButton {
    static let messageName = "gomuksSettings"

    static let script = """
    (() => {
        const icon = '<svg xmlns="http://www.w3.org/2000/svg" height="24px" viewBox="0 -960 960 960" width="24px" fill="currentColor"><path d="m370-80-16-128q-13-5-24.5-12T307-235l-119 50L78-375l103-78q-1-7-1-13.5v-27q0-6.5 1-13.5L78-585l110-190 119 50q11-8 23-15t24-12l16-128h220l16 128q13 5 24.5 12t22.5 15l119-50 110 190-103 78q1 7 1 13.5v27q0 6.5-2 13.5l103 78-110 190-118-50q-11 8-23 15t-24 12L590-80H370Zm70-80h79l14-106q31-8 57.5-23.5T639-327l99 41 39-68-86-65q5-14 7-29.5t2-31.5q0-16-2-31.5t-7-29.5l86-65-39-68-99 42q-22-23-48.5-38.5T533-694l-13-106h-79l-14 106q-31 8-57.5 23.5T321-633l-99-41-39 68 86 64q-5 15-7 30t-2 32q0 16 2 31t7 30l-86 65 39 68 99-42q22 23 48.5 38.5T427-266l13 106Zm42-180q58 0 99-41t41-99q0-58-41-99t-99-41q-59 0-99.5 41T342-480q0 58 40.5 99t99.5 41Zm-2-140Z"/></svg>';
        const button = document.createElement("button");
        button.className = "ios-settings-button";
        button.title = "Server and account";
        button.innerHTML = icon;
        button.addEventListener("click", () => window.webkit.messageHandlers.\(messageName).postMessage("open"));
        const insert = () => {
            if (button.isConnected) {
                return;
            }
            const wrapper = document.querySelector("div.room-search-wrapper");
            if (wrapper) {
                wrapper.appendChild(button);
            }
        };
        new MutationObserver(insert).observe(document.body, { childList: true, subtree: true });
        insert();
    })();
    """
}

enum TimelineScroll {
    static let script = """
    (() => {
        const heights = new WeakMap();
        const resizeObserver = new ResizeObserver((entries) => {
            for (const entry of entries) {
                const view = entry.target;
                const previous = heights.get(view);
                const current = view.clientHeight;
                heights.set(view, current);
                if (previous !== undefined && current < previous
                    && view.scrollTop + previous + 1 >= view.scrollHeight) {
                    view.scrollTop = view.scrollHeight;
                }
            }
        });
        const views = document.getElementsByClassName("timeline-view");
        const attach = () => {
            for (const view of views) {
                if (!heights.has(view)) {
                    heights.set(view, view.clientHeight);
                    resizeObserver.observe(view);
                }
            }
        };
        new MutationObserver(attach).observe(document.body, { childList: true, subtree: true });
        attach();
    })();
    """
}

enum MediaScript {
    static let messageName = "gomuksMedia"

    static let script = """
    (() => {
        const style = document.createElement("style");
        style.textContent = [
            "html.ios-native-lightbox div.lightbox { display: none !important; }",
            "div.url-preview[data-ios-shape] { width: 100% !important; max-width: none !important; max-height: none !important; grid-template: 'title actions' auto 'description description' auto 'media media' auto / 1fr auto !important; }",
            "div.url-preview[data-ios-shape] > div.inline-media-wrapper { padding: 0; border-radius: 0 0 .5rem .5rem; }",
            "div.url-preview[data-ios-shape] div.media-container { height: auto !important; contain: layout paint !important; content-visibility: visible !important; contain-intrinsic-size: none !important; align-self: start; justify-self: center; }",
            "div.url-preview[data-ios-shape=landscape] div.media-container { width: 100% !important; aspect-ratio: 16 / 9; }",
            "div.url-preview[data-ios-shape=portrait] div.media-container { width: min(100%, calc(50vh * 9 / 16)) !important; aspect-ratio: 9 / 16; }",
            "div.url-preview[data-ios-shape] div.media-container > img, div.url-preview[data-ios-shape] div.media-container > canvas { width: 100% !important; height: 100% !important; object-fit: cover; display: block; }",
        ].join(" ");
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
        let lastContainer = null;
        let lastPayload = null;
        window.__gomuksEmbedVideo = (src) => {
            const container = lastContainer;
            if (!container || container.querySelector("iframe.ios-inline-player")) {
                return;
            }
            container.style.position = "relative";
            const image = container.querySelector("img");
            if (image) {
                image.style.visibility = "hidden";
            }
            const frame = document.createElement("iframe");
            frame.className = "ios-inline-player";
            frame.src = src;
            frame.allow = "autoplay; fullscreen; picture-in-picture";
            frame.allowFullscreen = true;
            frame.style.cssText = "position: absolute; inset: 0; width: 100%; height: 100%; border: 0;";
            frame.gomuksPayload = lastPayload;
            container.appendChild(frame);
        };
        window.addEventListener("message", (event) => {
            if (!event.data || event.data.type !== "ytdlp-no-video") {
                return;
            }
            const frame = [...document.querySelectorAll("iframe.ios-inline-player")]
                .find((candidate) => candidate.contentWindow === event.source);
            if (!frame || new URL(frame.src).origin !== event.origin) {
                return;
            }
            const container = frame.parentElement;
            const payload = frame.gomuksPayload;
            frame.remove();
            const image = container && container.querySelector("img");
            if (image) {
                image.style.visibility = "";
            }
            if (payload) {
                window.webkit.messageHandlers.\(messageName).postMessage({
                    ...payload,
                    link: "",
                    noVideo: String(event.data.url || ""),
                    reason: String(event.data.reason || ""),
                });
            }
        });
        const visible = new Set();
        let prefetchTimer = 0;
        const schedulePrefetch = () => {
            clearTimeout(prefetchTimer);
            prefetchTimer = setTimeout(() => {
                const links = [...visible].filter((link) => link.isConnected).map((link) => link.href);
                if (links.length) {
                    window.webkit.messageHandlers.\(messageName).postMessage({ prefetch: links });
                }
            }, 300);
        };
        const visibleLinks = new IntersectionObserver((entries) => {
            for (const entry of entries) {
                if (entry.isIntersecting) {
                    visible.add(entry.target);
                } else {
                    visible.delete(entry.target);
                }
            }
            schedulePrefetch();
        });
        const previewRatio = (preview) => {
            const [width, height] = (preview.querySelector("div.media-container > img")?.style.aspectRatio || "").split("/").map(Number);
            if (width > 0 && height > 0) {
                return width / height;
            }
            const box = preview.querySelector("div.media-container");
            return box ? parseFloat(box.style.width) / parseFloat(box.style.height) : NaN;
        };
        const shapePreview = (preview) => {
            const ratio = previewRatio(preview);
            if (ratio > 0) {
                preview.dataset.iosShape = ratio < 1 ? "portrait" : "landscape";
            }
        };
        const watchTimeline = (node) => {
            if (node.nodeType !== Node.ELEMENT_NODE) {
                return;
            }
            const inTimeline = Boolean(node.closest("div.timeline-view"));
            const find = (selector) => !inTimeline
                ? node.querySelectorAll("div.timeline-view " + selector)
                : node.matches(selector) ? [node] : node.querySelectorAll(selector);
            for (const link of find("a[href]")) {
                if ((link.protocol === "https:" || link.protocol === "http:") && link.origin !== location.origin && link.hostname !== "matrix.to") {
                    visibleLinks.observe(link);
                }
            }
            const owner = inTimeline ? node.parentElement?.closest("div.url-preview") : null;
            for (const preview of owner ? [owner] : find("div.url-preview")) {
                shapePreview(preview);
            }
        };
        new MutationObserver((mutations) => {
            for (const mutation of mutations) {
                mutation.addedNodes.forEach(watchTimeline);
            }
        }).observe(document.body, { childList: true, subtree: true });
        document.addEventListener("scroll", schedulePrefetch, { capture: true, passive: true });
        watchTimeline(document.body);
        const fullSource = (img) => new URL(img.getAttribute("data-full-src") || img.src, location.href).href;
        const pushState = history.pushState.bind(history);
        history.pushState = (state, unused, url) => {
            const lightbox = state && state.lightbox;
            if (lightbox && typeof lightbox.src === "string") {
                const src = new URL(lightbox.src, location.href);
                if (src.protocol === "https:" || src.protocol === "http:") {
                    root.classList.add("ios-native-lightbox");
                    const images = [...document.querySelectorAll("div.timeline-view .image-container img")]
                        .map((img) => ({ src: fullSource(img), alt: img.alt || "" }))
                        .filter((image) => image.src.startsWith("http"));
                    let index = images.findIndex((image) => image.src === src.href);
                    if (index < 0) {
                        images.splice(0, images.length, { src: src.href, alt: String(lightbox.alt || "") });
                        index = 0;
                    }
                    const clicked = [...document.querySelectorAll("div.timeline-view img")]
                        .find((img) => fullSource(img) === src.href);
                    lastContainer = clicked?.closest(".media-container") || null;
                    const preview = clicked?.closest("div.url-preview");
                    const link = (preview
                        ? preview.querySelector(".title a")?.href
                        : lastContainer?.parentElement?.querySelector(".message-text a[href]")?.href) || "";
                    lastPayload = { images, index };
                    window.webkit.messageHandlers.\(messageName).postMessage({ images, index, link });
                    requestAnimationFrame(() => closeLightbox(0));
                    return;
                }
            }
            pushState(state, unused, url);
        };
    })();
    """
}

enum InlineVideoScript {
    static func script(subframesOnly: Bool) -> String {
        """
        (() => {
            if (\(subframesOnly) && window.top === window) {
                return;
            }
            const mark = () => {
                for (const video of document.querySelectorAll("video:not([playsinline])")) {
                    video.setAttribute("playsinline", "");
                    video.setAttribute("webkit-playsinline", "");
                }
            };
            new MutationObserver(mark).observe(document, { childList: true, subtree: true });
        })();
        """
    }
}
