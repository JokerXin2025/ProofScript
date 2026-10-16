(function () {
    // The view owns one live slot. All other graphs remain inert template contents.
    function createNavigationView(navigation) {
        const slot = navigation.querySelector("[data-theorem-navigation-content]");
        const templates = new Map(Array.from(navigation.querySelectorAll("template[data-theorem-id]"))
            .map(template => [template.dataset.theoremId, template]));
        let activeTheoremId = null;
        return {
            has(theoremId) {
                return templates.has(theoremId);
            },
            show(theoremId) {
                const template = templates.get(theoremId);
                const nextId = template ? theoremId : null;
                if (activeTheoremId === nextId) return;
                activeTheoremId = nextId;
                slot.replaceChildren(...(template ? [template.content.cloneNode(true)] : []));
                navigation.hidden = !template;
                if (nextId) navigation.dataset.theoremId = nextId;
                else delete navigation.dataset.theoremId;
            }
        };
    }

    window.addEventListener("DOMContentLoaded", () => {
        const navigation = document.querySelector(".theorem-dependency-navigation");
        if (!navigation) return;
        const view = createNavigationView(navigation);

        const closeDelay = 150;
        let pointer = null;
        let activeTheoremId = null;
        let closeTimer = null;
        let frame = null;

        function cancelClose() {
            if (closeTimer !== null) window.clearTimeout(closeTimer);
            closeTimer = null;
        }

        function activate(theoremId) {
            cancelClose();
            activeTheoremId = theoremId;
            view.show(theoremId);
        }

        function clear() {
            pointer = null;
            if (frame !== null) cancelAnimationFrame(frame);
            frame = null;
            activate(null);
        }

        function hitTheorem() {
            if (!pointer || document.hidden) return null;
            const hit = document.elementFromPoint(pointer.x, pointer.y);
            // Links belong to the active source, regardless of their destination.
            if (hit && !navigation.hidden && navigation.contains(hit)) return activeTheoremId;
            const proof = hit?.closest(".theorem-proof[data-theorem-id]");
            if (!proof || proof.closest("[hidden]")) return null;
            return view.has(proof.dataset.theoremId) ? proof.dataset.theoremId : null;
        }

        function update() {
            const theoremId = hitTheorem();
            if (theoremId) {
                activate(theoremId);
            } else if (activeTheoremId && closeTimer === null) {
                // PendingClose keeps the graph usable while crossing the sidebar gap.
                // Further layout events do not extend this deadline.
                closeTimer = window.setTimeout(() => {
                    closeTimer = null;
                    activate(hitTheorem());
                }, closeDelay);
            }
        }

        function scheduleUpdate() {
            if (!pointer || document.hidden || frame !== null) return;
            frame = requestAnimationFrame(() => {
                frame = null;
                update();
            });
        }

        document.addEventListener("pointermove", event => {
            if (event.pointerType !== "mouse") return;
            pointer = {x: event.clientX, y: event.clientY};
            scheduleUpdate();
        }, {passive: true});
        document.addEventListener("pointerout", event => {
            if (event.pointerType === "mouse" && event.relatedTarget === null) clear();
        });
        window.addEventListener("blur", clear);
        window.addEventListener("pagehide", clear);
        document.addEventListener("visibilitychange", () => {
            if (document.hidden) clear();
        });

        // These events only re-hit saved viewport coordinates; they never select by height.
        window.addEventListener("scroll", scheduleUpdate, {capture: true, passive: true});
        window.addEventListener("resize", scheduleUpdate);
        window.addEventListener("hashchange", scheduleUpdate);
        document.addEventListener("ps4html:layoutchange", scheduleUpdate);
        document.addEventListener("toggle", scheduleUpdate, true);
        document.addEventListener("load", scheduleUpdate, true);
        document.fonts?.addEventListener("loadingdone", scheduleUpdate);

        // Observe content rather than the navigation slot to avoid self-triggered updates.
        // Theorem boxes cover branch/flip resizing; main's children cover text and media
        // above them, including size changes that leave main's total height unchanged.
        const content = document.querySelector("#main-content");
        const layoutTargets = new Set([
            ...(content ? [content, ...content.children] : []),
            ...document.querySelectorAll(".theorem-proof[data-theorem-id]")
        ]);
        const observer = new ResizeObserver(scheduleUpdate);
        layoutTargets.forEach(target => {
            if (target !== navigation && !navigation.contains(target)) observer.observe(target);
        });
    });
})();
