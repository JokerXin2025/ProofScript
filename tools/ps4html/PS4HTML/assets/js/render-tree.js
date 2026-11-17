(function () {
    "use strict";
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
    const displayKinds = new Set(["concept", "relation", "operator"]);
    const languages = language => [...new Set([language, null, "en"])];
    const catalogIndexes = new WeakMap();
    const templateRequirements = new WeakMap();
    function binderRequirements(instructions) {
        const requirements = new Map();
        function visit(items) {
            for (const item of items) {
                if (item.kind === "mode_switch") visit(item.instructions);
                else if (item.kind === "binder" || item.kind === "body") {
                    if (!Number.isInteger(item.index) || item.index < 0 || !Number.isInteger(item.depth)
                            || item.depth < (item.kind === "binder" ? 1 : 0))
                        throw Error("invalid frozen binder selector");
                    if (item.depth > 0)
                        requirements.set(item.index, Math.max(requirements.get(item.index) || 0, item.depth));
                }
            }
        }
        visit(instructions);
        return requirements;
    }
    function templateIndex(catalog) {
        if (!catalogIndexes.has(catalog)) {
            if (!Number.isInteger(catalog.arity) || catalog.arity < 0) throw Error("invalid frozen arity");
            const index = new Map();
            for (const template of catalog.templates) {
                if (!Array.isArray(template.instructions) || !Array.isArray(template.argumentIndices)
                        || !Number.isInteger(template.precedence) || template.precedence < 0 || template.precedence > 100
                          || !["text", "formula"].includes(template.mode)) throw Error("invalid frozen template");
                templateRequirements.set(template, binderRequirements(template.instructions));
                const key = JSON.stringify([template.label, template.lang]);
                if (index.has(key)) throw Error("duplicate frozen template identity");
                index.set(key, template);
            }
            catalogIndexes.set(catalog, index);
        }
        return catalogIndexes.get(catalog);
    }
    function guardsMatch(template, node) {
        return [...templateRequirements.get(template)].every(([index, count]) => {
            let child = node?.children[template.argumentIndices[index]];
            for (let i = 0; i < count; i++) {
                if (!child) return false;
                child = visible(child);
                if (child.kind !== "lambda" || child.children.length !== 3) return false;
                child = child.children[2];
            }
            return true;
        });
    }
    function selectTemplate(catalog, requested, node, language) {
        if (node.children.length !== catalog.arity) return null;
        const index = templateIndex(catalog);
        const labels = new Set([requested, catalog.default, ...catalog.templates.map(item => item.label)]);
        for (const label of labels) {
            if (label == null) continue;
            for (const lang of languages(language)) {
                const template = index.get(JSON.stringify([label, lang]));
                if (template && guardsMatch(template, node)) return template;
            }
        }
        return null;
    }
    function availableLabels(catalog, node, language) {
        const candidates = languages(language);
        if (catalog.kind !== "builtin") {
            templateIndex(catalog);
            if (node && node.children.length !== catalog.arity) return [];
        }
        return [...new Set(catalog.templates.filter(template => template.available !== false
            && candidates.includes(template.lang ?? null)
            && (catalog.kind === "builtin" || !node || guardsMatch(template, node))).map(template => template.label))];
    }
    function childTex(child, parent, position) {
        let parens = child.precedence < parent.precedence;
        if (child.precedence === parent.precedence) {
            const same = parent.identity != null && child.identity === parent.identity
                && ["infix", "application"].includes(parent.fixity) && child.fixity === parent.fixity;
            parens = !(same && ((parent.associativity === "left" && position === 0)
                || (parent.associativity === "right" && position > 0)));
        }
        if (!parens) return switchMode(child.tex, child.mode, parent.mode);
        if (child.mode === "formula") return switchMode(`\\left(${child.tex}\\right)`, child.mode, parent.mode);
        const tex = switchMode(child.tex, child.mode, parent.mode);
        return parent.mode === "formula" ? `\\left(${tex}\\right)` : `(${tex})`;
    }
    function render(tree, catalog, selections, language, parentMode, fragments, names = {}) {
        let visits = 0, length = 0;
        const literalFragments = new Map();
        const fragmentOwners = new Map();
        const fragmentFor = owner => {
            const fragment = fragments(owner);
            fragmentOwners.set(fragment, owner);
            return fragment;
        };
        const rootNode = visible(tree);
        const mixedRoot = rootNode.metadata.mixedRoot && parentMode === "text";
        const checkLength = size => { if (size > 1048576) throw Error("render output limit exceeded"); };
        const visit = () => { if (++visits > 32768) throw Error("render work limit exceeded"); };
        const result = (tex, mode = "formula", fixity = "atom", precedence = 100, associativity = "none", identity = null) => {
            length += tex.length;
            if (length > 8388608) throw Error("render work limit exceeded");
            checkLength(tex.length);
            return {tex, mode, fixity, precedence, associativity, identity};
        };
        function renderApplication(items, style) {
            const identity = JSON.stringify(["builtin:application", style, null]);
            const parent = {mode: "formula", fixity: "application", precedence: 90, associativity: "left", identity};
            if (!items.length) return result("\\operatorname{app}\\left(\\right)", "formula", "application", 90, "left", identity);
            const head = childTex(items[0], parent, 0);
            const args = items.slice(1).map(item => style === "juxtaposed"
                ? childTex(item, parent, 1) : switchMode(item.tex, item.mode, "formula"));
            checkLength(head.length + args.reduce((sum, arg) => sum + arg.length + 2, 0));
            return result(style === "juxtaposed" ? [head, ...args].join("\\,")
                : `${head}\\left(${args.join(",")}\\right)`, "formula", "application", 90, "left", identity);
        }
        function renderNode(node, depth = 0) {
            visit();
            if (depth >= 256) throw Error("render depth exceeded");
            if (node.kind === "wrapper" || node.kind === "expression") return renderNode(node.children[0], depth + 1);
            let output;
            const builtinName = node.kind === "forall" ? (node.metadata.isArrow ? "forall.arrow" : "forall.dependent")
                : node.kind === "sort" ? node.metadata.builtinKey
                : node.kind === "literal" && ["literal.nat", "literal.str"].includes(node.metadata.literalKind)
                    ? node.metadata.literalKind
                : node.kind === "metavariable" ? "metavariable"
                : ["lambda", "let", "application"].includes(node.kind) ? node.kind : null;
            const builtinCatalog = builtinName && catalog[builtinKey(builtinName)];
            const requestedStyle = selections[builtinKey(builtinName)]
                ?? (node === rootNode ? node.metadata.requestedTemplate : null);
            const builtinStyle = builtinCatalog && builtinCatalog.templates.some(template =>
                template.label === requestedStyle && template.available !== false)
                ? requestedStyle : builtinCatalog?.default;
            const key = JSON.stringify(["constant", node.metadata.leanName || node.name]).replace(",", ", ");
            const macro = displayKinds.has(node.kind) && node.metadata.headConst ? catalog[key] : null;
            if (["const", "theorem"].includes(node.kind)) {
                const original = node.metadata.leanName || node.name;
                const category = node.kind === "theorem" ? "theorem" : "decl";
                const name = names[category]?.[original] || original;
                output = result(`\\operatorname{${escapeText(name)}}`);
            } else if (macro) {
                const template = selectTemplate(macro, selections[key]
                    ?? (node === rootNode ? node.metadata.requestedTemplate : null), node, language);
                if (!template) {
                    const original = node.metadata.leanName || node.name;
                    const head = result(`\\operatorname{${escapeText(names.decl?.[original] || original)}}`);
                    output = node.children.length ? renderApplication([head, ...node.children.map(child => renderNode(child, depth + 1))],
                        selections[builtinKey("application")] || catalog[builtinKey("application")]?.default || "call") : head;
                } else {
                    const identity = JSON.stringify([node.metadata.leanName || node.name, template.label, template.lang]);
                    const layout = {mode: template.mode, precedence: template.precedence,
                         fixity: ["$infix", "$infixl", "$infixr"].includes(template.label) ? "infix" : "custom",
                         associativity: template.label === "$infixl" ? "left" : template.label === "$infixr" ? "right" : "none", identity};
                    const children = new Map();
                    let position = 0;
                    function renderInstructions(instructions, mode, allowSwitch = true) {
                      const parts = [];
                      let size = 0;
                      for (const instruction of instructions) {
                        visit();
                        let value;
                        if (instruction.kind === "literal") value = instruction.content;
                        else if (instruction.kind === "mode_switch" && allowSwitch) {
                            if (instruction.mode !== (mode === "text" ? "formula" : "text")
                                || !Array.isArray(instruction.instructions) || !instruction.instructions.length)
                                throw Error("invalid mode switch");
                            value = switchMode(renderInstructions(instruction.instructions, instruction.mode, false),
                                instruction.mode, mode);
                        }
                        else if (["argument", "binder", "body"].includes(instruction.kind)) {
                            if (instruction.mode !== mode || typeof instruction.max_precedence !== "boolean")
                                throw Error("invalid insertion mode or precedence flag");
                            let child = node.children[template.argumentIndices[instruction.index]];
                            if (!child) throw Error("missing native argument");
                            if (instruction.kind === "binder" || instruction.kind === "body") {
                                if (!Number.isInteger(instruction.depth) || instruction.depth < (instruction.kind === "binder" ? 1 : 0))
                                    throw Error("invalid frozen binder selector");
                                for (let i = 0; i < instruction.depth - (instruction.kind === "binder" ? 1 : 0); i++)
                                    child = visible(child).children[2];
                                if (instruction.kind === "binder") child = visible(child).children[0];
                            }
                            if (!children.has(child)) children.set(child, renderNode(child, depth + 1));
                            const rendered = children.get(child);
                            // HTML atoms are split out at the page boundary;
                            // no TeX group may cross the atom's boundary.
                            value = child.metadata.htmlEligible && parentMode === "text" ? rendered.tex
                                : instruction.max_precedence
                                    ? switchMode(rendered.tex, rendered.mode, instruction.mode)
                                    : childTex(rendered, {...layout, mode: instruction.mode}, position);
                            position++;
                        } else throw Error("invalid frozen instruction");
                        size += value.length;
                        checkLength(size);
                        parts.push(value);
                      }
                      return parts.join("");
                    }
                    output = result(renderInstructions(template.instructions, template.mode), template.mode, layout.fixity, template.precedence,
                        layout.associativity, identity);
                }
            } else if (["fvar", "bvar", "binder"].includes(node.kind)) {
                let tex = node.generated ? `\\textcolor{gray}{${node.name}}` : node.name;
                if (node.metadata.reference) tex = `\\htmlData{l2t-kind=${node.kind},l2t-ref=${node.metadata.reference}${node.generated ? ",l2t-generated=true" : ""}}{${tex}}`;
                output = result(tex);
            } else if (node.kind === "literal") {
                output = node.metadata.literalKind === "literal.str" && node.metadata.htmlEligible && parentMode === "text"
                    ? result(literalAtom(node.name, builtinStyle || "plain", fragments
                        ? (literalFragments.has(node.occurrence) ? literalFragments.get(node.occurrence)
                            : (literalFragments.set(node.occurrence, fragmentFor(node.occurrence)), literalFragments.get(node.occurrence)))
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
                output = renderApplication(node.children.map(child => renderNode(child, depth + 1)), builtinStyle);
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
                            ? `\\htmlData{ps-expr-fragment=${fragmentFor(chain[i].occurrence)}}{${clause}}` : clause;
                    }).reverse();
                    output = result(`${switchMode(body.tex, body.mode, "formula")},\\ \\text{${language === "zh" ? "其中" : "where"}}\\ ${clauses.join(",\\ ")}`,
                        "formula", "binder", 20);
                } else if (node.kind === "let" && builtinStyle === "stacked") {
                    const declarations = entries.map(({binder, value}) =>
                        `\\operatorname{let}\\ ${binder.tex} := ${switchMode(value.tex, value.mode, "formula")}`);
                    if (fragments) for (let i = chain.length - 1; i > 0; i--) {
                        declarations[i] = `\\htmlData{ps-expr-fragment=${fragmentFor(chain[i].occurrence)}}{${declarations[i]}}`;
                    }
                    if (fragments) {
                        declarations[0] = `\\htmlData{ps-expr-fragment=${fragmentFor(node.occurrence)}}{${declarations[0]}}`;
                        for (let i = 1; i < declarations.length; i++)
                            declarations[i] = `\\htmlData{ps-expr-fragment=${fragmentFor(node.occurrence)}}{${declarations[i]}}`;
                        body.tex = `\\htmlData{ps-expr-fragment=${fragmentFor(node.occurrence)}}{\\operatorname{in}\\ ${switchMode(body.tex, body.mode, "formula")}}`;
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
                            const parent = {mode: "formula", fixity: "infix", precedence: 30, associativity: "right",
                                identity: JSON.stringify(["builtin:forall.arrow", builtinStyle, null])};
                            body = result(`${childTex(type, parent, 0)}${builtinStyle === "arrow" ? "\\to" : "\\implies"} ${childTex(body, parent, 1)}`, "formula", "infix", 30, "right", parent.identity);
                        } else if (builtinStyle === "symbol") {
                            body = result(`\\forall ${binder.tex}\\in ${switchMode(type.tex, type.mode, "formula")},\\ ${switchMode(body.tex, body.mode, "formula")}`, "formula", "binder", 20);
                        } else {
                            const phrase = forallPhrases[language] || forallPhrases.en;
                            body = result(phrase.replace(/\$\{(body|binder|type)\}/g, (_, key) => ({
                                body: switchMode(body.tex, body.mode, "text"), binder: binder.tex, type: type.tex,
                            })[key]), "text", "binder", 20);
                        }
                        if (i && fragments) {
                            const id = fragmentFor(chain[i].occurrence);
                            body.tex = body.mode === "formula" ? `\\htmlData{ps-expr-fragment=${id}}{${body.tex}}`
                                : body.tex.split("$").map((part, j) => j % 2
                                    ? `$\\htmlData{ps-expr-fragment=${fragmentFor(chain[i].occurrence)}}{${part}}$`
                                    : part ? `[[PS4HTML-START-${id}]]${part}[[PS4HTML-END-${id}]]` : "").join("");
                        }
                    }
                    output = body;
                }
            } else if (node.kind === "projection") {
                const source = renderNode(node.children[0], depth + 1);
                const tex = childTex(source, {mode: "formula", precedence: 90, fixity: "postfix"}, 0);
                output = result(`${tex}.\\operatorname{${escapeText(node.name)}}`, "formula", "postfix", 90);
            } else {
                throw Error(`unsupported dynamic node ${node.kind}`);
            }
            if (fragments && !output.tex.includes("\\begin{aligned}") &&
                !(node.kind === "literal" && node.metadata.htmlEligible && parentMode === "text") &&
                !(node === rootNode && mixedRoot)) {
                const id = fragmentFor(node.occurrence);
                if (output.mode === "formula") output.tex = `\\htmlData{ps-expr-fragment=${id}}{${output.tex}}`;
                else output.tex = output.tex.split("$").map((part, i) => i % 2
                    ? `$\\htmlData{ps-expr-fragment=${fragmentFor(node.occurrence)}}{${part}}$`
                    : part ? `[[PS4HTML-START-${id}]]${part}[[PS4HTML-END-${id}]]` : "").join("");
            }
            return output;
        }
        function finish(tex) {
            if (fragments) {
                const seen = new Set(), stack = [];
                const marker = /(ps-expr-fragment=)(p\d+)|\[\[PS4HTML-(START|END)-(p\d+)\]\]|\[\[PS4HTML-LITERAL-(plain|strong|code)-([0-9a-f]*)-(p\d+)\]\]/g;
                tex = tex.replace(marker, (match, prefix, math, side, text, style, encoded, literal) => {
                    const original = math || text || literal;
                    if (side === "END") {
                        if (stack.at(-1)?.[0] === original) return `[[PS4HTML-END-${stack.pop()[1]}]]`;
                        return match;
                    }
                    const current = seen.has(original) && fragmentOwners.has(original)
                        ? fragmentFor(fragmentOwners.get(original)) : original;
                    seen.add(original);
                    if (side === "START") { stack.push([original, current]); return `[[PS4HTML-START-${current}]]`; }
                    return literal ? `[[PS4HTML-LITERAL-${style}-${encoded}-${current}]]` : `${prefix}${current}`;
                });
            }
            checkLength(tex.length);
            return tex;
        }
        const rendered = renderNode(tree);
        if (rendered.tex.includes("[[PS4HTML-LITERAL-")) {
            const marker = /\[\[PS4HTML-LITERAL-(?:plain|strong|code)-[0-9a-f]*-p\d+\]\]/g;
            let offset = 0, match;
            const parts = [];
            while ((match = marker.exec(rendered.tex))) {
                if (match.index > offset) {
                    const part = rendered.tex.slice(offset, match.index);
                    parts.push(`$${fragments && mixedRoot ?
                        `\\htmlData{ps-expr-fragment=${fragmentFor(rootNode.occurrence)}}{${part}}` : part}$`);
                }
                parts.push(match[0]);
                offset = marker.lastIndex;
            }
            if (offset < rendered.tex.length) {
                const part = rendered.tex.slice(offset);
                parts.push(`$${fragments && mixedRoot ?
                    `\\htmlData{ps-expr-fragment=${fragmentFor(rootNode.occurrence)}}{${part}}` : part}$`);
            }
            const output = parts.join("");
            if (output.length > 1048576) throw Error("render limit exceeded");
            return finish(output);
        }
        return finish(switchMode(rendered.tex, rendered.mode, parentMode));
    }
    window.PS4HTMLRenderTree = {render, selectTemplate, availableLabels};
})();
