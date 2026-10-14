# ProofScript JSON Schemas

This document specifies the public JSON formats emitted by ProofScript.

The built-in consumer is documented in [the PS4HTML guide](../tools/ps4html/README.md).

The machine-readable JSON Schema files are:

- `docs/schema/recording-proof.schema.json`
- `docs/schema/render-effective.schema.json` (effective `script_info` rules per module)
- `docs/schema/lean2tex-events.schema.json` (Lean-owned expression rendering events per module)
- `docs/schema/computation-pending.schema.json`
- `docs/schema/computation-bundle.schema.json`
- `docs/schema/computation-published-bundle.schema.json`
- `docs/schema/computation-index.schema.json`

All listed schemas use JSON Schema Draft 2020-12.

## 1. Versioning

Proof and rendering schemas use `0.1.0`. Page/project, computation and Lean2TeX protocols remain `0.0.0`. This recording revision changes array and numeric parameter semantics; old data is handled by the consumer version adapter.

Project metadata and proof-tree JSON embed the version in their top-level `schemaVersion` field.
Page JSON uses the version of the enclosing project export.

Version changes follow these rules:

- Patch: documentation corrections or constraints that do not change accepted JSON.
- Minor: backward-compatible fields or component kinds are added.
- Major: existing fields, tags, or meanings change incompatibly.

The consumer accepts proof/rendering `0.0.0` and `0.1.0`, and only `0.0.0` for other protocols. Historical singleton arrays are normalized only at the old-version boundary; new-version scalars fail array validation. Missing semantic fields from old handwritten recorders are not synthesized; their original template/renderer requirements still apply.

## 2. Page JSON

### 2.1 Location

For Lean module `Paper.Chapter.Main`, the page file is:

```text
.ProofScript/pages/Paper/Chapter/Main.json
```

### 2.2 Top-level object

```json
{
  "module": "Paper.Chapter.Main",
  "source": "/project/Paper/Chapter/Main.lean",
  "components": []
}
```

Fields:

| Field | Type | Meaning |
| --- | --- | --- |
| `module` | string | Fully qualified Lean module name. |
| `source` | string | Source file path reported by Lean. Currently usually absolute. |
| `components` | array | Components in source order. |

Project metadata is exported separately as `.ProofScript/project.json` with
`schemaVersion` and `ProjectInfo`. At most one `project_info` declaration is allowed
for a site; PS4HTML rejects multiple declarations during the site build.

### 2.3 Source location

Every component has:

```json
{
  "file": "/project/Paper/Main.lean",
  "start": 120,
  "stop": 180
}
```

`start` and `stop` are UTF-8 byte offsets in the Lean source file. They are not line and column
numbers.

### 2.4 Component envelope

```json
{
  "source": { "file": "...", "start": 0, "stop": 10 },
  "data": {
    "text": { "value": {} }
  }
}
```

`data` is a tagged object. Exactly one component tag is expected.

Current tags:

- `text`
- `theorem`
- `lemma`
- `latex`
- `figure`
- `references`
- `computation`

The component envelope is open: modules may define additional tags without changing ProofScript's
page model. A custom command serializes its component-specific value and calls
`addPageComponent` with the tag, JSON value, and optional labels. Only the
`theorem` and `lemma` components are handled specially by the page exporter so their declaration
metadata can be resolved at `page_end`.

### 2.5 Text component

```json
{
  "text": {
    "value": {
      "source": "= Title <title>\n",
      "blocks": []
    }
  }
}
```

The original ProofText source and parsed semantic AST are both preserved.

Inline tags currently include:

- `text`
- `strong`
- `emphasis`
- `strongEmphasis`
- `code`
- `strike`
- `underline`
- `highlight`
- `superscript`
- `subscript`
- `link`
- `reference`
- `math`
- `softBreak`
- `hardBreak`

Block tags currently include:

- `paragraph`
- `heading`
- `code`
- `orderedList`
- `unorderedList`
- `quote`
- `displayMath`

### 2.6 Theorem and lemma components

