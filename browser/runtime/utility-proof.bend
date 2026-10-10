import Base
import ../../bendlib/categories.bend as Categories
import ./frontend-utility.bend as Utility
import ../document/SOURCE.bend as Source
import ../appearance/TYPOGRAPHY.bend as T

def recovery_evidence(+request: Utility.RecoveryButton) -> Utility.authored_recovery(Utility.RecoveryObservation{request, Utility.recovery_source(request)}):
  match request:
    case Utility.RecoveryButton{font, reason}:
      Categories.Intersection{{==}, Categories.Intersection{{==}, {==}}}

def Utility.recovery_evidence(): recovery_evidence

def construct_recovery(+request: Utility.RecoveryButton) -> Categories.Membership<Utility.RecoveryObservation, Utility.authored_recovery>:
  Categories.Membership{Utility.RecoveryObservation{request, Utility.recovery_source(request)}, recovery_evidence(request)}

def Utility.construct_recovery(): construct_recovery

def Utility.recovery_constructor_correspondence():
  +request => {==}

def recovery_children(purpose: Utility.Purpose, +font: T.Presentation) -> +List<Source.Node>:
  match purpose:
    case Utility.Preparing{}: Nil{}
    case Utility.Recovery{reason}: [Utility.constructed_recovery_node(Utility.construct_recovery(Utility.RecoveryButton{font, reason}))]

def source(+purpose: Utility.Purpose, +font: T.Presentation, glyph_only: Bool) -> Source.Node:
  Utility.source_with_recovery(purpose, font, glyph_only, recovery_children(purpose, font))
