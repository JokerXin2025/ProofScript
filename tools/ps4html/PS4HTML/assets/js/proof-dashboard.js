(function () {
    "use strict";

    function setOpen(header, open) {
        const step = header.parentElement;
        const panel = step.querySelector(":scope > .proof-dashboard-reveal");
        if (!panel) return;
        step.classList.toggle("is-dashboard-open", open);
        panel.classList.toggle("is-dashboard-visible", open);
        header.setAttribute("aria-expanded", String(open));
        panel.setAttribute("aria-hidden", String(!open));
        panel.inert = !open;
    }

    function toggle(header) {
        const open = header.getAttribute("aria-expanded") !== "true";
        setOpen(header, open);
        document.dispatchEvent(new Event("ps4html:dashboardchange"));
        // Languages render separate panels for the same proof. Carry the
        // step's state across those panels without persisting it on refresh.
        const theorem = header.closest(".theorem-proof[data-theorem-id]");
        if (!theorem) return;
        const steps = [...theorem.querySelectorAll(".proof-step.has-dashboard")];
        const index = steps.indexOf(header.parentElement);
        if (index < 0) return;
        for (const other of document.querySelectorAll(".theorem-proof[data-theorem-id]")) {
            if (other === theorem || other.dataset.theoremId !== theorem.dataset.theoremId) continue;
            const peer = other.querySelectorAll(".proof-step.has-dashboard")[index];
            const peerHeader = peer?.querySelector(":scope > .proof-step-header");
            if (peerHeader) setOpen(peerHeader, open);
        }
    }

    document.addEventListener("click", event => {
        if (!(event.target instanceof Element)) return;
        const step = event.target.closest(".proof-step.has-dashboard");
        if (!step) return;
        const header = step.querySelector(":scope > .proof-step-header");
        if (!header || !header.contains(event.target) && event.target !== step) return;
        const interactive = event.target.closest("a, button, input, select, textarea, [role='button'], [data-ps-expr-fragment], .katex, .ps-template-menu");
        if (interactive && interactive !== header) return;
        toggle(header);
    });

    document.addEventListener("keydown", event => {
        if (event.key !== "Enter" && event.key !== " ") return;
        if (!(event.target instanceof Element)) return;
        const header = event.target.closest?.(".proof-step.has-dashboard > .proof-step-header");
        if (header !== event.target) return;
        event.preventDefault();
        toggle(header);
    });
})();
