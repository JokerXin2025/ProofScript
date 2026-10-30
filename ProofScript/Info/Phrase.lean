import ProofScript.Info.Derive
import ProofScript.Info.Target
import ProofScript.Info.Template

namespace ProofScript

open Lean

structure PhraseTemplate where
  lang : String
  content : String
  deriving Inhabited, InfoSchema

instance : InfoSchema PhraseTemplate :=
  (inferInstance : InfoSchema PhraseTemplate).withOverrides! {
    fields := #[PhraseTemplate.infoFields.lang.withValidation fun value =>
      if value.isEmpty then .error "language must not be empty" else .ok ()]
    validateRecord := fun value =>
      if let some unknown := (namedPlaceholders value.content).find? (!#["body", "binder", "type"].contains ·) then
        .error { message := s!"unknown placeholder `{unknown}`", path := #[.key "content"] }
      else .ok () }

structure PhraseInfo where
  template : Array PhraseTemplate
  extra : ExtraFields := {}
  deriving Inhabited, InfoSchema

instance : InfoSchema PhraseInfo :=
  (inferInstance : InfoSchema PhraseInfo).withOverrides! {
    fields := #[PhraseInfo.infoFields.template.withMerge (keyedArray (·.lang))]
    validateRecord := fun value =>
      if value.template.isEmpty then
        .error { message := "at least one phrase template is required", path := #[.key "template"] }
      else .ok () }

def phraseSpec : InfoSpec PhraseInfo := {
  kind := "phrase" }

def resolvePhraseInfo (env : Environment) (query : Query) (target : Name) :
    Except Diagnostic (ResolvedInfo PhraseInfo) :=
  resolveConfiguredInfo phraseSpec env query target

end ProofScript