```json
{
  "theorem": {
    "value": {
      "name": "Main theorem",
      "proof": ".ProofScript/proofs/Paper/Main/mainTheorem.json",
      "sorryAx": false
    }
  }
}
```

A declaration introduced with `@lemma` has the same value shape but uses a distinct component tag:

```json
{
  "lemma": {
    "value": {
      "name": "Supporting lemma",
      "proof": ".ProofScript/proofs/Paper/Main/supportingLemma.json",
      "sorryAx": false
    }
  }
}
```

`name` is the display name from `theorem_info`; when omitted it defaults to the Lean declaration's
unqualified name. The fully qualified Lean declaration name, derived from `proof`, identifies the theorem
for references and HTML anchors. `proof` is the path to the independent proof-tree JSON file.
`sorryAx` is true when the declaration transitively uses Lean's `sorryAx`. The page does not embed
the proof document. Both `@theorem` and `@lemma` support `:= script` and unrestricted `:= by`.

### 2.7 LaTeX and figure components

```json
{
  "latex": {
    "value": {
      "metadata": {
        "title": "Commutative diagram",
        "label": "main-diagram",
        "extra": []
      },
      "language": "latex",
      "source": "\\begin{tikzpicture}...",
      "svg": {
        "$resource": {
          "path": ".ProofScript/resources/svg/123.svg",
          "hash": "123",
          "mediaType": "image/svg+xml",
          "encoding": "utf-8"
        }
      }
    }
  }
}
```

`@latex` accepts arbitrary LaTeX source and compiles it to SVG. The complete SVG is stored in the
referenced UTF-8 resource file. Its content hash enables integrity checks and identical SVG values
share one resource file; no SVG information is discarded.

`@figure` accepts a relative image resource path:

```json
{
  "figure": {
    "value": {
      "metadata": {
        "title": "Overview image",
        "label": "overview-image",
        "extra": [["width", "wide"]]
      },
      "path": "assets/overview.png",
      "extension": "png"
    }
  }
}
```

Both component kinds use the `figure` reference namespace. Figure paths must be relative and include
a file extension. ProofScript records the path and extension but does not copy or read the image.

### 2.8 Computation component

`@computation` connects a Lean function declaration to a versioned downstream renderer manifest.
All arguments are enclosed in one configuration object:

```lean
@computation {
  metadata := (title := "Explorer"),
  renderer := "example/calculator-v1",
  function := Paper.compute,
  payload := r#"{"fallback":"Waiting for computation resources"}"#}
```

```json
{
  "computation": {
    "value": {
      "schemaVersion": "0.0.0",
      "metadata": {"title": "Explorer", "label": "explorer", "extra": []},
      "renderer": "example/calculator-v1",
      "function": {
        "declaration": "Paper.compute",
        "type": "Bool → Nat",
        "expression": {"$ref": "e0"},
        "implementation": {"$ref": "e4"},
        "expressions": {"e0": {"kind": "const", "name": "Paper.compute"}}
      },
      "execution": {
        "backend": "wasm",
        "status": "pending",
        "abi": "proofscript-json-v1",
        "bundleId": "Paper.Main",
        "entry": "Paper.compute",
        "wrapper": "Paper.__proofScript_compute",
        "manifest": ".ProofScript/computations/pending/Paper/Main/Paper/compute.json"
      },
      "payload": {"fallback": "Waiting for computation resources"}
    }
  }
}
```

`expression` identifies the declaration and `implementation` points to its elaborated function body
in the shared, self-contained expression table. This compiler-produced intermediate artifact is
declaration provenance and suitable for analysis, but is not a stable executable Lean IR. The
runtime uses the exported `execution` contract; `payload` configures the renderer UI. See
`Embedded-Computation-Renderer-zh.md`.

During Lean elaboration, `@computation` validates a single-argument pure function, synthesizes
`FromJson`/`ToJson`, creates a `String → String` wrapper using `proofscript-json-v1`, and writes the
pending manifest referenced by `execution.manifest`. Both `α → β` and
`α → Except String β` are accepted; the former is lifted through `Except.ok`. The pending status is
replaced by a Wasm resource only in the later bundling/finalization stage.

