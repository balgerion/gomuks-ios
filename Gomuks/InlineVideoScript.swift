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
