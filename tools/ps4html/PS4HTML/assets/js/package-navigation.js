(function () {
    "use strict";
    const libraries = window.PS4HTMLLibraries;
    const tree = document.querySelector(".module-context-tree");
    if (!tree || !Array.isArray(libraries)) return;
    const root = new URL(document.documentElement.dataset.packageBaseUrl || "./", window.location.href);
    const currentLibrary = new URL(document.documentElement.dataset.projectBaseUrl || "./", window.location.href);
    function carry() {
        const current = new URL(window.location.href);
        document.querySelectorAll("[data-ps-library-link], [data-ps-package-home]").forEach(link => {
            const url = new URL(link.href);
            for (const key of ["ps4html-language", "ps-display-wrappers", "ps4html-sidebar-width"]) {
                if (current.searchParams.has(key)) url.searchParams.set(key, current.searchParams.get(key));
                else url.searchParams.delete(key);
            }
            link.href = url.href;
        });
    }
    // A module-tree-root can still show the library itself (e.g. on a direct
    // child page). Hide other libraries only after that root has become an
    // inner module such as Builtin on ProofScript.Builtin.Scripts.
    if (root.pathname !== currentLibrary.pathname) {
        const currentName = decodeURIComponent(currentLibrary.pathname.slice(root.pathname.length).replace(/\/$/, ""));
        const entries = [...tree.children].map(item => ({
            name: item.querySelector("a.module-tree-node, a.module-tree-parent")?.textContent.trim() || "", item,
        }));
        if (entries.some(entry => entry.name === currentName)) {
            for (const name of libraries) {
                if (typeof name !== "string" || !name || name === "assets" || name === currentName) continue;
                const item = document.createElement("li");
                const link = document.createElement("a");
                link.className = "module-tree-node";
                link.href = new URL(`${encodeURIComponent(name)}/index.html`, root).href;
                link.dataset.psLibraryLink = "";
                const mark = document.createElement("span");
                mark.className = "module-tree-node-mark";
                mark.setAttribute("aria-hidden", "true");
                link.append(mark, document.createTextNode(name));
                item.append(link);
                entries.push({name, item});
            }
            entries.sort((a, b) => a.name < b.name ? -1 : a.name > b.name ? 1 : 0);
            tree.replaceChildren(...entries.map(entry => entry.item));
        }
    }
    document.addEventListener("DOMContentLoaded", carry);
    window.addEventListener("popstate", carry);
    document.addEventListener("ps4html:languagechange", carry);
    document.addEventListener("ps4html:displaychange", carry);
    document.addEventListener("ps4html:sidebarchange", carry);
    carry();
})();
