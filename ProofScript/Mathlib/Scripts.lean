import ProofScript.Script.Config
import ProofScript.Script.RenderInfo
import ProofScript.Lean2TeX.Command
import Mathlib.Tactic

open Lean Parser Mathlib Tactic

def_info Real { kind := const, arguments := [], styles := [
  { name := "formula", template := "\\mathbb{R}", fixity := atom, precedence := 100 }
] }
def_info Set { kind := type, arguments := explicit, styles := [
  { name := "formula", template := "\\mathcal{P}(#0)", fixity := application, precedence := 90 }
] }


/-! # Mathlib Native Tactics -/

open Lean Elab.Command Mathlib.Linter in
run_cmd do
  let registrations := ProofScript.scriptTacticRegistrations (← getEnv)
  let metadataNames := ["remark", "svg", "latex", "cite"]
  let kinds := registrations.filter (fun r => metadataNames.contains r.name) |>.flatMap fun r =>
    r.executionKind :: r.recordingKind.toList
  elabCommand (← `(command| initialize do
    UnusedTactic.allowedRef.modify (·.insertMany $(Lean.quote kinds))))

script_macro «continuity»
"continuity" => `(tactic| continuity)

script_info «continuity» {
  template := [{
    lang := "zh", tag := "连续性",
    content := ""
  }, {
    lang := "en", tag := "«continuity»",
    content := ""
  }]
}

script_macro «exact_mod_cast»
"exact_mod_cast" proof:term => `(tactic| exact_mod_cast $proof:term)

script_info «exact_mod_cast» {
  template := [{
    lang := "zh", tag := "«exact_mod_cast»",
    content := ""
  }, {
    lang := "en", tag := "«exact_mod_cast»",
    content := ""
  }]
}

script_macro «field»
"field" args:(simpArgs)? => `(tactic| field $[$args:simpArgs]?)

script_info «field» {
  template := [{
    lang := "zh", tag := "域算术",
    content := ""
  }, {
    lang := "en", tag := "«field»",
    content := ""
  }]
}

script_macro «gcongr»
"gcongr" template:(ppSpace colGt term)? names:("with" (ppSpace colGt rintroPat)*)? =>
  match names with
  | none => `(tactic| gcongr $[$template]?)
  | some withNames =>
      let patterns : Array (Lean.TSyntax `rintroPat) :=
        withNames.raw.getArgs[1]!.getArgs.map (fun stx => ⟨stx⟩)
      `(tactic| gcongr $[$template]? with $patterns*)

declare_syntax_cat scriptITautoArgs
syntax "*" : scriptITautoArgs
syntax "[" term,* "]" : scriptITautoArgs

script_macro «itauto»
"itauto" args:(scriptITautoArgs)? =>
  match args with
  | some arg =>
      if arg.raw.getArgs[0]!.isAtom then `(tactic| itauto *)
      else
        match arg with
        | `(scriptITautoArgs| [$terms,*]) => `(tactic| itauto [$terms,*])
        | _ => Lean.Macro.throwUnsupported
  | none => `(tactic| itauto)

script_macro «itauto!»
"itauto!" args:(scriptITautoArgs)? =>
  match args with
  | some arg =>
      if arg.raw.getArgs[0]!.isAtom then `(tactic| itauto! *)
      else
        match arg with
        | `(scriptITautoArgs| [$terms,*]) => `(tactic| itauto! [$terms,*])
        | _ => Lean.Macro.throwUnsupported
  | none => `(tactic| itauto!)

script_macro «linarith»
"linarith" args:linarithArgsRest => `(tactic| linarith $args:linarithArgsRest)

script_macro «linarith!»
"linarith!" args:linarithArgsRest => `(tactic| linarith! $args:linarithArgsRest)

script_macro «measurability»
"measurability" => `(tactic| measurability)

script_info «measurability» {
  template := [{
    lang := "zh", tag := "可测性",
    content := ""
  }, {
    lang := "en", tag := "«measurability»",
    content := ""
  }]
}

script_macro «nlinarith»
"nlinarith" args:linarithArgsRest => `(tactic| nlinarith $args:linarithArgsRest)

script_macro «nlinarith!»
"nlinarith!" args:linarithArgsRest => `(tactic| nlinarith! $args:linarithArgsRest)

script_macro «norm_cast»
"norm_cast" loc:(location)? => `(tactic| norm_cast $[$loc:location]?)

script_macro «norm_num»
"norm_num" cfg:optConfig onlyFlag:("only")?
    args:(simpArgs)? loc:(location)? =>
  match onlyFlag with
  | none => `(tactic| norm_num $cfg:optConfig $[$args:simpArgs]? $[$loc:location]?)
  | some _ => `(tactic| norm_num $cfg:optConfig only $[$args:simpArgs]? $[$loc:location]?)

script_macro «positivity»
"positivity" => `(tactic| positivity)

