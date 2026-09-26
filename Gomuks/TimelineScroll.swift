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
