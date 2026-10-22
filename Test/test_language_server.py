"""Exercise ProofScript semantic information through Lean's actual LSP server.

Run after ``lake build ProofScript ProofScript.Script.Embed`` with::

    python3 -m unittest Test/test_language_server.py -v

No editor, Python dependencies, network, LaTeX, or Wasm compiler is required.
Documents are opened from memory and page artifacts go to a temporary directory.
"""

from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
import queue
import re
import shutil
import subprocess
import tempfile
import threading
import time
import unittest


ROOT = Path(__file__).resolve().parents[1]
TIMEOUT = 90
EMBED_ANCHOR = "embed recordedScript P embedInput as embeddedLinked"


class LeanServer:
    """Small synchronous JSON-RPC client that also services server requests."""

    def __init__(self, output_root: Path):
        self.messages = queue.Queue()
        self.diagnostics = {}
        self.next_id = 0
        self.stderr = tempfile.TemporaryFile()
        environment = os.environ.copy()
        environment["PROOF_SCRIPT_OUTPUT_ROOT"] = str(output_root)
        for name in ("PS4HTML_BUILD_SESSION", "PROOF_SCRIPT_BUILD_MANIFEST"):
            environment.pop(name, None)
        self.process = subprocess.Popen(
            ["lake", "env", "lean", "--server"], cwd=ROOT, env=environment,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=self.stderr,
        )
        threading.Thread(target=self._read, daemon=True).start()
        self.request("initialize", {
            "processId": None, "rootUri": ROOT.as_uri(), "capabilities": {},
            "initializationOptions": {"hasWidgets": False},
        })
        self.notify("initialized", {})

    def _read(self):
        try:
            while True:
                headers = {}
                while True:
                    line = self.process.stdout.readline()
                    if not line:
                        raise EOFError("Lean server closed stdout")
                    if line in (b"\r\n", b"\n"):
                        break
                    key, value = line.decode("ascii").split(":", 1)
                    headers[key.lower()] = value.strip()
                length = int(headers["content-length"])
                body = self.process.stdout.read(length)
                if len(body) != length:
                    raise EOFError("truncated JSON-RPC message")
                self.messages.put(json.loads(body))
        except BaseException as error:
            self.messages.put(error)

    def _send(self, message):
        body = json.dumps(message, ensure_ascii=False).encode("utf-8")
        self.process.stdin.write(f"Content-Length: {len(body)}\r\n\r\n".encode() + body)
        self.process.stdin.flush()

    def notify(self, method, params):
        self._send({"jsonrpc": "2.0", "method": method, "params": params})

    def request(self, method, params):
        self.next_id += 1
        request_id = self.next_id
        self._send({"jsonrpc": "2.0", "id": request_id,
                    "method": method, "params": params})
        deadline = time.monotonic() + TIMEOUT
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError(f"Lean server timed out handling {method}")
            try:
                message = self.messages.get(timeout=remaining)
            except queue.Empty as error:
                raise TimeoutError(f"Lean server timed out handling {method}") from error
            if isinstance(message, BaseException):
                raise RuntimeError(str(message))
            if "method" in message and "id" in message:
                # Lean may ask for dynamic capabilities or workspace settings.
                result = None
                if message["method"] == "workspace/configuration":
                    result = [None] * len(message.get("params", {}).get("items", []))
                elif message["method"] == "workspace/applyEdit":
                    result = {"applied": False}
                self._send({"jsonrpc": "2.0", "id": message["id"], "result": result})
            elif message.get("method") == "textDocument/publishDiagnostics":
                notification = message["params"]
                uri = notification["uri"]
                if notification.get("isIncremental", False):
                    self.diagnostics.setdefault(uri, []).extend(notification["diagnostics"])
                else:
                    self.diagnostics[uri] = notification["diagnostics"]
            elif message.get("id") == request_id:
                if "error" in message:
                    raise RuntimeError(f"{method}: {message['error']}")
                return message.get("result")

    def open(self, document):
        self.notify("textDocument/didOpen", {"textDocument": {
            "uri": document.uri, "languageId": "lean4", "version": 1,
            "text": document.text,
        }})
        self.request("textDocument/waitForDiagnostics", {"uri": document.uri, "version": 1})
        # Diagnostics and usable semantic snapshots can arrive at different times.
        deadline = time.monotonic() + TIMEOUT
        while not self.at("hover", document, document.find("#check Nat.succ", "Nat.succ")):
            errors = [item for item in self.diagnostics.get(document.uri, [])
                      if item.get("severity", 1) == 1]
            if errors:
                raise RuntimeError("fixture has no usable semantic snapshot: " +
                                   json.dumps(errors, ensure_ascii=False))
            if time.monotonic() >= deadline:
                raise TimeoutError("document semantic information did not become ready")
            time.sleep(0.05)
        self.request("textDocument/waitForDiagnostics", {"uri": document.uri, "version": 1})

    def at(self, method, document, token):
        position = dict(token.start)
        # Query inside a token, away from adjacent syntax and whitespace.
        position["character"] += min(1, token.end["character"] - position["character"] - 1)
        return self.request("textDocument/" + method, {
            "textDocument": {"uri": document.uri}, "position": position,
        })

    def close(self):
        try:
            if self.process.poll() is None:
                self.request("shutdown", None)
                self.notify("exit", None)
                self.process.wait(timeout=10)
        finally:
            if self.process.poll() is None:
                self.process.kill()
                self.process.wait(timeout=10)
            self.process.stdin.close()
            self.process.stdout.close()
            self.stderr.close()


