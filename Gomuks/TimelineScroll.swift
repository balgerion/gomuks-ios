enum TimelineScroll {
    static let script = """
    (() => {
        const atBottom = new WeakMap();
        document.addEventListener("scroll", (event) => {
            const view = event.target;
            if (view instanceof Element && view.classList.contains("timeline-view")) {
                atBottom.set(view, view.scrollTop + view.clientHeight + 1 >= view.scrollHeight);
            }
        }, { capture: true, passive: true });
        window.addEventListener("resize", () => {
            for (const view of document.querySelectorAll("div.timeline-view")) {
                if (atBottom.get(view) !== false) {
                    view.scrollTop = view.scrollHeight;
                }
            }
        });
    })();
    """
}
