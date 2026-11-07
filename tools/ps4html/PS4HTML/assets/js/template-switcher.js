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
    const language = () => document.documentElement.dataset.language || document.documentElement.dataset.defaultLanguage || "zh";
    const literalKey = JSON.stringify(["builtin", "literal.str"]).replace(",", ", ");
    function literalEligible(key, occurrence, root, node) {
        if (key !== literalKey) return true;
        return !!node?.metadata?.htmlEligible && root?.parentMode === "text";
    }
    const catalogsFor = key => Object.values(roots).filter(root => root.catalog[key]).map(root => root.catalog[key]);
    const eligible = (catalog, lang) => catalog.templates.filter(template =>
        template.available !== false && (!template.lang || template.lang === lang));
    function replaceSelections(next) {
        for (const key of Object.keys(selections)) delete selections[key];
        Object.assign(selections, next);
    }
    function supported(key, label, lang) {
        const catalogs = catalogsFor(key);
        // Keep selections used by another page; only reject labels that this
        // page's catalog actually knows to be unavailable.
        if (!catalogs.length) return true;
        return catalogs.some(catalog => catalog.templates.some(template =>
            template.available !== false && template.label === label
            && (template.lang === lang || template.lang == null)));
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
    function hasChoices(key, occurrence) {
        if (key === literalKey && !occurrence?.details?.htmlEligible) return false;
        const catalog = catalogsFor(key);
        if (!catalog.length) return false;
        return catalog.some(entry => new Set(eligible(entry, language()).map(template => template.label)).size > 1);
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
        function locate(node) {
            if (node.occurrence === id) return node;
            for (const child of node.children) {
                const found = locate(child);
                if (found) return found;
            }
            return null;
        }
        const node = locate(root.tree);
        return {rootElement, root, node,
            previewNode: node && ["lambda", "let", "forall"].includes(node.kind) ? chainHead(root.tree, node) : node};
    }
    function render(root, choices, preview = false, subtree = root.tree) {
        const fragments = Object.create(null);
        const parentMode = preview && subtree !== root.tree ? "text" : root.parentMode;
        const tex = window.PS4HTMLRenderTree.render(subtree, root.catalog, choices, root.language,
            parentMode, preview ? null : owner => {
                const id = `p${++counter}`;
                fragments[id] = owner;
                return id;
            });
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
        if (fragments) container.querySelectorAll("[data-ps-expr-fragment]").forEach(node => {
            if (!fragments[node.dataset.psExprFragment]) node.removeAttribute("data-ps-expr-fragment");
        });
        return container;
    }
    function update(key) {
        for (const [rootId, root] of Object.entries(roots)) {
            if (!root.dependencies.includes(key)) continue;
            const element = document.querySelector(`[data-ps-render-root="${rootId}"]`);
            if (!element) continue;
            try {
                const output = render(root, selections);
                const replacement = materialize(output.tex, output.fragments, root.parentMode);
                window.PS4HTMLExpressionInteractions?.replaceFragments(element, output.fragments);
                element.replaceChildren(...replacement.childNodes);
            } catch (error) {
                console.error("PS4HTML template rendering failed", error);
            }
        }
        document.dispatchEvent(new Event("ps4html:layoutchange"));
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
                window.PS4HTMLExpressionInteractions?.replaceFragments(element, output.fragments);
                element.replaceChildren(...replacement.childNodes);
            } catch (error) {
                console.error("PS4HTML template rendering failed", error);
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
        if (target.occurrence.kind === "wrapper" || target.occurrence.kind === "expression") return false;
        if (!literalEligible(key, target.occurrence, root, node)) return false;
        const choices = [...new Set(eligible(catalog, language())
            .map(template => template.label))];
        if (choices.length < 2) return false;
        if (!previewNode) return false;
        close();
        menu = document.createElement("aside");
        menu.className = "display-options-menu ps-template-menu";
        menu.setAttribute("role", "menu");
        menu.setAttribute("aria-label", "切换模版");
        for (const label of choices) {
            const button = document.createElement("button");
            button.type = "button";
            button.className = "display-option";
            button.setAttribute("role", "menuitemradio");
            button.setAttribute("aria-checked", label === (selections[key] || catalog.default) ? "true" : "false");
            button.setAttribute("aria-label", label);
            button.dataset.templateLabel = label;
            button.classList.toggle("is-enabled", button.getAttribute("aria-checked") === "true");
            const mark = document.createElement("span");
            mark.className = "display-option-mark";
            mark.setAttribute("aria-hidden", "true");
            button.append(mark);
            const content = document.createElement("span");
            content.className = "ps-template-choice";
            try {
                const state = {...selections, [key]: label};
                const output = render(root, state, true, previewNode);
                content.append(materialize(output.tex, null, output.parentMode));
            } catch (error) {
                button.disabled = true;
                button.title = `此处不支持该模版：${error.message}`;
            }
            button.append(content);
            button.addEventListener("click", event => {
                event.stopPropagation();
                if (label === catalog.default) delete selections[key];
                else selections[key] = label;
                close();
                update(key);
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
    document.addEventListener("DOMContentLoaded", () => restore(true));
    window.addEventListener("popstate", () => { cancelPress(); restore(); close(); });
    window.PS4HTMLTemplateSwitcher = {selections, close, hasChoices};
})();
