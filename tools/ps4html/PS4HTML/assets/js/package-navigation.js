(function () {
    "use strict";
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
    document.addEventListener("DOMContentLoaded", carry);
    window.addEventListener("popstate", carry);
    document.addEventListener("ps4html:languagechange", carry);
    document.addEventListener("ps4html:displaychange", carry);
    document.addEventListener("ps4html:sidebarchange", carry);
    carry();
})();