script_info «positivity» {
  template := [{
    lang := "zh", tag := "正性",
    content := ""
  }, {
    lang := "en", tag := "«positivity»",
    content := ""
  }]
}

script_macro «push_cast»
"push_cast" cfg:optConfig disch:(discharger)?
    onlyFlag:("only")? lemmas:(simpArgs)?
    loc:(location)? => do
  let base ← match onlyFlag with
    | none => `(tactic| push_cast $cfg:optConfig $[$disch:discharger]? $[$loc:location]?)
    | some _ => `(tactic| push_cast $cfg:optConfig $[$disch:discharger]? only $[$loc:location]?)
  match lemmas with
  | none => pure base
  | some args =>
      let parts := base.raw.getArgs
      let withLemmas := parts.set! 4 args.raw
      pure (Lean.Syntax.node base.raw.getHeadInfo base.raw.getKind withLemmas)

script_macro «qify»
"qify" args:(simpArgs)? loc:(location)? =>
  `(tactic| qify $[$args:simpArgs]? $[$loc:location]?)

script_macro «rify»
"rify" args:(simpArgs)? loc:(location)? =>
  `(tactic| rify $[$args:simpArgs]? $[$loc:location]?)

script_macro «ring»
"ring" => `(tactic| ring)

script_info «ring» {
  template := [{
    lang := "zh", tag := "环算术",
    content := ""
  }, {
    lang := "en", tag := "«ring»",
    content := ""
  }]
}

script_macro «ring!»
"ring!" => `(tactic| ring!)

script_macro «ring_nf»
"ring_nf" cfg:optConfig loc:(location)? =>
  `(tactic| ring_nf $cfg:optConfig $[$loc:location]?)

script_macro «ring_nf!»
"ring_nf!" cfg:optConfig loc:(location)? =>
  `(tactic| ring_nf! $cfg:optConfig $[$loc:location]?)

script_macro «tauto»
"tauto" => `(tactic| tauto)

script_info «tauto» {
  template := [{
    lang := "zh", tag := "重言",
    content := ""
  }, {
    lang := "en", tag := "«tauto»",
    content := ""
  }]
}

script_macro «tauto_set»
"tauto_set" => `(tactic| tauto_set)

script_info «tauto_set» {
  template := [{
    lang := "zh", tag := "重言",
    content := ""
  }, {
    lang := "en", tag := "«tauto_set»",
    content := ""
  }]
}

declare_syntax_cat scriptWlogGeneralizing
syntax "generalizing" (ppSpace colGt ident)* : scriptWlogGeneralizing
declare_syntax_cat scriptWlogWith
syntax "with" ident : scriptWlogWith

script_macro «wlog»
"wlog" h:ident ":" proposition:term vars:(scriptWlogGeneralizing)?
    hypothesis:(scriptWlogWith)? =>
  let generalizingArgs := vars.map (fun stx => stx.raw.getArgs)
  let xs : Array (Lean.TSyntax `ident) :=
    (generalizingArgs.map (fun args => args[1]!.getArgs)).getD #[] |>.map (fun stx => ⟨stx⟩)
  let H : Option (Lean.TSyntax `ident) := hypothesis.map (fun stx => ⟨stx.raw.getArgs[1]!⟩)
  match vars, H with
  | none, none => `(tactic| wlog $h:ident : $proposition:term)
  | some _, none => `(tactic| wlog $h:ident : $proposition:term generalizing $xs*)
  | none, some name => `(tactic| wlog $h:ident : $proposition:term with $name:ident)
  | some _, some name =>
      `(tactic| wlog $h:ident : $proposition:term generalizing $xs* with $name:ident)

script_macro «wlog!»
"wlog!" cfg:optConfig h:ident ":" proposition:term
    vars:(scriptWlogGeneralizing)? hypothesis:(scriptWlogWith)? =>
  let generalizingArgs := vars.map (fun stx => stx.raw.getArgs)
  let xs : Array (Lean.TSyntax `ident) :=
    (generalizingArgs.map (fun args => args[1]!.getArgs)).getD #[] |>.map (fun stx => ⟨stx⟩)
  let H : Option (Lean.TSyntax `ident) := hypothesis.map (fun stx => ⟨stx.raw.getArgs[1]!⟩)
  match vars, H with
  | none, none => `(tactic| wlog! $cfg:optConfig $h:ident : $proposition:term)
  | some _, none => `(tactic| wlog! $cfg:optConfig $h:ident : $proposition:term generalizing $xs*)
  | none, some name => `(tactic| wlog! $cfg:optConfig $h:ident : $proposition:term with $name:ident)
  | some _, some name =>
      `(tactic| wlog! $cfg:optConfig $h:ident : $proposition:term generalizing $xs* with $name:ident)

script_macro «zify»
"zify" args:(simpArgs)? loc:(location)? =>
  `(tactic| zify $[$args:simpArgs]? $[$loc:location]?)
