import ProofScript.Info.Decl.Commands
import Mathlib

import ProofScript.Extensions.Title
import ProofScript.Extensions.ProofText

-- TODO: determine the precedence of text-templates

#page title "Type Configurations in *ProofScript*"


decl_info Nat {
  var_name := "n",
  parameter_template := "$#self\\in #type$"
}
decl_info Int {
  var_name := "n",
  parameter_template := "$#self\\in #type$"
}
decl_info Rat {
  var_name := "q",
  parameter_template := "$#self\\in #type$"
}
decl_info Real {
  var_name := "x",
  parameter_template := "$#self\\in #type$"
}
decl_info Complex {
  var_name := "z",
  parameter_template := "$#self\\in #type$"
}
