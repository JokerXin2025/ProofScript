import Test.TheoremDependencyFactsTest

-- Independent of ModuleTest: the importer must report both project assignment origins.
theorem_info TheoremDependencyFacts.ordinary { project := "Facts.other" }
