(function () {
    "use strict";
    function hideInactive() {
        document.querySelectorAll(".verso-source .hl.lean .token, .verso-source .hl.lean .tactic, .verso-source .hl.lean .has-info").forEach(node => {
            const face = node.closest(".proof-flip-back");
            if (!node.closest("[hidden]") && (!face || face.closest(".is-flipped"))) return;
            node._tippy?.hide();
        });
        for (const node of document.querySelectorAll(".verso-source .hl.lean")) {
            if (node.closest("[hidden]") || (node.closest(".proof-flip-back") && !node.closest(".is-flipped"))) {
                node.querySelectorAll(".binding-hl").forEach(token => token.classList.remove("binding-hl"));
            }
        }
    }
    document.addEventListener("DOMContentLoaded", async () => {
        await window.ProofScriptVersoInit?.();
        hideInactive();
    });
    document.addEventListener("ps4html:languagechange", hideInactive);
    document.addEventListener("ps4html:layoutchange", () => {
        hideInactive();
        document.querySelectorAll(".verso-source .hl.lean .token, .verso-source .hl.lean .tactic").forEach(node => {
            if (node._tippy?.state.isVisible) node._tippy.popperInstance?.update();
        });
    });
    document.addEventListener("click", event => {
        const button = event.target.closest(".verso-copy");
        if (!button) return;
        navigator.clipboard.writeText(button.dataset.versoSource || "");
    });
})();
