import Base
import ../document/SOURCE.bend as Source
import ./physical-space.bend as Model
import ./SPACE.bend as Space
import ./enclosure.bend as Enclosure

# Field dimensions are physical CSS units. Columns multiply the measured
# reference advance; the minimum never falls below the observed minimum, and
# the preferred width never falls below either. Authored line limits use the
# actual resolved line height. Multiline content grows only to its maximum
# line count; every field retains its minimum line count.
def multiline(kind: Source.NativeFieldKind) -> Bool:
  match kind:
    case Source.TextField{}: False{}
    case Source.MessageField{}: True{}
    case Source.TextAreaField{}: True{}
    case Source.SelectField{}: False{}
    case Source.MultiSelectField{}: False{}
    case Source.ToggleField{}: False{}
    case Source.NumberField{minimum}: False{}
    case Source.RangeField{minimum, maximum, step}: False{}
    case Source.DecimalField{minimum, maximum, step}: False{}
    case Source.FileField{multiple}: False{}
    case Source.DirectoryField{}: False{}
    case Source.SearchField{}: False{}
    case Source.SecretField{}: False{}


def height(variable: Bool, key: String, height: Nat) -> Model.Height:
  match variable:
    case True{}: Model.HeightAtWidth{key}
    case False{}: Model.FixedHeight{height}


def height_extent(variable: Bool, +line_floor: Nat, maximum_lines: Nat, line_height: Nat, +measured: Nat) -> Nat:
  match variable:
    case True{}: Nat.max(line_floor, Nat.min(Nat.mul(maximum_lines, line_height), measured))
    case False{}: Nat.max(line_floor, measured)


def natural_height(variable: Bool, policy: Source.FieldPolicy, +line_height: Nat, +measured: Nat) -> Nat:
  Source.FieldPolicy{columns, minimum_lines, maximum_lines} = policy
  +line_floor = Nat.mul(minimum_lines, line_height)
  height_extent(variable, line_floor, maximum_lines, line_height, measured)

def natural_demand(+kind: Source.NativeFieldKind, +policy: Source.FieldPolicy,
  line_height: Nat, minimum: Nat, preferred: Nat, measured: Nat, advance: Nat) -> Space.Demand:
  Source.FieldPolicy{columns, minimum_lines, maximum_lines} = policy
  +minimum_width = Nat.max(Nat.mul(columns, advance), minimum)
  +preferred_width = Nat.max(minimum_width, preferred)
  +height = natural_height(multiline(kind), policy, line_height, measured)
  Space.Demand{Enclosure.Extent{minimum_width, height}, Enclosure.Extent{preferred_width, height}}
