document.addEventListener("DOMContentLoaded", function() {
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
