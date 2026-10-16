import ProofScript.Mathlib.Scripts
import ProofScript.Info.Commands

/-! Mathlib expression and script presentation, separate from tactic registration. -/

def_info Real { kind := const, arguments := [], styles := [
  { name := "formula", template := "\\mathbb{R}", fixity := atom, precedence := 100 }
] }

def_info Set { kind := type, arguments := explicit, styles := [
  { name := "formula", template := "\\mathcal{P}(#0)", fixity := application, precedence := 90 }
] }

script_info ProofScript.Mathlib.Scripts.«continuity» {
  template := [{
    lang := "zh", tag := "连续性",
    content := ""
  }, {
    lang := "en", tag := "«continuity»",
    content := ""
  }]
}

script_info ProofScript.Mathlib.Scripts.«exact_mod_cast» {
  template := [{
    lang := "zh", tag := "«exact_mod_cast»",
    content := ""
  }, {
    lang := "en", tag := "«exact_mod_cast»",
    content := ""
  }]
}

script_info ProofScript.Mathlib.Scripts.«field» {
  template := [{
    lang := "zh", tag := "域算术",
    content := ""
  }, {
    lang := "en", tag := "«field»",
    content := ""
  }]
}

script_info ProofScript.Mathlib.Scripts.«measurability» {
  template := [{
    lang := "zh", tag := "可测性",
    content := ""
  }, {
    lang := "en", tag := "«measurability»",
    content := ""
  }]
}

script_info ProofScript.Mathlib.Scripts.«positivity» {
  template := [{
    lang := "zh", tag := "正性",
    content := ""
  }, {
    lang := "en", tag := "«positivity»",
    content := ""
  }]
}

script_info ProofScript.Mathlib.Scripts.«ring» {
  template := [{
    lang := "zh", tag := "环算术",
    content := ""
  }, {
    lang := "en", tag := "«ring»",
    content := ""
  }]
}

script_info ProofScript.Mathlib.Scripts.«tauto» {
  template := [{
    lang := "zh", tag := "重言",
    content := ""
  }, {
    lang := "en", tag := "«tauto»",
    content := ""
  }]
}

script_info ProofScript.Mathlib.Scripts.«tauto_set» {
  template := [{
    lang := "zh", tag := "重言",
    content := ""
  }, {
    lang := "en", tag := "«tauto_set»",
    content := ""
  }]
}
