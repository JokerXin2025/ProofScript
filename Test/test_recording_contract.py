import copy
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from PS4HTML.engine import ProofEngine
from PS4HTML.make import _validate_render_inputs
from PS4HTML.page import PageRenderer, load_page, build_label_index
from PS4HTML.project import PS4HTMLError
from PS4HTML.recording import adapt_legacy_record, validate_contract
from PS4HTML.render_rules import validate_record, validate_rules
from PS4HTML.schema import ExpressionResolver


ROOT = Path(__file__).resolve().parents[1]
EXPORT = ROOT / ".ProofScript"
MODULE = "Test.RecordingComplexTest"
GOAL = {"_goal_": {"$ref": "e0"}}


def contract(schema, name="items", nullable=False):
    return {"name": name, "schema": schema, "nullable": nullable}


def rule(fields, text="${items}"):
    return {"ruleId": "probe", "strategy": False, "recordedFields": fields,
            "fields": {"template": [{"lang": "zh", "tag": "Probe", "content": text}]}}


class RecordingContractTest(unittest.TestCase):
    def test_legacy_singleton_adapter_is_versioned_and_does_not_mutate_input(self):
        fields = [contract({"kind": "array", "element": {"kind": "expression"}})]
        original = {"_ruleId": "probe", "items": {"$ref": "e0"}}
        adapted = adapt_legacy_record(original, fields, "0.0.0")
        self.assertEqual(adapted["items"], [{"$ref": "e0"}])
        self.assertIsInstance(original["items"], dict)
        self.assertIs(adapt_legacy_record(original, fields, "0.1.0"), original)
        with self.assertRaisesRegex(ValueError, "array schema"):
            validate_record(rule(fields), original, GOAL)
        validate_record(rule(fields), original, GOAL, "0.0.0")
        self.assertEqual(adapt_legacy_record({"items": []}, fields, "0.0.0")["items"], [])
        resolver = ExpressionResolver({"e0": {"kind": "const", "name": "True", "isProp": True}})
        legacy = ProofEngine([GOAL, original], rules={"probe": rule(fields, "${items.0}")},
                             expression_resolver=resolver, proof_version="0.0.0")
        self.assertTrue(legacy.render([GOAL, original]))

    def test_contract_checks_type_nullability_missing_fields_and_duplicate_names(self):
        numeric = rule([contract({"kind": "number"})])
        validate_record(numeric, {"items": 42}, GOAL)
        for invalid in (True, "42", None, {"$ref": "e0"}):
            with self.assertRaisesRegex(ValueError, "number schema"):
                validate_record(numeric, {"items": invalid}, GOAL)
        with self.assertRaisesRegex(ValueError, "Missing recorded field"):
            validate_record(numeric, {}, GOAL)
        optional = rule([contract({"kind": "optional", "element": {"kind": "number"}})])
        validate_record(optional, {"items": None}, GOAL)
        nullable = rule([contract({"kind": "number"}, nullable=True)])
        validate_record(nullable, {"items": None}, GOAL)
        with self.assertRaisesRegex(ValueError, "duplicate recorded field"):
            validate_contract(numeric["recordedFields"] * 2)

    def test_structured_slots_are_validated_and_escaped(self):
        fields = [contract({"kind": "array", "element": {"kind": "object", "fields": [
            {"name": "text", "schema": {"kind": "string"}},
            {"name": "flag", "schema": {"kind": "boolean"}}]}})]
        entry = rule(fields, "<tag> ${items.0.text}; ${items}")
        doc = {"schemaVersion": "0.1.0", "module": "Probe", "imports": [], "rules": [entry]}
        rules = validate_rules(doc, "Probe")
        steps = [GOAL, {"_ruleId": "probe", "items": [{"text": "<script>&", "flag": True}]}]
        rendered = ProofEngine(steps, rules=rules).render(steps)
        self.assertIn("&lt;tag&gt; &lt;script&gt;&amp;", rendered)
        self.assertIn("text: &lt;script&gt;&amp;", rendered)
        self.assertNotIn("<script>", rendered)
        for bad_slot in ("oldName", "items.text", "items.0.missing", "items.0.text.private"):
            malformed = copy.deepcopy(doc)
            malformed["rules"][0]["fields"]["template"][0]["content"] = "${" + bad_slot + "}"
            with self.assertRaisesRegex(ValueError, "Unknown recorded template field"):
                validate_rules(malformed, "Probe")
        steps[1]["items"][0]["extra"] = "bad"
        with self.assertRaisesRegex(ValueError, "object schema"):
            ProofEngine(steps, rules=rules).render(steps)

    def test_new_rules_require_contracts_and_legacy_rules_remain_readable(self):
        entry = rule([] , "")
        del entry["recordedFields"]
        doc = {"schemaVersion": "0.1.0", "module": "Probe", "imports": [], "rules": [entry]}
        with self.assertRaisesRegex(ValueError, "Missing recordedFields"):
            validate_rules(doc, "Probe")
        doc["schemaVersion"] = "0.0.0"
        validate_rules(doc, "Probe")

    def test_structured_kind_does_not_become_a_lean_expression(self):
        fields = [contract({"kind": "object", "fields": [
            {"name": "kind", "schema": {"kind": "literal", "value": "const"}},
            {"name": "label", "schema": {"kind": "string"}}]})]
        entry = rule(fields)
        steps = [GOAL, {"_ruleId": "probe", "items": {"kind": "const", "label": "<safe>"}}]
        rendered = ProofEngine(steps, rules={"probe": entry}).render(steps)
        self.assertIn("label: &lt;safe&gt;", rendered)


class RealRecordingExportTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        snapshot = EXPORT / "rendering/effective/Test/RecordingComplexTest.json"
        if not snapshot.exists():
            raise RuntimeError("Run lake build Test.RecordingComplexTest before this integration test")
        cls.rules = validate_rules(json.loads(snapshot.read_text()), MODULE)
        cls.docs = {path.stem: json.loads(path.read_text())
                    for path in (EXPORT / "proofs/Test/RecordingComplexTest").rglob("*.json")}

    def test_real_proofs_validate_resolve_and_render_in_both_languages(self):
        expected = {"recordingComplexArrays", "recordingComplexRw", "recordingComplexSimp",
                    "recordingComplexChange", "recordingComplexCalc", "recordingComplexInfer",
                    "recordingComplexOptional", "recordingComplexConstructor", "recordingComplexConstructorAuto"}
        self.assertTrue(expected <= self.docs.keys())
        for name in expected:
            with self.subTest(proof=name):
                doc = self.docs[name]
                self.assertEqual(doc["schemaVersion"], "0.1.0")
                resolver = ExpressionResolver(doc["expressions"])
                resolver.resolve(doc["proof"])
                for index in range(1, len(doc["proof"]), 2):
                    step = doc["proof"][index]
                    validate_record(self.rules[step["_ruleId"]], step, doc["proof"][index - 1])
                for language in ("zh", "en"):
                    engine = ProofEngine(doc["proof"], language=language, rules=self.rules,
                                         expression_resolver=resolver, proof_version=doc["schemaVersion"])
                    self.assertTrue(engine.render(doc["proof"]))

    def test_real_complex_values_and_collected_references(self):
        simp = self.docs["recordingComplexSimp"]["proof"][1]
        self.assertEqual(simp["config"], [{"name": "maxSteps", "value": 100}])
        self.assertEqual(len(simp["args"]), 2)
        self.assertTrue(simp["loc_before"]["wildcard"])
        self.assertIsNone(simp["loc_after"])
        rw = self.docs["recordingComplexRw"]["proof"]
        self.assertFalse(rw[1]["rules"][0]["reverse"])
        self.assertTrue(rw[3]["rules"][0]["reverse"])
        self.assertEqual(len(rw[1]["loc_before"]["hypotheses"]), 1)
        optional = self.docs["recordingComplexOptional"]["proof"]
        self.assertIsNone(optional[1]["label"])
        self.assertEqual(optional[3]["label"], "gamma")
        page = json.loads((EXPORT / "pages/Test/RecordingComplexTest.json").read_text())
        refs = [item for component in page["components"]
                for item in component["data"].get("references", {}).get("value", [])]
        self.assertIn("recordingComplexLiterature", {item["name"] for item in refs})
        self.assertIn("recordingComplexRewriteLemma", {item["name"] for item in refs})

    def test_exported_input_shapes_use_structural_metadata(self):
        manifest = json.loads((EXPORT / "rendering/modules/Test/RecordingComplexRules.json").read_text())
        registrations = {entry["ruleId"].rsplit(".", 1)[-1]: entry for entry in manifest["registrations"]}
        self.assertEqual(registrations["labels"]["parameters"], [{"name": "labels", "shape": {
            "kind": "array", "element": {"kind": "category", "name": "recordingLabel"}}}])
        self.assertEqual(registrations["optionalLabel"]["parameters"], [{"name": "label", "shape": {
            "kind": "optional", "element": {"kind": "category", "name": "recordingLabel"}}}])

    def isolated_exports(self, root):
        manifests = {json.loads(path.read_text())["module"]: path
                     for path in (EXPORT / "rendering/modules").rglob("*.json")}
        visible, pending = set(), [MODULE]
        while pending:
            owner = pending.pop()
            if owner in visible:
                continue
            visible.add(owner)
            pending.extend(json.loads(manifests[owner].read_text())["imports"])
        for name in ("rendering/modules", "rendering/effective", "tactics", "strategys", "lean2tex/events"):
            for source in (EXPORT / name).rglob("*.json"):
                if json.loads(source.read_text()).get("module") not in visible:
                    continue
                destination = root / source.relative_to(EXPORT)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, destination)
        shutil.copytree(EXPORT / "proofs/Test/RecordingComplexTest", root / "proofs/Test/RecordingComplexTest")

    def test_exported_manifests_agree_with_proofs_and_rules(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.isolated_exports(root)
            _validate_render_inputs(root)
            path = root / "rendering/modules/Test/RecordingComplexRules.json"
            manifest = json.loads(path.read_text())
            labels = next(entry for entry in manifest["registrations"] if entry["ruleId"] == "Test.RecordingComplexRules.labels")
            labels["recordedFields"][0]["nullable"] = True
            path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(PS4HTMLError, "Recording contract differs"):
                _validate_render_inputs(root)

    def test_real_page_renders_proofs_and_references(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            self.isolated_exports(root)
            page = load_page(EXPORT / "pages/Test/RecordingComplexTest.json", ROOT)
            renderer = PageRenderer(ROOT, root / "html", build_label_index([page]),
                                    pages=[page], export_root=root)
            rendered = renderer.render(page)
            self.assertIn("recordingComplexArrays", rendered)
            self.assertIn("Complex reference", rendered)
            self.assertIn("data-language-panel=\"en\"", rendered)
            self.assertIn("Rewrite", rendered)

    def test_machine_readable_schemas_validate_real_exports(self):
        from jsonschema import Draft202012Validator
        schemas = ROOT / "docs/schema"
        proof_schema = json.loads((schemas / "recording-proof.schema.json").read_text())
        rules_schema = json.loads((schemas / "render-effective.schema.json").read_text())
        for schema in (proof_schema, rules_schema):
            Draft202012Validator.check_schema(schema)
        for doc in self.docs.values():
            Draft202012Validator(proof_schema).validate(doc)
        Draft202012Validator(rules_schema).validate(
            json.loads((EXPORT / "rendering/effective/Test/RecordingComplexTest.json").read_text()))


class RegistrationExportTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.module = "Test.RecordingRegistrationTest"
        snapshot = EXPORT / "rendering/effective/Test/RecordingRegistrationTest.json"
        if not snapshot.exists():
            raise RuntimeError("Run lake build Test.RecordingRegistrationTest before this integration test")
        cls.rules = validate_rules(json.loads(snapshot.read_text()), cls.module)
        cls.docs = {path.stem: json.loads(path.read_text())
                    for path in (EXPORT / "proofs/Test/RecordingRegistrationTest").rglob("*.json")}

    def test_imported_manual_recorder_commits_local_expression(self):
        doc = self.docs["recordingRegistrationImported"]
        resolver = ExpressionResolver(doc["expressions"])
        resolver.resolve(doc["proof"])
        self.assertEqual(doc["proof"][1]["items"], ["alpha"])
        step = doc["proof"][3]
        self.assertEqual(step["_ruleId"], "Test.TacticRewriteTest.recordedIdentity")
        expression = doc["expressions"][step["proof"]["$ref"]]
        self.assertEqual((expression["kind"], expression["name"]), ("fvar", "h"))
        validate_record(self.rules[step["_ruleId"]], step, doc["proof"][2])

    def test_editor_rollback_exports_only_the_revised_contract(self):
        doc = self.docs["recordingRegistrationEdited"]
        step = doc["proof"][1]
        self.assertEqual(step["value"], 42)
        self.assertNotIn("label", step)
        entry = self.rules[step["_ruleId"]]
        self.assertEqual(entry["recordedFields"], [contract({"kind": "number"}, "value")])
        self.assertEqual(entry["fields"]["template"], [
            {"tag": "record_editor_probe", "lang": "zh", "content": ""}])
        manifest = json.loads((EXPORT / "rendering/modules/Test/RecordingRegistrationTest.json").read_text())
        probe = next(item for item in manifest["registrations"] if item["ruleId"] == step["_ruleId"])
        self.assertEqual(probe["parameters"], [{"name": "value", "shape": {"kind": "category", "name": "num"}}])
        self.assertEqual(probe["recordedFields"], entry["recordedFields"])
        for doc in self.docs.values():
            ExpressionResolver(doc["expressions"]).resolve(doc["proof"])
            for index in range(1, len(doc["proof"]), 2):
                step = doc["proof"][index]
                validate_record(self.rules[step["_ruleId"]], step, doc["proof"][index - 1])


if __name__ == "__main__":
    unittest.main()
