# Extending parameter recording

`import ProofScript.Script.Recording` exposes values, codecs, builtin instances, plans and
the capture/commit engine. `ProofScript.Script.Record` adds step and strategy adapters;
`ProofScript.Script.Config` adds declaration commands. `import ProofScript` includes all three.
Parser normalization and declaration-time schema evaluation are separate from the runtime API.

Run the complete [Labels example](../examples/recording/Labels.lean) from the repository root:

```sh
lake env lean examples/recording/Labels.lean
```

Define a named syntax category and provide a `ProofScript.Recording.RecordCategory` instance. Its schema describes the stable output; capture interprets the category's parser node:

```lean
declare_syntax_cat labelValue
syntax ident : labelValue

instance : ProofScript.Recording.RecordCategory `labelValue where
  schema := .name
  capture value := ProofScript.Recording.identifierName ⟨value.raw[0]⟩

script_macro recordLabels
  (params := [labels(timing := once, field := "items", failure := required)])
  "record_labels" "[" labels:sepBy(labelValue, ",") "]" => `(tactic| skip)
```

The category node wraps its ident child, hence `raw[0]`. Parse each category according to its own syntax layout. `RecordParam` composes arrays and optionals automatically; parentheses, `+`, `*`, `?`, `sepBy`, `sepBy1` and supported layout wrappers need no generator change. Outputs are `[]`, `["alpha"]` and `["alpha", "beta"]`; an absent optional is null. Instances must be visible when the script declaration generates its recorder.

Parameter configuration supports timing (once/before/after/both), codec (default/expression/typeOf/name/"syntax"), context (main/continuation/branch name), failure (bestEffort/required) and field (output name). Explicit codecs currently apply to single parameters; containers compose category instances. intro/clear are after/before shorthand. Both emits `<field>_before` and `<field>_after`. A strategy's continuation index identifies its continuation goal after execution; preceding goals are proof branches.

For step-specific results, declare a `script_recorder` with `fields := #[...]` and use a recording plan:

```lean
script_recorder recordLabels
  (fields := #[{ name := "items", schema := .array .name, nullable := false }])
  "record_labels" "[" labels:sepBy(labelValue, ",") "]" => do
    recordStep [] (parameters := { parameters := #[
      ProofScript.Recording.param (.array (.category `labelValue))
        "items" .once (labels.getElems.map fun value => ⟨value.raw⟩) .required
    ] })
```

Each OutputField declares name, schema and nullable. Nullable permits failed best-effort capture; optional permits absent input. Schemas include expression/string/number/boolean/name/syntax/literal/array/optional/object/union/json. Compose nested expressions using expression snapshots and RecordedValue object/array constructors so the engine can merge expression tables and collect references. Open json is for component metadata and resources. External IO is outside the Lean-state rollback boundary.

Automatic recorders export their contracts directly. An external handwritten recorder may omit fields and export an opaque null contract. Every migrated builtin supplies a contract. Plan output names must match the declared fields.

`recordStep` accepts inline fields, a `parameters` plan and an optional `execute` action;
`recordStrategy` accepts the same fields/plan plus branch labels and a continuation index.
Capture actions belong to each invocation. Persistent registrations store declaration names,
parser signatures and field contracts, so imports and editor rollback retain no invocation closures.
Handwritten recorder signatures are checked before generating declarations: normalized signatures
compare category/container extraction, and unsupported parsers compare structural syntax. Parameters
whose source name starts with `_` may be renamed by the recorder.

Capture already elaborated expressions with `snapshotExpression`. Use `commitValue` to merge their
local tables into the proof export; `RecordedValue.toJson` only inspects the snapshot's local references.
The legacy ParamRaw and preTerms/postTerms APIs have been removed; all captures use a plan.

```lean
script_info recordLabels {
  template := [{ lang := "en", tag := "Labels", content := "${items}" }]
}
```

Configuration takes effect in proof modules importing the declaration module; local updates are exported for later importers. Slots are checked against emitted names and schemas, including paths such as `${rules.0.expression}`. Structured values render recursively with HTML-escaped keys and text; expression references use Lean2TeX. Null displays `—`. Out-of-range indices or absent object fields fail, so a fixed-index template requires enough elements.

Proof/rendering exports use `0.1.0`; old singleton arrays are adapted only at the old-version consumer boundary. num emits a JSON number, while a numeral parsed as term remains an expression. Complex builtin codecs and explicit config semantics are described in [JSON Schemas](JSON-Schemas.md). Page, computation and Lean2TeX protocols remain `0.0.0`.
