(function () {
    "use strict";
    const dataNode = document.getElementById("ps-expression-data");
    if (!dataNode) return;
    let data;
    try { data = JSON.parse(dataNode.textContent); } catch (_) { return; }
    const roots = data.renderRoots || {};
    const selections = Object.create(null);
    const navigation = window.PS4HTMLNavigationState;
    let menu = null;
    let press = null;
    let suppressClick = false;
    let counter = 0;
    for (const occurrence of Object.values(data.occurrences || {})) {
        for (const fragment of occurrence.fragmentIds || []) {
            counter = Math.max(counter, Number(fragment.slice(1)) || 0);
        }
    }
    const language = () => document.documentElement.dataset.language || document.documentElement.dataset.defaultLanguage || "en";
    const literalKey = JSON.stringify(["builtin", "literal.str"]).replace(",", ", ");
    function literalEligible(key, occurrence, root, node) {
        if (key !== literalKey) return true;
        return !!node?.metadata?.htmlEligible && root?.parentMode === "text";
    }
    // Render catalogs are immutable. Index once instead of scanning every root
    // for every expression each time interaction styles are refreshed.
    const catalogsByKey = new Map();
    for (const root of Object.values(roots)) {
        for (const [key, catalog] of Object.entries(root.catalog)) {
            if (!catalogsByKey.has(key)) catalogsByKey.set(key, []);
            catalogsByKey.get(key).push(catalog);
        }
    }
    const catalogsFor = key => catalogsByKey.get(key) || [];
    const locations = new Map();
    const occurrenceIds = new WeakMap();
    for (const root of Object.values(roots)) {
        const pending = [root.tree];
        while (pending.length) {
            const node = pending.pop();
            locations.set(node.occurrence, {root, node});
            const occurrence = data.occurrences[node.occurrence];
            if (occurrence) occurrenceIds.set(occurrence, node.occurrence);
            pending.push(...node.children);
        }
    }
    const choicesByLanguage = new Map();
    const eligible = (catalog, node, lang) => window.PS4HTMLRenderTree.availableLabels(catalog, node, lang);
    const currentSelections = (root, choices = selections) => ({...root.initialSelections, ...choices});
    const visible = node => {
        while (["wrapper", "expression"].includes(node.kind)) node = node.children[0];
        return node;
    };
    const requested = (root, node, choices, key) => choices[key]
        ?? (node === visible(root.tree) ? node.metadata.requestedTemplate : null);
    const tr = (key, fallback) => data.ui?.[language()]?.[key] || data.ui?.en?.[key] || fallback;
    const builtinLabels = {"$relation": "relation", "$prefix": "prefix", "$infix": "infix",
        "$infixl": "infixl", "$infixr": "infixr", "$postfix": "postfix"};
    const labelName = label => Object.hasOwn(builtinLabels, label)
        ? tr(`template.${builtinLabels[label]}`, builtinLabels[label]) : label;
    function replaceSelections(next) {
        for (const key of Object.keys(selections)) delete selections[key];
        Object.assign(selections, next);
    }
    function supported(key, label, lang) {
        const catalogs = catalogsFor(key);
        // Keep selections used by another page; only reject labels that this
        // page's catalog actually knows to be unavailable.
        if (!catalogs.length) return true;
        return catalogs.some(catalog => eligible(catalog, null, lang).includes(label));
    }
    function prune(lang) {
        const removed = [];
        for (const [key, label] of Object.entries(selections)) {
            if (!supported(key, label, lang)) {
                delete selections[key];
                removed.push(key);
            }
        }
        return removed;
    }
    function close() { menu?.remove(); menu = null; }
    function hasChoices(key, occurrence, id = occurrenceIds.get(occurrence)) {
        if (["const", "theorem", "wrapper", "expression"].includes(occurrence?.kind)) return false;
        if (key === literalKey && !occurrence?.details?.htmlEligible) return false;
        const location = locations.get(id);
        const catalog = location?.root.catalog[key];
        if (!catalog) return false;
        const lang = language();
        if (!choicesByLanguage.has(lang)) choicesByLanguage.set(lang, new WeakMap());
        const choices = choicesByLanguage.get(lang);
        if (!choices.has(location.node)) choices.set(location.node, eligible(catalog, location.node, lang).length > 1);
        return choices.get(location.node);
    }
    function chainHead(root, target) {
        const path = [];
        function trace(current) {
            if (current === target) return true;
            for (const [index, child] of current.children.entries()) {
                if (trace(child)) { path.unshift({node: current, index}); return true; }
            }
            return false;
        }
        trace(root);
        for (const {node: parent, index} of path.reverse()) {
            if (index !== 2 || parent.kind !== target.kind ||
                    (parent.kind === "forall" && !!parent.metadata.isArrow !== !!target.metadata.isArrow)) break;
            target = parent;
        }
        return target;
    }
    function effectiveTarget(anchor, id) {
        const rootElement = anchor.closest("[data-ps-render-root]");
        const root = roots[rootElement?.dataset.psRenderRoot];
        if (!root) return {rootElement, root};
        const location = locations.get(id);
        const node = location?.root === root ? location.node : null;
        return {rootElement, root, node,
            previewNode: node && ["lambda", "let", "forall"].includes(node.kind) ? chainHead(root.tree, node) : node};
    }
    function render(root, choices, preview = false, subtree = root.tree) {
        const fragments = Object.create(null);
        const parentMode = preview && subtree !== root.tree ? "text" : root.parentMode;
        const tree = document.documentElement.dataset.displayBetaReduce === "on"
            ? window.PS4HTMLBetaReduce.reduce(subtree) : subtree;
        const tex = window.PS4HTMLRenderTree.render(tree, root.catalog, currentSelections(root, choices), root.language,
            parentMode, preview ? null : owner => {
                const id = `p${++counter}`;
                fragments[id] = owner;
                return id;
            }, root.names);
        return {tex, fragments, parentMode};
    }
    function materialize(tex, fragments, parentMode) {
        const container = document.createElement("span");
        const used = new Set();
        const appendText = (chunk, parent) => {
            const marker = /\[\[PS4HTML-(START|END)-(p\d+)\]\]|\[\[PS4HTML-LITERAL-(plain|strong|code)-([0-9a-f]*)-(p\d+)\]\]/g;
            const stack = [parent];
            let previous = 0, match;
            while ((match = marker.exec(chunk))) {
                stack[stack.length - 1].append(document.createTextNode(chunk.slice(previous, match.index)));
                if (match[1] === "START") {
                    const span = document.createElement("span");
                    span.dataset.psExprFragment = match[2];
                    stack[stack.length - 1].append(span);
                    stack.push(span);
                } else if (match[1] === "END") {
                    if (stack.length > 1) stack.pop();
                } else {
                    const value = match[4].match(/.{6}/g)?.map(part => String.fromCodePoint(parseInt(part, 16))).join("") || "";
                    const element = document.createElement({plain: "span", strong: "strong", code: "code"}[match[3]]);
                    element.textContent = value;
                    if (fragments) {
                        let fragment = match[5];
                        if (used.has(fragment)) {
                            const next = `p${++counter}`;
                            fragments[next] = fragments[fragment];
                            fragment = next;
                        }
                        used.add(fragment);
                        element.dataset.psExprFragment = fragment;
                    }
                    stack[stack.length - 1].append(element);
                }
                previous = marker.lastIndex;
            }
            stack[stack.length - 1].append(document.createTextNode(chunk.slice(previous)));
        };
        const parts = parentMode === "formula" && !tex.includes("[[PS4HTML-LITERAL-") ? ["", tex, ""] : tex.split("$");
        for (const [index, chunk] of parts.entries()) {
            if (index % 2) {
                const math = document.createElement("span");
                katex.render(chunk, math, {throwOnError: false, trust: context => context.command === "\\htmlData"});
                container.append(math);
            } else if (chunk) {
                const text = document.createElement("span");
                appendText(chunk, text);
                container.append(text);
            }
        }
        if (fragments) {
            const visible = new Set();
            container.querySelectorAll("[data-ps-expr-fragment]").forEach(node => {
                if (fragments[node.dataset.psExprFragment]) visible.add(node.dataset.psExprFragment);
                else node.removeAttribute("data-ps-expr-fragment");
            });
            for (const id of Object.keys(fragments)) if (!visible.has(id)) delete fragments[id];
        }
        return container;
    }
    function updateIdentities(root) {
        const choices = currentSelections(root);
        const identities = Object.create(null);
        const pending = [root.tree];
        while (pending.length) {
            const node = pending.pop();
            const occurrence = data.occurrences[node.occurrence];
            const key = occurrence?.entityKey;
            const catalog = root.catalog[key];
            if (catalog && catalog.kind !== "builtin" && node.metadata.headConst &&
                    ["concept", "relation", "operator"].includes(node.kind)) {
                const template = window.PS4HTMLRenderTree.selectTemplate(catalog, requested(root, node, choices, key), node, root.language);
                occurrence.details.templateIdentity = template ? {label: template.label, lang: template.lang} : null;
                identities[node.occurrence] = occurrence.details.templateIdentity;
            }
            pending.push(...node.children);
        }
        return identities;
    }
    function refresh(keys) {
        const changed = new Set(keys);
        if (!changed.size) return;
        for (const [rootId, root] of Object.entries(roots)) {
            if (!root.dependencies.some(key => changed.has(key))) continue;
            const element = document.querySelector(`[data-ps-render-root="${rootId}"]`);
            if (!element) continue;
            try {
                const output = render(root, selections);
                const replacement = materialize(output.tex, output.fragments, root.parentMode);
                window.PS4HTMLExpressionInteractions?.replaceFragments(element, output.fragments, updateIdentities(root));
                element.replaceChildren(...replacement.childNodes);
            } catch (error) {
                console.error("PS4HTML template rendering failed", error);
            }
        }
        document.dispatchEvent(new Event("ps4html:layoutchange"));
    }
    function refreshAll() {
        for (const [rootId, root] of Object.entries(roots)) {
            const element = document.querySelector(`[data-ps-render-root="${rootId}"]`);
            if (!element) continue;
            try {
                const output = render(root, selections);
                const replacement = materialize(output.tex, output.fragments, root.parentMode);
                window.PS4HTMLExpressionInteractions?.replaceFragments(element, output.fragments, updateIdentities(root));
                element.replaceChildren(...replacement.childNodes);
            } catch (error) {
                console.error("PS4HTML beta rendering failed", error);
            }
        }
        document.dispatchEvent(new Event("ps4html:layoutchange"));
    }
    function restore(write = false) {
        const previous = {...selections};
        replaceSelections(navigation?.read() || {});
        const removed = prune(language());
        refresh(new Set([...Object.keys(previous), ...Object.keys(selections)]));
        if (write && removed.length) navigation?.save(selections);
        else navigation?.carryToLinks(selections);
    }
    function open(target, x, y) {
        const key = target.occurrence?.entityKey;
        if (!key || !["constant", "builtin"].includes(JSON.parse(key)[0])) return false;
        const {rootElement, root, node, previewNode} = effectiveTarget(target.anchor, target.id);
        const catalog = root?.catalog[key];
        if (!catalog) return false;
        if (["const", "theorem", "wrapper", "expression"].includes(target.occurrence.kind)) return false;
        if (!literalEligible(key, target.occurrence, root, node)) return false;
        const choices = eligible(catalog, node, language());
        if (choices.length < 2) return false;
        if (!previewNode) return false;
        close();
        menu = document.createElement("aside");
        menu.className = "display-options-menu ps-template-menu";
        menu.setAttribute("role", "menu");
        menu.setAttribute("aria-label", tr("template.menu", "Choose template"));
        const state = currentSelections(root);
        const chosen = requested(root, node, state, key);
        const selected = catalog.kind === "builtin" ? (choices.includes(chosen) ? chosen : catalog.default)
            : window.PS4HTMLRenderTree.selectTemplate(catalog, chosen, node, root.language)?.label;
        for (const label of choices) {
            const button = document.createElement("button");
            button.type = "button";
            button.className = "display-option";
            button.setAttribute("role", "menuitemradio");
            button.setAttribute("aria-checked", label === selected ? "true" : "false");
            button.setAttribute("aria-label", labelName(label));
            button.dataset.templateLabel = label;
            button.classList.toggle("is-enabled", button.getAttribute("aria-checked") === "true");
            const mark = document.createElement("span");
            mark.className = "display-option-mark";
            mark.setAttribute("aria-hidden", "true");
            button.append(mark);
            const content = document.createElement("span");
            content.className = "ps-template-choice";
            const name = document.createElement("span");
            name.className = "ps-template-label";
            name.textContent = labelName(label);
            content.append(name);
            try {
                const state = {...selections, [key]: label};
                const output = render(root, state, true, previewNode);
                content.append(materialize(output.tex, null, output.parentMode));
            } catch (error) {
                button.disabled = true;
                button.title = tr("template.unavailable", "This template cannot be displayed here");
            }
            button.append(content);
            button.addEventListener("click", event => {
                event.stopPropagation();
                if (label === catalog.default && !Object.values(roots).some(root =>
                    (root.initialSelections?.[key] && root.initialSelections[key] !== label) ||
                    (data.occurrences[visible(root.tree).occurrence]?.entityKey === key &&
                        visible(root.tree).metadata.requestedTemplate && visible(root.tree).metadata.requestedTemplate !== label)))
                    delete selections[key];
                else selections[key] = label;
                close();
                refresh([key]);
                navigation?.save(selections);
            });
            menu.append(button);
        }
        document.body.append(menu);
        menu.style.left = `${Math.max(12, Math.min(x, window.innerWidth - menu.offsetWidth - 12))}px`;
        menu.style.top = `${Math.max(12, Math.min(y, window.innerHeight - menu.offsetHeight - 12))}px`;
        return true;
    }
    function cancelPress() {
        if (press) clearTimeout(press.timer);
        press = null;
    }
    function resolvePressTarget(element, x, y) {
        // A newly opened menu can cover the expression before pointerup fires.
        // Hit-test through it so the release still refers to the underlying object.
        if (menu) menu.style.pointerEvents = "none";
        try {
            return window.PS4HTMLExpressionInteractions?.resolveTarget(element, x, y);
        } finally {
            if (menu) menu.style.pointerEvents = "";
        }
    }
    document.addEventListener("pointerdown", event => {
        cancelPress();
        if (!event.isPrimary || event.button !== 0) return;
        const target = window.PS4HTMLExpressionInteractions?.resolveTarget(event.target, event.clientX, event.clientY);
        if (!target || !target.anchor.classList.contains("ps-expression-switchable")) return;
        const pending = {id: event.pointerId, target, x: event.clientX, y: event.clientY,
            ready: false, opened: false, timer: null};
        pending.timer = setTimeout(() => {
            if (press !== pending || !document.contains(target.anchor)) return;
            pending.ready = true;
            const landing = resolvePressTarget(target.anchor, pending.x, pending.y);
            if (landing?.id === target.id && landing.anchor.classList.contains("ps-expression-switchable")) {
                pending.opened = open(landing, pending.x + 12, pending.y + 14);
            }
        }, 1000);
        press = pending;
    });
    document.addEventListener("pointermove", event => {
        if (press?.id === event.pointerId) {
            press.x = event.clientX;
            press.y = event.clientY;
        }
    });
    document.addEventListener("pointerup", event => {
        if (press?.id !== event.pointerId) return;
        const pending = press;
        cancelPress();
        if (!pending.ready || !document.contains(pending.target.anchor)) return;
        const landing = resolvePressTarget(event.target, event.clientX, event.clientY);
        if (landing?.id !== pending.target.id ||
                !landing.anchor.classList.contains("ps-expression-switchable")) {
            if (pending.opened) close();
            return;
        }
        if (pending.opened || open(landing, event.clientX + 12, event.clientY + 14)) {
            // The release click may be retargeted after the menu appears
            // (especially on touch devices). Consume it wherever it lands.
            suppressClick = true;
            setTimeout(() => { suppressClick = false; }, 700);
        }
    });
    document.addEventListener("pointercancel", event => { if (press?.id === event.pointerId) cancelPress(); });
    document.addEventListener("scroll", cancelPress, true);
    document.addEventListener("click", event => {
        if (!suppressClick) return;
        suppressClick = false;
        event.preventDefault();
        event.stopImmediatePropagation();
    }, true);
    document.addEventListener("click", event => { if (!event.target.closest(".ps-template-menu")) close(); });
    document.addEventListener("keydown", event => {
        if (event.key === "Escape") { cancelPress(); close(); }
    });
    document.addEventListener("ps4html:languagechange", () => {
        cancelPress();
        const removed = prune(language());
        refresh(removed);
        if (removed.length) navigation?.save(selections);
        close();
    });
    let betaEnabled = false;
    function syncBeta() {
        const enabled = document.documentElement.dataset.displayBetaReduce === "on";
        if (enabled === betaEnabled) return;
        betaEnabled = enabled;
        close();
        refreshAll();
    }
    document.addEventListener("ps4html:displaychange", syncBeta);
    document.addEventListener("DOMContentLoaded", () => { restore(true); setTimeout(syncBeta, 0); });
    window.addEventListener("popstate", () => { cancelPress(); restore(); close(); setTimeout(syncBeta, 0); });
    window.PS4HTMLTemplateSwitcher = {selections, close, hasChoices};
})();
