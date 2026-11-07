(function () {
    "use strict";

    const selector = ".ps-fit-viewport";
    let scheduled = false;
    let notifying = false;

    function alignCalculations() {
        const groups = new Map();
        document.querySelectorAll(".proof-step.calc").forEach(block => {
            const parent = block.parentElement;
            if (!groups.has(parent)) groups.set(parent, []);
            groups.get(parent).push(block);
        });
        groups.forEach(blocks => {
            let left = 0, right = 0;
            blocks.forEach(block => {
                const lhs = block.querySelector(".proof-calc-lhs");
                const rhs = block.querySelector(".proof-calc-rhs");
                if (lhs) {
                    lhs.style.flex = "0 0 auto";
                    left = Math.max(left, lhs.scrollWidth);
                }
                if (rhs) {
                    rhs.style.flex = "0 0 auto";
                    right = Math.max(right, rhs.scrollWidth);
                }
            });
            blocks.forEach(block => {
                const lhs = block.querySelector(".proof-calc-lhs");
                const rhs = block.querySelector(".proof-calc-rhs");
                if (lhs) lhs.style.flex = `1 1 ${left}px`;
                if (rhs) rhs.style.flex = `1 1 ${right}px`;
            });
        });
    }

    function fit(viewport) {
        const content = viewport.querySelector(":scope > .ps-fit-content");
        if (!content || !viewport.clientWidth) return;
        content.style.transform = "";
        viewport.style.height = "";
        // scrollWidth measures untransformed KaTeX and other unbreakable children.
        const naturalWidth = content.scrollWidth;
        const scale = naturalWidth > viewport.clientWidth
            ? viewport.clientWidth / naturalWidth : 1;
        if (scale < 1) {
            content.style.transform = `scale(${scale})`;
            viewport.style.height = `${content.scrollHeight * scale}px`;
        }
    }

    function alignAndScaleMath() {
        scheduled = false;
        alignCalculations();
        document.querySelectorAll(selector).forEach(fit);
        notifying = true;
        document.dispatchEvent(new Event("ps4html:layoutchange"));
        notifying = false;
    }

    function schedule() {
        if (scheduled) return;
        scheduled = true;
        requestAnimationFrame(alignAndScaleMath);
    }

    window.addEventListener("resize", schedule);
    window.addEventListener("load", schedule);
    document.addEventListener("DOMContentLoaded", () => {
        schedule();
        const main = document.querySelector("#main-content");
        if (main && typeof ResizeObserver !== "undefined") {
            let previousWidth = main.clientWidth;
            new ResizeObserver(() => {
                if (previousWidth !== main.clientWidth) {
                    previousWidth = main.clientWidth;
                    schedule();
                }
            }).observe(main);
        }
        if (main && typeof MutationObserver !== "undefined") {
            new MutationObserver(schedule).observe(main, {subtree: true, childList: true, characterData: true});
        }
        document.fonts?.addEventListener("loadingdone", schedule);
    });
    document.addEventListener("ps4html:layoutchange", () => { if (!notifying) schedule(); });
    document.addEventListener("toggle", schedule, true);
})();
