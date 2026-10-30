/-
    ProofScript.Utils.FileSystem
    Released under Apache 2.0 license as described in the file LICENSE.
    Authors: JokerXin
-/

import Lean


/-- Ensure the parent directory of the path exists, creating missing ancestors
recursively. It does nothing if the path has no parent. -/
def System.FilePath.ensureParentDir (path : System.FilePath) : IO Unit := do
  if let some parent := path.parent then IO.FS.createDirAll parent
