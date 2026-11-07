(function () {
    "use strict";

    const dataNode = document.getElementById("ps-expression-data");
    if (!dataNode) return;

    let data;
    try { data = JSON.parse(dataNode.textContent || "{}"); } catch (_) { return; }
    const occurrences = data.occurrences || {};
    const entities = data.entities || {};
    const fragmentOccurrences = new Map();
    const occurrenceNodes = new Map();
    const activeOccurrences = new Set();
    let indexedNodes = [];
    const state = { anchor: null, candidates: [], selected: -1, pinned: null, tooltip: null, indicator: null };
    const highlights = document.createElement("div");
    highlights.className = "ps-expression-highlights";
    highlights.setAttribute("aria-hidden", "true");
    document.body.append(highlights);
    let highlightFrame = null;
    let measuredRects = new WeakMap();
    let pointerPosition = null;

    Object.entries(occurrences).forEach(([id, occurrence]) => {
        (occurrence.fragmentIds || []).forEach(fragment => {
            if (!fragmentOccurrences.has(fragment)) fragmentOccurrences.set(fragment, []);
            fragmentOccurrences.get(fragment).push(id);
        });
    });

    function wrappersEnabled() {
        return document.documentElement.dataset.displayWrappers === "on";
    }

    function isWrapper(id) {
        const occurrence = occurrences[id];
        return occurrence && (occurrence.kind === "wrapper" || (occurrence.traits || []).includes("wrapper"));
    }

    function depth(id) {
        let value = 0;
        const seen = new Set();
        let current = id;
        while (occurrences[current] && occurrences[current].parentId && !seen.has(current)) {
            seen.add(current);
            value += 1;
            current = occurrences[current].parentId;
        }
        return value;
    }

    function clearClasses() {
        occurrenceNodes.forEach(nodes => nodes.forEach(node => {
            node.classList.remove("ps-expression-active", "ps-expression-selected", "ps-expression-wrapper",
                "ps-expression-fvar", "ps-expression-bvar", "ps-expression-binder");
            node.querySelectorAll?.("[data-l2t-ref]").forEach(reference => {
                reference.removeAttribute("data-l2t-active");
                reference.classList.remove("ps-expression-active", "ps-expression-selected",
                    "ps-expression-fvar", "ps-expression-bvar", "ps-expression-binder");
            });
        }));
    }

    function visibleRects(node) {
        if (measuredRects.has(node)) return measuredRects.get(node);
        const math = node.closest(".katex")?.getBoundingClientRect();
        const bands = [...node.getClientRects()].filter(rect => rect.width > 0 && rect.height > 0 &&
            (!math || (rect.left >= math.left - 8 && rect.right <= math.right + 8)));
        const groups = bands.map(rect => ({left: rect.left, right: rect.right,
            top: rect.top, bottom: rect.bottom}));
        if (!groups.length) return [];
        const range = document.createRange();
        const walker = document.createTreeWalker(node, NodeFilter.SHOW_ELEMENT | NodeFilter.SHOW_TEXT, {
            acceptNode(part) {
                if (part.nodeType === Node.ELEMENT_NODE && part !== node &&
                        (part.closest(".katex-mathml, .vlist-t.vlist-t2 > .vlist-r + .vlist-r") ||
                         (part instanceof SVGElement && part.closest("svg") !== part) ||
                         part.classList.contains("strut")))
                    return NodeFilter.FILTER_REJECT;
                return NodeFilter.FILTER_ACCEPT;
            },
        });
        for (let part = walker.nextNode(); part; part = walker.nextNode()) {
            let rects;
            if (part.nodeType === Node.TEXT_NODE) {
                if (!part.textContent.trim()) continue;
                range.selectNodeContents(part);
                rects = range.getClientRects();
            } else if (part instanceof SVGElement || !part.firstChild) {
                rects = part.getClientRects();
            } else continue;
            for (const rect of rects) {
                if (!rect.width || !rect.height) continue;
                // KaTeX can expose zero-origin SVG/layout boxes for stretched
                // arrows. They are not painted at (0, 0); never enlarge an
                // expression to a distant descendant's reported rectangle.
                if ((math && (rect.left < math.left - 8 || rect.right > math.right + 8 ||
                        rect.bottom < math.top - 8 || rect.top > math.bottom + 8)) ||
                    !bands.some(band => rect.right >= band.left - 8 &&
                        rect.left <= band.right + 8)) continue;
                // Associate each visible leaf with its closest inline segment;
                // an operator's vlist can extend far beyond that segment's line box.
                const group = groups.reduce((best, candidate) => {
                    const score = item => Math.max(0, item.left - rect.right, rect.left - item.right) +
                        Math.abs((item.top + item.bottom - rect.top - rect.bottom) / 2);
                    return score(candidate) < score(best) ? candidate : best;
                });
                group.left = Math.min(group.left, rect.left);
                group.right = Math.max(group.right, rect.right);
                group.top = Math.min(group.top, rect.top);
                group.bottom = Math.max(group.bottom, rect.bottom);
            }
        }
        measuredRects.set(node, groups);
        return groups;
    }

    function invalidateRects() {
        measuredRects = new WeakMap();
        scheduleHighlights();
        if (!state.pinned && pointerPosition) hoverAt(pointerPosition.x, pointerPosition.y);
    }

    function containsPoint(rect, x, y) {
        return x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;
    }

    function fragmentAt(x, y) {
        const underneath = document.elementFromPoint(x, y);
        if (!underneath || underneath.closest(".ps-expression-tooltip, .ps-template-menu")) return null;
        const root = underneath.closest("[data-ps-render-root]") || underneath.closest(".katex");
        const direct = fragmentTarget(underneath);
        const candidates = root ? [...root.querySelectorAll("[data-ps-expr-fragment]")] :
            indexedNodes.filter(node => {
                const rect = node.getBoundingClientRect();
                return x >= rect.left - 8 && x <= rect.right + 8 &&
                    y >= rect.top - 120 && y <= rect.bottom + 120;
            });
        if (root?.hasAttribute("data-ps-expr-fragment")) candidates.push(root);
        let best = null;
        let bestArea = Infinity;
        for (const candidate of candidates) {
            if (!fragmentOccurrences.has(candidate.dataset.psExprFragment)) continue;
            for (const rect of visibleRects(candidate)) {
                if (!containsPoint(rect, x, y)) continue;
                const area = (rect.right - rect.left) * (rect.bottom - rect.top);
                if (area < bestArea || (area === bestArea && direct === candidate)) {
                    best = candidate;
                    bestArea = area;
                }
            }
        }
        return best || (root ? null : direct);
    }

    function hoverAt(x, y) {
        const anchor = fragmentAt(x, y);
        if (anchor) enter(anchor);
        else if (state.anchor) clearHover();
    }

    function paintHighlights() {
        highlightFrame = null;
        const marked = new Set();
        const boxes = [];
        // Paint each semantic occurrence once. A text template may produce
        // several math/text anchors for the same object; linked occurrences
        // need exactly the same treatment as the hovered occurrence.
        for (const id of activeOccurrences) {
            const occurrence = occurrences[id];
            const style = isWrapper(id) ? "wrapper" : occurrence?.kind === "binder" ? "binder"
                : ["fvar", "bvar"].includes(occurrence?.kind) ? "variable" : "expression";
            const rects = [];
            for (const node of occurrenceNodes.get(id) || []) {
                if (marked.has(node)) continue;
                marked.add(node);
                rects.push(...visibleRects(node));
            }
            for (const rect of mergeHighlightRects(rects)) {
                const box = document.createElement("span");
                box.className = `ps-expression-highlight ps-expression-highlight-${style}`;
                if (state.pinned?.id === id) box.classList.add("is-selected");
                box.style.left = `${rect.left}px`;
                box.style.top = `${rect.top}px`;
                box.style.width = `${rect.right - rect.left}px`;
                box.style.height = `${rect.bottom - rect.top}px`;
                boxes.push(box);
            }
        }
        highlights.replaceChildren(...boxes);
    }

    function mergeHighlightRects(rects) {
        const lines = [];
        for (const rect of [...rects].sort((a, b) => a.top - b.top || a.left - b.left)) {
            const line = lines.find(item => rect.top <= item.bottom + 2 && rect.bottom >= item.top - 2);
            if (line) {
                line.left = Math.min(line.left, rect.left);
                line.right = Math.max(line.right, rect.right);
                line.top = Math.min(line.top, rect.top);
                line.bottom = Math.max(line.bottom, rect.bottom);
            } else lines.push({...rect});
        }
        return lines;
    }

    function scheduleHighlights() {
        if (highlightFrame !== null) cancelAnimationFrame(highlightFrame);
        highlights.replaceChildren();
        highlightFrame = requestAnimationFrame(paintHighlights);
    }

    function addObjectClasses(node, id, active, selected) {
        const occurrence = occurrences[id];
        const kindClass = occurrence?.kind === "fvar" ? "ps-expression-fvar"
            : occurrence?.kind === "bvar" ? "ps-expression-bvar"
            : occurrence?.kind === "binder" ? "ps-expression-binder" : null;
        // Only a variable occurrence may activate its nested legacy marker.
        // A parent expression must never light up its child fvar/bvar.
        const reference = kindClass && (node.matches("[data-l2t-ref]")
            ? node : node.querySelector("[data-l2t-ref]"));
        for (const target of reference && reference !== node ? [node, reference] : [node]) {
            target.classList.toggle("ps-expression-active", active);
            target.classList.toggle("ps-expression-selected", selected);
            if (kindClass) target.classList.add(kindClass);
            if (kindClass && target.hasAttribute("data-l2t-ref")) {
                target.toggleAttribute("data-l2t-active", active);
            }
        }
    }

    function setEntityActive(id, selected) {
        const entityKey = occurrences[id] && occurrences[id].entityKey;
        if (!entityKey) return;
        // Built-in layout families identify switchable styles, not shared
        // objects. Only constants and bound/free variables link occurrences.
        let category;
        try { category = JSON.parse(entityKey)[0]; } catch (_) { return; }
        if (!["constant", "fvar", "bvar"].includes(category)) return;
        Object.entries(occurrences).forEach(([otherId, occurrence]) => {
            if (occurrence.entityKey !== entityKey) return;
            activeOccurrences.add(otherId);
            (occurrenceNodes.get(otherId) || []).forEach(node => {
                node.classList.toggle("ps-expression-wrapper", isWrapper(otherId));
                addObjectClasses(node, otherId, true, selected && otherId === id);
            });
        });
    }

    function updateClasses() {
        clearClasses();
        activeOccurrences.clear();
        const active = state.pinned ? null : state.candidates[state.selected];
        for (const id of new Set([active, state.pinned?.id])) {
            if (!id) continue;
            activeOccurrences.add(id);
            const selected = id === state.pinned?.id;
            (occurrenceNodes.get(id) || []).forEach(node => {
                node.classList.toggle("ps-expression-wrapper", isWrapper(id));
                addObjectClasses(node, id, true, selected);
            });
            setEntityActive(id, selected);
        }
        scheduleHighlights();
    }

    function candidateIds(anchor) {
        const ids = [...(fragmentOccurrences.get(anchor.dataset.psExprFragment) || [])];
        const unique = [...new Set(ids)];
        const filtered = wrappersEnabled() ? unique : unique.filter(id => !isWrapper(id));
        return filtered.sort((a, b) => depth(b) - depth(a));
    }

    function clearHover() {
        state.anchor = null;
        state.candidates = [];
        state.selected = -1;
        state.indicator?.remove();
        state.indicator = null;
        updateClasses();
    }

    function clearPinned() {
        state.pinned = null;
        state.tooltip?.remove();
        state.tooltip = null;
        updateClasses();
    }

    function detailsFor(id) {
        const occurrence = occurrences[id] || {};
        const entity = occurrence.entityKey ? entities[occurrence.entityKey] : null;
        return { category: occurrence.kind, entity, occurrence: occurrence.details || {},
            traits: occurrence.traits || [],
            layer: `${state.pinned.index + 1} / ${state.pinned.candidates.length}` };
    }

    function showTooltip(id) {
        state.tooltip?.remove();
        const tooltip = window.PS4HTMLExpressionTooltip.render(detailsFor(id), data.ui || {}, wrappersEnabled());
        document.body.append(tooltip);
        state.tooltip = tooltip;
        positionOverlay();
    }

    function positionOverlay() {
        if (state.tooltip && state.pinned) {
            const rect = state.pinned.anchor.getBoundingClientRect();
            const width = state.tooltip.offsetWidth;
            const left = Math.min(window.innerWidth - width - 12, Math.max(12, rect.right + 10));
            state.tooltip.style.left = `${left}px`;
            state.tooltip.style.top = `${Math.min(window.innerHeight - state.tooltip.offsetHeight - 12, Math.max(12, rect.top))}px`;
        }
        if (state.indicator && state.anchor) {
            const rect = state.anchor.getBoundingClientRect();
            state.indicator.style.left = `${Math.min(window.innerWidth - 10, rect.right + 4)}px`;
            state.indicator.style.top = `${Math.max(4, rect.top)}px`;
        }
    }

    function updateIndicator() {
        state.indicator?.remove();
        if (!state.anchor || state.candidates.length < 2) return;
        const indicator = document.createElement("div");
        indicator.className = "ps-expression-layer-indicator";
        indicator.style.setProperty("--ps-layer-count", String(state.candidates.length));
        indicator.setAttribute("aria-hidden", "true");
        state.candidates.forEach((id, index) => {
            const dot = document.createElement("i");
            dot.className = "ps-expression-layer-dot";
            dot.classList.toggle("is-current", index === state.selected);
            dot.classList.toggle("is-wrapper", isWrapper(id));
            const occurrence = occurrences[id];
            dot.title = occurrence?.kind || "expression";
            indicator.append(dot);
        });
        document.body.append(indicator);
        state.indicator = indicator;
        positionOverlay();
    }

    function select(index) {
        if (!state.candidates.length) return;
        state.selected = Math.max(0, Math.min(state.candidates.length - 1, index));
        updateClasses();
        updateIndicator();
    }

    function enter(anchor) {
        const candidates = candidateIds(anchor);
        if (!candidates.length) return;
        if (state.anchor === anchor && candidates.join("/") === state.candidates.join("/")) return;
        clearHover();
        state.anchor = anchor;
        state.candidates = candidates;
        // Candidates are deepest-first; default selection skips wrappers.
        const first = candidates.findIndex(id => !isWrapper(id));
        state.selected = first < 0 ? 0 : first;
        select(state.selected);
    }

    function fragmentTarget(value) {
        return value instanceof Element ? value.closest("[data-ps-expr-fragment]") : null;
    }

    function refreshIndex() {
        measuredRects = new WeakMap();
        fragmentOccurrences.clear();
        Object.entries(occurrences).forEach(([id, occurrence]) => {
            (occurrence.fragmentIds || []).forEach(fragment => {
                if (!fragmentOccurrences.has(fragment)) fragmentOccurrences.set(fragment, []);
                fragmentOccurrences.get(fragment).push(id);
            });
        });
        occurrenceNodes.clear();
        indexedNodes = [...document.querySelectorAll("[data-ps-expr-fragment]")].filter(node => !node.closest(".ps-template-menu"));
        indexedNodes.forEach(node => {
            node.classList.remove("ps-expression-switchable");
            delete node.dataset.psEntityKey;
            const fragment = node.dataset.psExprFragment;
            (fragmentOccurrences.get(fragment) || []).forEach(id => {
                if (!occurrenceNodes.has(id)) occurrenceNodes.set(id, []);
                occurrenceNodes.get(id).push(node);
                const entityKey = occurrences[id]?.entityKey;
                if (entityKey) node.dataset.psEntityKey = entityKey;
                if (entityKey && window.PS4HTMLTemplateSwitcher?.hasChoices?.(entityKey, occurrences[id])) {
                    node.classList.add("ps-expression-switchable");
                }
            });
        });
        if (state.pinned) {
            const pinned = state.pinned;
            if (!document.contains(pinned.anchor)) clearPinned();
            else {
                const candidates = candidateIds(pinned.anchor);
                if (!candidates.includes(pinned.id)) clearPinned();
                else state.pinned = { ...pinned, candidates, index: candidates.indexOf(pinned.id) };
            }
        }
        if (state.anchor && !document.contains(state.anchor)) clearHover();
        else if (state.anchor) enter(state.anchor);
        updateClasses();
        if (state.pinned) {
            showTooltip(state.pinned.id);
        }
    }

    window.PS4HTMLExpressionInteractions = {
        getState: () => ({ anchor: state.anchor?.dataset.psExprFragment || null,
            candidates: [...state.candidates], selected: state.selected,
            pinned: state.pinned?.id || null }),
        refresh: refreshIndex,
        resolveTarget(value, x, y) {
            const anchor = Number.isFinite(x) && Number.isFinite(y)
                ? fragmentAt(x, y) : fragmentTarget(value);
            if (!anchor) return null;
            const candidates = candidateIds(anchor);
            const id = state.anchor === anchor && candidates.includes(state.candidates[state.selected])
                ? state.candidates[state.selected] : candidates[0];
            return id ? {anchor, id, occurrence: occurrences[id]} : null;
        },
        replaceFragments(root, mapping) {
            const old = root.querySelectorAll("[data-ps-expr-fragment]");
            const replaced = new Set(Array.from(old, item => item.dataset.psExprFragment));
            Object.values(occurrences).forEach(item => {
                item.fragmentIds = item.fragmentIds.filter(id => !replaced.has(id));
            });
            Object.entries(mapping).forEach(([id, owner]) => {
                if (occurrences[owner] && !occurrences[owner].fragmentIds.includes(id))
                    occurrences[owner].fragmentIds.push(id);
                let parent = occurrences[owner]?.parentId;
                while (parent && (occurrences[parent]?.kind === "wrapper" || occurrences[parent]?.kind === "expression")) {
                    if (!occurrences[parent].fragmentIds.includes(id)) occurrences[parent].fragmentIds.push(id);
                    parent = occurrences[parent].parentId;
                }
            });
            clearPinned();
            clearHover();
        },
    };

    document.addEventListener("pointermove", event => {
        if (!event.isPrimary || event.pointerType === "touch") return;
        pointerPosition = {x: event.clientX, y: event.clientY};
        if (!state.pinned) hoverAt(event.clientX, event.clientY);
    });
    document.addEventListener("pointerleave", () => {
        pointerPosition = null;
        if (!state.pinned) clearHover();
    });

    document.addEventListener("click", event => {
        if (event.target.closest?.(".ps-expression-tooltip")) return;
        if (event.target.closest?.(".display-options, .language-switcher")) return;
        const anchor = fragmentAt(event.clientX, event.clientY) || fragmentTarget(event.target);
        if (!anchor) {
            clearPinned();
            clearHover();
            return;
        }
        if (state.pinned) clearPinned();
        enter(anchor);
        const id = state.candidates[state.selected];
        if (!id) {
            clearPinned();
            return;
        }
        const pinned = { anchor, id, candidates: [...state.candidates], index: state.selected };
        clearHover();
        state.pinned = pinned;
        updateClasses();
        showTooltip(id);
    });

    document.addEventListener("wheel", event => {
        if (event.target.closest?.(".ps-expression-tooltip")) return;
        if (state.pinned) {
            clearPinned();
            clearHover();
            return;
        }
        if (!state.anchor || state.candidates.length < 2 || event.ctrlKey ||
                !fragmentAt(event.clientX, event.clientY)) return;
        // The entire wheel gesture belongs to layer selection, including
        // attempts beyond the first or last layer.
        event.preventDefault();
        const delta = event.deltaY > 0 ? 1 : -1;
        const next = state.selected + delta;
        if (next < 0 || next >= state.candidates.length) return;
        select(next);
    }, { passive: false });

    window.addEventListener("resize", () => { positionOverlay(); invalidateRects(); });
    window.visualViewport?.addEventListener("resize", invalidateRects);
    window.visualViewport?.addEventListener("scroll", invalidateRects);
    document.addEventListener("scroll", invalidateRects, true);
    document.fonts?.addEventListener?.("loadingdone", invalidateRects);
    document.addEventListener("ps4html:layoutchange", () => { refreshIndex(); positionOverlay(); });
    document.addEventListener("ps4html:displaychange", refreshIndex);
    document.addEventListener("ps4html:languagechange", () => {
        if (state.pinned) showTooltip(state.pinned.id);
    });
    window.addEventListener("DOMContentLoaded", () => {
        refreshIndex();
        // Initial script order may run before display-options.js applies its state.
        window.setTimeout(refreshIndex, 0);
    });
})();
