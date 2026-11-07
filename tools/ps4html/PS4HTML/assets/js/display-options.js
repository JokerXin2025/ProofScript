(function () {
    const options = {
        wrappers: {
            parameter: "ps-display-wrappers",
            storage: "ps4html-display-wrappers",
            defaultValue: false,
        },
    };

    function readValue(option) {
        const url = new URL(window.location.href);
        const raw = url.searchParams.get(option.parameter);
        if (raw === "1" || raw === "0") return raw === "1";
        return window.localStorage.getItem(option.storage) === "1";
    }

    function currentState() {
        return Object.fromEntries(Object.entries(options).map(([key, option]) => [key, readValue(option)]));
    }

    function updateUrl(state) {
        const url = new URL(window.location.href);
        Object.entries(options).forEach(([key, option]) => {
            if (state[key] === option.defaultValue) url.searchParams.delete(option.parameter);
            else url.searchParams.set(option.parameter, state[key] ? "1" : "0");
        });
        window.history.replaceState(window.history.state, "", url);
    }

    function persist(state) {
        Object.entries(options).forEach(([key, option]) => {
            window.localStorage.setItem(option.storage, state[key] ? "1" : "0");
        });
    }

    function carryToLinks(state) {
        document.querySelectorAll("a[href]").forEach(link => {
            const raw = link.getAttribute("href");
            if (!raw || raw.startsWith("#") || raw.startsWith("mailto:") || raw.startsWith("javascript:")) return;
            let url;
            try { url = new URL(raw, window.location.href); } catch (_) { return; }
            if (url.origin !== window.location.origin) return;
            Object.entries(options).forEach(([key, option]) => {
                if (state[key] === option.defaultValue) url.searchParams.delete(option.parameter);
                else url.searchParams.set(option.parameter, state[key] ? "1" : "0");
            });
            link.setAttribute("href", url.pathname + url.search + url.hash);
        });
    }

    function setOption(key, value, announce = true) {
        if (!options[key]) return;
        const state = currentState();
        state[key] = Boolean(value);
        persist(state);
        updateUrl(state);
        document.documentElement.dataset.displayWrappers = state.wrappers ? "on" : "off";
        document.querySelectorAll(`[data-display-option="${key}"]`).forEach(item => {
            item.setAttribute("aria-checked", state[key] ? "true" : "false");
            item.classList.toggle("is-enabled", state[key]);
        });
        carryToLinks(state);
        if (announce) document.dispatchEvent(new CustomEvent("ps4html:displaychange", { detail: state }));
    }

    window.PS4HTMLDisplayOptions = {
        getState: currentState,
        setOption,
        carryToLinks,
    };

    function closeMenus() {
        document.querySelectorAll(".display-options.is-open, .language-switcher.is-open").forEach(menu => {
            menu.classList.remove("is-open");
            menu.classList.add("is-dismissed");
            menu.querySelector("button")?.setAttribute("aria-expanded", "false");
        });
    }

    document.addEventListener("pointerleave", event => {
        if (event.target.matches?.(".display-options")) event.target.classList.remove("is-dismissed");
    }, true);

    document.addEventListener("click", event => {
        const button = event.target.closest(".display-options-button");
        const item = event.target.closest("[data-display-option]");
        if (item) {
            const key = item.dataset.displayOption;
            setOption(key, !(currentState()[key]));
            return;
        }
        if (button) {
            document.querySelectorAll(".language-switcher.is-open").forEach(menu => {
                menu.classList.remove("is-open");
                menu.classList.add("is-dismissed");
                menu.querySelector(".language-button")?.setAttribute("aria-expanded", "false");
            });
            const menu = button.closest(".display-options");
            const open = menu.classList.toggle("is-open");
            menu.classList.toggle("is-dismissed", !open);
            button.setAttribute("aria-expanded", open ? "true" : "false");
            return;
        }
        if (!event.target.closest(".display-options, .language-switcher")) closeMenus();
    });

    document.addEventListener("keydown", event => {
        if (event.key === "Escape") closeMenus();
    });

    window.addEventListener("popstate", () => {
        const state = currentState();
        Object.keys(options).forEach(key => setOption(key, state[key], false));
    });

    window.addEventListener("DOMContentLoaded", () => {
        const state = currentState();
        Object.keys(options).forEach(key => setOption(key, state[key], false));
        carryToLinks(state);
    });
})();