@dataclass(frozen=True)
class Token:
    start: dict
    end: dict

    def key(self):
        return range_key({"start": self.start, "end": self.end})


def range_key(value):
    return tuple(value[side][part] for side in ("start", "end")
                 for part in ("line", "character"))


def contains(value, point):
    start = value["start"]["line"], value["start"]["character"]
    end = value["end"]["line"], value["end"]["character"]
    return start <= (point["line"], point["character"]) < end


class Document:
    def __init__(self, mode, text):
        self.uri = (ROOT / "Test" / f"LanguageServer_{mode}.lean").as_uri()
        # Lean assigns unsaved, non-package documents this external module name.
        self.module_name = f"«external:{self.uri}»"
        self.text = text

    def position(self, index):
        before = self.text[:index]
        return {"line": before.count("\n"),
                "character": len(before.rsplit("\n", 1)[-1].encode("utf-16-le")) // 2}

    def find(self, anchor, spelling=None, *, occurrence=0):
        if self.text.count(anchor) != 1:
            raise AssertionError(f"fixture anchor must be unique: {anchor!r}")
        spelling = spelling or anchor
        index = self.text.index(anchor)
        local = -1
        for _ in range(occurrence + 1):
            local = anchor.index(spelling, local + 1)
        index += local
        return Token(self.position(index), self.position(index + len(spelling)))

    def keyword(self, rule_id, spelling):
        marker = f"-- keyword: {rule_id}\n"
        start = self.text.index(marker) + len(marker)
        end = self.text.find("-- keyword:", start)
        block = self.text[start:end if end >= 0 else len(self.text)]
        # The first line starting with the keyword is its intended invocation.
        match = re.search(r"(?m)^  (" + re.escape(spelling) + r")(?=\s|$)", block)
        if match is None:
            raise AssertionError(f"no invocation for {rule_id}")
        index = start + match.start(1)
        return Token(self.position(index), self.position(index + len(spelling)))


# One valid invocation for every registration in Script/Basic.lean, including
# overloads and no-op annotations. Ordinary examples avoid invoking page-only
# resource recorders (the LaTeX sample therefore needs no external compiler).
BASIC_CASES = [
    ("assumption", "assumption", "example (P : Prop) (hp : P) : P := script\n  assumption"),
    ("change", "change", "example (n : Nat) : (fun x => x) n = n := script\n  change n = n\n  rfl"),
    ("contradiction", "contradiction", "example (P : Prop) (hp : P) (hnp : ¬ P) : True := script\n  contradiction"),
    ("exfalso", "exfalso", "example (impossible : False) : True := script\n  exfalso\n  exact impossible"),
    ("omega", "omega", "example (n : Nat) : n + 1 > n := script\n  omega"),
    ("rfl", "rfl", "example (n : Nat) : n = n := script\n  rfl"),
    ("symm", "symm", "example (a b : Nat) (hab : a = b) : b = a := script\n  symm\n  exact hab"),
    ("trivial", "trivial", "example : True := script\n  trivial"),
    ("simp", "simp", "example (n : Nat) : 0 + n = n := script\n  simp [Nat.zero_add]"),
    ("rw", "rw", "example (n : Nat) : 0 + n = n := script\n  rw [Nat.zero_add]"),
    ("unfold", "unfold", "example (n : Nat) : ideIdentity n = n := script\n  unfold ideIdentity\n  rfl"),
    ("have", "have", "example (P : Prop) (hp : P) : P := script\n  have haveLinked := hp\n  exact haveLinked"),
    ("exact", "exact", "example (P : Prop) (exactInput : P) : P := script\n  exact exactInput"),
    ("exact_proj", "exact_proj", "example (P Q : Prop) (projectionInput : P ∧ Q) : P := script\n  exact_proj projectionInput"),
    ("intro", "intro", "example (P : Prop) : P → P := script\n  intro introLinked\n  exact introLinked"),
    ("left", "left", "example : True ∨ False := script\n  left\n  trivial"),
    ("right", "right", "example : False ∨ True := script\n  right\n  trivial"),
    ("unpack_and", "unpack_and", "example (P Q : Prop) (andInput : P ∧ Q) : P := script\n  unpack_and ⟨andLinked, andOther⟩ := andInput\n  exact andLinked"),
    ("unpack_iff", "unpack_iff", "example (P Q : Prop) (iffInput : P ↔ Q) : P → Q := script\n  unpack_iff ⟨iffLinked, iffOther⟩ := iffInput\n  exact iffLinked"),
    ("obtain_exist", "obtain_exist", "example (existInput : ∃ n : Nat, n = n) : ∃ n : Nat, n = n := script\n  obtain_exist ⟨existLinked, existProof⟩ := existInput\n  provide existLinked"),
    ("obtain_exist'", "obtain_exist", "example (threeInput : ∃ n : Nat, n = n ∧ n = n) : ∃ n : Nat, n = n := script\n  obtain_exist ⟨threeLinked, threeLeft, threeRight⟩ := threeInput\n  provide threeLinked"),
    ("funext", "funext", "example : (fun n : Nat => n) = (fun n : Nat => n) := script\n  funext funextLinked\n  change funextLinked = funextLinked\n  rfl"),
    ("provide", "provide", "example : ∃ n : Nat, n = n := script\n  provide 0"),
    ("apply", "apply", "example (P Q : Prop) (applyInput : P → Q) (hp : P) : Q := script\n  apply applyInput\n  exact hp"),
    ("quot_induction", "quot_induction", "example (r : Nat → Nat → Prop) (q : Quot r) : True := script\n  quot_induction q with quotientLinked\n  trivial"),
    ("claim", "claim", "example (P : Prop) (hp : P) : P := script\n  claim claimLinked : P\n  | proof => exact hp\n  exact claimLinked"),
    ("claimExistTwo", "claim_exist", "example (claimInput : ∃ n : Nat, n = n) : ∃ n : Nat, n = n := script\n  claim_exist ⟨claimTwoLinked, claimTwoProof⟩ : ∃ n : Nat, n = n\n  | proof => exact claimInput\n  provide claimTwoLinked"),
    ("claimExistThree", "claim_exist", "example (claimThreeInput : ∃ n : Nat, n = n ∧ n = n) : ∃ n : Nat, n = n := script\n  claim_exist ⟨claimThreeLinked, claimThreeLeft, claimThreeRight⟩ : ∃ n : Nat, n = n ∧ n = n\n  | proof => exact claimThreeInput\n  provide claimThreeLinked"),
    ("witness", "witness", "example : ∃ n : Nat, n = 0 := script\n  witness\n  | data => provide 0\n  | proof => rfl"),
    ("split_and", "split_and", "example : True ∧ True := script\n  split_and\n  | left => trivial\n  | right => trivial"),
    ("split_and!", "split_and!", "example : True ∧ True ∧ True := script\n  split_and!\n  | goalI => trivial\n  | goalII => trivial\n  | goalIII => trivial"),
    ("split_iff", "split_iff", "example (P : Prop) : P ↔ P := script\n  split_iff\n  | suffice => trivial\n  | necess => trivial"),
    ("cases_by", "cases_by", "example (P Q : Prop) (caseInput : P ∨ Q) : True := script\n  cases_by caseInput\n  | left => trivial\n  | right => trivial"),
    ("cases_by!", "cases_by!", "example (P Q : Prop) (caseBangInput : P ∨ Q) : True := script\n  cases_by! caseBangInput\n  | goalI => trivial\n  | goalII => trivial"),
    ("cases_on", "cases_on", "example (flag : Bool) : True := script\n  cases_on flag\n  | false => trivial\n  | true => trivial"),
    ("contra", "contra", "example (P : Prop) (np : ¬ P) : P → False := script\n  contra contraLinked\n  | proof => exact (np contraLinked)"),
    ("induction", "induction", "example (n : Nat) : n = n := script\n  induction n\n  | zero => rfl\n  | succ => rfl"),
    ("complete_induction", "complete_induction", "example (n : Nat) : n = n := script\n  complete_induction n\n  | zero => rfl\n  | succ => rfl"),
    ("constructor", "constructor", "example : True := script\n  constructor"),
    ("constructor!", "constructor!", "example : True := script\n  constructor! True.intro"),
    ("remark", "remark", 'example : True := script\n  remark "IDE remark"\n  trivial'),
    ("svg", "svg", 'example : True := script\n  svg "<svg/>"\n  trivial'),
    ("latex", "latex", 'example : True := script\n  latex (title := "IDE formula") "x"\n  trivial'),
    ("admit", "admit", 'example : False := script\n  admit "IDE informal proof"'),
    ("cite", "cite", "example : True := script\n  cite LinkConstants.literature\n  trivial"),
    ("renderCalc", "calc", "example (calcInput : Nat) : calcInput = calcInput := script\n  calc\n    calcInput = calcInput := rfl"),
    ("infer", "infer", "example (P : Prop) (inferInput : P) : P := script\n  infer\n    P => P := inferInput"),
]


MATHLIB_IMPORTS = (
    "Mathlib.Topology.Basic",
    "Mathlib.MeasureTheory.MeasurableSpace.Basic",
)

MATHLIB_PREAMBLE = """set_option linter.unusedTactic false
set_option linter.unusedVariables false
"""

MATHLIB_CASES = [
    ("continuity", "continuity", """example {α : Type} [TopologicalSpace α] : Continuous (id : α → α) := script
  continuity
"""),
    ("exact_mod_cast", "exact_mod_cast", """example (n m : Nat) (h : n ≤ m) : (n : Int) ≤ m := script
  exact_mod_cast h
"""),
    ("field", "field", """example : (2 : Rat) / 3 + 1 / 3 = 1 := script
  field
"""),
    ("gcongr", "gcongr", """example (a b : Rat) (h : a ≤ b) : a + 1 ≤ b + 1 := script
  gcongr
"""),
    ("itauto", "itauto", """example (P Q : Prop) (h : P ∧ Q) : Q ∧ P := script
  itauto
"""),
    ("itauto!", "itauto!", """example (P Q : Prop) (h : P ∧ Q) : Q ∧ P := script
  itauto!
"""),
    ("linarith", "linarith", """example (a b : Rat) (h : a ≤ b) : a ≤ b + 1 := script
  linarith
"""),
    ("linarith!", "linarith!", """example (a b : Rat) (h : a ≤ b) : a ≤ b + 1 := script
  linarith!
"""),
    ("measurability", "measurability", """example {α : Type} [MeasurableSpace α] : Measurable (id : α → α) := script
  measurability
"""),
    ("nlinarith", "nlinarith", """example (x : Rat) : 0 ≤ x * x := script
  nlinarith [sq_nonneg x]
"""),
    ("nlinarith!", "nlinarith!", """example (x : Rat) : 0 ≤ x * x := script
  nlinarith! [sq_nonneg x]
"""),
    ("norm_cast", "norm_cast", """example : ((1 : Nat) : Int) = 1 := script
  norm_cast
"""),
    ("norm_num", "norm_num", """example : (2 : Rat) + 3 = 5 := script
  norm_num
"""),
    ("positivity", "positivity", """example : (0 : Rat) < 1 := script
  positivity
"""),
    ("push_cast", "push_cast", """example (a b : Nat) : ((a + b : Nat) : Int) = (a : Int) + b := script
  push_cast
  rfl
"""),
    ("qify", "qify", """example (a b : Nat) : (a : Rat) ≤ b ↔ a ≤ b := script
  qify
"""),
    ("rify", "rify", """example (a b : Nat) : (a : Real) ≤ b ↔ a ≤ b := script
  rify
"""),
    ("ring", "ring", """example (x y : Rat) : x + y = y + x := script
  ring
"""),
    ("ring!", "ring!", """example (x y : Rat) : x + y = y + x := script
  ring!
"""),
    ("ring_nf", "ring_nf", """example (x : Rat) : x + 0 = x := script
  ring_nf
"""),
    ("ring_nf!", "ring_nf!", """example (x : Rat) : x + 0 = x := script
  ring_nf!
"""),
    ("tauto", "tauto", """example (P Q : Prop) (h : P ∧ Q) : Q ∧ P := script
  tauto
"""),
    ("tauto_set", "tauto_set", """example (s t : Set Nat) : s ∩ t = t ∩ s := script
  tauto_set
"""),
    ("wlog", "wlog", """example (x y : Nat) : True := script
  wlog h : x ≤ y generalizing x y with ih
  · exact ih y x (le_of_not_ge h)
  · trivial
"""),
    ("wlog!", "wlog!", """example (x y : Nat) : True := script
  wlog! h : x ≤ y generalizing x y with ih
  · exact ih y x (le_of_lt h)
  · trivial
"""),
    ("zify", "zify", """example (a b : Nat) : (a : Int) ≤ b ↔ a ≤ b := script
  zify
"""),
]


PREAMBLE = r'''import ProofScript
import ProofScript.Script.Embed
set_option proofScript.pageBuild PAGE_MODE
set_option linter.unusedVariables false
set_option linter.unusedTactic false
set_option linter.unreachableTactic false

open Lean Elab Tactic ProofScript

project_info "IDE language server" { title := "IDE language server" }
namespace LinkConstants
def original : Nat := 0
def alternate : Nat := 1
theorem literature : True := True.intro
-- namespace-relative resolution
def_info original {}
end LinkConstants
open LinkConstants
open LinkConstants renaming original → renamedOriginal
-- open and renamed-open resolution
def_info original { «alias» := some alternate }
def_info renamedOriginal {}
theorem_info literature {}
theorem_info literature { name := "IDE literature" }
def aliasEquality (n m : Nat) := n = m
def unwrapIdentity (n : Nat) := n
def_info aliasEquality { «alias» := some Eq }
def_info unwrapIdentity { unwrap := some 0 }
def styledIdentity (n : Nat) := n
def_info styledIdentity { styles := [{ name := "IDE nested style", mode := formula, template := "n" }] }
var_info "IDE.Nat" { default := "n", names := ["n"] }
phrase_info "IDE.phrase" { template := [{ lang := "en", content := "${body}" }] }

script_macro macroRule (intro := [introduced])
"ide_intro" introduced:ident => `(tactic| intro $introduced:ident)
script_recorder macroRule "ide_intro" introduced:ident => recording_step do
  execute_recorded
script_info macroRule {}
script_info MODULE_NAME.macroRule {}
script_info macroRule { renderer := none }
script_info macroRule { template := [{ lang := "en", tag := "Custom intro", content := "intro" }] }

script_elab elabRule (clear := [subject],
  params := [label(codec := name, timing := once, failure := required)])
"ide_exact" subject:term "," label:ident => withMainContext do
  let _ := label.getId
  let goal ← getMainGoal
  let expression ← elabTermEnsuringType subject (← goal.getType)
  goal.assign expression
  replaceMainGoal []
script_recorder elabRule "ide_exact" subject:term "," label:ident => recording_step do
  execute_recorded
script_info elabRule {}
script_info elabRule { template := [{ lang := "en", tag := "Custom exact", content := "exact" }] }

example (P : Prop) : P → P := script
  ide_intro customLinked
  exact customLinked
example (P : Prop) (customInput : P) : P := script
  ide_exact customInput, labelValue
example (P : Prop) : P → P := by
  script_ide_intro nativeLinked
  exact nativeLinked
example (P : Prop) (nativeInput : P) : P := by
  script_ide_exact nativeInput, labelValue

@theorem recordedScript (P : Prop) (recordedInput : P) : P := script
  have recordedLinked := recordedInput
  exact recordedLinked
@theorem recordedBy (info := { name := "IDE by proof" }) (P : Prop) (byInput : P) : P := by
  have byLinked := byInput
  exact byLinked
@lemma recordedLemma (lemmaInput : True) : True := by
  exact lemmaInput
@theorem recordedEmbedded (P : Prop) (embedInput : P) : P := script
  embed recordedScript P embedInput as embeddedLinked
  exact embeddedLinked

@theorem recordedBinders (P : Prop) (binderInput : P) : P → P := script
  intro recordedIntro
  claim recordedClaim : P
  | proof => exact recordedIntro
  have recordedHave := recordedClaim
  exact recordedHave

@theorem recordedFunction : (fun n : Nat => n) = (fun n : Nat => n) := script
  funext recordedArgument
  change recordedArgument = recordedArgument
  rfl

@theorem recordedContra (P : Prop) (recordedNegative : ¬ P) : P → False := script
  contra recordedAssumption
  | proof => exact (recordedNegative recordedAssumption)

@theorem recordedRewrite (recordedNumber : Nat) : 0 + recordedNumber = recordedNumber := script
  rw [Nat.zero_add]

@theorem recordedCustom (P : Prop) : P → P := script
  ide_intro runtimeCustom
  ide_exact runtimeCustom, runtimeLabel

@theorem recordedUnpack (P Q : Prop) (recordedAndInput : P ∧ Q) : P := script
  unpack_and ⟨recordedAndLeft, recordedAndRight⟩ := recordedAndInput
  exact recordedAndLeft

@theorem recordedExist (recordedExistInput : ∃ n : Nat, n = n ∧ n = n) : ∃ n : Nat, n = n := script
  obtain_exist ⟨recordedWitness, recordedLeft, recordedRight⟩ := recordedExistInput
  provide recordedWitness

@theorem recordedClaimExist (recordedClaimExistInput : ∃ n : Nat, n = n) : ∃ n : Nat, n = n := script
  claim_exist ⟨recordedClaimWitness, recordedClaimProof⟩ : ∃ n : Nat, n = n
  | proof => exact recordedClaimExistInput
  provide recordedClaimWitness
#check recordedScript
#check recordedBy
#check recordedLemma

def ideIdentity (n : Nat) : Nat := n

def ideComputation (flag : Bool) : Nat := if flag then 1 else 0
@computation {
  metadata := (title := "IDE computation"),
  renderer := "proofscript/test-json-v1",
  function := ideComputation,
  payload := "{}" }
'''


EXTRA = r'''
-- The other contra branch delegates to native by_contra.
example (P : Prop) (positive : P) : P := script
  contra negativeLinked
  | proof => exact (negativeLinked positive)

-- All three explicitly named obtain binders must retain source references.
example (allInput : ∃ n : Nat, n = n ∧ n = n) : ∃ n : Nat, n = n ∧ n = n := by
  script_obtain_exist ⟨allWitness, allLeft, allRight⟩ := allInput
  exact ⟨allWitness, allLeft, allRight⟩

#check Nat.succ
'''


def make_document(mode):
    preamble = PREAMBLE.replace("PAGE_MODE", "true" if mode == "page" else "false")
    preamble = preamble.replace("MODULE_NAME", Document(mode, "").module_name)
    source = preamble + "\n\n" + "\n\n".join(
        f"-- keyword: {rule_id}\n{proof}" for rule_id, _, proof in BASIC_CASES
    ) + "\n" + EXTRA
    return Document(mode, source)


def make_mathlib_document(mode):
    source = "import ProofScript\n" + "".join(
        f"import {module}\n" for module in MATHLIB_IMPORTS)
    source += f"set_option proofScript.pageBuild {'true' if mode == 'page' else 'false'}\n"
    source += MATHLIB_PREAMBLE + "\n" + "\n\n".join(
        f"-- keyword: {rule_id}\n{proof}" for rule_id, _, proof in MATHLIB_CASES)
    return Document("mathlib_" + mode, source + "\n#check Nat.succ\n")


@unittest.skipUnless(shutil.which("lake"), "Lean's Lake executable is not installed")
class LanguageServerTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="proofscript-lsp-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.server = LeanServer(Path(cls.temporary.name))
        cls.addClassCleanup(cls.server.close)
        cls.documents = {}
        for mode in ("verification", "page"):
            document = make_document(mode)
            cls.server.open(document)
            cls.documents[mode] = document
        cls.mathlib_documents = {}
        for mode in ("verification", "page"):
            document = make_mathlib_document(mode)
            cls.server.open(document)
            cls.mathlib_documents[mode] = document

    def definitions(self, document, token):
        result = self.server.at("definition", document, token) or []
        if isinstance(result, dict):
            result = [result]
        return [(value.get("targetUri", value.get("uri")),
                 value.get("targetSelectionRange", value.get("range"))) for value in result]

    def assert_hover(self, document, token, expected=None):
        result = self.server.at("hover", document, token)
        self.assertIsNotNone(result, f"missing hover at {token}")
        if expected:
            self.assertIn(expected, json.dumps(result, ensure_ascii=False))

    def assert_definition(self, document, reference, target, uri=None):
        definitions = self.definitions(document, reference)
        self.assertTrue(any(location == (uri or document.uri) and contains(span, target.start)
                            for location, span in definitions),
                        f"wrong definition for {reference}: {definitions}; expected {target}")

    def assert_links(self, document, anchors, spelling):
        tokens = [document.find(anchor, spelling) if isinstance(anchor, str)
                  else document.find(anchor[0], spelling, occurrence=anchor[1])
                  for anchor in anchors]
        expected = {token.key() for token in tokens}
        for token in tokens:
            with self.subTest(position=token.start):
                self.assert_hover(document, token, spelling)
                highlights = self.server.at("documentHighlight", document, token) or []
                actual = {range_key(item["range"]) for item in highlights}
                self.assertEqual(actual, expected)
                self.assert_definition(document, token, tokens[0])

    def test_documents_have_no_errors(self):
        documents = [(f"{module}/{mode}", document)
                     for module, collection in (("Basic", self.documents),
                                                ("Mathlib", self.mathlib_documents))
                     for mode, document in collection.items()]
        for mode, document in documents:
            with self.subTest(mode=mode):
                errors = [item for item in self.server.diagnostics.get(document.uri, [])
                          if item.get("severity", 1) == 1]
                self.assertEqual(errors, [], json.dumps(errors, ensure_ascii=False, indent=2))

    def test_every_registration_has_a_fixture(self):
        for module, cases in (("Script/Basic", BASIC_CASES),
                              ("Mathlib/Scripts", MATHLIB_CASES),
                              ("Script/Embed", [("embed", "embed", EMBED_ANCHOR)])):
            with self.subTest(module=module):
                source = (ROOT / f"ProofScript/{module}.lean").read_text()
                registered = {escaped or simple for escaped, simple in re.findall(
                    r"(?m)^script_(?:elab|macro)\s+(?:«([^»]+)»|(\w+))", source)}
                self.assertEqual({rule for rule, _, _ in cases}, registered)

    def test_all_basic_keywords_have_semantic_targets(self):
        for mode, document in self.documents.items():
            for rule_id, keyword, _ in BASIC_CASES:
                with self.subTest(mode=mode, rule=rule_id):
                    token = document.keyword(rule_id, keyword)
                    self.assert_hover(document, token)
                    definitions = self.definitions(document, token)
                    self.assertTrue(any(uri.endswith("/ProofScript/Script/Basic.lean")
                                        for uri, _ in definitions), definitions)
            with self.subTest(mode=mode, rule="embed"):
                token = document.find(EMBED_ANCHOR, "embed")
                self.assert_hover(document, token)
                definitions = self.definitions(document, token)
                self.assertTrue(any(uri.endswith("/ProofScript/Script/Embed.lean")
                                    for uri, _ in definitions), definitions)

    def test_all_mathlib_keywords_have_semantic_targets(self):
        for mode, document in self.mathlib_documents.items():
            for rule_id, keyword, _ in MATHLIB_CASES:
                with self.subTest(mode=mode, rule=rule_id):
                    token = document.keyword(rule_id, keyword)
                    self.assert_hover(document, token)
                    definitions = self.definitions(document, token)
                    self.assertTrue(any(uri.endswith("/ProofScript/Mathlib/Scripts.lean")
                                        for uri, _ in definitions), definitions)

    def test_metadata_targets_and_aliases(self):
        for mode, document in self.documents.items():
            original = document.find("def original : Nat", "original")
            alternate = document.find("def alternate : Nat", "alternate")
            literature = document.find("theorem literature : True", "literature")
            references = [
                ("def_info original {}", "original", original),
                ("def_info original { «alias» := some alternate }", "original", original),
                ("def_info renamedOriginal {}", "renamedOriginal", original),
                ("def_info original { «alias» := some alternate }", "alternate", alternate),
                ("theorem_info literature {}", "literature", literature),
                ("cite LinkConstants.literature", "LinkConstants.literature", literature),
            ]
            for anchor, spelling, target in references:
                with self.subTest(mode=mode, reference=anchor, spelling=spelling):
                    token = document.find(anchor, spelling)
                    self.assert_hover(document, token)
                    self.assert_definition(document, token, target)
                    highlights = self.server.at("documentHighlight", document, token) or []
                    self.assertIn(target.key(), {range_key(item["range"]) for item in highlights})

    def test_registration_ids_and_keyword_invocations(self):
        for mode, document in self.documents.items():
            for kind, registration, keyword, anchor in (
                    ("macro", "macroRule", "ide_intro", "ide_intro customLinked"),
                    ("elab", "elabRule", "ide_exact", "ide_exact customInput, labelValue")):
                with self.subTest(mode=mode, kind=kind):
                    binder = document.find(f"script_{kind} {registration}", registration)
                    references = [
                        document.find(f"script_recorder {registration}", registration),
                        document.find(f"script_info {registration} {{}}", registration),
                        document.find(anchor, keyword),
                        document.find("script_" + anchor.replace("custom", "native"), "script_" + keyword),
                    ]
                    if kind == "macro":
                        references.append(document.find(
                            f"script_info {document.module_name}.macroRule {{}}",
                            f"{document.module_name}.macroRule"))
                    for token in references:
                        self.assert_hover(document, token)
                        self.assert_definition(document, token, binder)
                    highlights = self.server.at("documentHighlight", document, binder) or []
                    actual = {range_key(item["range"]) for item in highlights}
                    for token in [binder, *references]:
                        self.assertIn(token.key(), actual)

    def test_metadata_keys_have_projection_definitions_and_completion(self):
        fields = [
            ('project_info "IDE language server" { title := "IDE language server" }',
             "title", "ProjectInfo", "Project"),
            ('theorem_info literature { name := "IDE literature" }',
             "name", "TheoremInfo", "Theorem"),
            ('unwrap := some 0',
             "unwrap", "DefinitionInfo", "Definition"),
            ('var_info "IDE.Nat" { default := "n", names := ["n"] }',
             "default", "VariableInfo", "Variable"),
            ('phrase_info "IDE.phrase" { template := [{ lang := "en", content := "${body}" }] }',
             "template", "PhraseInfo", "Phrase"),
            ('script_info macroRule { renderer := none }',
             "renderer", "ScriptInfo", "Script"),
        ]
        for mode, document in self.documents.items():
            for anchor, key, model, module in fields:
                with self.subTest(mode=mode, model=model, field=key):
                    token = document.find(anchor, key)
                    self.assert_hover(document, token, f"{model}.{key}")
                    definitions = self.definitions(document, token)
                    self.assertTrue(any(uri.endswith(f"/ProofScript/Info/{module}.lean")
                                        for uri, _ in definitions), definitions)
                    result = self.server.request("textDocument/completion", {
                        "textDocument": {"uri": document.uri},
                        "position": {"line": token.start["line"],
                                     "character": token.start["character"] + 2},
                        "context": {"triggerKind": 1},
                    }) or []
                    items = result.get("items", []) if isinstance(result, dict) else result
                    self.assertIn(key, [item["label"] for item in items])

    def test_configuration_parameters_link_to_parser_binders(self):
        groups = [
            (["introduced:ident => `(tactic| intro $introduced:ident)",
              "intro := [introduced]", "intro $introduced:ident"], "introduced"),
            (['"ide_exact" subject:term "," label:ident => withMainContext do',
              "clear := [subject]", "elabTermEnsuringType subject"], "subject"),
            (['"ide_exact" subject:term "," label:ident => withMainContext do',
              "label(codec := name, timing := once, failure := required)", "let _ := label.getId"], "label"),
        ]
        for mode, document in self.documents.items():
            for anchors, spelling in groups:
                with self.subTest(mode=mode, parameter=spelling):
                    self.assert_links(document, anchors, spelling)

    def test_script_configuration_fields_and_enum_values(self):
        fields = [
            ("intro := [introduced]", "intro", "ScriptCfg.intro"),
            ("clear := [subject]", "clear", "ScriptCfg.clear"),
            ("params := [label(codec := name, timing := once, failure := required)]",
             "params", "ScriptCfg.params"),
            ("label(codec := name, timing := once, failure := required)",
             "timing", "ParamCfg.timing"),
            ("label(codec := name, timing := once, failure := required)",
             "failure", "ParamCfg.failure"),
            ("label(codec := name, timing := once, failure := required)",
             "once", "CaptureTiming.once"),
            ("label(codec := name, timing := once, failure := required)",
             "required", "FailurePolicy.required"),
        ]
        for mode, document in self.documents.items():
            for anchor, spelling, symbol in fields:
                with self.subTest(mode=mode, symbol=symbol):
                    token = document.find(anchor, spelling)
                    self.assert_hover(document, token, symbol)
                    self.assertTrue(self.definitions(document, token))

    def test_nested_and_inline_metadata(self):
        samples = [
            ('metadata := (title := "IDE computation")', "title", "ComponentMetadata.title"),
            ('latex (title := "IDE formula") "x"', "title", "ComponentMetadata.title"),
            ('info := { name := "IDE by proof" }', "name", "TheoremInfo.name"),
            ('name := "IDE nested style", mode := formula, template := "n"',
             "mode", "DefinitionStyle.mode"),
            ('name := "IDE nested style", mode := formula, template := "n"',
             "template", "DefinitionStyle.template"),
            ('lang := "en", tag := "Custom intro", content := "intro"',
             "lang", "OrdinaryScriptTemplate.lang"),
        ]
        for mode, document in self.documents.items():
            for anchor, spelling, symbol in samples:
                with self.subTest(mode=mode, metadata=anchor):
                    token = document.find(anchor, spelling)
                    self.assert_hover(document, token, symbol)
                    self.assertTrue(self.definitions(document, token))

    def test_verification_components_skip_payload_work_and_keep_metadata_semantics(self):
        document = Document("components", r'''import ProofScript
set_option proofScript.pageBuild false
@figure (title := "Unloaded figure") "/missing/figure.svg"
@latex (label := "uncompiled-latex") "\\undefinedLatexCommand"
@computation { metadata := (title := "Skipped computation"), function := missingFunction }
#check Nat.succ
''')
        self.server.open(document)
        errors = [item for item in self.server.diagnostics.get(document.uri, [])
                  if item.get("severity", 1) == 1]
        self.assertEqual(errors, [])
        for anchor, spelling in (('title := "Unloaded figure"', "title"),
                                 ('label := "uncompiled-latex"', "label"),
                                 ('title := "Skipped computation"', "title")):
            with self.subTest(component=anchor):
                token = document.find(anchor, spelling)
                self.assert_hover(document, token, "ComponentMetadata." + spelling)
                self.assertTrue(self.definitions(document, token))

    def test_local_binder_highlights_hover_and_definition(self):
        groups = [
            (["have haveLinked := hp", "exact haveLinked"], "haveLinked"),
            (["intro introLinked", "exact introLinked"], "introLinked"),
            (["unpack_and ⟨andLinked, andOther⟩ := andInput", "exact andLinked"], "andLinked"),
            (["unpack_iff ⟨iffLinked, iffOther⟩ := iffInput", "exact iffLinked"], "iffLinked"),
            (["obtain_exist ⟨existLinked, existProof⟩ := existInput", "provide existLinked"], "existLinked"),
            (["obtain_exist ⟨threeLinked, threeLeft, threeRight⟩ := threeInput", "provide threeLinked"], "threeLinked"),
            (["funext funextLinked", ("change funextLinked = funextLinked", 0),
              ("change funextLinked = funextLinked", 1)], "funextLinked"),
            (["claim claimLinked : P", "exact claimLinked"], "claimLinked"),
            (["claim_exist ⟨claimTwoLinked, claimTwoProof⟩ :", "provide claimTwoLinked"], "claimTwoLinked"),
            (["claim_exist ⟨claimThreeLinked, claimThreeLeft, claimThreeRight⟩ :", "provide claimThreeLinked"], "claimThreeLinked"),
            (["contra contraLinked", "exact (np contraLinked)"], "contraLinked"),
            (["contra negativeLinked", "exact (negativeLinked positive)"], "negativeLinked"),
            (["ide_intro customLinked", "exact customLinked"], "customLinked"),
            (["script_ide_intro nativeLinked", "exact nativeLinked"], "nativeLinked"),
            (["have recordedLinked := recordedInput", "exact recordedLinked"], "recordedLinked"),
            (["@theorem recordedScript (P : Prop) (recordedInput : P)",
              "have recordedLinked := recordedInput"], "recordedInput"),
            (["have byLinked := byInput", "exact byLinked"], "byLinked"),
            (["(P : Prop) (byInput : P) : P := by", "have byLinked := byInput"], "byInput"),
            (["embed recordedScript P embedInput as embeddedLinked", "exact embeddedLinked"], "embeddedLinked"),
            (["intro recordedIntro", "exact recordedIntro"], "recordedIntro"),
            (["claim recordedClaim : P", "have recordedHave := recordedClaim"], "recordedClaim"),
            (["have recordedHave := recordedClaim", "exact recordedHave"], "recordedHave"),
            (["funext recordedArgument", ("change recordedArgument = recordedArgument", 0),
              ("change recordedArgument = recordedArgument", 1)], "recordedArgument"),
            (["contra recordedAssumption", "exact (recordedNegative recordedAssumption)"], "recordedAssumption"),
            (["ide_intro runtimeCustom", "ide_exact runtimeCustom, runtimeLabel"], "runtimeCustom"),
            (["unpack_and ⟨recordedAndLeft, recordedAndRight⟩ := recordedAndInput",
              "exact recordedAndLeft"], "recordedAndLeft"),
            (["obtain_exist ⟨recordedWitness, recordedLeft, recordedRight⟩ := recordedExistInput",
              "provide recordedWitness"], "recordedWitness"),
            (["claim_exist ⟨recordedClaimWitness, recordedClaimProof⟩ :",
              "provide recordedClaimWitness"], "recordedClaimWitness"),
        ]
        for name in ("allWitness", "allLeft", "allRight"):
            groups.append((["script_obtain_exist ⟨allWitness, allLeft, allRight⟩ := allInput",
                            "exact ⟨allWitness, allLeft, allRight⟩"], name))
        for mode, document in self.documents.items():
            for anchors, spelling in groups:
                with self.subTest(mode=mode, binder=spelling):
                    self.assert_links(document, anchors, spelling)

    def test_macro_term_references_and_recorded_declarations(self):
        for mode, document in self.documents.items():
            for anchor, spelling in (("simp [Nat.zero_add]", "Nat.zero_add"),
                                     ("-- keyword: rw\nexample (n : Nat) : 0 + n = n := script\n  rw [Nat.zero_add]", "Nat.zero_add"),
                                     ("@theorem recordedRewrite (recordedNumber : Nat) : 0 + recordedNumber = recordedNumber := script\n  rw [Nat.zero_add]", "Nat.zero_add"),
                                     ("«alias» := some Eq", "Eq")):
                with self.subTest(mode=mode, reference=anchor):
                    token = document.find(anchor, spelling)
                    self.assert_hover(document, token, spelling)
                    self.assertTrue(self.definitions(document, token))
            for name, kind in (("recordedScript", "theorem"), ("recordedBy", "theorem"),
                               ("recordedLemma", "lemma")):
                token = document.find(f"#check {name}", name)
                self.assert_definition(document, token, document.find(f"@{kind} {name}", name))
            for anchor in ("unfold ideIdentity", "function := ideComputation"):
                spelling = anchor.split()[-1]
                with self.subTest(mode=mode, reference=anchor):
                    token = document.find(anchor, spelling)
                    self.assert_hover(document, token, spelling)
                    self.assert_definition(document, token, document.find(f"def {spelling} (", spelling))

    def test_script_steps_expose_goal_context(self):
        samples = [
            ("exact haveLinked", "haveLinked"),
            ("exact introLinked", "introLinked"),
            ("exact nativeLinked", "nativeLinked"),
            ("exact recordedLinked", "recordedLinked"),
            ("exact embeddedLinked", "embeddedLinked"),
            ("change recordedArgument = recordedArgument", "recordedArgument"),
        ]
        for mode, document in self.documents.items():
            for anchor, name in samples:
                with self.subTest(mode=mode, step=anchor):
                    # Lean deliberately reports the state after execution at
                    # positions past a tactic's start. Query its exact start
                    # to inspect the context immediately before the step.
                    token = document.find(anchor)
                    result = self.server.request("$/lean/plainGoal", {
                        "textDocument": {"uri": document.uri}, "position": token.start,
                    })
                    self.assertIsNotNone(result)
                    self.assertTrue(any(name in goal for goal in result["goals"]), result)


if __name__ == "__main__":
    unittest.main()
