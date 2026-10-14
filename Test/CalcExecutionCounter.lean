import ProofScript

namespace Test

/-- Test-only witness that recorded calc elaborates its proof once. -/
initialize calcExecutionCount : IO.Ref Nat ← IO.mkRef 0

end Test
