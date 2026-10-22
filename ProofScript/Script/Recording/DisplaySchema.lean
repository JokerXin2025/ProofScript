import ProofScript.Script.Recording.Shape

namespace ProofScript.Recording

/-- The explicit companion-field contract. Literal markers prevent ordinary JSON
    from silently opting into expression display interpretation. -/
def displaySchema (field : String) : ParamSchema :=
  let binder := ParamSchema.union [
    .literal "default", .literal "implicit", .literal "strictImplicit", .literal "instImplicit"]
  .object [
    ("kind", .literal "expression-display-v1"), ("field", .literal field),
    ("views", .array (.object [
      ("root", .union [
        .object [("kind", .literal "field"),
          ("path", .array (.union [.string, .number]))],
        .object [("kind", .literal "auxiliary"), ("expression", .expression)]]),
      ("hints", .array (.object [
        ("path", .array .string), ("isProp", .optional .boolean),
        ("declaration", .optional (.object [
          ("name", .string), ("typeView", .optional .number), ("valueView", .optional .number)])),
        ("appBinders", .optional (.array (.optional binder))),
        ("sourceRange", .optional (.object [
          ("file", .string), ("start", .number), ("stop", .number)]))]))]))]

end ProofScript.Recording
