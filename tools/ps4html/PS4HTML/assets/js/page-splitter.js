(function () {
    "use strict";

    const layout = document.querySelector(".page-layout");
    const splitter = layout?.querySelector(".page-splitter");
    if (!splitter) return;

    const minSidebar = 240;
    const minContent = 480;
    const step = 24;
    const parameter = "ps4html-sidebar-width";
    let width = null;
    let pointer = null;
    let frame = null;

    function bounds() {
        return Math.max(minSidebar, layout.clientWidth - splitter.offsetWidth - minContent);
    }

    function update(value) {
        width = Math.max(minSidebar, Math.min(value, bounds()));
        layout.style.setProperty("--sidebar-width", `${width}px`);
        splitter.setAttribute("aria-valuemax", String(bounds()));
        splitter.setAttribute("aria-valuenow", String(Math.round(width)));
        if (frame === null) frame = requestAnimationFrame(() => {
            frame = null;
            window.dispatchEvent(new Event("resize"));
        });
    }

    function save() {
        if (width === null) return;
        const url = new URL(window.location.href);
        url.searchParams.set(parameter, String(Math.round(width)));
        window.history.replaceState(window.history.state, "", url);
        window.PS4HTMLNavigationState?.carryToLinks();
        document.dispatchEvent(new Event("ps4html:sidebarchange"));
    }

    function restore() {
        const raw = new URL(window.location.href).searchParams.get(parameter);
        const value = raw !== null && /^\d+$/.test(raw) ? Number(raw) : NaN;
        if (Number.isSafeInteger(value) && value >= minSidebar) update(value);
        else {
            width = null;
            layout.style.removeProperty("--sidebar-width");
            splitter.setAttribute("aria-valuemax", String(bounds()));
            splitter.setAttribute("aria-valuenow", String(Math.round(splitter.getBoundingClientRect().left - layout.getBoundingClientRect().left)));
        }
    }
    restore();
    window.addEventListener("popstate", restore);

    splitter.addEventListener("pointerdown", event => {
        if (!event.isPrimary || event.button !== 0) return;
        pointer = event.pointerId;
        splitter.setPointerCapture(pointer);
        layout.classList.add("is-resizing");
        event.preventDefault();
    });
    splitter.addEventListener("pointermove", event => {
        if (pointer === event.pointerId) update(event.clientX - layout.getBoundingClientRect().left - splitter.offsetWidth / 2);
    });
    function finish(event) {
        if (pointer !== event.pointerId) return;
        if (event.type === "pointerup") update(event.clientX - layout.getBoundingClientRect().left - splitter.offsetWidth / 2);
        pointer = null;
        layout.classList.remove("is-resizing");
        if (width !== null) save();
    }
    splitter.addEventListener("pointerup", finish);
    splitter.addEventListener("pointercancel", finish);
    splitter.addEventListener("lostpointercapture", finish);
    splitter.addEventListener("keydown", event => {
        if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
        event.preventDefault();
        const current = width ?? splitter.getBoundingClientRect().left - layout.getBoundingClientRect().left;
        update(event.key === "Home" ? minSidebar : event.key === "End" ? bounds() :
            current + (event.key === "ArrowLeft" ? -step : step));
        save();
    });
    window.addEventListener("resize", () => {
        if (width !== null && width > bounds()) update(width);
        else splitter.setAttribute("aria-valuemax", String(bounds()));
    });
})();
