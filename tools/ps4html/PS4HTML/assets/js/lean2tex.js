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
    const entityOccurrences = new Map();
    const activeOccurrences = new Set();
    const styledNodes = new Set();
    const dashboardOf = new WeakMap();
    function inactiveDashboard(node) {
        if (!dashboardOf.has(node)) dashboardOf.set(node, node.closest(".proof-dashboard-reveal"));
        const panel = dashboardOf.get(node);
        return !!panel && !panel.classList.contains("is-dashboard-visible");
    }
    let indexedNodes = [];
    const state = { anchor: null, candidates: [], selected: -1, pinned: null, tooltip: null, indicator: null };
    const highlights = document.createElement("div");
    highlights.className = "ps-expression-highlights";
    highlights.setAttribute("aria-hidden", "true");
    document.body.append(highlights);
    let highlightFrame = null;
    let measuredRects = new WeakMap();
    let rootFragments = new WeakMap();
    let pointerPosition = null;
    let hoverFrame = null;

    function scheduleHover() {
        if (hoverFrame !== null) return;
        hoverFrame = requestAnimationFrame(() => {
            hoverFrame = null;
            if (!state.pinned && pointerPosition) hoverAt(pointerPosition.x, pointerPosition.y);
        });
    }

    Object.entries(occurrences).forEach(([id, occurrence]) => {
        if (occurrence.entityKey) {
            if (!entityOccurrences.has(occurrence.entityKey)) entityOccurrences.set(occurrence.entityKey, []);
            entityOccurrences.get(occurrence.entityKey).push(id);
        }
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
        styledNodes.forEach(node => {
            node.classList.remove("ps-expression-active", "ps-expression-selected", "ps-expression-wrapper",
                "ps-expression-fvar", "ps-expression-bvar", "ps-expression-binder");
            node.querySelectorAll?.("[data-l2t-ref]").forEach(reference => {
                reference.removeAttribute("data-l2t-active");
                reference.classList.remove("ps-expression-active", "ps-expression-selected",
                    "ps-expression-fvar", "ps-expression-bvar", "ps-expression-binder");
            });
        });
        styledNodes.clear();
    }

    function visibleRects(node) {
        if (inactiveDashboard(node)) return [];
        if (measuredRects.has(node)) return measuredRects.get(node);
        const math = node.closest(".katex")?.getBoundingClientRect();
        const bands = [...node.getClientRects()].filter(rect => rect.width > 0 && rect.height > 0 &&
            (!math || (rect.left >= math.left - 8 && rect.right <= math.right + 8)));
        const groups = bands.map(rect => ({left: rect.left, right: rect.right,
            top: rect.top, bottom: rect.bottom}));
        if (!groups.length) {
            measuredRects.set(node, groups);
            return groups;
        }
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
        if (!state.pinned && pointerPosition) scheduleHover();
    }

    let scrollFrame = null;
    function onScroll() {
        if (scrollFrame !== null) return;
        scrollFrame = requestAnimationFrame(() => {
            scrollFrame = null;
            invalidateRects();
        });
    }

    function containsPoint(rect, x, y) {
        return x >= rect.left && x <= rect.right && y >= rect.top && y <= rect.bottom;
    }

    function fragmentAt(x, y) {
        const underneath = document.elementFromPoint(x, y);
        if (!underneath || underneath.closest(".ps-expression-tooltip, .ps-template-menu")) return null;
        if (inactiveDashboard(underneath)) return null;
        const root = underneath.closest("[data-ps-render-root]") || underneath.closest(".katex");
        const direct = fragmentTarget(underneath);
        // Browser hit testing already identifies the local math/render island,
        // including overflowing SVG leaves. Blank space must never scan the page.
        if (!root) return direct;
        if (!rootFragments.has(root)) {
            const nodes = [...root.querySelectorAll("[data-ps-expr-fragment]")];
            if (root.hasAttribute("data-ps-expr-fragment")) nodes.push(root);
            rootFragments.set(root, nodes);
        }
        const candidates = rootFragments.get(root);
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
        // Semantic occurrences select the anchors to highlight, but each
        // rendered fragment owns its own geometry. Never bridge the space
        // between separate anchors, even when they share an occurrence.
        for (const id of activeOccurrences) {
            const occurrence = occurrences[id];
            const style = isWrapper(id) ? "wrapper" : occurrence?.kind === "binder" ? "binder"
                : ["fvar", "bvar"].includes(occurrence?.kind) ? "variable" : "expression";
            for (const node of occurrenceNodes.get(id) || []) {
                if (marked.has(node)) continue;
                marked.add(node);
                for (const rect of visibleRects(node)) {
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
        }
        highlights.replaceChildren(...boxes);
    }

    function scheduleHighlights() {
        if (highlightFrame !== null) return;
        highlightFrame = requestAnimationFrame(paintHighlights);
    }

    function addObjectClasses(node, id, active, selected) {
        styledNodes.add(node);
        const occurrence = occurrences[id];
        const kindClass = occurrence?.kind === "fvar" ? "ps-expression-fvar"
            : occurrence?.kind === "bvar" ? "ps-expression-bvar"
            : occurrence?.kind === "binder" ? "ps-expression-binder" : null;
        // Only a variable occurrence may activate its nested variable marker.
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
        (entityOccurrences.get(entityKey) || []).forEach(otherId => {
            activeOccurrences.add(otherId);
            (occurrenceNodes.get(otherId) || []).forEach(node => {
                if (inactiveDashboard(node)) return;
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
                if (inactiveDashboard(node)) return;
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

    function enter(anchor, refresh = false) {
        if (!refresh && state.anchor === anchor) return;
        const candidates = candidateIds(anchor);
        if (!candidates.length) {
            if (state.anchor) clearHover();
            return;
        }
        if (state.anchor === anchor && candidates.join("/") === state.candidates.join("/")) return;
        state.anchor = anchor;
        state.candidates = candidates;
        // Candidates are deepest-first; default selection skips wrappers.
        const first = candidates.findIndex(id => !isWrapper(id));
        state.selected = first < 0 ? 0 : first;
        select(state.selected);
    }

    function fragmentTarget(value) {
        return value instanceof Element && !inactiveDashboard(value)
            ? value.closest("[data-ps-expr-fragment]") : null;
    }

    function refreshIndex() {
        clearClasses();
        measuredRects = new WeakMap();
        rootFragments = new WeakMap();
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
                if (entityKey && window.PS4HTMLTemplateSwitcher?.hasChoices?.(entityKey, occurrences[id], id)) {
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
        else if (state.anchor) enter(state.anchor, true);
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
        replaceFragments(root, mapping, templateIdentities = {}) {
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
            Object.entries(templateIdentities).forEach(([id, identity]) => {
                if (occurrences[id]) occurrences[id].details.templateIdentity = identity;
            });
            clearPinned();
            clearHover();
        },
    };

    document.addEventListener("pointermove", event => {
        if (!event.isPrimary || event.pointerType === "touch") return;
        pointerPosition = {x: event.clientX, y: event.clientY};
        if (!state.pinned) scheduleHover();
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
    document.addEventListener("scroll", onScroll, true);
    document.fonts?.addEventListener?.("loadingdone", invalidateRects);
    // Geometry changes do not change semantic ownership or template choices.
    document.addEventListener("ps4html:layoutchange", () => { invalidateRects(); positionOverlay(); });
    document.addEventListener("ps4html:dashboardchange", () => {
        if (state.anchor?.closest(".proof-dashboard-reveal:not(.is-dashboard-visible)")) clearHover();
        if (state.pinned?.anchor?.closest(".proof-dashboard-reveal:not(.is-dashboard-visible)")) clearPinned();
        invalidateRects();
    });
    document.addEventListener("transitionend", event => {
        if ((event.propertyName === "grid-template-rows" && event.target.classList.contains("proof-dashboard-reveal")) ||
                (event.propertyName.startsWith("padding") && event.target.classList.contains("proof-step-header"))) {
            invalidateRects();
            positionOverlay();
        }
    });
    document.addEventListener("ps4html:displaychange", refreshIndex);
    document.addEventListener("ps4html:languagechange", refreshIndex);
    window.addEventListener("DOMContentLoaded", () => {
        refreshIndex();
        const main = document.querySelector("#main-content");
        if (main && typeof MutationObserver !== "undefined") {
            new MutationObserver(() => {
                refreshIndex();
                if (pointerPosition) scheduleHover();
            }).observe(main, {subtree: true, childList: true, characterData: true});
        }
        // Initial script order may run before display-options.js applies its state.
        window.setTimeout(refreshIndex, 0);
    });
})();
