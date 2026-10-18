import Base
import ../../bendlib/string-equality.bend as SafeText
import ../../bendlib/equality-proof.bend as TextProof
import ../../bendlib/categories.bend as Categories
import ../../bendlib/stdlib.bend as Std
import ./RENDERED.bend as Rendered
import ./render-proof.bend as RenderedEvidence
import ./CONTRACT.bend as Rule
import ../controls/GEOMETRY.bend as Geometry
import ./SPEC.bend as Spec
import ../../interaction/presentation/SURFACE.bend as SurfaceTypes
import ../../interaction/IDENTITY.bend as UIIdentity
import ../../interaction/presentation/PROGRAM.bend as InterfaceView
import ../../bendlib/logic-proof.bend as Logic

# The validity Boolean is a projection of the independent, complete diagnostic
# requirement. Reflection is proved from the real public validator result.
def clear_requirement(+faults: +List<Rendered.Violation>) ->
  {Rule.clear(faults) == Spec.no_diagnostics(faults) : Bool}:
  match faults:
    case Nil{}: {==}
    case Con{first, rest}: {==}

def reflected(+surface: SurfaceTypes.Surface, +frame: Rendered.Frame) ->
  {Rule.clear(Rendered.violations(surface, frame)) == Spec.valid(surface, frame) : Bool}:
  Equal.trans(Bool, Rule.clear(Rendered.violations(surface, frame)),
    Rule.clear(Spec.ordinary_frame_diagnostics(surface, frame)), Spec.valid(surface, frame),
    Equal.cong((+List<Rendered.Violation>), Bool, Rule.clear,
      Rendered.violations(surface, frame), Spec.ordinary_frame_diagnostics(surface, frame), RenderedEvidence.complete_violations(surface, frame)),
    clear_requirement(Spec.ordinary_frame_diagnostics(surface, frame)))

def realized_faults_imply_valid(+faults: +List<Rendered.Violation>, +surface: SurfaceTypes.Surface,
  +frame: Rendered.Frame, generation: Nat,
  matching: {faults == Rendered.violations(surface, frame) : +List<Rendered.Violation>},
  realized: {Rendered.accepted(faults, generation, frame) == Rendered.Realized{generation, frame} : Rendered.State}) ->
  {Spec.valid(surface, frame) == True{} : Bool}:
  match faults:
    case Nil{}:
      Equal.trans(Bool,
        Spec.valid(surface, frame),
        Rule.clear(Rendered.violations(surface, frame)),
        True{},
        Equal.sym(Bool, Rule.clear(Rendered.violations(surface, frame)), Spec.valid(surface, frame), reflected(surface, frame)),
        Equal.trans(Bool,
          Rule.clear(Rendered.violations(surface, frame)),
          Rule.clear(faults),
          True{},
          Equal.sym(Bool, Rule.clear(faults), Rule.clear(Rendered.violations(surface, frame)),
            Equal.cong(+List<Rendered.Violation>, Bool, Rule.clear, faults, Rendered.violations(surface, frame), matching)),
          {==}))
    case Con{fault, rest}:
      Logic.impossible({Spec.valid(surface, frame) == True{} : Bool},
        Equal.cong(Rendered.State, Bool, Rule.realized_tag,
          Rendered.accepted(faults, generation, frame),
          Rendered.Realized{generation, frame}, realized))

def Rule.evidence():
  Rule.Requirements{reflected, +current => +received => +surface => +frame => +previous => owned => realized =>
      observed_owner = Std.transport(Bool, True{},
        (ownership => @observed:{Nat.is_eq(current, received) == ownership : Bool} ->
          {Rendered.received(Categories.admit_checked(Rendered.FrameReceipt, Rendered.frame_correlated,
            Rendered.FrameReceipt{current, received, surface, frame}, ownership, observed), previous) ==
            Rendered.received_calculation(current, surface, frame) : Rendered.State}),
        observed => {==}, Nat.is_eq(current, received), owned)({==})
      accepted_realized = Equal.trans(Rendered.State,
        Rendered.received_calculation(current, surface, frame),
        Rendered.observe(current, received, surface, frame, previous),
        Rendered.Realized{current, frame},
        Equal.sym(Rendered.State, Rendered.observe(current, received, surface, frame, previous),
          Rendered.received_calculation(current, surface, frame), observed_owner), realized)
      realized_faults_imply_valid(Rendered.violations(surface, frame), surface, frame, current, {==}, accepted_realized)
    }

def requirement_issue_clear(+valid: Bool, fault: Rendered.Violation) ->
  {Spec.no_diagnostics(Spec.issue(Bool.not(valid), fault)) == valid : Bool}:
  match valid:
    case False{}: {==}
    case True{}: {==}

def Rule.dialog_actions_region_geometry(found, viewport):
  match found:
    case None{}: {==}
    case Some{Rendered.Element{key, +visible, enabled, tab, keyboard, scroll, +bounds, hit, paint}}:
      requirement_issue_clear(visible && Geometry.contains(viewport, bounds), Rendered.EscapedDialog{""})

def Rule.dialog_actions_children_visible(inherited, found, viewport):
  match inherited:
    case False{}: {==}
    case True{}: {==}
