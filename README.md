# ProofScript

ProofScript is a compile-time language extension for [Lean 4](https://lean-lang.org/).
It provides a structured, extensible, and semantically enriched proof DSL that records Lean's live proof goals, tactic arguments, and branch structure and exports them as JSON.
ProofScript also integrates page components such as ProofText body content, theorem statements, images, and LaTeX SVG. Page builds compile and export this data as JSON for renderers or other downstream tools to consume.

## Table of Contents

- [Quick Start](#quick-start)
- [Formal Proofs](#formal-proofs)
- [ProofText](#prooftext)
- [Automatic Reference Management](#automatic-reference-management)
- [Other Page Components](#other-page-components)
- [Unified Info Configuration](#unified-info-configuration)
- [Page Export](#page-export)
- [Requirements](#requirements)
- [Current Limitations](#current-limitations)
- [Related Documentation](#related-documentation)
- [PS4HTML Site Generator](#ps4html-site-generator)

## Quick Start

PS4HTML is included in this repository under [`tools/ps4html/`](tools/ps4html/). Install the site tool
from the repository root with Python 3.11+ (preferably in a virtual environment):

```sh
python3 -m pip install -e ./tools/ps4html
```

After configuring the Lean project's ProofScript dependency and running `lake update`, use
`lake build MyLibrary:ps4html` (replace `MyLibrary` with your Lean library name) to generate
`.PS4HTML/build/index.html`, then `ps4html serve` to preview it.
See [`examples/site/`](examples/site/) and the [PS4HTML guide](tools/ps4html/README.md).
Computation pages additionally need Node, Emscripten, and a matching Lean/Wasm runtime.
The unified Info protocol is `5.0.0`; the recording protocol is `0.1.0`. Each script step is one object with ordinary goal snapshot fields. Artifact manifests select configuration snapshots and invocation contracts. Rebuild older caches with the Lake facet; see the [configuration and export documentation](#unified-info-configuration).

Add ProofScript as a dependency in `lakefile.toml` and run `lake update`. You can then use it in a Lean project.

```lean
import ProofScript

project_info {
  title := "An Example Formal Paper",
  authors := ["Alice", "Bob"],
  description := "A small demonstration of ProofScript.",
  keywords := ["Lean", "formal proof", "structured proof"],
  year := "2026"
}

@text r#"
= Introduction <introduction>

This page contains a recorded theorem. See @thm:mainResult.
"#

@theorem mainResult (info := { name := "Main Result" }) (P : Prop) (h : P) : P := script
  assumption


@references

page_end
```

Assuming the Lean file above is `./Project/Module/Page.lean`, the proof and page information will be exported after compilation to, respectively:

```text
./.ProofScript/pages/Project/Module/Page.json
./.ProofScript/proofs/Project/Module/Page/mainResult.json
```

## Formal Proofs

### Script Mode

ProofScript introduces script mode, initiated by `:= script`, as an alternative to tactic mode. Within `:= script`, users write script tactic names without prefixes; the framework automatically rewrites them to the internal execution entry point `script_<name>` and uses `_script_<name>` while recording. Its syntax is consistent with tactic mode (and is in fact built on tactic mode). Script mode broadly contains the following three kinds of basic elements:

1. Steps: `intro`, `apply`, and others serve as logical units in formal proofs and carry stronger semantics than ordinary Lean tactics.
2. Strategies: `split_and`, `contra`, `induction`, and others determine the proof structure at a high level and share a uniform syntax.
3. Metadata: `remark`, `latex`, and others embed explanatory text, diagrams, and other metadata in proof scripts.

These three kinds of elements are collectively called script tactics. These constraints make proof scripts more suitable for stable mapping to natural language or interactive presentations while retaining Lean's formal verification capabilities. The following code provides a complete example.

```lean
theorem implicationChain
    (P Q R : Prop) (hPQ : P → Q) (hQR : Q → R) : P → R := script
  intro hP
  infer
    P => Q := hPQ hP
    => R := hQR ?_
```

### Built-in ProofScript Tactics

#### Steps

##### Native Lean Tactics

The core module wraps the following Lean tactics. Only the simplified syntax listed here is supported:

| Tactic | Effect |
| :- | :- |
| `assumption` | Closes the goal using a matching hypothesis from the context |
| `change t` | Replaces the goal with the definitionally equal `t` |
| `contradiction` | Closes the goal from a contradiction in the context |
| `exfalso` | Changes the current proposition goal to `False` |
| `omega` | Solves Presburger arithmetic goals |
| `rfl` | Closes the goal by reflexivity |
| `simp only [l₁ l₂ ...]` / `simp only [l₁ l₂ ...] at h₁ h₂` / `simp only [l₁ l₂ ...] at *` / `simp only [l₁ l₂ ...] at ⊢` | Simplifies using only the specified whitespace-separated identifiers, on selected hypotheses, all hypotheses, or the target |
| `symm` | Swaps the two sides of a symmetric relation |
| `trivial` | Solves simple goals |
| `rw [h₁ h₂ ...]` / `rw [← h₁ h₂ ...]` with `at h₁ h₂`, `at *`, or `at ⊢` | Rewrites using equalities, then attempts native `rfl` |
| `unfold d₁ d₂ ...` | Unfolds one or more whitespace-separated definitions |

##### Dedicated Script Tactics

| Tactic | Effect | Corresponding Native Tactic | Restriction |
| :- | :- | :- | :- |
| `intro x₁ ... xₙ` | Introduces hypotheses and variables in order | `intro` | Nonempty list; implications to `False` still require `contra` |
| `provide ⟨h⟩` | Supplies a witness in `witness.data`, or for an existential target | `exact` / `exists` | It is not a general `exact`; it is restricted to these two contexts |
| `apply t` | Applies a proposition of the form `P → Q` or `P ↔ Q`, leaving exactly one premise subgoal | `apply` / `Iff.mp` / `Iff.mpr` | The outermost proposition must be an implication or equivalence; only one goal is produced |
| `funext x` | Reduces a function equality to pointwise equality | `funext` | Both sides of the equality must be functions with the same domain |
| `obtain_exist ⟨x, hx⟩ := h` | Destructures a local existential hypothesis | `cases` | `h` must prove an existential proposition |
| `left` / `right` | Selects the left or right side of a disjunction goal | `apply Or.inl/inr` | The current goal must be a disjunction |
| `quot_induction q with a` | Performs quotient induction | `induction` | |
| `unpack_and ⟨h₁, ..., hₙ⟩ := h` | Destructures a local conjunction hypothesis | `cases` | Nonempty list; splits the right-hand remainder `n - 1` times, keeping the final remainder intact |
| `unpack_iff ⟨h₁, h₂⟩ := h` | Destructures a local equivalence hypothesis | `cases` | `h` must prove an equivalence |

The introduction lists are nonempty and whitespace-separated. Each name is introduced in the
context produced by the preceding name, including dependent binders. These forms also work as
`by script_intro ...` and `by script_unpack_and ...`, and in recorded
`@theorem` script proofs; native `by` tactics are unchanged.

For `h : P ∧ Q ∧ R ∧ S`, `unpack_and ⟨hp, hq, rest⟩ := h` binds `hp : P`, `hq : Q`,
and `rest : R ∧ S`. It does not flatten left-nested conjunctions. Too many names fail when a
required right-hand remainder is no longer a conjunction. The singleton form
`unpack_and ⟨whole⟩ := h` requires a conjunction but simply renames the original hypothesis
(including allowing the same name), without splitting it. This is deliberately different from
native `rcases h with ⟨whole⟩`, which destructures the conjunction and names its first field;
for two or more names, the right-associated grouping agrees with native tuple patterns.

Recorded introduction parameters (`h`) and unpack outputs (`names`) contain all supplied
identifiers, while unpack's input `h` is recorded before splitting or renaming. The existing
serializer represents a singleton as one expression and multiple values as an array.

`apply` accepts a term whose outermost proposition is an implication or equivalence. It applies only the outermost implication layer, so a chain such as `P → Q → R` produces the single premise goal `P`, with the remaining implication retained in the conclusion. For an equivalence, it selects the direction matching the current target:

```lean
theorem compose (P Q R : Prop) (hPQ : P → Q) (hQR : Q → R) (hP : P) : R := script
  apply hQR
  apply hPQ
  assumption
```

#### Strategies

Strategy tactics split a goal into branches with **semantic names**, thereby establishing the proof's high-level structure.
Complete strategy branches with `| case => …` or anonymous `·` branches. A bullet focuses the next remaining goal and must close it before the next branch. Both forms can be nested and mixed. Recordings retain semantic goal labels (for example, `left`/`right` for `split_and`); ambiguous anonymous labels require explicit named branches. For `claim`, the first bullet proves the claim (`proof`), and subsequent steps or a second bullet prove the continuation with the new hypothesis available.

The currently available strategy and structural tactics are:

| Tactic | Effect or Branches |
| :- | :- |
| `claim h : P` | Produces the continuation goal and an assertion proof goal named `proof` |
| `have h := t` | Behaves like native `have`; the top-level function used by `t` may not have proposition-valued parameters |
| `exact t` | Behaves like native `exact`; the top-level function used by `t` may not have proposition-valued parameters |
| `witness` | Constructs an existential, producing `data` and `proof` |
| `split_and` | Splits a binary conjunction, producing `left` and `right` |
| `split_and!` | Recursively splits a conjunction, producing `goalI`, `goalII`, and so on |
| `split_iff` | Proves an equivalence, producing `suffice` and `necess` |
| `cases_by h` | Splits on a local disjunction hypothesis, producing `left` and `right` |
| `cases_by! h` | Recursively splits a local disjunction, producing `goalI`, `goalII`, and so on |
| `cases_on t` | Splits on the truth of a proposition or the constructors of data |
| `contra h` | Proves by contradiction, producing `proof` |
| `induction n` | Performs natural-number induction |
| `complete_induction n` | Performs strong induction on natural numbers |
| `constructor` | Applies the target inductive type's default constructor and names branches after its fields |
| `constructor! c` | Applies the specified constructor `c` and names branches after its fields |

##### Existential Construction

`witness` operates on an existential proposition of the form `∃ x, P x` and splits it into two branches:

- `data`: construct an object satisfying the condition
- `proof`: prove that the object satisfies `P`

```lean
theorem demo_witness : ∃ n : Nat, n = 0 := script
  witness
  | data => provide 0
  | proof => trivial
```

`provide` can also construct an existential directly, without the two branches of `witness`. It cannot be used as a general `exact` step:

```lean
theorem provide_witness : ∃ n : Nat, n = 0 := script
  provide 0
  rfl
```

##### Goal Decomposition: Conjunction

`split_and` operates on a conjunction of the form `P ∧ Q` and splits it into two branches:

- `left`: the left branch
- `right`: the right branch

`split_and!` recursively decomposes a conjunction of the form `P₁ ∧ P₂ ∧ ... ∧ Pₙ` into branches named `goalI`, `goalII`, and so on.

```lean
variable {P Q R : Prop}
theorem demo_split_and (hP : P) (hQ : Q) : P ∧ Q := script
  split_and
  | left => assumption
  | right => assumption
theorem nestedAnd (hP : P) (hQ : Q) (hR : R) : P ∧ Q ∧ R := script
  split_and!
  | goalI => assumption
  | goalII => assumption
  | goalIII => assumption
```

##### Goal Decomposition: Equivalence

`split_iff` operates on an equivalence proposition of the form `P ↔ Q` and splits it into two branches:

- `suffice`: sufficiency, namely `P → Q`
- `necess`: necessity, namely `Q → P`

```lean
variable {P Q : Prop}
theorem demo_split_iff (hPQ : P → Q) (hQP : Q → P) : P ↔ Q := script
  split_iff
  | suffice h₁ =>
    apply hPQ
    assumption
  | necess h₂ =>
    apply hQP
    assumption
```

##### Proof by Contradiction

In script mode, `contra h` can:

1. Operate on a negation of the form `¬ P` and produce a `proof` branch in which `P` is introduced as a hypothesis.
2. Operate on another proposition and produce a `proof` branch in which `¬ P` is introduced as a hypothesis.

In the `proof` branch, the goal is changed to `False`, so the proof is completed by deriving a contradiction.

```lean
theorem demo_by_contra_pos (P : Prop) (h : ¬ P → False) : P := script
  contra hnp
  | proof =>
    apply h
    assumption
theorem demo_by_contra_neg (P : Prop) : ¬ (P ∧ ¬ P) := script
  contra h
  | proof =>
    unpack_and ⟨hP, hNP⟩ := h
    apply hNP
    assumption
```

##### Mathematical Induction

In script mode, `induction n` performs mathematical induction on the natural number `n` and produces two branches, `zero` and `succ k ih`:

```lean
theorem demo_induction (n : Nat) : n + 0 = n := script
  induction n
  | zero => rfl
  | succ k ih => rfl
```

##### Strong (Complete) Induction

`complete_induction n` performs strong induction on the natural number `n`. It likewise produces `zero` and `succ k ih` branches, but the induction hypothesis in the `succ` branch, `ih : ∀ m < k + 1, P m`, covers every smaller natural number:

```lean
theorem demo_complete_induction (n : Nat) : n + 0 = n := script
  complete_induction n
  | zero => rfl
  | succ k ih => rfl
```

##### Case Analysis with `cases_on`

`cases_on p` performs case analysis on whether proposition `p` is true or false, producing the two branches `true h` (`h : p`) and `false h` (`h : ¬p`):

```lean
theorem demo_cases_on (n : Nat) : n = 0 ∨ n ≠ 0 := script
  cases_on (n = 0)
  | true h =>
    left
    assumption
  | false h =>
    right
    assumption
```

##### Arbitrary Constructors

`constructor` applies the default constructor of the target inductive type. `constructor! c` applies
a named constructor explicitly. Both tactics name the resulting branches after the constructor's
fields. They are intentionally not available for `∧`, `↔`, `∃`, or `∨`; use `split_and`, `split_iff`,
`witness`, or `left`/`right` respectively.

```lean
inductive TwoPremises (P Q : Prop) : Prop where
  | first (left : P) (right : Q)
  | second (value : P)

example (P Q : Prop) (hP : P) (hQ : Q) : TwoPremises P Q := script
  constructor
  | left => assumption
  | right => assumption

example (P Q : Prop) (hP : P) : TwoPremises P Q := script
  constructor! TwoPremises.second
  | value => assumption
```

#### Metadata

The core module provides the following metadata tactics:

| Tactic | Effect |
| :- | :- |
| `remark "text"` | Inserts a natural-language annotation |
| `svg "code"` | Inserts raw SVG metadata |
| `latex (title := "...", ...) "source"` | Compiles and records arbitrary LaTeX source and its SVG |
| `admit "reason"` | Temporarily closes the goal with `sorry` and records the reason |
| `cite theorem` | Records a reference to a theorem carrying `theorem_info` without changing the goal |

##### Informal Proofs

The `admit` tactic lets you use natural language in place of a proof that has not yet been formalized. It uses `sorry` to fill the proof temporarily, for example:

```lean
theorem draft (P : Prop) : P := script
  admit "This result has not been formalized yet."
```

For term form, use the ordinary term macro `admit`, for example `:= admit "Not yet formalized"`; it is not a directly executable script tactic name.

##### Annotations

The `remark` tactic inserts a natural-language annotation to help readers better understand part of a proof, for example:

```lean
@theorem demo_remark {P : Prop} (h_P : P) : P := script
  remark "This is a simple proof"
  assumption
```

##### LaTeX (SVG)

Proofs provide a unified `latex` metadata tactic. Like the page component `@latex`, it accepts metadata and arbitrary LaTeX source. During recording, it invokes the local LaTeX toolchain to generate SVG and writes the metadata, source, and SVG into the proof tree. For example:

```lean
@theorem proofWithDiagram (P : Prop) (h : P) : P := script
  latex (title := "Derivation Diagram", label := "proof-diagram") r#"
    \begin{tikzpicture}
      \draw[->] (0,0) -- (1,0);
    \end{tikzpicture}
  "#
  assumption
```

To ensure that the precompiler works correctly, make sure TeX Live is installed locally. This is the proof-level tactic; use the `@latex` command described below for arbitrary page-level LaTeX.

#### Calculation Chains with `calc`

ProofScript wraps `calc` blocks as a script tactic, so they can be used in script mode.

#### Inference Chains with `infer`

As is well known, `calc` blocks greatly simplify chained calculations over transitive relations. Inference chains with `infer` use similar syntax to simplify general chains of deductions, for example:

```lean
theorem divisibility_chain {a b c d e : ℕ}
    (h_ab : a ∣ b) (h_bc : b ∣ c)
    (h_pos : 0 < c * d * e)
  : a ≤ c * d * e
:= script
  remark "Here we prove the inequality using divisibility"
  infer
    (a ∣ b) => (a ∣ c)
                := dvd_trans h_ab h_bc
            => (a ∣ c * d)
                := dvd_mul_of_dvd_left ?_ d
            => (a ∣ c * d * e)
                := dvd_mul_of_dvd_left ?_ e
            => (a ≤ c * d * e)
                := Nat.le_of_dvd h_pos ?_
```

Only the first step states the initial proposition: `P => Q := ...`. Every later step starts with just `=>`, as in `=> R := ...`; its premise is the preceding conclusion. The Unicode arrow `⇒` works the same way.

Each step adds its conclusion using `have`. For ordinary proof terms, the first step must not use `?_` and must use a proof of the initial proposition; every later step must contain exactly one `?_`, directly replaced with the preceding conclusion's proof.

A step may instead use `:= by ...`. In later steps, `this` refers to the preceding conclusion's proof, so `=> R := by exact hQR this` needs no placeholder. Tactic proofs may use and solve their own holes. The first step must still use a proof of the initial proposition.

Conclusions may optionally be named, for example `P => hQ : Q := hPQ hP` followed by `=> hR : R := by exact hQR this`. These names are available in later steps and, when `infer` is used as a tactic, in the following tactics.

`infer` can:

- Be used as an intermediate step, adding every new conclusion to the context (anonymously unless named, similar to `claim`).
- Close the goal as a terminating tactic.
- Be used directly as a term (written `:= infer`); here, `infer` is an ordinary term macro rather than an unprefixed executable script tactic.

### Mathlib Script Tactics

`import ProofScript` includes Mathlib tactics and their presentation modules through `ProofScript.Mathlib.Info`. Presentation configuration is registered during page builds. To load only tactic implementations and registrations, use:

```lean
import ProofScript.Mathlib.Scripts
```

For builtin tactics, `ProofScript.Script.Basic` provides execution and registrations; `ProofScript.Defaults.Script` adds their page presentation. The public `ProofScript` entry imports all defaults, whose Info commands are active only in page mode. See [Unified Info Configuration](#unified-info-configuration). The currently wrapped tactics, in alphabetical order, are:

| Tactic | Supported Simplified Forms |
| :- | :- |
| `script_continuity` | Default form |
| `script_exact_mod_cast` | `script_exact_mod_cast proof` |
| `script_field` | Default; `script_field [lemmas...]` |
| `script_gcongr` | Default; pattern; `with names...`; and combinations of both |
| `script_itaotu` / `script_itauto` | Default; `*`; proposition lists; and `!` variants |
| `linarith` | Default; fact lists; `only`; and `!` variants |
| `script_measurability` | Default form |
| `script_nlinarith` | Default; fact lists; `only`; and `!` variants |
| `script_norm_cast` | Default and `at` forms |
| `norm_num` | Default; lemma lists; `only`; and corresponding `at` forms |
| `script_positivity` | Default and fact-list forms |
| `script_push_cast` | Default; lemma lists; `only`; and corresponding `at` forms |
| `qify` / `rify` / `zify` | Default; lemma lists; and corresponding `at` forms |
| `script_ring` | `script_ring`; `script_ring!` |
| `script_ring_nf` | Default; `!`; and corresponding `at` forms |
| `script_tauto` | Default form |
| `script_wlog` | Default; `generalizing`; `with`; combinations of both; and `script_wlog!` |

To keep arguments stable for recording, the wrappers use only basic categories such as `ident` and `term`. Arguments in square brackets are whitespace-separated:

```lean
linarith [h₁ h₂]
qify [hab] at h ⊢
norm_num only [Nat.add_zero Nat.zero_add] at *
```

Tactics that support locations may use `at h`, `at h₁ h₂`, `at *`, `at ⊢`, and `at h₁ h₂ ⊢`. Configuration objects, custom dischargers, arbitrary tactic blocks, and suggestion-only `?` variants are not wrapped. See the [Mathlib tactic definitions](ProofScript/Mathlib/Scripts.lean) for the supported syntax.

### Custom Script Tactics

Use `script_macro <id>` / `script_elab <id>` to create a script tactic. The ID is required and unique within the defining module; it is independent of the tactic's initial keyword. Within `:= script`, users still write the unprefixed tactic keyword; the framework automatically rewrites it to the execution entry point `script_<keyword>` and then to `_script_<keyword>` during recording. The unprefixed keyword does not become an executable tactic in ordinary `:= by` blocks. These commands use tactic syntax, so no `: tactic` suffix is needed. When a term version is needed, use an ordinary `macro` to wrap it as a `script` proof. For example:

```lean
script_macro finishRule
"finish" proof:term => `(tactic| exact $proof:term)

script_elab introNamedRule (intro := [h])
"intro_named" h:ident => do
  Lean.Elab.Tactic.evalTactic (← `(tactic| intro $h:ident))

macro "finish" proof:term : term => `(script
  finish $proof:term)
```

Parameters use `RecordParam` instances: a leaf category registers `RecordParam (.category name)`, and array and optional inputs compose these instances automatically. Builtin include `term`, `ident`, `str`, `num`, `location`, `rwRuleSeq`, `simpArgs` and `optConfig`. Parenthesized categories, `+`, `*`, `?`, `sepBy` and `sepBy1` compose their codecs; an unnamed sequence needs a named category or a handwritten recorder. Arrays always remain arrays, including zero or one element. `num` records a JSON number; a numeral parsed as `term` remains a Lean expression reference.

The declaration configuration supports:

| Option | Meaning |
| --- | --- |
| `intro`, `clear` | Capture the listed parameters after or before execution. |
| `strategy` | Mark a branching tactic. |
| `continuation` | Zero-based index of the continuation goal after execution. |
| `params` | Per-parameter `codec`, `timing`, `context`, `failure` and `field`. |

Timing is `once`, `before`, `after` or `both`; `both` emits `<field>_before` and `<field>_after`. Strings default to `once`, other parameters to `both`. The default failure policy is `bestEffort` (`null` on failure); `required` fails and rolls back the recording and tactic state. Context is `main`, `continuation` or a named branch. Explicit single-parameter codecs are `expression`, `typeOf`, `name` and `"syntax"`.

```lean
script_macro finishRule
  (params := [proof(timing := before, field := "evidence")])
  "finish" proof:term => `(tactic| exact $proof:term)

script_info finishRule {
  template := [{ lang := "en", tag := "Finish", content := "${evidence}" }]
}
```

Use `script_recorder <id>` when output requires custom capture logic, such as elaborated calc steps or generated media. Supply the emitted field contract and write the execution order with the recorder DSL used by automatic recording:

```lean
open ProofScript.Recording

script_recorder finishRule
  (fields := goalFields ++ #[{ name := "evidence", schema := .expression }])
  "finish" proof:term => recording_step do
    capture_params #[goalParam "goal_before", param (.category `term) "evidence" proof]
    execute_recorded
    capture_params #[goalParam "goal_after"]
```

The recorder ID and tactic keyword must match the registration. When automatic recording is unavailable because a category lacks an instance or a parameter parser is unsupported, and no handwritten recorder is bound, recording emits a warning and execution continues. The step exports the reserved `_ruleId: "ProofScript.Recording.unrecorded"` and its original keyword in `name`; strategy branches are still recorded separately. PS4HTML displays a red “Data not exported” box. Handwritten recorders without `fields` have an opaque contract (`recordedFields: null`).

`script_info` configuration takes effect in proof modules importing its declaration module; local updates are exported for later importers. Templates use field objects, are merged per language, and fall back to the first language. Imported updates use the full ID, such as `script_info MyRules.finishRule`. Slots use actual emitted names; nested paths such as `${rules.0.expression}` and `${loc_before.hypotheses}` are checked against the schema. Failed captures display `—`; structured values and text are HTML-escaped. A specialized `renderer` uses the merged configuration. Overloads sharing a keyword require distinct IDs.

The public DSL and runtime API are exported by `import ProofScript.Script.Recording`; `import ProofScript` also includes the script declaration commands. A `recording_step do` block opens one recording destination in the main goal's context. Its body is ordinary Lean `TacticM` code, so it supports variables, conditionals, loops and custom execution. The block itself adds no goal snapshots and executes no tactic implicitly; metadata-only recorders are supported.

| Statement | Meaning |
| --- | --- |
| `capture_params parameters` | Capture an ordered `Array ParamCapture` at this statement's execution point. |
| `record_value key value` | Convert an existing value through `ToRecordedValue` and commit it under `key`. |
| `execute_recorded` | Execute this invocation's selected original tactic with its original arguments. |

For example, capture a hypothesis before clearing it, write an existing metadata variable, then attempt another capture:

```lean
open Lean ProofScript ProofScript.Recording

script_macro snapshotThenClear "snapshot_then_clear" h:ident => `(tactic| clear $h:ident)
script_recorder snapshotThenClear (fields := goalFields ++ #[
  { name := "evidence_before", schema := .expression, nullable := false },
  { name := "module", schema := .string, nullable := false },
  { name := "evidence_after", schema := .expression }])
  "snapshot_then_clear" h:ident => recording_step do
    capture_params #[
      goalParam "goal_before",
      { name := "evidence_before", onFailure := .required, capture := expression h.raw }
    ]
    let moduleName := toJson (← getEnv).mainModule
    record_value "module" moduleName
    execute_recorded
    capture_params #[
      goalParam "goal_after",
      { name := "evidence_after", onFailure := .bestEffort, capture := expression h.raw }
    ]
```

`ParamCapture` and `param` describe captures without scheduling them. Constructing the array does not capture anything: `capture_params` runs its entries in order using the state present at that point. `onFailure` defaults to `.bestEffort`, which writes `null` on capture failure; `.required` aborts. Each capture restores temporary elaboration state before committing its snapshot, and a failed batch rolls back all fields it wrote even if the caller catches the error. Set `collectReferences := false` to omit a field's citations. `ParamCapture.field` defaults to `name`; overriding it changes the emitted key while preserving the logical name for diagnostics. Use distinct keys for manual before/after snapshots.

`record_value` supports `RecordedValue`, `Json`, `String`, `Bool`, `Nat`, `Int` and `Expr`, with composing instances for arrays, lists and options. `ToRecordedValue.capture` returns `CaptureM RecordedData`; `Expr` is captured in the current context, and custom types can implement this interface. Conversion is isolated and required. Use `CaptureM.run` to save a `RecordedValue` before execution and commit it afterward:

```lean
-- Inside a recording_step or recording_strategy block:
let saved ← CaptureM.run (expression h.raw)
execute_recorded
record_value "evidence" saved
```

`RecordedValue` is the pure `{ data, nodes }` result of `CaptureM.run`. It has no `ToJson` instance; `RecordedValue.encode : Json` exports its data, expression table and root paths together. Its expression nodes can be imported into a new builder or committed to a proof's shared node array, with relocated references. Steps and branches keep structured `RecordedData` until final proof export. Passing it through `record_value`, including inside containers, preserves its graph without consulting the original context again; citations come from the pure graph.

The recording format is `0.1.0`. `recordedProofJson` exports the pure structural graph and explicit `expressionRoots`. PS4HTML follows only these registered roots and applies display companions only through their invocation contract; ordinary JSON stays data. Old caches must be regenerated with `lake build MyLibrary:ps4html`; `ps4html make --cache` does not migrate them. The old expression exporter and compatibility adapters have been removed.

Use explicit `<field>_display` companions for declaration names/types/local values, proposition hints and application binder information. Enable them with `goalParamWithDisplay`, `paramWithDisplay`, `explicitParamWithDisplay` or `recordValueWithDisplay`, and extend the output contract with `withDisplayFields`. Companions are ordinary `RecordedData`; auxiliary expressions share the subject's graph but add no citations. A missing subject or best-effort failure writes two nulls atomically. Ordinary `record_value` and custom conversions do not add companions automatically.

```lean
-- Freeze both fields while the context exists, then commit the saved pair:
let saved ← CaptureM.run <| captureWithDisplay "evidence" (expression h.raw) (some h.raw)
execute_recorded
recordCapturedWithDisplay "evidence" saved
```

Custom conversions still compose structure. Use `snapshotExpression` for expression leaves, as below; callers explicitly request display for the whole conversion with `recordValueWithDisplay "evidence" value`. Nested expression occurrences receive paths relative to that field. Importing an existing snapshot relocates nodes without querying declarations again, so capture its display when first saving the subject.

```lean
structure Evidence where
  term : Lean.Expr
  label : String

instance : ToRecordedValue Evidence where
  capture value := do
    return .object [
      ("term", ← snapshotExpression value.term),
      ("label", .plain (Lean.toJson value.label))]
```

Strategies use `recording_strategy nodes do ...`, with optional `(continuation := some index)`. `nodes` is a `List String` describing the script's proof branches; parenthesize compound expressions. A handwritten strategy recorder receives the runner's newline-separated labels through the additional `"_strategy_cases" strategyCases:str` parser arguments:

```lean
script_macro rememberTrue (strategy := true, continuation := 1)
  "remember_true" h:ident => `(tactic| script_claim $h:ident : True)

script_recorder rememberTrue
  (fields := strategyGoalFields ++ #[
    { name := "hypothesis", schema := .expression, nullable := false }])
  "remember_true" h:ident "_strategy_cases" strategyCases:str =>
  recording_strategy (strategyCases.getString.splitOn "\n") (continuation := some 1) do
    capture_params #[goalParam "goal_before"]
    execute_recorded
    capture_params #[
      { (param (.category `ident) "hypothesis" h .required) with context := .continuation }
    ]
```

The block prepares branches automatically after its body succeeds, including after an early `return`. It resolves the final goals and calls `prepareBranches` before closing the recording destination. An exception rolls back the block without preparing branches. The script runner then advances branch proofs and merges them into the parent record.

Each `ParamCapture.context` is interpreted when that capture runs: `.main` selects the current main goal, while a strategy block also supports `.continuation` and `.branch "label"`. Selectors read current goals rather than a cached post-execution snapshot. Missing or invalid selected contexts follow that parameter's failure policy; non-main selectors outside a strategy block do likewise. Main-goal captures before execution do not require strategy branches to exist yet.

Automatic ordinary recorders capture `goal_before`, `goal_after` and their `_display` companions; strategy recorders capture only the before pair. Expression parameters also receive companions, named `<field>_before_display` and `<field>_after_display` for `both` timing. Handwritten recorders choose snapshots with `goalParam` or `goalParamWithDisplay`, and declare matching contracts with `goalFields`, `strategyGoalFields`, `withDisplayFields` or custom fields. Declaring a field does not capture it. No remaining goal writes null for the goal and its enabled companion; goal constants add no citations. Templates may reference only fields supplied by their recorder.

`timing` belongs only to declaration configuration. Automatic generation places `once`/`before` captures before execution and `after` captures afterward; `both` emits `<field>_before` and `<field>_after`. Handwritten DSL code schedules captures by statement position. Empty keys, reserved keys (`_ruleId`, `branches`) and duplicate writes always fail, including conflicts across capture and value statements; `bestEffort` cannot suppress these errors. Cross-phase collisions may be detected after tactic execution. Declaration checks still reject invalid names and collisions after expanding timing.

Successful blocks preserve tactic execution; failed blocks roll back Lean state, records, expression tables and references. Nested blocks reserve stable destinations, so the outer block remains writable afterward. Pure data can be recorded after the final goal closes. External IO, such as LaTeX compilation and resource files, is outside Lean's rollback boundary. For custom execution, call ordinary `TacticM` operations in place of `execute_recorded`; reusable recorder helpers take `[RecorderContext]` to use their caller's scope.

See the runnable [direct recorder example](examples/recording/DirectRecorder.lean) and [category example](examples/recording/Labels.lean). Adding a category requires a `RecordParam (.category name)` instance; arrays and optional inputs compose it automatically.

Defining script tactics in the style of `macro_rules` / `elab_rules` is not currently supported.

### Exporting Proof Trees

Declare a page theorem with `@theorem` or `@lemma`, then run `lake build MyLibrary:ps4html` to export it. In page JSON, they use the tags `"theorem"` and `"lemma"`, respectively.
Published proof data is available under `.PS4HTML/inputs/<package>/<library>/.ProofScript/proofs/` in the Lean project.
At the top level, every proof tree contains `schemaVersion` and the complete Lean source in `code`. Script-mode trees also contain the expression table `expressions`, the registered expression paths `expressionRoots` and recorded step array `proof`. Each array entry is a single step object containing `_ruleId`, captured fields, and any strategy `branches`; each branch's `proof` uses the same format. Default ordinary recorders include `goal_before` and `goal_after` as expression references or `null`; default strategy recorders include only `goal_before`.

Within `:= script`, use unprefixed DSL names directly; the framework automatically adds the `script_` prefix and checks every step, recording it during page builds. `:= by` accepts ordinary Lean tactics but cannot use ProofScript's script tactics. Its exported tree retains only `schemaVersion`, `module` and the complete `code`, and does not output `expressions`, `expressionRoots` or `proof`. Both proof forms collect references during page builds.

`@theorem` and `@lemma` create native Lean theorems in both verification and page builds. They no longer generate `scriptcheck_<name>` declarations. Ordinary `lake build` and IDE checking use the execution version of `script` or native `by`, preserve asynchronous proof checking, and skip recording and page export. Inline `info` and citation presentation checks are consumed during page builds. All six standalone Info commands skip field decoding, semantic validation and configuration registration in verification mode; their syntax must still parse. Both modes retain editor references, including best-effort resolution of metadata targets. Explicit low-level recorder APIs retain their recording capability.

`lake build MyLibrary:ps4html` automatically enables `proofScript.pageBuild` and compiles the required source packages, including the ProofScript framework and configuration-bearing dependencies, in `.lake/ps4html/<package>/<library>/`. This restores framework presentation defaults as well as user configuration. It preserves ordinary `.lake/build/` artifacts and reuses base dependencies that need no page or Info data, such as Mathlib. Page builds currently record the source modules afresh; a module cannot change build mode midway through its commands.

The repository's default build runs verification tests. Run `lake build TestPage:pageTests` for tests that require recording, page components or exported state; this target uses isolated page build artifacts.

## ProofText

`@text` accepts a Lean string literal and parses it as ProofText, a dedicated lightweight markup language with syntax broadly similar to Typst.

````lean
@text r#"
= ProofText Overview <overview>

This paragraph contains *bold*, _emphasis_, *_bold emphasis_*,
~~deleted~~, __underlined__, ==highlighted==, x^2^, a~n~,
`inline code`, $x + y$, and [a link](https://example.com).

- First item
- Second item

+ First step
4. Forced fourth step
+ Automatically numbered fifth step

> A quoted paragraph.

$$
\int_0^1 x^2\,dx = \frac{1}{3}
$$

```lean
theorem example : True := by
  trivial
```
"#
````

### Block-Level Structures

- Level 1 through 4 headings: `= TITLE` / ... / `==== TITLE` at the start of a line, where `TITLE` is the heading text
- Headings with custom labels: `== TITLE <label>`, where `label` is the label name
- Ordinary paragraphs
- Unordered lists: introduced by `-` at the start of a line
- Ordered lists: introduced by `+` at the start of a line
- Ordered lists with forced numbering: introduced by `n.` at the start of a line, where `n` is any natural number
- Block quotes: introduced by `>` at the start of a line
- Display formulas: enclosed by `$$` lines
- Full code blocks: enclosed by <code>```</code>, with optional language annotations

### Inline Structures

| Syntax | Meaning |
| --- | --- |
| `*text*` | Bold |
| `_text_` | Emphasis |
| `*_text_*` | Bold emphasis |
| `~~text~~` | Strikethrough |
| `__text__` | Underline |
| `==text==` | Highlight |
| `x^2^` | Superscript |
| `a~n~` | Subscript |
| `` `code` `` | Inline code |
| `$x + y$` | Inline math |
| `[text](url)` | Link |
| `@<label>` | Heading reference |
| `@thm:Lean.DeclarationName` | Theorem reference (fully qualified across modules) |
| `@fig:label` | Image or LaTeX component reference |

ProofScript exports both the ProofText source and the parsed semantic AST to the page JSON file. See the following documentation:

- [ProofText syntax in Chinese](docs/ProofText-Syntax-zh.md)
- [ProofText English syntax](docs/ProofText-Syntax.md)

## Automatic Reference Management

### Registering Publication Information

During page builds, `project_info` configures and selects an active project and persists it in the page-build `.olean`. Use `project_info "MyProject" { ... }` for a stable named identity. Without a target, it updates the active project or creates one using the module name. Projects support repeated updates, and a site can contain multiple projects. Verification builds skip this configuration command.

```lean
project_info {
  title := "Project Title",
  authors := ["Alice", "Bob"],
  description := "Project description",
  keywords := ["Lean", "logic"],
  year := "2026",
  base_url := "https://example.com",
  license := "..."
}
```

### Registering Theorem Information

Configure an existing theorem for subsequent uses with `theorem_info`. For a recorded declaration’s own title, use inline `(info := { ... })` immediately after its name:

```lean
theorem referencedTheorem (P : Prop) (h : P) : P := h

theorem_info referencedTheorem {
  name := "Displayed theorem name",
  tags := ["algebra", "foundational"],
  customField := "custom value"
}
```

```lean
@theorem mainResult (info := { name := "Main Result", tags := ["algebra"] })
    (P : Prop) (h : P) : P := script
  assumption
```

A later `theorem_info mainResult` affects later content and downstream modules; it does not rename the theorem component already created. `name` and `tags` control presentation; `project` stores a literal project name as `String`. Initial configuration binds the active project, and later ordinary field updates preserve that association. Unknown fields are placed in an `extra` object. All six Info commands support repeated updates, known-field checks, `none`, and `reset`. The Lean declaration name identifies the theorem in references and page anchors.

### Automatic Reference Collection

When `@theorem` records expression arguments, ProofScript collects declaration identities in first-occurrence order without duplication. Each proof and page component captures the current local metadata boundary. An `@references` component uses the configuration available when that component is created. Imported modules contribute all their final updates. Later local commands cannot change preceding content, including updates before `page_end`.

The following command locally disables automatic reference collection:

```lean
set_option referenceCollection false in
@theorem noReferences (P : Prop) (h : P) : P := script
  assumption
```

At any point on a page, use the `@references` command to output all reference information in the current staging area as a page component. This operation clears the reference staging area. The command does not accept a filename and does not write a separate references JSON file.

## Other Page Components

### Arbitrary LaTeX

`@latex` accepts arbitrary LaTeX source and generates SVG at compile time. `title` is required, `label` is optional, and other fields are stored in the metadata's `extra`:

```lean
@latex (
  title := "Commutative Diagram",
  label := "commutative-diagram"
) r#"
\begin{tikzpicture}
  \draw[->] (0,0) -- (1,0);
\end{tikzpicture}
"#
```

### Image Assets

`@figure` accepts a relative image asset path that includes a file extension. ProofScript exports only the path and extension; it does not read or copy the file:

```lean
@figure (
  title := "Architecture Diagram",
  label := "architecture",
  width := "wide"
) "assets/architecture.png"
```

### Custom Page Components

Page modules can call `addPageComponent` to register open-ended JSON components. Wrap the custom command's entire action in `whenPageBuild do`, including validation, JSON construction, and resource IO. Ordinary verification skips that action; `addPageComponent` also checks the mode before registering data, but cannot skip work its caller has already performed. See [the custom component example](Test/CustomComponentTest.lean).

For embedded computation, prefer the built-in `@computation`: it accepts component metadata, a downstream renderer ID, a Lean function declaration, and a renderer-specific JSON manifest:

```lean
def chooseOffset (large : Bool) : Nat := if large then 128 else 112

@computation {
  metadata := (title := "Finite Computation", label := "finite-computation"),
  renderer := "my-renderer/table-v1",
  function := chooseOffset,
  payload := r#"{"execution":{"backend":"table"},"results":[112,128]}"#
}
```

The output includes the declaration's full name, readable type, function body, and a structured Lean expression table. These fields are source information and intermediate artifacts; they do not promise a browser ABI for Lean compiler internals. Actual execution is jointly determined by the versioned renderer ID and manifest. See `docs/Frontend-Computation-Handoff-zh.md` for details.

Function provenance uses an independent structural capture and pure encoding boundary. The default command and `ComputationFunction.encode` / `ComputationComponent.encode` export `function.recordingVersion = "0.1.0"`, its own graph, `expressionRoots` and display companions, with paths relative to `function`. Consumers reject missing or old function versions and require a page rebuild. Component, pending manifest and bundle versions remain `0.0.0`; the `proofscript-json-v1` execution ABI is unchanged, and finalization preserves the complete function data.

`ComputationFunction` stores one `recording : RecordedValue`. Export functions and components through `.encode`, which returns `Except String Json`; neither type has an unchecked `ToJson` instance.

The computation entry point must have the form `α → β` or `α → Except String β`, with `Lean.FromJson α` and `Lean.ToJson β` instances available. The command generates a `String → String` wrapper and a pending build manifest; the actual Wasm resource is generated by a later bundler stage.

After generating pending manifests, run the following from the project root:

```bash
source "$HOME/Developer/emsdk/emsdk_env.sh"
PROOF_SCRIPT_LEAN_WASM_PREFIX=/path/to/lean-wasm-prefix \
  node /path/to/ProofScript/scripts/build-computations.mjs
```

This command generates a multi-entry bundle for each module under `.ProofScript/computations/bundles/`. Page resource backfilling is completed by the finalize stage:

```bash
node /path/to/ProofScript/scripts/finalize-computations.mjs
```

Finalization publishes resources to a content-addressed directory and updates page execution to `ready`. For the frontend implementation, see `docs/Frontend-Computation-Handoff-zh.md`.

For the implemented computation pipeline and renderer API, see `docs/Frontend-Computation-Handoff-zh.md`.

Frontend renderers can use the Fibonacci example in `docs/Embedded-Computation-Quickstart-zh.md` for an initial end-to-end test.

## Unified Info Configuration

See the [Info command reference (Chinese)](docs/Info-Commands-zh.md) for all builtin fields, defaults, template syntax, and examples.

All six commands are page-only configuration actions. In ordinary builds and IDE checking they skip field decoding, semantic validation and persistent updates; syntax parsing and module-mode consistency checks still apply. Existing targets and known fields retain editor navigation and highlighting, while unresolved metadata targets remain optional. See [IDE and language server support (Chinese)](docs/IDE-Support-zh.md). The rules and examples below describe page mode.

During page builds, they use typed models in `ProofScript.Info`, schema-derived fields, persistent updates and the same export protocol:

| Command | Model | Target |
| --- | --- | --- |
| `project_info` | `ProjectInfo` | Nonempty project name string; an omitted target selects the active project |
| `theorem_info` | `TheoremInfo` | Existing Lean theorem |
| `script_info` | `ScriptInfo` | Full registered ruleId, or an ID registered in this module |
| `def_info` | `DefinitionInfo` | Existing Lean constant |
| `var_info` | `VariableInfo` | Nonempty category string |
| `phrase_info` | `PhraseInfo` | Nonempty phrase key |

Commands may repeat and update only supplied fields. Invalid known fields, duplicate keys and unknown nested fields are errors. Unknown top-level fields enter `extra`, which accepts JSON literals; explicit extension keys have a separate namespace.

```lean
project_info "Course notes" { title := "Notes", authors := ["Alice"], edition := 1 }
project_info "Course notes" { title := "Revised notes", edition := 2 }
script_info ProofScript.Script.Basic.«rfl» { display := true, reviewed := true }
var_info "Nat" { default := "n", names := ["n", "m", "k"] }
phrase_info "forall" { template := [{ lang := "en", content := "${body} for every ${binder}" }] }
```

Project IDs use nonempty string literals, such as `"Course notes"`. They match the full text; namespaces and `open` do not change them. A theorem can select a configured project with `project := "Course notes"`.

Omitted fields retain their values. `none` is an Option value; `reset` masks inherited values and restores the schema default, or makes a required field absent. Ordinary lists and styles replace as a whole; templates merge by language. Extension fields update by key, and resetting a key removes it.

Lean resolves the actual import graph: later local writes and descendant writes override earlier ancestors. Independent branches combine different fields; conflicting values retain source diagnostics until resolved locally. Unconsumed partial configurations may remain incomplete. Each proof and page component uses the local metadata available at its creation, while imported modules contribute their complete final configuration. Standalone proofs use the same captured-boundary rule. `page_end` writes the page; it does not define configuration scope. Use inline `(info := { ... })` for a recorded theorem or lemma’s own metadata.

### Modules and Maintenance

`import ProofScript` includes scripts, pages and all presentation default modules; their Info registration occurs only in page builds. `ProofScript.Info` supplies metadata models and commands without the execution runtime; `Script.Registry` supplies pure registrations, `Script.Command` declares tactics, and `Page.Command` integrates pages. `Script.Basic` / `Mathlib.Scripts` contain execution and registrations; `Defaults.Script` / `Defaults.Lean2TeX` / `Mathlib.Info` provide presentation.

Use model names such as `ProofScript.Info.ProjectInfo` and source locations from `ProofScript.Foundation.SourceLocation`. Domain queries such as `resolveProjectInfo` explicitly take `Info.Query` with a module and optional boundary; exporters must query the requested owner. Queries cannot recover Info commands skipped during verification. Models, schemas, codecs, query APIs and explicit low-level recording remain available in both modes.

Add ordinary fields to the domain structure and derive `InfoSchema`. The `InfoSchema` typeclass holds the field rules directly. Register special merge and validation rules as an `InfoSchema` instance using the generated typed handles and `withOverrides!`; configuration consumers and JSON decoding then share the final rules. New value types implement `InfoCodec`, which extends Lean's `ToJson` and automatically supplies `FromJson` through its structured decoder. Use `toJson` / `fromJson?` for ordinary JSON consumers; Info validation retains `Diagnostic` paths and related fields. New domains also need an `InfoSpec` for the kind and dependency query, target resolution, a thin command and snapshot dependency handling. Consumers obtain field rules from the `InfoSchema` instance. The Python backend adapts frozen values for rendering. It does not maintain another input field list or replay configuration events.

Derivation currently supports ordinary nonrecursive structures without parameters, inheritance, dependent field types or dependent defaults. Custom Info commands should place all target resolution, field processing and registration inside `whenPageBuild do`; explicit low-level APIs such as `commitInfo` remain available in either mode. Configuration codecs remain separate from Recording capture APIs. `script_info` does not change recorders or output contracts. A ruleId includes its defining module; moving a registration changes its identity.

Public interface smoke tests are `Test.InfoCoreAPITest` and `Test.InfoAPITest`; `Test.InfoSchemaTest` checks that configuration consumers and JSON decoding apply the same rules; `Test/test_theorem_site_browser.mjs` checks theorem navigation on the generated example site. Internal Python scripts used for stage acceptance have been removed. See the [Chinese configuration section](README-zh.md#统一-info-配置) for query examples.

## Page Export

During page builds, `page_end` writes the page using each component’s captured configuration; subsequent page components are ignored. Info commands after `page_end` remain available to later code and importing modules in that mode. Build complete sites with `lake build MyLibrary:ps4html`. Info uses protocol `5.0.0`, recording uses `0.1.0`, and `info/index.json` is the completion index containing digests, schemas, snapshots and invocation-contract associations. Metadata is reconstructed from page-build `.olean` files; build steps generate page/proof/resource contents. Verification `.olean` files omit skipped Info data and must be rebuilt for page export. `ps4html make --cache` only reads completed exports; incomplete or incompatible caches require rebuilding.

## Requirements

### Required Environment

A complete installation of Lean + Lake + Elan.

### Optional LaTeX Environment

To use the `@latex` page component, the following commands must also be available on the system `PATH`:

```bash
latex --version
dvisvgm --version
```

## Current Limitations

- `script` permits only registered tactics with the `script_` prefix, plus named and anonymous branches; it does not support arbitrary Lean tactics.
- The automatic recorder supports only a limited set of parser argument forms; complex tactics require a handwritten `script_recorder` for complete data export, otherwise they emit a warning and display “Data not exported”.
- `complete_induction` is currently a strong-induction template for natural numbers.
- Automatic references scan only expressions touched by the recorder and collect only declarations with registered `theorem_info` metadata; this is not complete dependency analysis.
- ProofText references are checked only for syntax during elaboration; the referenced target is not guaranteed to exist. Cross-page indexes should be built by downstream consumers.
- ProofText is a small, specialized language and does not provide the full capabilities of Markdown or Typst.
- Pages follow a single-module, single-export model; components after `page_end` produce a warning and are ignored.
- LaTeX components require local `latex`, `dvisvgm`, and the relevant TeX packages; compilation failures interrupt Lean elaboration.
- Page source paths are currently usually absolute; source locations use UTF-8 byte offsets.
- Lean expression JSON is tightly coupled to Lean's internal AST and remains an extensible interface; use it with care across Lean versions.
- The current serialization of universe-level `max`/`imax` has a duplicate-key issue; do not rely on its left and right operands being fully distinguishable.

## Related Documentation

- [Chinese README](README-zh.md)
- [ProofText syntax in Chinese](docs/ProofText-Syntax-zh.md)
- [ProofText English syntax](docs/ProofText-Syntax.md)
- [Recording proof JSON Schema](docs/schema/recording-proof.schema.json)
- Info model and snapshot schemas are generated in `.ProofScript/info/schema/`.

## PS4HTML Site Generator

PS4HTML is the site generator included in this repository under [`tools/ps4html/`](tools/ps4html/). It consumes the pages, proof trees and resources exported by ProofScript; Lean remains responsible for checking proofs. PS4HTML provides:

- HTML pages organized by Lean module, a project index, module navigation, cross-page links, theorem dependencies and grouped references.
- ProofText, theorem and lemma components, structured proof steps and branches, source-code views, syntax highlighting, images and LaTeX-generated SVGs. Missing rendering rules and malformed resources produce visible fallbacks or diagnostics.
- Lean2TeX expression-to-TeX rendering with configurable macros and variable names; bilingual Chinese/English proof text, KaTeX display and interactive variable highlighting.
  - Build orchestration for Lean and embedded Lean/Wasm computations, plus browser Worker renderers, local preview serving and the `lean2tex-report.json` diagnostics report. The `script_info` command configures presentation in Lean; artifact manifests select frozen configurations and invocation contracts. Cached rendering does not execute Lean. For example, `script_info ProofScript.Script.Basic.renderCalc { renderer := «calc» }` selects the calculation renderer.

Install with `python3 -m pip install -e ./tools/ps4html` (Python 3.11+), then run `lake build MyLibrary:ps4html` in a Lean project and `ps4html serve` to preview `.PS4HTML/build/`. `ps4html make --cache` renders existing exports without rebuilding Lean. For computation toolchain requirements and limitations, see the [PS4HTML guide](tools/ps4html/README.md) and the [site example](examples/site/README.md).