Pending entry manifests are written below:

```text
.ProofScript/computations/pending/<module path>/<declaration path>.json
```

They contain the stable module bundle ID, original declaration, generated wrapper, ABI, source
location, pretty-printed input/output types, and `pure`/`except` error mode. Renderer configuration
remains in the page component because multiple visualizations may share one compiled entry.

### 2.9 Computation bundle

The stage 4 bundler scans pending manifests, groups entries by `bundleId`, verifies each generated
wrapper is present in the module C IR, and emits one multi-entry Wasm module per group below:

```text
.ProofScript/computations/bundles/<bundleId>/bundle.{mjs,wasm,json}
```

`bundle.json` follows `docs/schema/computation-bundle.schema.json`. It records sorted entry IDs,
wrapper declarations, linked C modules, artifact paths, byte size, SHA-256, and the generic
unknown-entry smoke-test result. The manifest retains the `module-local` mode label; the builder
also follows generated C symbol dependencies through available imported artifacts. Content-addressed
publication is implemented by the finalizer described below.

### 2.10 Finalized computation resources

`scripts/finalize-computations.mjs` validates pending entries against built bundles and publishes
each module/wasm pair into a content-addressed directory:

```text
.ProofScript/resources/computation/<bundleHash>/bundle.{json,mjs,wasm}
```

`bundleHash` is SHA-256 over the module bytes, a zero separator, and the Wasm bytes. Every resource
also carries its own SHA-256 and byte size. Page execution changes from `pending` to `ready` and
contains resource references for the published manifest, ES module, and Wasm binary. The finalizer
writes changed pages and `.ProofScript/computations/index.json` through temporary files followed by
atomic rename. It rejects missing bundles, stale bundle entries, missing page components, and hash
mismatches before changing any page.

Published bundle and index formats are specified by
`computation-published-bundle.schema.json` and `computation-index.schema.json`.

### 2.11 References component

The no-argument `@references` command inserts:

```json
{
  "references": {
    "value": [
      {
        "name": "Library.result",
        "info": {
          "project": {},
          "name": "Display name",
          "label": "result",
          "tags": [],
          "extra": []
        }
      }
    ]
  }
}
```

The component is placed exactly where `@references` occurs. The reference staging area is cleared
after insertion. `@references` does not support standalone file export.

## 3. Proof-tree JSON

### 3.1 Location

Proof trees are written below:

```text
.ProofScript/proofs/<module path>/<declaration path>.json
```

### 3.2 Top-level object

The top level contains the schema version, owning module, complete Lean source code, an expression table,
and the proof-step array. Display rules are exported once per module, not per call:

```json
{
  "schemaVersion": "0.1.0",
  "module": "Paper.Main",
  "code": "@theorem mainTheorem : True := script\n  trivial",
  "expressions": {
    "e0": { "kind": "const", "name": "True", "levels": [], "isProp": true },
    "e1": { "kind": "const", "name": "True.intro", "levels": [], "isProp": false }
  },
  "proof": [
    { "_goal_": { "$ref": "e0" } },
    { "_ruleId": "ProofScript.Script.Basic.trivial" }
  ]
}
```

For `@theorem` or `@lemma` declarations written with `:= by`, ProofScript accepts any Lean tactic,
does not validate or record individual steps, and emits a code-only document:

```json
{
  "schemaVersion": "0.1.0",
  "code": "@lemma supportingLemma : True := by\n  trivial"
}
```

Reference collection remains enabled for this mode and scans the elaborated proof term directly.

Each item is one of the following logical forms.

Goal record:

```json
{
  "_goal_": { "$ref": "e0" }
}
```

Step record:

```json
{
  "_ruleId": "ProofScript.Script.Basic.assumption"
}
```

Arguments recorded at both points are separate fields such as `proof_before` and
`proof_after`. Either field may be `null` if elaboration fails; single-point
arguments retain their original names.

