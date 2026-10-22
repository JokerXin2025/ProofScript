document.addEventListener("DOMContentLoaded", function() {
    // Display data is captured explicitly with the variable declaration. Native
    // titles keep the information accessible without interpreting it as HTML.
    function setDeclarationTitle(node) {
        if (!node || !node.dataset.l2tInfo) {
            return;
        }
        try {
            var encoded = node.dataset.l2tInfo.replace(/-/g, "+").replace(/_/g, "/");
            var bytes = Uint8Array.from(atob(encoded), function(character) { return character.charCodeAt(0); });
            node.title = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
        } catch (_) {
            // A malformed presentation attribute must not affect proof content.
        }
    }
    document.querySelectorAll("[data-l2t-info]").forEach(setDeclarationTitle);
    function referenceTarget(value) {
        return value instanceof Element ? value.closest("[data-l2t-ref]") : null;
    }

    function setReferenceActive(target, active) {
        var reference = target.dataset.l2tRef;
        var scope = target.closest(".theorem-proof");
        if (!reference || !scope) {
            return;
        }

        scope.querySelectorAll("[data-l2t-ref]").forEach(function(node) {
            if (node.dataset.l2tRef === reference) {
                node.toggleAttribute("data-l2t-active", active);
            }
        });
    }

    document.addEventListener("pointerover", function(event) {
        var target = referenceTarget(event.target);
        if (!target) {
            return;
        }
        setDeclarationTitle(target);
        var previous = referenceTarget(event.relatedTarget);
        if (previous && previous.dataset.l2tRef === target.dataset.l2tRef) {
            return;
        }
        setReferenceActive(target, true);
    });

    document.addEventListener("pointerout", function(event) {
        var target = referenceTarget(event.target);
        if (!target) {
            return;
        }
        var next = referenceTarget(event.relatedTarget);
        if (next && next.dataset.l2tRef === target.dataset.l2tRef) {
            return;
        }
        setReferenceActive(target, false);
    });
});
