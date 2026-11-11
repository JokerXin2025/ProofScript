(function () {
    "use strict";
    const parameter = "ps4html-templates";
    const base = new URL(document.documentElement.dataset.projectBaseUrl || "./", window.location.href);
    const project = base.pathname.endsWith("/") ? base.pathname : `${base.pathname}/`;
    const projectId = document.documentElement.dataset.projectId || project;
    const pageParameters = [parameter, "ps-display-wrappers", "ps4html-language", "ps4html-sidebar-width"];
    const limit = 8192;
    // Mirror Lean2TeX/builtin_styles.py. These identities may appear in a URL before
    // their rendering implementations become available in a page catalog.
    const builtinLabels = {
        lambda: ["mapsto", "fun", "typed"],
        application: ["call", "juxtaposed"],
        "forall.dependent": ["phrase", "symbol"],
        "forall.arrow": ["implies", "arrow"],
        let: ["where", "inline", "stacked"],
        "sort.level.zero": ["prop", "sort"],
        "sort.level.succ": ["compact", "structural"],
        "sort.level.max": ["compact", "structural"],
        "sort.level.imax": ["compact", "structural"],
        "sort.level.param": ["compact", "structural"],
        "sort.level.mvar": ["compact", "structural"],
        metavariable: ["question", "unknown"],
        "literal.nat": ["decimal", "chinese-simplified", "chinese-traditional", "greek-ionian", "roman"],
        "literal.str": ["plain", "strong", "code"],
    };
    const validKey = (key, label) => {
        try {
            const value = JSON.parse(key);
            return Array.isArray(value) && value.length === 2 && typeof value[1] === "string"
                && ((value[0] === "constant" && value[1].length > 0 && value[1].length < 512)
                    || (value[0] === "builtin" && Object.hasOwn(builtinLabels, value[1])
                        && builtinLabels[value[1]].includes(label)));
        } catch (_) { return false; }
    };
    const validLabel = label => typeof label === "string" && label.length > 0 && label.length < 128
        && /^[\x20-\x7e]+$/.test(label);
    function decode(raw) {
        if (!raw || raw.length > limit) return null;
        try {
            const value = JSON.parse(raw);
            if (value.v !== 1 || value.project !== projectId || !Array.isArray(value.choices)
                    || value.choices.length > 128) return null;
            const choices = Object.create(null);
            for (const entry of value.choices) {
                if (!Array.isArray(entry) || entry.length !== 2 || !validKey(entry[0], entry[1])
                        || !validLabel(entry[1]) || Object.hasOwn(choices, entry[0])) return null;
                choices[entry[0]] = entry[1];
            }
            return choices;
        } catch (_) { return null; }
    }
    function encode(choices) {
        return JSON.stringify({v: 1, project: projectId, choices: Object.entries(choices).sort(([a], [b]) =>
            a < b ? -1 : a > b ? 1 : 0)});
    }
    function read() {
        const url = new URL(window.location.href);
        return decode(url.searchParams.get(parameter)) || Object.create(null);
    }
    function destination(link) {
        const raw = link.getAttribute("href");
        if (!raw || raw.startsWith("#")) return null;
        let url;
        try { url = new URL(raw, window.location.href); } catch (_) { return null; }
        if (url.origin !== base.origin || !url.pathname.startsWith(project)
                || !/(?:\.html|\/)$/i.test(url.pathname)) return null;
        if (link.dataset?.psProjectId && link.dataset.psProjectId !== projectId) return null;
        return url;
    }
    function carryToUrl(url, choices = read()) {
        const current = new URL(window.location.href);
        for (const key of pageParameters) {
            if (current.searchParams.has(key)) url.searchParams.set(key, current.searchParams.get(key));
            else url.searchParams.delete(key);
        }
        const encoded = encode(choices);
        if (Object.keys(choices).length && encoded.length <= limit) url.searchParams.set(parameter, encoded);
        else url.searchParams.delete(parameter);
        return url;
    }
    function carryToLinks(choices = read()) {
        document.querySelectorAll("a[href]").forEach(link => {
            const url = destination(link);
            if (!url) return;
            carryToUrl(url, choices);
            link.setAttribute("href", url.protocol === "file:" ? url.href : `${url.pathname}${url.search}${url.hash}`);
        });
    }
    function save(choices) {
        const encoded = encode(choices);
        if (encoded.length > limit || Object.keys(choices).length > 128) return false;
        const url = new URL(window.location.href);
        if (Object.keys(choices).length) url.searchParams.set(parameter, encoded);
        else url.searchParams.delete(parameter);
        window.history.replaceState(window.history.state, "", url);
        carryToLinks(choices);
        return true;
    }
    window.PS4HTMLNavigationState = {read, save, carryToLinks, carryToUrl, project};
    document.addEventListener("DOMContentLoaded", () => carryToLinks());
    window.addEventListener("popstate", () => carryToLinks());
})();