Merged strategy record:

```json
{
  "_ruleId": "ProofScript.Script.Basic.split_and",
  "branches": [{"name": "left", "proof": []}, {"name": "right", "proof": []}]
}
```

The exact fields of tactic steps depend on the tactic and its recorder. Use `_ruleId` to select
the owning module's rendering rule. Strategy records carry `branches` and their recorded
parameters directly on the strategy object; `name` identifies individual branches only.

### 3.3 Expression values

Goals and tactic parameters contain expression references of the form `{ "$ref": "eN" }`.
`eN` resolves against the top-level `expressions` object. Every referenced entry must exist.
Expression entries use a `kind` discriminator such as:

- `bvar`
- `fvar`
- `mvar`
- `sort`
- `const`
- `app`
- `lam`
- `forall`
- `let`
- `lit`
- `mdata`
- `proj`

The table represents a directed acyclic graph. Recursive expression fields (`fn`, `arg`, `type`,
`body`, `value`, `expr`, `typeOf`, and every `arguments[].expr`) are references rather than copied
subtrees. Resolving all references reconstructs the complete expression fields without loss.
The IDs are local to one proof document and have no meaning outside it.

Every serialized expression node includes `isProp`, computed using Lean's `Meta.isProp` for that
exact expression. This distinguishes propositions such as `P`, proofs such as `h : P`, and data
expressions without relying on names or structural guesses.

Application nodes retain the binary `fn` and `arg` fields and additionally provide:

```json
{
  "headConstant": "HAdd.hAdd",
  "arguments": [
    {
      "expr": { "$ref": "e7" },
      "binderInfo": "instImplicit",
      "isExplicit": false,
      "isTypeclass": true
    }
  ]
}
```

`headConstant` is a fully qualified declaration name or null when the application head is not a
constant. `arguments` is flattened and ordered. Binder metadata is derived from the head
declaration's instantiated forall telescope; fields are null when no reliable telescope entry is
available.

Expression nodes may contain `sourceRange` using the same `{file,start,stop}` UTF-8 byte-offset
format as page components. It is emitted only when Lean retained source syntax in expression
metadata; absent ranges are omitted rather than inferred.

### 3.4 LaTeX component steps

The `latex` proof tactic accepts the same metadata and arbitrary LaTeX source as the page-level
`@latex` component. It produces a step record containing:

```json
{
  "_ruleId": "ProofScript.Script.Basic.latex",
  "metadata": {
    "title": "Inline figure",
    "label": "inline-figure",
    "extra": []
  },
  "language": "latex",
  "source": "\\begin{figure}...",
  "svg": {
    "$resource": {
      "path": ".ProofScript/resources/svg/123.svg",
      "hash": "123",
      "mediaType": "image/svg+xml",
      "encoding": "utf-8"
    }
  }
}
```

### 3.5 External resources and embed

Large immutable values use a resource reference:

```json
{
  "$resource": {
    "path": ".ProofScript/proofs/Library/Theorem.json",
    "hash": "123",
    "mediaType": "application/vnd.proofscript.proof+json",
    "encoding": "utf-8"
  }
}
```

Paths are relative to the project working directory. Readers must load the complete UTF-8 file and
verify that its `hash` equals ProofScript's string hash recorded in the reference. SVG resources
contain the original complete SVG. An `embed` step references the original complete proof document
instead of duplicating and replaying its proof tree; its `theorem`, `type`, `args`, `argKinds`, and
introduced `h` fields remain in the parent step, so all former information remains available.

The current format stores expression DAGs and SVG resources through references rather than duplicating
their contents: consumers obtain the complete data by resolving
`$ref` and `$resource` objects.

### 3.6 Parameter contracts and structured values (0.1.0)

Rendering module manifests and effective rules use `schemaVersion: "0.1.0"`. Each registration/rule includes `recordedFields`: an array of emitted field contracts, or null for an opaque external handwritten recorder. Contract metadata must agree between the manifest and effective snapshot.

