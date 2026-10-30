import ProofScript.Mathlib.Scripts
import ProofScript.Info.Commands

/-! Mathlib expression and script presentation, separate from tactic registration. -/

def_info Real { var_name := "x", parameter_template := some "$#self\\in\\mathbb{R}$", kind := const, styles := [
  { name := "formula", template := "\\mathbb{R}", fixity := atom, precedence := 100 }
] }

def_info Set { kind := type, parameter_template := some "$#self\\subseteq #0$", styles := [
  { name := "formula", template := "\\mathcal{P}(#0)", fixity := application, precedence := 90 }
] }

def_info Set.Icc { kind := operator, styles := [
  { template := "[#0,#1]", fixity := atom }
] }

def_info Set.Elem { parameter_template := some "$#self\\in #0$", styles := [
  { template := "#0", fixity := atom }
] }

script_info «continuity» {
  template := [{
    lang := "zh", tag := "连续性",
    content := ""
  }, {
    lang := "en", tag := "«continuity»",
    content := ""
  }]
}

script_info «exact_mod_cast» {
  template := [{
    lang := "zh", tag := "«exact_mod_cast»",
    content := ""
  }, {
    lang := "en", tag := "«exact_mod_cast»",
    content := ""
  }]
}

script_info «field» {
  template := [{
    lang := "zh", tag := "域算术",
    content := ""
  }, {
    lang := "en", tag := "«field»",
    content := ""
  }]
}

script_info «measurability» {
  template := [{
    lang := "zh", tag := "可测性",
    content := ""
  }, {
    lang := "en", tag := "«measurability»",
    content := ""
  }]
}

script_info «positivity» {
  template := [{
    lang := "zh", tag := "正性",
    content := ""
  }, {
    lang := "en", tag := "«positivity»",
    content := ""
  }]
}

script_info «ring» {
  template := [{
    lang := "zh", tag := "环算术",
    content := ""
  }, {
    lang := "en", tag := "«ring»",
    content := ""
  }]
}

script_info «tauto» {
  template := [{
    lang := "zh", tag := "重言",
    content := ""
  }, {
    lang := "en", tag := "«tauto»",
    content := ""
  }]
}

script_info «tauto_set» {
  template := [{
    lang := "zh", tag := "重言",
    content := ""
  }, {
    lang := "en", tag := "«tauto_set»",
    content := ""
  }]
}
