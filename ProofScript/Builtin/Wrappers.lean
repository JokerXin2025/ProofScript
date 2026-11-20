import ProofScript.Info.Decl.Commands
import Mathlib

import ProofScript.Extensions.Title
import ProofScript.Extensions.ProofText

-- TODO: determine the precedence of text-templates

#page title "Wrapper Configurations in *ProofScript*"


decl_info wrapper OfNat.ofNat 1
decl_info wrapper Nat.cast 2
decl_info wrapper Int.cast 2
decl_info wrapper Rat.cast 2
decl_info wrapper NNRat.cast 2
decl_info wrapper NatCast.natCast 2
decl_info wrapper IntCast.intCast 2
decl_info wrapper RatCast.ratCast 2
decl_info wrapper Int.ofNat 0
decl_info wrapper Rat.ofInt 0
decl_info wrapper Algebra.cast 5

decl_info wrapper NNReal.mk 0
decl_info wrapper NNReal.toReal 0
decl_info wrapper ENNReal.ofReal 0
decl_info wrapper ENNReal.ofNNReal 0
decl_info wrapper ENat.toENNReal 0
decl_info wrapper Real.toEReal 0
decl_info wrapper ENNReal.toEReal 0
decl_info wrapper Hyperreal.ofReal 0
decl_info wrapper Complex.ofReal 0
decl_info wrapper Complex.UnitDisc.coe 0
decl_info wrapper Complex.UnitClosedDisc.coe 0
decl_info wrapper RCLike.ofReal 2
decl_info wrapper Quaternion.coe 2
decl_info wrapper Quaternion.coeComplex 0
decl_info wrapper QuaternionAlgebra.coe 5
decl_info wrapper Real.Angle.coe 0

decl_info wrapper Coe.coe 3
decl_info wrapper CoeTC.coe 3
decl_info wrapper CoeT.coe 1
decl_info wrapper CoeHTCT.coe 3
decl_info wrapper CoeSort.coe 3
decl_info wrapper CoeTail.coe 3
decl_info wrapper SetLike.coe 3

decl_info wrapper ULift.up 1
decl_info wrapper ULift.down 1
decl_info wrapper PLift.up 1
decl_info wrapper PLift.down 1
decl_info wrapper WithTop.some 1
decl_info wrapper WithBot.some 1
decl_info wrapper WithZero.coe 1
decl_info wrapper WithOne.coe 1
decl_info wrapper Subtype.mk 2
decl_info wrapper Subtype.val 2
decl_info wrapper Fin.mk 1
decl_info wrapper Fin.val 1
decl_info wrapper PNat.val 0
decl_info wrapper Nat.Primes.toPNat 0

decl_info wrapper Option.some 1
decl_info wrapper Part.some 1
decl_info wrapper Part.ofOption 1
decl_info wrapper Trunc.mk 1
decl_info wrapper Quotient.mk 2
decl_info wrapper Quotient.mk' 2
decl_info wrapper Quotient.mk'' 2
decl_info wrapper Quot.mk 2
decl_info wrapper Associates.mk 2
decl_info wrapper Sym.mk 2
decl_info wrapper Sym.toMultiset 2
decl_info wrapper Finset.mk 1
decl_info wrapper Finset.val 1
decl_info wrapper Multiset.ofList 1
decl_info wrapper Cycle.ofList 1

decl_info wrapper Interval.coe 2
decl_info wrapper Heyting.Regular.val 2
decl_info wrapper MeasureTheory.ProbabilityMeasure.toMeasure 2
decl_info wrapper MeasureTheory.FiniteMeasure.toMeasure 2
decl_info wrapper Cardinal.ofENat 0
decl_info wrapper Class.ofSet 0
decl_info wrapper ONote.ofNat 0
decl_info wrapper ZMod.val 1
decl_info wrapper ZMod.cast 3

decl_info wrapper Polynomial.ofFinsupp 2
decl_info wrapper Polynomial.toFinsupp 2
decl_info wrapper Polynomial.toPowerSeries 2
decl_info wrapper MvPolynomial.toMvPowerSeries 3
decl_info wrapper Submodule.toAffineSubspace 5
decl_info wrapper PointedCone.ofSubmodule 7
decl_info wrapper ProperCone.toPointedCone 8
decl_info wrapper DivisibleHull.coe 2
decl_info wrapper DoubleCentralizer.coe 7
decl_info wrapper RatFunc.coePolynomial 3
decl_info wrapper NumberField.RingOfIntegers.val 2
decl_info wrapper FractionalIdeal.coeIdeal 6
decl_info wrapper FractionalIdeal.coeToSubmodule 6
decl_info wrapper UniformSpace.Completion.coe' 2
decl_info wrapper BoxIntegral.Box.toSet 1
decl_info wrapper Delone.DeloneSet.toSet 2

decl_info wrapper FreeMonoid.of 1
decl_info wrapper FreeGroup.of 1
decl_info wrapper FreeRing.of 1
decl_info wrapper FreeCommRing.of 1
decl_info wrapper FreeRing.castFreeCommRing 1
decl_info wrapper FreeAlgebra.ι 3