Module registrations also expose structural input metadata as `parameters: [{name, shape}]`.
A category shape is `{kind:"category", name:"term"}`; array/optional shapes contain an `element`
shape. Unsupported compound parsers export `shape: null`. This replaces the old string `kind`
labels and is independent of the emitted-value contract used by rendering.

An emitted field contract has this form:

```json
{
  "name": "rules",
  "nullable": true,
  "schema": {
    "kind": "array",
    "element": {
      "kind": "object",
      "fields": [
        { "name": "reverse", "schema": { "kind": "boolean" } },
        { "name": "expression", "schema": { "kind": "expression" } }
      ]
    }
  }
}
```

Schema kinds: expression, string, name, syntax, number, boolean, json; array/optional with `element`; object with `fields` (name/schema); union with a nonempty `options` array; literal with a string `value`. Object values contain exactly their declared fields. An expression value is a `$ref` object, never a structured object with an expression-like name. `json` permits open component/resource JSON. `nullable` permits capture failure independently of optional input.

The declaration's field rename and timing determine actual names. Both emits `<field>_before`/`<field>_after`; other timings emit `<field>`. Templates are validated against these names and schemas in Lean and Python, including nested paths `${rules.0.expression}` or `${loc_before.hypotheses}`. Missing optional/capture values display `—`; arbitrary text and structured keys are escaped. Missing fields and out-of-range indices fail.

Complex category output:

| Category | Recorded value |
| --- | --- |
| location | `{kind:"location", wildcard:bool, goal:bool, hypotheses:[expression]}`; an absent optional location is null. Wildcard captures visible local declarations and target role. |
| rwRuleSeq | Always an array of `{reverse:bool, expression:expression}`. |
| simpArgs | Always an array of lemma `{kind:"lemma", phase:"pre" or "post", reverse:bool, expression:expression}`, erasure `{kind:"erase", name:string, expression:expression or null}`, or `{kind:"star"}`. Non-term simproc erasures retain their name. |
| optConfig | Always an array of explicit `{name:string, value:bool/number/string/{kind:"syntax",text:string}}` settings. Empty configuration is `[]`. Typed expressions retain syntax because the category has no tactic-specific expected type; tactic defaults are not materialized. |

`num` is a JSON number. A numeral parsed as term is still a Lean expression reference. All generated arrays preserve their shape for zero, one or multiple elements. Nested RecordedValue objects recursively merge expression snapshots, relocate references and collect constants.

Readers accept legacy 0.0.0 proof/rendering files. Contract-guided singleton normalization is confined to the old-version boundary; 0.1.0 records never coerce a scalar into an array. Historical handwritten steps may lack the new semantic fields; readers retain their original rendering requirements instead of inventing them. Use a fresh Lean export to obtain new complex fields and contracts. This is an explicit pre-1.0 protocol revision, not a version-only rewrite of old data.

## 4. Compatibility Requirements

Writers must:

- preserve source component order;
- emit page `schemaVersion` as a semantic-version string;
- use UTF-8 byte offsets for source locations;
- keep proof trees independent from page JSON;
- use `null` for absent optional heading and media labels;
- preserve `extra` metadata pairs in order.
- emit every expression ID referenced by a proof record or another expression node;
- retain complete resource contents at the referenced paths.

Readers should:

- reject unsupported schema versions (the built-in renderer accepts proof/rendering `0.0.0` and `0.1.0`);
- ignore unknown compatible component fields;
- preserve unknown proof-step fields;
- resolve theorem `proof` paths relative to the project working directory;
- build cross-page indexes for Lean declaration names and other component labels after loading all page files.
- resolve `$ref` against the current proof document's `expressions` table;
- resolve `$resource` paths relative to the project working directory and verify their hashes.

## 5. Known Schema Limitations

- Lean expression serialization is described only structurally and remains extensible.
- Source paths are currently commonly absolute.
- Custom page components are intentionally open and therefore do not receive component-specific
  validation from the core schema unless promoted to a built-in tag.
- Cross-page reference validity is checked by the future renderer, not by individual Lean modules.
