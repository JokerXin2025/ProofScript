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
The unified Info protocol is `9.0.0`; artifact manifests use version `9` and snapshot payloads use version `7`. The recording protocol is `0.3.0`, and invocation contracts use version `2` without output field declarations. Each script step is one object with framework fields `$ruleId`, `$goal_before`, `$goal_after`, and `$branches`. Artifact manifests select configuration snapshots and invocation contracts. Rebuild older caches with the Lake facet; see the [configuration and export documentation](#unified-info-configuration).

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

#page text r#"
= Introduction <introduction>

This page contains a recorded theorem. See @thm:mainResult.
"#

#page theorem mainResult (P : Prop) (h : P) : P := script
  assumption
theorem_info mainResult { name := "Main Result" }

#page references

#page end
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
| `let x := value` / `let x : T := value` | Introduces a local definition and records its type and value at this step | `let` | The value must have the declared type when one is supplied |
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
`#page theorem` script proofs; native `by` tactics are unchanged.

For `h : P ∧ Q ∧ R ∧ S`, `unpack_and ⟨hp, hq, rest⟩ := h` binds `hp : P`, `hq : Q`,
and `rest : R ∧ S`. It does not flatten left-nested conjunctions. Too many names fail when a
required right-hand remainder is no longer a conjunction. The singleton form
`unpack_and ⟨whole⟩ := h` requires a conjunction but simply renames the original hypothesis
(including allowing the same name), without splitting it. This is deliberately different from
native `rcases h with ⟨whole⟩`, which destructures the conjunction and names its first field;
for two or more names, the right-associated grouping agrees with native tuple patterns.

Recorded introduction parameters (`h`) and unpack outputs (`names`) contain all supplied
identifiers, while unpack's input `h` is recorded before splitting or renaming. Repeated
parameters remain arrays, including when they contain only one element.

`apply` accepts a term whose outermost proposition is an implication or equivalence. It applies only the outermost implication layer, so a chain such as `P → Q → R` produces the single premise goal `P`, with the remaining implication retained in the conclusion. For an equivalence, it selects the direction matching the current target:

```lean
theorem compose (P Q R : Prop) (hPQ : P → Q) (hQR : Q → R) (hP : P) : R := script
  apply hQR
  apply hPQ
  assumption
```

#### Strategies

Strategy tactics split a goal into branches with **semantic names**, thereby establishing the proof's high-level structure.
Complete strategy branches with `| case => …` or anonymous `·` branches. A bullet focuses the next remaining goal and must close it before the next branch. Both forms can be nested and mixed. Recordings retain full goal labels (for example, `left`/`right` for `split_and`) and assign unique export labels to anonymous branches when needed. For `claim`, the first bullet proves the claim (`proof`), and subsequent steps or a second bullet prove the continuation with the new hypothesis available.

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
| `cite proof` | Records proof constants from a proposition's proof without changing the goal |

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
#page theorem demo_remark {P : Prop} (h_P : P) : P := script
  remark "This is a simple proof"
  assumption
```

##### LaTeX (SVG)

Proofs provide a unified `latex` metadata tactic. Like the page component `#page latex`, it accepts metadata and arbitrary LaTeX source. During recording, it invokes the local LaTeX toolchain to generate SVG and writes the metadata, source, and SVG into the proof tree. For example:

```lean
#page theorem proofWithDiagram (P : Prop) (h : P) : P := script
  latex (title := "Derivation Diagram", label := "proof-diagram") r#"
    \begin{tikzpicture}
      \draw[->] (0,0) -- (1,0);
    \end{tikzpicture}
  "#
  assumption
```

To ensure that the precompiler works correctly, make sure TeX Live is installed locally. This is the proof-level tactic; use the `#page latex` command described below for arbitrary page-level LaTeX.

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

For builtin tactics, `ProofScript.Builtin.Script` provides execution, registrations, recorders and page presentation together. The public `ProofScript` entry imports all defaults, whose Info commands are active only in page mode. See [Unified Info Configuration](#unified-info-configuration). The currently wrapped tactics, in alphabetical order, are:

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

Parameters use `RecordValue α` instances, where `α` is the actual Lean type of the macro binding. Builtins include `TSyntax \`term`, `TSyntax \`ident`, `TSyntax \`str`, `TSyntax \`num`, `location`, `rwRuleSeq`, `simpArgs` and `optConfig`; `Array`, `Option` and `Syntax.TSepArray` compose element instances automatically. A custom syntax category defines an instance for its own `TSyntax` type. Unsupported anonymous syntax keeps automatic recording unavailable and should use a handwritten recorder; it is never silently converted to text. `num` records a JSON number; a numeral parsed as `term` remains a Lean expression reference.

The declaration configuration supports:

| Option | Meaning |
| --- | --- |
| `intro`, `clear` | Mark named declaration parameters as available after or before execution. |
| `strategy` | Mark a branching tactic. |
| `continuation` | Name the goal that continues the parent recording, for example ``continuation := `rest``. |

`params`, per-parameter timing, context selectors and field renaming are removed. Use a handwritten recorder when a declaration needs custom capture order or field names. Parameters are read through their actual `RecordValue α` instance.

```lean
script_macro finishRule
  "finish" proof:term => `(tactic| exact $proof:term)

script_recorder finishRule => do
  record_param "evidence" proof
  execute_tactic
```

Use `script_recorder <id> => ...` when output requires custom capture logic, such as elaborated calc steps or generated media. The recorder receives the bindings from the original `script_macro` or `script_elab` declaration:

```lean
open ProofScript

script_recorder finishRule => do
  Lean.Elab.Tactic.withRollback do
    record_goal "$goal_before"
    record_param "evidence" proof
  execute_tactic
  record_goal "$goal_after"
```

The recorder ID selects the registration; its parameter bindings and tactic keyword come from that registration. Its writes define the available output fields, which have no separate declaration or schema. Custom parameter readers and conversions of existing values implement `RecordValue.record`. When automatic recording is unavailable because a category lacks an instance or a parameter parser is unsupported, and no handwritten recorder is bound, recording emits a warning and execution continues. The step exports the reserved `$ruleId: "ProofScript.unrecorded"` and its original keyword in `name`; strategy branches are still recorded separately. PS4HTML displays a red “Data not exported” box.

`script_info` uses the final configuration of the proof's module and all its transitive imports. Local updates after a proof or `#page end` also affect that module's proofs; downstream overrides affect downstream content. Templates use field objects, are merged per language, and fall back to the first language. Imported updates use the full ID, such as `script_info MyRules.finishRule`. The renderer reads actual emitted names and nested paths such as `${rules_before.0.expression}` and `${loc_before.hypotheses}`. Lean preserves template strings verbatim, including unknown paths, `${}` and unclosed `${...`; it checks the surrounding template structure and its compatibility with ordinary or strategy registrations. Rendering determines how placeholders are interpreted and how errors are handled. PS4HTML rejects missing fields and invalid paths when consuming actual steps, including validation during bundle loading, and displays empty or unclosed placeholders as text. An absent optional parameter is exported as `null`; a capture error aborts the step. Structured values and text are HTML-escaped. A specialized `renderer` uses the merged configuration. Overloads sharing a keyword require distinct IDs.

The public DSL and runtime API are exported by `import ProofScript.Script.Recording`; `import ProofScript` also includes the script declaration commands. `script_recorder foo => do ...` automatically opens one recording destination in the main goal's context. Its body is ordinary Lean `TacticM` code, so it supports variables, conditionals, loops and custom execution. The recorder itself adds no goal snapshots and executes no tactic implicitly; metadata-only recorders are supported.

| Statement | Meaning |
| --- | --- |
| `record_param "field" value` | Record a parsed parameter with the `ProofScript.ParamRecorder` instance scope. |
| `record_param "field" value (goal := name)` | Resolve the `Name` value and record the parameter in that goal's context. |
| `record_value key value` | Record an existing value with the `ProofScript.ValueRecorder` instance scope, without collecting references. |
| `record_goal "field"` / `record_goal "field" (goal := name)` | Record the main goal or resolve the specified goal name. |
| `execute_tactic` | Execute this invocation's selected original tactic with its original arguments. |

For example, capture a hypothesis before clearing it, write an existing metadata variable, then attempt another capture:

```lean
open Lean ProofScript

script_macro snapshotThenClear "snapshot_then_clear" h:ident => `(tactic| clear $h:ident)
script_recorder snapshotThenClear => do
  Lean.Elab.Tactic.withRollback do
    record_goal "$goal_before"
    record_param "evidence_before" h
  let moduleName := toJson (← getEnv).mainModule
  record_value "module" moduleName
  execute_tactic
  Lean.Elab.Tactic.withRollback do
    record_goal "$goal_after"
    record_param "evidence_after" h
```

`record_param` and `record_value` use the same internal writer but open different instance scopes for their individual calls. `ProofScript.ParamRecorder` provides syntax-parameter readers; `ProofScript.ValueRecorder` provides existing-value conversions. Shared `Array`, `List` and `Option` instances follow their element's scope. This is a default instance-visibility distinction, not a strict type-level restriction: explicitly opening a scope or providing another instance can change which values are accepted. Statement order determines the Lean state observed. A genuine read or conversion failure is reported with the field name and propagated to the surrounding `TacticM`; it is never converted to `null`. An absent `Option` value is valid and is recorded as `null`. Each recording operation restores temporary elaboration state before committing its value. Wrap a sequence in `withRollback` when its fields must roll back together after a later failure. Recording saves values without collecting literature references, including expressions containing theorem constants and nested containers. `dependencyCollection` does not affect these operations. Pass distinct field names for manual before and after snapshots.

All handwritten recorders use `script_recorder foo => do ...`. The generator reads the original script registration's `strategy` setting, manages the recording destination and prepares strategy branches after the body succeeds.

`record_value` supports `RecordedValue`, `Json`, `String`, `Bool`, `Nat`, `Int` and `Expr`, with composing instances for arrays, lists and options. `RecordValue.record value context` returns `TacticM RecordedValue`; the instance decides which facts to capture, and containers propagate the context to their elements. Pure-value instances may ignore it. `none` preserves the caller's context; an explicit goal is focused during conversion. The named-target `record_param` macro resolves the name before passing that goal to the internal writer. Handwritten `script_recorder` code chooses custom capture logic and timing. Conversion is isolated and required. Use `recordValueFrom` to save a complete value before execution and commit it afterward:

```lean
-- Inside a script_recorder do block:
let saved ← recordValueFrom "evidence" (expression h.raw)
execute_tactic
record_value "evidence" saved
```

This preserves the value read before execution and writes it afterward. Literature references are collected separately from recorded values.

`RecordedValue` is a pure value with four forms: plain JSON, a native `Lean.Expr`, an array, or an object. `RecordedValue.expression expr` stores the expression and its existing metadata without contextual queries. The default `Expr` conversion calls `recordExpression`, which instantiates assigned expression and universe metavariables and always adds free-variable names, naming type descriptors and available trusted source locations as scalar native `MData` along the original structure. Complete declaration types, local definition values and application binder descriptors are not collected. Containers combine their element conversions; an existing `RecordedValue` passes through unchanged.

The recording format is `0.3.0`. `recordedProofJson` assigns node IDs once at final proof export and emits the node table and explicit `expressionRoots`. `encodeOwner` provides the same pure boundary for other owners. Scalar metadata is exported as `mdata.data`, with one structural child `mdata.expr`; syntax values and empty wrappers are omitted. PS4HTML enters the graph only at registered roots; ordinary JSON remains data. Rendering configuration dependencies follow native structural expressions and effective naming-type annotations without expanding declarations. Recorded parameters and values do not populate the literature-reference staging area. The format is specified by the [proof JSON Schema](docs/schema/recording-proof.schema.json). Old caches must be regenerated with `lake build MyLibrary:ps4html`; `ps4html make --cache` does not migrate them.

Custom conversions choose their output at capture time. Use `recordExpression` for the default expression reader:

```lean
structure Evidence where
  term : Lean.Expr
  label : String

namespace ProofScript.ValueRecorder
scoped instance : RecordValue Evidence where
  record value _ := do
    return .object [
      ("term", ← recordExpression value.term),
      ("label", .plain (Lean.toJson value.label))]
end ProofScript.ValueRecorder
```

To supply your own expression and native `MData`, return `RecordedValue.expression expr` instead. `record_value "term" expr` uses the default `Expr` instance; `record_value "term" (RecordedValue.expression expr)` preserves the supplied expression. The default reader adds `ProofScript.userName`, `ProofScript.type` and available `ProofScript.sourceFile/sourceStart/sourceStop`. The naming descriptor is a string on free variables and binder nodes; `decl:<name>` also freezes that declaration's `def_info` for naming, without adding a citation. All scalar metadata, including custom keys, is always exported without an enable switch. Nested keys use the outermost value; a source range belongs only to that occurrence and is not inherited by structural children. The dedicated `let` recorder exports `name`, `type` and `value` when the definition is introduced; later variable references do not copy those fields or generate declaration tooltips.

`def_info.auto_arity := true` is resolved to numeric indices from the declaration's native binders when Lean freezes the configuration. With `auto_arity := false`, template indices address the complete raw application arguments. Dynamic `#*` templates are not supported.

Strategies also use `script_recorder foo => do ...`. The runner supplies proof branch labels and the registration supplies the named continuation, so handwritten recorders do not read or repeat this routing information:

```lean
script_macro rememberTrue (kind := strategy, continuation := `rest)
  "remember_true" h:ident => `(tactic| script_claim $h:ident : True)

script_recorder rememberTrue => do
  record_goal "$goal_before"
  execute_tactic
  record_param "hypothesis" h (goal := `rest)
