(function () {
    function updateDependencyNavigation() {
        const navigation = document.querySelector(".theorem-dependency-navigation");
        if (!navigation) return;
        const proofs = Array.from(document.querySelectorAll(".theorem-proof:not([hidden])"));
        const topBoundary = 32;
        const active = proofs.reduce((current, proof) => (
            proof.getBoundingClientRect().top <= topBoundary ? proof : current
        ), null);
        const anchor = active?.id?.replace(/-en$/, "");
        let matched = false;
        navigation.querySelectorAll(".theorem-dependency-panel").forEach(panel => {
            const visible = panel.dataset.theoremAnchor === anchor;
            panel.hidden = !visible;
            matched ||= visible;
        });
        navigation.hidden = !matched;
    }

    let scheduled = false;
    function scheduleUpdate() {
        if (scheduled) return;
        scheduled = true;
        requestAnimationFrame(() => {
            scheduled = false;
            updateDependencyNavigation();
        });
    }

    window.addEventListener("DOMContentLoaded", updateDependencyNavigation);
    window.addEventListener("scroll", scheduleUpdate, {passive: true});
    window.addEventListener("resize", scheduleUpdate);
    window.addEventListener("hashchange", () => requestAnimationFrame(updateDependencyNavigation));
    document.addEventListener("click", event => {
        if (event.target.closest(".language-menu [data-language]")) {
            requestAnimationFrame(updateDependencyNavigation);
        }
    });
})();
