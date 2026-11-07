(function () {
    "use strict";

    // Keep reader-facing classification and the ordered field lists together.
    // Paths only point into the already published interaction record.
    const common = ["expression", "type"];
    const definitions = {
        freeVariable: ["display", "variableType", "variableKind", "variableValue"],
        boundVariable: ["display", "variableType", "index", "binderInfo"],
        binder: ["display", "variableType", "binderInfo", "binderKind", "variableValue"],
        unknownVariable: ["type"],
        universe: ["display", "level"],
        localDefinition: common,
        constant: ["expression", "type", "leanName", "declarationKind", "declarationType", "argumentCount"],
        lambda: ["expression", "type", "binderInfo"],
        implication: common,
        forall: ["expression", "type", "binderInfo"],
        exists: ["expression", "type", "leanName"],
        number: ["literal", "type"],
        string: ["literal", "type"],
        projection: ["expression", "type", "ownerType", "fieldIndex"],
        application: ["expression", "type", "leanName"],
        operator: ["expression", "type", "leanName"],
        relation: ["expression", "type", "leanName"],
        wrapper: ["expression", "type", "leanName"],
        expression: common,
    };

    function classify(data) {
        const kind = data.category;
        const detail = data.occurrence || {};
        if (kind !== "application" && kind !== "wrapper" && kind !== "expression" &&
                detail.headConst === "Exists" &&
                detail.originalExprKind === "app") return "exists";
        if (kind === "forall") return detail.isArrow ? "implication" : "forall";
        if (kind === "literal") return detail.literalKind === "literal.nat" ? "number"
            : detail.literalKind === "literal.str" ? "string" : "expression";
        return ({ fvar: "freeVariable", bvar: "boundVariable", binder: "binder",
            metavariable: "unknownVariable", sort: "universe", let: "localDefinition",
            lambda: "lambda", projection: "projection", wrapper: "wrapper",
            const: "constant", concept: "constant", application: "application", operator: "operator",
            relation: "relation" })[kind] || (detail.headConst && kind !== "unknown" ? "constant" : "expression");
    }

    function universe(level, depth = 0) {
        if (!level || depth > 256) return null;
        switch (level.kind) {
            case "level.zero": return "0";
            case "level.param": return level.name;
            case "level.mvar": return "?";
            case "level.succ": {
                let inner = level;
                let count = 0;
                while (inner?.kind === "level.succ" && count + depth < 256) {
                    count++;
                    inner = inner.level;
                }
                const base = universe(inner, depth + count);
                return base === "0" ? String(count) : base ? `${base} + ${count}` : null;
            }
            case "level.max":
            case "level.imax": {
                const left = universe(level.u, depth + 1);
                const right = universe(level.v, depth + 1);
                return left && right ? `${level.kind.slice(6)}(${left}, ${right})` : null;
            }
            default: return null;
        }
    }

    const fields = {
        display: { label: "display", get: d => d.occurrence.display },
        expression: { label: "expression", get: d => d.occurrence.expressionText },
        type: { label: "type", get: d => d.occurrence.expressionType },
        variableType: { label: "type", get: d => d.occurrence.variableType },
        variableKind: { label: "variableKind", get: d => d.occurrence.variableKind, localized: true },
        variableValue: { label: "value", get: d => d.occurrence.variableValue },
        index: { label: "index", get: d => d.occurrence.index },
        binderInfo: { label: "binderInfo", get: d => d.occurrence.binderInfo, localized: true },
        binderKind: { label: "binderKind", get: d => d.occurrence.binderKind, localized: true },
        level: { label: "level", get: d => universe(d.occurrence.level) },
        leanName: { label: "leanName", get: d => d.occurrence.leanName || d.entity?.leanName || d.occurrence.headConst },
        declarationKind: { label: "declarationKind", get: d => d.entity?.declaration?.kind, localized: true },
        declarationType: { label: "declarationType", get: d => d.entity?.declaration?.type },
        argumentCount: { label: "argumentCount", get: d => d.occurrence.rawArgumentCount },
        literal: { label: "literal", get: d => d.occurrence.value },
        ownerType: { label: "ownerType", get: d => d.occurrence.typeName },
        fieldIndex: { label: "fieldIndex", get: d => d.occurrence.index },
    };

    function render(data, translations, technical) {
        const language = document.documentElement.dataset.language || document.documentElement.dataset.defaultLanguage || "zh";
        const messages = translations[language] || translations.zh || {};
        const tr = (key) => messages[key] || key;
        const tooltip = document.createElement("aside");
        tooltip.className = "ps-expression-tooltip";
        tooltip.setAttribute("role", "tooltip");
        const category = classify(data);
        const title = document.createElement("strong");
        title.textContent = tr(`title.${category}`);
        tooltip.append(title);
        const list = document.createElement("ul");
        list.className = "ps-expression-fields";
        let visible = 0;
        for (const key of definitions[category]) {
            const field = fields[key];
            let value = field.get(data);
            if (value === null || value === undefined || value === "") continue;
            if (field.localized) value = messages[`value.${value}`] || value;
            const item = document.createElement("li");
            const label = document.createElement("span");
            label.className = "ps-expression-field-label";
            label.textContent = tr(`field.${field.label}`);
            const content = document.createElement("span");
            content.className = "ps-expression-field-value";
            content.textContent = String(value);
            item.append(label, content);
            list.append(item);
            visible++;
        }
        if (!visible) {
            const item = document.createElement("li");
            item.className = "ps-expression-empty";
            item.textContent = tr("empty");
            list.append(item);
        }
        tooltip.append(list);
        if (technical) {
            const raw = document.createElement("section");
            raw.className = "ps-expression-raw";
            const heading = document.createElement("span");
            heading.className = "ps-expression-raw-heading";
            heading.textContent = tr("field.rawData");
            const pre = document.createElement("pre");
            pre.textContent = JSON.stringify(data, null, 2);
            raw.append(heading, pre);
            tooltip.append(raw);
        }
        return tooltip;
    }

    window.PS4HTMLExpressionTooltip = { render };
})();