```

The block prepares branches automatically after its body succeeds, including after an early `return`. It resolves the final goals and calls `prepareBranches` before closing the recording destination. An exception rolls back the block without preparing branches. The script runner then advances branch proofs and merges them into the parent record.

A capture without a target uses the caller's context. Both `record_param` and `record_goal` select a goal through `(goal := name)`, where `name` is a `Name` value, for example ``record_param "h_after" h (goal := `rest)`` or ``record_goal "rest_goal" (goal := `rest)``. Names use exact matching first and a unique suffix match second. Missing or ambiguous targets are errors.

Automatic ordinary recorders write `$goal_before` and `$goal_after`; automatic strategy recorders write only `$goal_before`. Each expression field stores its native expression and the annotations selected by its reader. Handwritten recorders write goals with `record_goal`. When no goal remains, returns `null`; ordinary value writes never add citations. Template paths should match the fields supplied by their recorder.

The builtin `cases_by` records `subject` before execution, and `contra` records `hypothesis` afterward. Both are display values written with `record_value`; their `h` arguments use `record_param`. `embed` records its parameters and goal snapshots, and replays its inner recorders for proof data. These recording operations do not collect literature references.

Default captures before execution use `<parameter>_before` field names. Builtin templates therefore use `change.equation_before`, `exact_proj.value_before` and `provide.data_before`. The `let` recorder reads `value` from the newly introduced local definition through parameter capture, and writes `name` and `type` as ordinary values. The `calc` and `infer` recorders assemble `init` and `chain` at their respective capture points and commit them in one transaction. See the [phase 6 migration notes](docs/Script-Binding-Phase6-zh.md) for fields and validation examples.

Automatic ordinary recorders capture ordinary parameters before and after execution; `intro` parameters are captured only after execution and `clear` parameters only before it. Strategy recorders capture non-`intro` parameters before execution and skip `intro` parameters. Handwritten DSL code schedules captures by statement position. User parameter names and recording keys must be nonempty and cannot begin with `$`. Other keys and recordable values are accepted; PS4HTML checks rendering requirements. Within one step, a later successful write to the same field replaces the earlier value; a failed write leaves the previous value intact. Declaration checks reject invalid names and conflicting `intro`/`clear` configuration.

Successful blocks preserve tactic execution; failed blocks roll back Lean state, recorded values and references. Nested blocks reserve stable destinations, so the outer block remains writable afterward. Pure data can be recorded after the final goal closes. External IO, such as LaTeX compilation and resource files, is outside Lean's rollback boundary. For custom execution, call ordinary `TacticM` operations in place of `execute_tactic`; reusable recorder helpers take `[RecordingStep]` to use their caller's scope.

See the runnable [recording API example](examples/recording/RecordingAPI.lean). Adding a category requires a `scoped instance` of `RecordValue (TSyntax \`categoryName)` inside `ProofScript.ParamRecorder`; arrays and optional inputs compose it automatically.

Defining script tactics in the style of `macro_rules` / `elab_rules` is not currently supported.

### Exporting Proof Trees

Declare a page theorem with `#page theorem` or `#page lemma`, then run `lake build MyLibrary:ps4html` to export it. In page JSON, they use the tags `"theorem"` and `"lemma"`, respectively.
Published proof data is available under `.PS4HTML/inputs/<package>/<library>/.ProofScript/proofs/` in the Lean project.
At the top level, every proof tree contains `schemaVersion` and the complete Lean source in `code`. Script-mode trees also contain the expression table `expressions`, the registered expression paths `expressionRoots` and recorded step array `proof`. Each array entry is a single step object containing `$ruleId`, captured fields, and any strategy `$branches`; each branch's `proof` uses the same format. Default ordinary recorders include `$goal_before` and `$goal_after` as expression references or `null`; default strategy recorders include only `$goal_before`.

Within `:= script`, use unprefixed DSL names directly; the framework automatically adds the `script_` prefix and checks every step, recording it during page builds. `:= by` accepts ordinary Lean tactics but cannot use ProofScript's script tactics. Its exported tree retains only `schemaVersion`, `module` and the complete `code`, and does not output `expressions`, `expressionRoots` or `proof`. Literature-reference collection is separate from recording; see [Automatic Reference Collection](#automatic-reference-collection).

In every build mode, `#page theorem` and `#page lemma` expand to `script_theorem_impl` / `script_lemma_impl`, which check the proof synchronously in a differently named internal `def`, followed by a native theorem that directly references it. The proof runs once, while the native declaration provides the IDE completion checkmark. Proof failures report “证明存在错误”. Metadata, proof resources and dependency identities use the public theorem name.

Ordinary `lake build` and IDE checking use the execution version of `script` or native `by` and skip recording and page export. Page builds record within the internal `def`. In both modes, `cite` checks that its complete argument is a proof of a proposition; it does not require `theorem_info`. All five Info commands skip field decoding, semantic validation and configuration registration in verification mode; their syntax must still parse. Both modes retain editor references, including best-effort resolution of metadata targets. Explicit low-level recorder APIs retain their recording capability.

Lemmas can appear among a declaration's dependencies in the upper half of its graph and have their own graphs. The lower half lists theorems using the current declaration and excludes lemmas. The underlying proof dependency data remains complete.

`lake build MyLibrary:ps4html` automatically enables `proofScript.pageBuild` and compiles the required source packages, including the ProofScript framework and configuration-bearing dependencies, in `.lake/ps4html/<package>/<library>/`. This restores framework presentation defaults as well as user configuration. It preserves ordinary `.lake/build/` artifacts and reuses base dependencies that need no page or Info data, such as Mathlib. Page builds currently record the source modules afresh; a module cannot change build mode midway through its commands.

The repository's default `lake build` builds the ProofScript library.

## ProofText

`#page text` accepts a Lean string literal and parses it as ProofText, a dedicated lightweight markup language with syntax broadly similar to Typst.

````lean
#page text r#"
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

Configure theorem metadata only through `theorem_info`, after the target declaration exists. It also sets a recorded declaration's own title, even when placed after `#page end`:

```lean
theorem referencedTheorem (P : Prop) (h : P) : P := h

theorem_info referencedTheorem {
  name := "Displayed theorem name",
  tags := ["algebra", "foundational"],
  customField := "custom value"
}
```

```lean
#page theorem mainResult (P : Prop) (h : P) : P := script
  assumption
theorem_info mainResult { name := "Main Result", tags := ["algebra"] }
```

The declaration and its metadata update are separate commands. Native `/-- ... -/` doc comments remain available to Lean and the editor. `name` and `tags` control presentation; `project` stores a literal project name as `String`. Explicit project assignments take precedence. Otherwise, final consumption selects the unique local project in the theorem's first registering module, or the unique project in its transitive imports when there is no local project. Recorded declarations register in their defining module; ordinary Lean declarations register where their first `theorem_info` appears. Multiple candidates require an explicit `project`; `none` or `reset` explicitly removes ownership. Unknown fields are placed in an `extra` object. All five Info commands support repeated updates, known-field checks, `none`, and `reset`. The Lean declaration name identifies the theorem in references and page anchors.

### Automatic Reference Collection

`record_param` and `record_value` save values without adding literature references, even when expressions or nested containers contain theorem constants. `dependencyCollection` does not affect parameter or value recording. Rendering configuration dependencies are resolved separately, and theorem navigation reads final-proof facts.

During page builds, `#page theorem` and `#page lemma` collect automatic references after their proofs complete, using the same scan for `script` and `by`. The scan expands generated helpers and compiler auxiliary proofs, preserves user declarations as dependency boundaries, and keeps constants only when `Meta.isProp info.type` holds for their declaration type. Each automatic reference has `isDependency := true`. A definition such as `def MyProp : Prop := ...` is excluded; a definition whose type is a proposition is retained. `dependencyCollection false` disables automatic reference collection.

`cite` always checks its complete argument with `Meta.isProp (inferType expression)`, then applies the same declaration-type filter to its constants. It accepts proof-valued definitions, applications, lambdas and local proofs, without requiring `theorem_info`. Collected names have `isDependency := false` and are staged even when `dependencyCollection` is false. Page-theorem transactions also persist them in `DeclarationFacts.proofRefs`, independently of the page staging area. References merge by name, and an automatic dependency takes precedence over a citation. Failed transactions restore the previous references and facts.

Named proof artifacts export the complete `proofRefs` array, including citations and references outside the source project. Each item contains a lossless Lean `name` and a required Boolean `isDependency`. The navigation field `proofDependencies` contains only automatic references whose final project matches the source theorem's project; proof-valued definitions follow the same rule as theorems. `dependencyCollection false` therefore also disables automatic navigation edges. Both arrays are covered by `proofFactsDigest`, and consumers check the projection against frozen target metadata. Manifest `9` requires these fields; rebuild older caches with `lake build MyLibrary:ps4html`.

Each proof and page component uses its owner module's final metadata together with all transitive imports. An `#page references` component collects declaration identities where it appears and resolves their metadata at final export. Later local Info commands, including commands after `#page end`, affect preceding content. Reused upstream proof artifacts retain their upstream snapshots; downstream configuration does not alter them.

The following command locally disables automatic reference collection while retaining a manual citation:

```lean
theorem citedResult : True := True.intro
theorem_info citedResult { name := "Cited result" }

set_option dependencyCollection false in
#page theorem manualReference (P : Prop) (h : P) : P := script
  cite citedResult
  exact h

#page references
```

At any point on a page, use the `#page references` command to output all reference information in the current staging area as a page component. This operation clears the reference staging area. The command does not accept a filename and does not write a separate references JSON file.
References without configured theorem metadata are collected but omitted from this display.

The [recording example](examples/recording/README.md) records a theorem used only for display and then adds an explicit citation. The [dependency page](examples/site/PS4HTMLDemo/Dependencies.lean) shows both automatic references and citations collected with automatic collection disabled. These literature references are separate from Lean's editor symbol references; see [IDE support](docs/IDE-Support-zh.md).

## Other Page Components

### Arbitrary LaTeX

`#page latex` accepts arbitrary LaTeX source and generates SVG at compile time. `title` is required, `label` is optional, and other fields are stored in the metadata's `extra`:

```lean
#page latex (
  title := "Commutative Diagram",
  label := "commutative-diagram"
) r#"
\begin{tikzpicture}
  \draw[->] (0,0) -- (1,0);
\end{tikzpicture}
"#
```

### Image Assets

`#page figure` accepts a relative image asset path that includes a file extension. ProofScript exports only the path and extension; it does not read or copy the file:

```lean
#page figure (
  title := "Architecture Diagram",
  label := "architecture",
  width := "wide"
) "assets/architecture.png"
```

### Custom Page Components

Use `page_component` to define a page component command. It is available through `import ProofScript` or `import ProofScript.Page.Component.Command`:

```lean
open Lean ProofScript

page_component "myWidget" source:str => do
  when_page_build
    let value := json% { "text": $(source.getString) }
    addPageComponent source.raw "myWidget" value

#page myWidget "Hello"
```

The first string names the component after `#page`; `end` is reserved for `#page end` and cannot be registered. Subsequent arguments use native `elab` syntax, including optional arguments, repetitions and `sepBy`. Component names do not become reserved words for ordinary Lean identifiers. Identical or overlapping syntax follows native `elab` overloading and parser rules.

The code after `=>` has type `CommandElabM Unit` and runs in both modes. `when_page_build` is a `doElem` statement available only in a component definition's context. Only its indented block runs in page builds; returning to the surrounding indentation resumes ordinary code. Even initial pure calculations in that block are delayed, and its local variables stay inside the block. Editor annotations can remain outside it:

```lean
page_component "myFigure" metadata:componentMeta path:str => do
  addComponentMetadataInfo metadata.raw
  when_page_build
    let value := json% { path: $(path.getString) }
    addPageComponent path.raw "myFigure" value
```

Put validation, JSON construction and resource IO inside `when_page_build`. The author chooses the JSON, labels and registration calls. `#page end` closes the current module's page in both modes. A later component fails at entry before any component code runs, including code outside `when_page_build`. Page builds also persist the page draft; ordinary verification does not create one. Ordinary Lean declarations and Info commands may follow, and later Info still participates in final export. The closed state does not propagate through imports.

`figure`, `latex`, `text`, `references`, `#page computation`, `#page theorem` and `#page lemma` all use the unified page-component entry point and early page-closure check, while retaining their field-specific validation and proof/computation logic. The old `@figure`, `@latex`, `@text`, `@references`, `@computation`, `@theorem`, `@lemma` and `page_end` spellings have no compatibility aliases. The lower-level `addPageComponent` remains available, but does not replace the command's entry check around its entire action. See the [command definition](ProofScript/Page/Component/Command.lean) and [component API](ProofScript/Page/Component/Core.lean).

For embedded computation, prefer the built-in `#page computation`: it accepts component metadata, a downstream renderer ID, a Lean function declaration, and a renderer-specific JSON manifest:

```lean
def chooseOffset (large : Bool) : Nat := if large then 128 else 112

#page computation {
  metadata := (title := "Finite Computation", label := "finite-computation"),
  renderer := "my-renderer/table-v1",
  function := chooseOffset,
  payload := r#"{"execution":{"backend":"table"},"results":[112,128]}"#
}
```

The output includes the declaration's full name, readable type, function body, and a structured Lean expression table. These fields are source information and intermediate artifacts; they do not promise a browser ABI for Lean compiler internals. Actual execution is jointly determined by the versioned renderer ID and manifest. See `docs/Frontend-Computation-Handoff-zh.md` for details.

Function provenance uses native expressions with scalar `MData` and an independent pure encoding boundary. The default command and `ComputationFunction.encode` / `ComputationComponent.encode` export `function.recordingVersion = "0.3.0"`, its own expression node table, and `expressionRoots` with paths relative to `function`. The function's declaration name and readable type are explicit fields of this recorder. Consumers reject missing or old function versions and require a page rebuild. Component, pending manifest and bundle versions remain `0.0.0`; the `proofscript-json-v1` execution ABI is unchanged, and finalization preserves the complete function data.

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

Frontend renderers can use the [Fibonacci example](examples/site/PS4HTMLDemo/Fibonacci.lean) for an initial end-to-end test.

## Unified Info Configuration

See the [Info command reference (Chinese)](docs/Info-Commands-zh.md) for all builtin fields, defaults, template syntax, and examples.

All five commands are page-only configuration actions. In ordinary builds and IDE checking they skip field decoding, semantic validation and persistent updates; syntax parsing and module-mode consistency checks still apply. Existing targets and known fields retain editor navigation and highlighting, while unresolved metadata targets remain optional. See [IDE and language server support (Chinese)](docs/IDE-Support-zh.md). The rules and examples below describe page mode.

During page builds, they use typed models in `ProofScript`, schema-derived fields, persistent updates and the same export protocol:

| Command | Model | Target |
| --- | --- | --- |
| `project_info` | `ProjectInfo` | Nonempty project name string; an omitted target selects the active project |
| `theorem_info` | `TheoremInfo` | Existing Lean theorem |
| `script_info` | `ScriptInfo` | Full registered ruleId, or an ID registered in this module |
| `def_info` | `DefinitionInfo` | Existing Lean constant |
| `phrase_info` | `PhraseInfo` | Nonempty phrase key |

Commands may repeat and update only supplied fields. Invalid known fields, duplicate keys and unknown nested fields are errors. Unknown top-level fields enter `extra`, which accepts JSON literals; explicit extension keys have a separate namespace.

```lean
project_info "Course notes" { title := "Notes", authors := ["Alice"], edition := 1 }
project_info "Course notes" { title := "Revised notes", edition := 2 }
 script_info «rfl» { display := true, reviewed := true }
def_info Nat { var_name := "n" }
phrase_info "forall" { template := [{ lang := "en", content := "${body} for every ${binder}" }] }
```

Project IDs use nonempty string literals, such as `"Course notes"`. They match the full text; namespaces and `open` do not change them. A theorem can select a configured project with `project := "Course notes"`.

`def_info` has no required fields: `{}` preserves existing settings, and `var_name` controls the prefix for unnamed variables of that declaration's type. An empty prefix uses the first character of the declaration name's last component. Defaults are `Nat/Int → n`, `Rat → q`, and `Real → x` in the Mathlib configuration. Proof variables always use `h`, independently of `theorem_info`. Usable names are preserved; generated names share a counter per prefix, start at 1 and render as `\textcolor{gray}{n_{1}}`. Unassigned metavariables render as `\textcolor{gray}{?}`. See the [variable system guide](tools/ps4html/Variable-System.md) for type descriptors, binder identities and template usage.

Omitted fields retain their values. `none` is an Option value; `reset` masks inherited values and restores the schema default, or makes a required field absent. Ordinary lists and styles replace as a whole; templates merge by language. Extension fields update by key, and resetting a key removes it.

Lean resolves the actual import graph: later local writes and descendant writes override earlier ancestors. Independent branches combine different fields; conflicting values retain source diagnostics until resolved locally. Import order does not choose between conflicting values. Unconsumed partial configurations may remain incomplete. Each proof and page component uses the final metadata of its owner module and all transitive imports. Standalone proofs follow the same rule. `#page end` closes page content collection; later Info commands still participate in final export.

### Modules and Maintenance

`import ProofScript` includes scripts, pages and all presentation default modules; their Info registration occurs only in page builds. `ProofScript.Info` supplies metadata models and commands without the execution runtime; `Script.Registry` supplies pure registrations, `Script.Command` declares tactics, and `Page.Command` integrates pages. `Builtin.Script` contains builtin execution, registrations, recorders and presentation; `Mathlib.Scripts` contains Mathlib execution and registrations, and `Mathlib.Info` provides their presentation.

Use model names such as `ProofScript.ProjectInfo` and source locations from `ProofScript.SourceLocation`. Domain queries such as `resolveProjectInfo` explicitly take `ProofScript.Query` with a module; exporters must query the requested owner after compilation completes. Queries inside source commands can only read the environment already elaborated. Queries cannot recover Info commands skipped during verification. Models, schemas, codecs, query APIs and explicit low-level recording remain available in both modes. Declaration namespaces are independent of module paths: `ProofScript.Info` remains an import module, while its declarations belong to `ProofScript`.

Add ordinary fields to the domain structure and derive `InfoSchema`. The `InfoSchema` typeclass holds the field rules directly. Register special merge and validation rules as an `InfoSchema` instance using the generated typed handles and `withOverrides!`; configuration consumers and JSON decoding then share the final rules. New value types implement `InfoCodec`, which extends Lean's `ToJson` and automatically supplies `FromJson` through its structured decoder. Use `toJson` / `fromJson?` for ordinary JSON consumers; Info validation retains `Diagnostic` paths and related fields. New domains also need an `InfoSpec` for the kind and dependency query, target resolution, a thin command and snapshot dependency handling. Consumers obtain field rules from the `InfoSchema` instance. The Python backend adapts frozen values for rendering. It does not maintain another input field list or replay configuration events.

Derivation currently supports ordinary nonrecursive structures without parameters, inheritance, dependent field types or dependent defaults. Custom Info commands should place all target resolution, field processing and registration inside `whenPageBuild do`; explicit low-level APIs such as `commitInfo` remain available in either mode. Configuration codecs remain separate from Recording capture APIs. `script_info` does not change recorders or output contracts. A ruleId includes its defining module; moving a registration changes its identity.

See the [Chinese configuration section](README-zh.md#统一-info-配置) for query examples.

## Page Export

During page builds, `#page end` closes page content collection and persists the draft in `.olean`; subsequent page components fail before their bodies run in either build mode. It does not write page JSON. Final export generates page JSON directly from that draft and its owner module's final Info, including Info commands after `#page end`. Repeated exports can overwrite the generated page without reading a previous page file. Build complete sites with `lake build MyLibrary:ps4html`. Info uses protocol `9.0.0`, artifact manifest version `9` and snapshot payload version `7`; recording uses `0.3.0`, and invocation contracts use version `2` without output field declarations. Consumers read actual step data. `info/index.json` is the completion index containing digests, schemas, snapshots and invocation-contract associations. Metadata and page drafts are reconstructed from page-build `.olean` files. Snapshot queries contain only the owning `module`; historical boundary fields are rejected. Compilation generates proof and resource files, and export generates the final pages. Verification `.olean` files omit skipped Info data and must be rebuilt for page export. Older manifests must also be rebuilt through Lean. `ps4html make --cache` only reads completed exports; incomplete or incompatible caches require rebuilding.

## Requirements

### Required Environment

A complete installation of Lean + Lake + Elan.

### Optional LaTeX Environment

To use the `#page latex` page component, the following commands must also be available on the system `PATH`:

```bash
latex --version
dvisvgm --version
```

## Current Limitations

- `script` permits only registered tactics with the `script_` prefix, plus named and anonymous branches; it does not support arbitrary Lean tactics.
- The automatic recorder supports only a limited set of parser argument forms; complex tactics require a handwritten `script_recorder` for complete data export, otherwise they emit a warning and display “Data not exported”.
- `complete_induction` is currently a strong-induction template for natural numbers.
- Literature lists display declarations with registered `theorem_info` metadata. Automatic references come from completed proofs; parameter and value recording do not add literature references.
- ProofText references are checked only for syntax during elaboration; the referenced target is not guaranteed to exist. Cross-page indexes should be built by downstream consumers.
- ProofText is a small, specialized language and does not provide the full capabilities of Markdown or Typst.
- Each module has one page draft; components after `#page end` fail before any component code runs in both modes. Final page export may be repeated.
- LaTeX components require local `latex`, `dvisvgm`, and the relevant TeX packages; compilation failures interrupt Lean elaboration.
- Page source paths are currently usually absolute; source locations use UTF-8 byte offsets.
- Lean expression JSON is tightly coupled to Lean's internal AST and remains an extensible interface; use it with care across Lean versions.
- The current serialization of universe-level `max`/`imax` has a duplicate-key issue; do not rely on its left and right operands being fully distinguishable.

## Related Documentation

- [Chinese README](README-zh.md)
- [ProofText syntax in Chinese](docs/ProofText-Syntax-zh.md)
- [ProofText English syntax](docs/ProofText-Syntax.md)
- [Recording API simplification plan in Chinese](docs/Recording-API-Simplification-Plan-zh.md)
- [Recording module architecture](docs/Recording-Architecture-zh.md)
- [Script binding refactor: phase 5 in Chinese](docs/Script-Binding-Phase5-zh.md)
- [Recording proof JSON Schema](docs/schema/recording-proof.schema.json)
- [Recording function JSON Schema](docs/schema/recording-function.schema.json)
- Info model and snapshot schemas are generated in `.ProofScript/info/schema/`.

## PS4HTML Site Generator

PS4HTML is the site generator included in this repository under [`tools/ps4html/`](tools/ps4html/). It consumes the pages, proof trees and resources exported by ProofScript; Lean remains responsible for checking proofs. PS4HTML provides:

- HTML pages organized by Lean module, a project index, module navigation, cross-page links, theorem dependencies and grouped references.
- ProofText, theorem and lemma components, structured proof steps and branches, source-code views, syntax highlighting, images and LaTeX-generated SVGs. Missing rendering rules and malformed resources produce visible fallbacks or diagnostics.
- Lean2TeX expression-to-TeX rendering with configurable macros and variable names; bilingual Chinese/English proof text, KaTeX display and interactive variable highlighting.
   - Build orchestration for Lean and embedded Lean/Wasm computations, plus browser Worker renderers, local preview serving and the `lean2tex-report.json` diagnostics report. The `script_info` command configures presentation in Lean; artifact manifests select frozen configurations and invocation contracts. Cached rendering does not execute Lean. For example, `script_info «renderCalc» { renderer := «calc» }` selects the calculation renderer.

Install with `python3 -m pip install -e ./tools/ps4html` (Python 3.11+), then run `lake build MyLibrary:ps4html` in a Lean project and `ps4html serve` to preview `.PS4HTML/build/`. `ps4html make --cache` renders existing exports without rebuilding Lean. For computation toolchain requirements and limitations, see the [PS4HTML guide](tools/ps4html/README.md) and the [site example](examples/site/README.md).
