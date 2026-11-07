(function () {
    "use strict";
    const selector = /(?<!@)(@+)(\d+)(?!\d)|#(\d+)/g;
    const forallPhrases = {
        zh: "${body}对一切 $${binder}\\in ${type}$ 成立",
        en: "${body} holds for every $${binder}\\in ${type}$",
    };
    const visible = node => {
        while ((node.kind === "wrapper" || node.kind === "expression") && node.children.length) node = node.children[0];
        return node;
    };
    const builtinKey = name => JSON.stringify(["builtin", name]).replace(",", ", ");
    const literalAtom = (value, style, fragment) => `[[PS4HTML-LITERAL-${style}-${Array.from(value)
        .map(char => char.codePointAt(0).toString(16).padStart(6, "0")).join("")}-${fragment}]]`;
    const escapeText = value => value.replace(/[\\{}_\%#&$]/g, char => ({
        "\\": "\\textbackslash{}", "{": "\\{", "}": "\\}", "_": "\\_",
        "%": "\\%", "#": "\\#", "&": "\\&", "$": "\\$",
    })[char]);
    const textToFormula = text => `\\text{${text.replace(/\[\[PS4HTML-(START|END)-(p\d+)\]\]/g,
        (_, side, id) => side === "START" ? `\\htmlData{ps-expr-fragment=${id}}{` : "}")}}`;
    function switchMode(tex, source, target) {
        if (source === target) return tex;
        if (source === "formula") return ` $${tex}$ `;
        const parts = tex.split("$");
        return parts.length === 1 ? textToFormula(tex) : parts.map((part, i) =>
            part ? (i % 2 ? part : textToFormula(part)) : "").join("");
    }
    function childTex(child, parent, position) {
        const tex = switchMode(child.tex, child.mode, parent.mode);
        if ((parent.isolatedArguments || []).includes(position) || child.mode !== parent.mode || parent.mode === "text") return tex;
        let parens = child.precedence < parent.precedence;
        if (child.precedence === parent.precedence && parent.fixity === "infix" && child.fixity === "infix") {
            parens = parent.associativity === "none" || (parent.associativity === "left" && position > 0)
                || (parent.associativity === "right" && position === 0);
        }
        return parens ? `\\left(${tex}\\right)` : tex;
    }
    function render(tree, catalog, selections, language, parentMode, fragments) {
        let visits = 0, length = 0;
        const literalFragments = new Map();
        const result = (tex, mode = "formula", fixity = "atom", precedence = 100, associativity = "none") => {
            length += tex.length;
            if (length > 8388608 || tex.length > 1048576) throw Error("render limit exceeded");
            return {tex, mode, fixity, precedence, associativity};
        };
        function renderNode(node, depth = 0) {
            if (++visits > 32768 || depth > 256) throw Error("render depth exceeded");
            if (node.kind === "wrapper" || node.kind === "expression") return renderNode(node.children[0], depth + 1);
            let output;
            const builtinName = node.kind === "forall" ? (node.metadata.isArrow ? "forall.arrow" : "forall.dependent")
                : node.kind === "sort" ? node.metadata.builtinKey
                : node.kind === "literal" && ["literal.nat", "literal.str"].includes(node.metadata.literalKind)
                    ? node.metadata.literalKind
                : node.kind === "metavariable" ? "metavariable"
                : ["lambda", "let", "application"].includes(node.kind) ? node.kind : null;
            const builtinCatalog = builtinName && catalog[builtinKey(builtinName)];
            const builtinStyle = builtinCatalog && builtinCatalog.templates.some(template =>
                template.label === selections[builtinKey(builtinName)] && template.available !== false)
                ? selections[builtinKey(builtinName)] : builtinCatalog?.default;
            const key = JSON.stringify(["constant", node.metadata.leanName || node.name]).replace(",", ", ");
            const macro = (node.kind === "const" ||
                ["concept", "operator", "relation"].includes(node.kind) ||
                (node.kind === "projection" && node.metadata.headConst))
                ? catalog[key] : null;
            if (macro) {
                if (macro.kind === "operator" || macro.kind === "relation") {
                    const arity = macro.fixity === "infix" ? 2 : 1;
                    if (node.metadata.originalExprKind === "const" || node.children.length !== arity) {
                        output = result(`\\operatorname{${node.name.split(".").pop()}}`);
                    } else {
                        const layout = {mode: "formula", fixity: macro.fixity,
                            precedence: macro.precedence, associativity: macro.associativity};
                        const children = node.children.map((child, index) =>
                            childTex(renderNode(child, depth + 1), layout, index));
                        const symbol = /^\\[A-Za-z]+$/.test(macro.symbol) ? `${macro.symbol} ` : macro.symbol;
                        const tex = macro.fixity === "prefix" ? symbol + children[0]
                            : macro.fixity === "postfix" ? children[0] + symbol
                            : children[0] + symbol + children[1];
                        output = result(tex, "formula", macro.fixity, macro.precedence, macro.associativity);
                    }
                } else {
                    const label = selections[key] || macro.default;
                    const matching = (candidate, wanted = label, lang = language) => candidate.label === wanted
                        && (candidate.lang === lang || candidate.label === "formula")
                        && (!candidate.binders || Object.entries(candidate.binders).every(([index, count]) => {
                            let child = node.children[Number(index)];
                            if (!child) return false;
                            child = visible(child);
                            for (let i = 0; i < count; i++) {
                                if (child.kind !== "lambda") return false;
                                child = visible(child.children[2]);
                            }
                            return true;
                        }));
                    const template = macro.templates.find(item => matching(item))
                        || macro.templates.find(item => matching(item, macro.default))
                        || macro.templates.find(item => matching(item, "formula"))
                        || macro.templates.find(item => matching(item, macro.default, "en"));
                    if (!template) throw Error(`no template for ${key}`);
                    if (node.metadata.originalExprKind === "const" && /#\d+|@\d+/.test(template.content)) {
                        output = result(`\\operatorname{${node.name.split(".").pop()}}`);
                    } else {
                        // Binder selectors expose a lambda's binder/body, not the
                        // lambda itself. Only render whole arguments used by #n.
                        const children = new Map();
                        const tex = template.content.replace(selector, (match, ats, atIndex, index, offset) => {
                            const i = Number(atIndex || index);
                            if (!node.children[i]) throw Error(`missing argument ${i}`);
                            // A text template may already be inside $...$ at this
                            // selector; adding another math delimiter breaks the run.
                            const layout = template.mode === "text" && template.content.slice(0, offset).split("$").length % 2 === 0
                                ? {...template, mode: "formula"} : template;
                            if (!ats) {
                                if (!children.has(i)) children.set(i, renderNode(node.children[i], depth + 1));
                                const child = children.get(i);
                                return node.children[i].metadata.htmlEligible && parentMode === "text"
                                    ? child.tex : childTex(child, layout, i);
                            }
                            const count = template.binders?.[i];
                            let child = visible(node.children[i]);
                            for (let j = 1; j < ats.length; j++) child = visible(child.children[2]);
                            if (child.kind === "lambda") child = child.children[0];
                            if (ats.length > count + 1) throw Error("invalid binder selector");
                            return childTex(renderNode(child, depth + 1), layout, i);
                        });
                        output = result(tex, template.mode, template.fixity, template.precedence, template.associativity);
                    }
                }
            } else if (["fvar", "bvar", "binder"].includes(node.kind)) {
                let tex = node.generated ? `\\textcolor{gray}{${node.name}}` : node.name;
                if (node.metadata.reference) tex = `\\htmlData{l2t-kind=${node.kind},l2t-ref=${node.metadata.reference}${node.generated ? ",l2t-generated=true" : ""}}{${tex}}`;
                output = result(tex);
            } else if (node.kind === "const") {
                output = result(`\\operatorname{${node.name.split(".").pop()}}`);
            } else if (node.kind === "literal") {
                output = node.metadata.literalKind === "literal.str" && node.metadata.htmlEligible && parentMode === "text"
                    ? result(literalAtom(node.name, builtinStyle || "plain", fragments
                        ? (literalFragments.has(node.occurrence) ? literalFragments.get(node.occurrence)
                            : (literalFragments.set(node.occurrence, fragments(node.occurrence)), literalFragments.get(node.occurrence)))
                        : "p0"), "text")
                    : result(node.metadata.literalKind === "literal.nat" ?
                    (node.metadata.styles?.[builtinStyle] || node.metadata.styles?.decimal || node.name) :
                        node.metadata.literalKind === "literal.str" ? escapeText(node.name) : node.name,
                    node.metadata.literalKind === "literal.str" ? "text" : "formula");
            } else if (node.kind === "sort") {
                output = result(node.metadata.styles?.[builtinStyle] || node.metadata.styles?.prop ||
                    node.metadata.styles?.compact || (node.name === "Prop" ? "\\mathbb{P}" : "\\operatorname{Type}"));
            } else if (node.kind === "metavariable") {
                output = result(builtinStyle === "unknown" ? "\\operatorname{未知}" : "\\textcolor{gray}{?}");
            } else if (node.kind === "application") {
                const items = node.children.map(child => renderNode(child, depth + 1));
                if (!items.length) {
                    output = result("\\operatorname{app}\\left(\\right)", "formula", "application", 90);
                } else {
                    const parent = {mode: "formula", fixity: "application", precedence: 90, associativity: "left"};
                    const head = childTex(items[0], parent, 0);
                    output = builtinStyle === "juxtaposed"
                        ? result([head, ...items.slice(1).map(item => {
                            const arg = childTex(item, parent, 1);
                            return item.mode === "formula" && item.fixity === "application" && item.precedence === 90
                                ? `\\left(${arg}\\right)` : arg;
                        })].join("\\,"), "formula", "application", 90, "left")
                        : result(`${head}\\left(${items.slice(1).map(item => switchMode(item.tex, item.mode, "formula")).join(",")}\\right)`, "formula", "application", 90, "left");
                }
            } else if (["lambda", "forall", "let"].includes(node.kind)) {
                const arrow = node.kind === "forall" && !!node.metadata.isArrow;
                const chain = [node];
                let terminal = node.children[2];
                while (true) {
                    const inner = visible(terminal);
                    if (inner.kind !== node.kind || (node.kind === "forall" && !!inner.metadata.isArrow !== arrow)) break;
                    if (inner !== terminal) break;
                    if (chain.length >= 256 - depth) throw Error("render depth exceeded");
                    chain.push(inner);
                    terminal = inner.children[2];
                }
                const entries = chain.map(member => ({
                    binder: node.kind === "forall" && arrow ? null : renderNode(member.children[0], depth + 1),
                    type: node.kind === "let" ? null : renderNode(member.children[1], depth + 1),
                    value: node.kind === "let" ? renderNode(member.children[1], depth + 1) : null,
                }));
                let body = renderNode(terminal, depth + chain.length);
                if (node.kind === "let" && builtinStyle === "where") {
                    const clauses = entries.map(({binder, value}, i) => {
                        const clause = `${binder.tex}=${switchMode(value.tex, value.mode, "formula")}`;
                        return i && fragments
                            ? `\\htmlData{ps-expr-fragment=${fragments(chain[i].occurrence)}}{${clause}}` : clause;
                    }).reverse();
                    output = result(`${switchMode(body.tex, body.mode, "formula")},\\ \\text{${language === "zh" ? "其中" : "where"}}\\ ${clauses.join(",\\ ")}`,
                        "formula", "binder", 20);
                } else if (node.kind === "let" && builtinStyle === "stacked") {
                    const declarations = entries.map(({binder, value}) =>
                        `\\operatorname{let}\\ ${binder.tex} := ${switchMode(value.tex, value.mode, "formula")}`);
                    if (fragments) for (let i = chain.length - 1; i > 0; i--) {
                        declarations[i] = `\\htmlData{ps-expr-fragment=${fragments(chain[i].occurrence)}}{${declarations[i]}}`;
                    }
                    if (fragments) {
                        declarations[0] = `\\htmlData{ps-expr-fragment=${fragments(node.occurrence)}}{${declarations[0]}}`;
                        for (let i = 1; i < declarations.length; i++)
                            declarations[i] = `\\htmlData{ps-expr-fragment=${fragments(node.occurrence)}}{${declarations[i]}}`;
                        body.tex = `\\htmlData{ps-expr-fragment=${fragments(node.occurrence)}}{\\operatorname{in}\\ ${switchMode(body.tex, body.mode, "formula")}}`;
                    } else body.tex = `\\operatorname{in}\\ ${switchMode(body.tex, body.mode, "formula")}`;
                    output = result(`\\begin{aligned}${declarations.join("\\\\")}\\\\${body.tex}\\end{aligned}`,
                        "formula", "binder", 20);
                } else {
                    for (let i = chain.length - 1; i >= 0; i--) {
                        const {binder, type, value} = entries[i];
                        if (node.kind === "lambda") {
                            const name = builtinStyle === "typed" ? `(${binder.tex}:${switchMode(type.tex, type.mode, "formula")})` : binder.tex;
                            body = result(builtinStyle === "fun"
                                ? `\\operatorname{fun}\\ ${name} \\Rightarrow ${switchMode(body.tex, body.mode, "formula")}`
                                : `${name} \\mapsto ${switchMode(body.tex, body.mode, "formula")}`, "formula", "binder", 20);
                        } else if (node.kind === "let") {
                            body = result(`\\operatorname{let}\\ ${binder.tex} := ${switchMode(value.tex, value.mode, "formula")}\\ \\operatorname{in}\\ ${switchMode(body.tex, body.mode, "formula")}`, "formula", "binder", 20);
                        } else if (arrow) {
                            const parent = {mode: "formula", fixity: "infix", precedence: 30, associativity: "right"};
                            body = result(`${childTex(type, parent, 0)}${builtinStyle === "arrow" ? "\\to" : "\\implies"} ${childTex(body, parent, 1)}`, "formula", "infix", 30, "right");
                        } else if (builtinStyle === "symbol") {
                            body = result(`\\forall ${binder.tex}\\in ${switchMode(type.tex, type.mode, "formula")},\\ ${switchMode(body.tex, body.mode, "formula")}`, "formula", "binder", 20);
                        } else {
                            const phrase = forallPhrases[language] || forallPhrases.en;
                            body = result(phrase.replace(/\$\{(body|binder|type)\}/g, (_, key) => ({
                                body: switchMode(body.tex, body.mode, "text"), binder: binder.tex, type: type.tex,
                            })[key]), "text", "binder", 20);
                        }
                        if (i && fragments) {
                            const id = fragments(chain[i].occurrence);
                            body.tex = body.mode === "formula" ? `\\htmlData{ps-expr-fragment=${id}}{${body.tex}}`
                                : body.tex.split("$").map((part, j) => j % 2
                                    ? `$\\htmlData{ps-expr-fragment=${fragments(chain[i].occurrence)}}{${part}}$`
                                    : part ? `[[PS4HTML-START-${id}]]${part}[[PS4HTML-END-${id}]]` : "").join("");
                        }
                    }
                    output = body;
                }
            } else if (node.kind === "exists") {
                const type = renderNode(node.children[0], depth + 1).tex;
                const predicate = visible(node.children[1]);
                if (predicate.kind === "lambda") {
                    const binder = renderNode(predicate.children[0], depth + 1).tex;
                    const body = renderNode(predicate.children[2], depth + 1);
                    const phrase = "there exists ${binder} in ${type} such that ${body}";
                    output = result(phrase.replace(/\$\{(body|binder|type)\}/g, (_, key) => ({
                        body: switchMode(body.tex, body.mode, "text"), binder, type,
                    })[key]), "text", "binder", 20);
                } else output = result(`\\exists\\ ${renderNode(predicate, depth + 1).tex}`, "formula", "binder", 20);
            } else if (node.kind === "projection") {
                const source = renderNode(node.children[0], depth + 1);
                const tex = source.precedence < 90 ? `\\left(${source.tex}\\right)` : source.tex;
                output = result(`${tex}.\\operatorname{${node.name}}`, "formula", "postfix", 90);
            } else {
                throw Error(`unsupported dynamic node ${node.kind}`);
            }
            if (fragments && !output.tex.includes("\\begin{aligned}") &&
                !(node.kind === "literal" && node.metadata.htmlEligible && parentMode === "text") &&
                !(node === tree && node.metadata.mixedRoot && parentMode === "text")) {
                const id = fragments(node.occurrence);
                if (output.mode === "formula") output.tex = `\\htmlData{ps-expr-fragment=${id}}{${output.tex}}`;
                else output.tex = output.tex.split("$").map((part, i) => i % 2
                    ? `$\\htmlData{ps-expr-fragment=${fragments(node.occurrence)}}{${part}}$`
                    : part ? `[[PS4HTML-START-${id}]]${part}[[PS4HTML-END-${id}]]` : "").join("");
            }
            return output;
        }
        const rendered = renderNode(tree);
        if (rendered.tex.includes("[[PS4HTML-LITERAL-")) {
            const marker = /\[\[PS4HTML-LITERAL-(?:plain|strong|code)-[0-9a-f]*-p\d+\]\]/g;
            let offset = 0, match;
            const parts = [];
            while ((match = marker.exec(rendered.tex))) {
                if (match.index > offset) {
                    const part = rendered.tex.slice(offset, match.index);
                    parts.push(`$${fragments && tree.metadata.mixedRoot ?
                        `\\htmlData{ps-expr-fragment=${fragments(tree.occurrence)}}{${part}}` : part}$`);
                }
                parts.push(match[0]);
                offset = marker.lastIndex;
            }
            if (offset < rendered.tex.length) {
                const part = rendered.tex.slice(offset);
                parts.push(`$${fragments && tree.metadata.mixedRoot ?
                    `\\htmlData{ps-expr-fragment=${fragments(tree.occurrence)}}{${part}}` : part}$`);
            }
            const output = parts.join("");
            if (output.length > 1048576) throw Error("render limit exceeded");
            return output;
        }
        return switchMode(rendered.tex, rendered.mode, parentMode);
    }
    window.PS4HTMLRenderTree = {render};
})();
