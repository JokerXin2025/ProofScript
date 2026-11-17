(function () {
    "use strict";
    // Bindings in a frozen display tree have stable bindId/bindRef identities.
    // Substitute by identity rather than by printed name (or de Bruijn index).
    function reduce(tree) {
        let work = 0, steps = 0;
        const visit = depth => {
            if (++work > 32768 || depth > 256) throw Error("beta reduction work limit exceeded");
        };
        const visible = node => {
            while (["wrapper", "expression"].includes(node.kind)) node = node.children[0];
            return node;
        };
        function substitute(node, binding, value, depth) {
            visit(depth);
            if (node.kind === "bvar" && node.metadata.bindRef === binding) return value;
            if (!node.children.length) return node;
            const children = node.children.map(child => substitute(child, binding, value, depth + 1));
            return children.every((child, index) => child === node.children[index]) ? node : {...node, children};
        }
        function normalize(node, depth) {
            visit(depth);
            const children = node.children.map(child => normalize(child, depth + 1));
            let current = children.every((child, index) => child === node.children[index]) ? node : {...node, children};
            if (current.kind !== "application" || children.length < 2) return current;
            // Application nodes are flattened by the semantic converter. Consume
            // one argument at a time, preserving any remaining application.
            let head = children[0];
            let index = 1;
            while (index < children.length && visible(head).kind === "lambda") {
                if (++steps > 1024) throw Error("beta reduction step limit exceeded");
                const lambda = visible(head);
                head = normalize(substitute(lambda.children[2], lambda.children[0].metadata.bindId,
                    children[index++], depth + 1), depth + 1);
            }
            if (index === 1) return current;
            return index === children.length ? head : {...current, children: [head, ...children.slice(index)]};
        }
        return normalize(tree, 0);
    }
    window.PS4HTMLBetaReduce = {reduce};
})();
