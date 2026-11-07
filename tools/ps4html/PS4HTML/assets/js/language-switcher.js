(function () {
    const supported = ["zh", "en"];
    const stored = window.localStorage.getItem("ps4html-language");
    const pageDefault = document.documentElement.dataset.defaultLanguage;
    const initial = supported.includes(stored) ? stored : (supported.includes(pageDefault) ? pageDefault : "zh");

    function setLanguage(language) {
        if (!supported.includes(language)) return;
        document.documentElement.dataset.language = language;
        document.querySelectorAll("[data-language-panel]").forEach(panel => {
            panel.hidden = panel.dataset.languagePanel !== language;
        });
        document.documentElement.lang = language === "en" ? "en" : "zh-CN";
        document.querySelectorAll(".language-current").forEach(current => {
            current.textContent = language === "en" ? "EN" : "中文";
        });
        document.querySelectorAll("[data-display-option-text]").forEach(label => {
            label.textContent = language === "en" ? label.dataset.labelEn : label.dataset.labelZh;
        });
        document.querySelectorAll(".language-menu [data-language]").forEach(item => {
            item.setAttribute("aria-checked", item.dataset.language === language ? "true" : "false");
        });
        window.localStorage.setItem("ps4html-language", language);
        document.dispatchEvent(new CustomEvent("ps4html:languagechange", {detail: {language}}));
        document.dispatchEvent(new Event("ps4html:layoutchange"));
    }

    function closeMenus() {
        document.querySelectorAll(".language-switcher.is-open").forEach(switcher => {
            switcher.classList.remove("is-open");
            switcher.classList.add("is-dismissed");
            switcher.querySelector(".language-button")?.setAttribute("aria-expanded", "false");
        });
    }

    document.addEventListener("pointerleave", event => {
        if (event.target.matches?.(".language-switcher")) event.target.classList.remove("is-dismissed");
    }, true);

    document.addEventListener("click", event => {
        const button = event.target.closest(".language-button");
        const item = event.target.closest(".language-menu [data-language]");
        if (item) {
            setLanguage(item.dataset.language);
            closeMenus();
            return;
        }
        if (button) {
            document.querySelectorAll(".display-options.is-open").forEach(menu => {
                menu.classList.remove("is-open");
                menu.classList.add("is-dismissed");
                menu.querySelector(".display-options-button")?.setAttribute("aria-expanded", "false");
            });
            const switcher = button.closest(".language-switcher");
            const open = switcher.classList.toggle("is-open");
            switcher.classList.toggle("is-dismissed", !open);
            button.setAttribute("aria-expanded", open ? "true" : "false");
            return;
        }
        if (!event.target.closest(".language-switcher")) closeMenus();
    });

    document.addEventListener("keydown", event => {
        if (event.key === "Escape") closeMenus();
    });

    window.addEventListener("DOMContentLoaded", () => setLanguage(initial));
})();
