(function () {
    "use strict";
    const trigger = document.querySelector("[data-share-open]");
    const dialog = document.querySelector(".share-dialog");
    if (!trigger || !dialog) return;
    const local = dialog.querySelector('[data-share-copy="local"]');
    const publicButton = dialog.querySelector('[data-share-copy="public"]');
    const closeButton = dialog.querySelector("[data-share-close]");
    const status = dialog.querySelector(".share-dialog-status");
    const projectUrl = document.documentElement.dataset.projectUrl;
    const language = () => document.documentElement.dataset.language || document.documentElement.dataset.defaultLanguage || "en";
    const text = element => language() === "en" ? element.dataset.shareEn : element.dataset.shareZh;
    const message = key => dialog.dataset[`${key}${language() === "en" ? "En" : "Zh"}`];

    function currentUrl() {
        const url = new URL(window.location.href);
        window.PS4HTMLNavigationState?.carryToUrl(url);
        return url;
    }

    function publicUrl(current) {
        if (!projectUrl) return null;
        try {
            const base = new URL(projectUrl);
            if (!["https:", "http:"].includes(base.protocol)) return null;
            const root = new URL(document.documentElement.dataset.projectBaseUrl || "./", current);
            if (!current.pathname.startsWith(root.pathname)) return null;
            const relative = current.pathname.slice(root.pathname.length);
            if (base.search || base.hash) return null;
            const destination = new URL(relative || "index.html", base.href.endsWith("/") ? base : `${base.href}/`);
            current.searchParams.forEach((value, key) => destination.searchParams.set(key, value));
            destination.hash = current.hash;
            return destination.href;
        } catch (_) { return null; }
    }

    function refresh() {
        const current = currentUrl();
        const localAvailable = current.protocol === "file:";
        const publicAvailable = !!publicUrl(current);
        local.disabled = !localAvailable;
        publicButton.disabled = !publicAvailable;
        dialog.querySelector('[data-share-hint="local"]').hidden = localAvailable;
        dialog.querySelector('[data-share-hint="public"]').hidden = publicAvailable;
        local.title = localAvailable ? "" : message("localUnavailable");
        publicButton.title = publicAvailable ? "" : message("publicUnavailable");
    }

    function updateLanguage() {
        dialog.querySelectorAll("[data-share-zh]").forEach(element => { element.textContent = text(element); });
        trigger.setAttribute("aria-label", text(dialog.querySelector("#share-dialog-title")));
        trigger.title = trigger.getAttribute("aria-label");
        closeButton.setAttribute("aria-label", message("close"));
        closeButton.title = closeButton.getAttribute("aria-label");
        refresh();
    }

    async function copy(value) {
        if (navigator.clipboard?.writeText) {
            try { await navigator.clipboard.writeText(value); return true; } catch (_) { /* File pages may lack clipboard access. */ }
        }
        const input = document.createElement("textarea");
        input.value = value;
        input.setAttribute("readonly", "");
        input.style.position = "fixed";
        input.style.opacity = "0";
        dialog.append(input);
        input.select();
        let success = false;
        try { success = document.execCommand("copy"); } catch (_) { /* Show failure below. */ }
        input.remove();
        return success;
    }

    trigger.addEventListener("click", () => {
        status.dataset.shareZh = status.dataset.shareEn = "";
        status.textContent = "";
        refresh();
        dialog.showModal();
    });
    closeButton.addEventListener("click", () => dialog.close());
    dialog.addEventListener("click", event => { if (event.target === dialog) dialog.close(); });
    dialog.querySelectorAll("[data-share-copy]").forEach(button => button.addEventListener("click", async () => {
        const current = currentUrl();
        const value = button === local ? (current.protocol === "file:" ? current.href : null) : publicUrl(current);
        if (!value) return;
        const success = await copy(value);
        status.dataset.shareZh = dialog.dataset[success ? "copiedZh" : "failedZh"];
        status.dataset.shareEn = dialog.dataset[success ? "copiedEn" : "failedEn"];
        status.textContent = text(status);
    }));
    document.addEventListener("ps4html:languagechange", updateLanguage);
    document.addEventListener("DOMContentLoaded", updateLanguage);
})();
