import Base
import ../../bendlib/json.bend as J
import ../../interaction/interactive_markdown/DECIMAL.bend as Decimal
import ../../interaction/interactive_markdown/EXPRESSION.bend as Expression

# Charts show the first 512 input rows in their original order. Each point keeps
# the original values as well as drawing coordinates; a drawing never replaces
# a missing or invalid value with zero. The total retains the truncation count.
type ChartKind is Data:
  Line{}
  Bar{}

type Row is Data:
  Row{source: J.Json, x: J.Json, y: String}

type Point is Data:
  Point{row: Row, x: String, y: String}

type Values is Data:
  Values{kind: ChartKind, points: +List<Point>, total: Nat, x_magnitude: String, y_magnitude: String}

def parse_kind(name: String) -> Maybe<&2, ChartKind>:
  match name:
    case "line-chart": Some{Line{}}
    case "bar-chart": Some{Bar{}}
    # DEFENSE: The public chart producer accepts only the line-chart and bar-chart kinds defined by the interactive declaration protocol.
    case _: None{}

def decimal_valid(result: Result<&2, &2, String, String>) -> Bool:
  match result:
    case Done{number}: True{}
    case Fail{reason}: False{}

def x_valid(value: J.Json) -> Bool:
  match value:
    case J.Text{text}: True{}
    case J.Number{number}: decimal_valid(Decimal.parse(number))
    case _: False{}

def y_valid(value: J.Json) -> Bool:
  match value:
    case J.Number{number}: decimal_valid(Decimal.parse(number))
    case _: False{}

def row_checked(+source: J.Json, +x: J.Json, +y: J.Json, valid: Bool) -> Result<&2, &2, String, Row>:
  match y valid:
    case J.Number{number} True{}: Done{Row{source, x, number}}
    # DEFENSE: Interactive chart rows come from user/model JSON; missing or nonnumeric axis fields must produce a diagnostic rather than a fabricated zero.
    case _ _: Fail{"Chart rows require a text or fixed-decimal x value and a fixed-decimal y value"}

def read_row(+source: J.Json, +x_path: String, +y_path: String) -> Result<&2, &2, String, Row>:
  +x = Expression.path_field(source, x_path)
  +y = Expression.path_field(source, y_path)
  row_checked(source, x, y, x_valid(x) && y_valid(y))

def prepend_row(+first: Result<&2, &2, String, Row>, rest: Result<&2, &2, String, +List<Row>>) -> Result<&2, &2, String, +List<Row>>:
  match first rest:
    case Fail{reason} _: Fail{reason}
    case _ Fail{reason}: Fail{reason}
    case Done{row} Done{rows}: Done{row <> rows}

def read_rows(limit: Nat, rows: +List<J.Json>, +x_path: String, +y_path: String) -> Result<&2, &2, String, +List<Row>>:
  match limit rows:
    case 0n _: Done{Nil{}}
    case _ Nil{}: Done{Nil{}}
    case 1n+remaining Con{+row, rest}:
      prepend_row(read_row(row, x_path, y_path), read_rows(remaining, rest, x_path, y_path))

def absolute(number: String) -> String:
  match number:
    case SCon{'-', remaining}: remaining
    case other: other

def row_magnitude(row: Row, x_axis: Bool) -> String:
  match row x_axis:
    case Row{source, J.Number{number}, y} True{}: absolute(number)
    case Row{source, x, y} True{}: "0"
    case Row{source, x, y} False{}: absolute(y)

def larger(+value: String, +previous: String, comparison: Result<&2, &2, String, Bool>) -> Result<&2, &2, String, String>:
  match comparison:
    case Fail{reason}: Fail{reason}
    case Done{True{}}: Done{value}
    case Done{False{}}: Done{previous}

def magnitude_step(row: Row, +x_axis: Bool, +previous: String) -> Result<&2, &2, String, String>:
  +value = row_magnitude(row, x_axis)
  larger(value, previous, Decimal.compare(">", value, previous))

def magnitude_loop(rows: +List<Row>, +x_axis: Bool, maximum: Result<&2, &2, String, String>) -> Result<&2, &2, String, String>:
  match rows maximum:
    case _ Fail{reason}: Fail{reason}
    case Nil{} Done{value}: Done{value}
    case Con{row, rest} Done{value}: magnitude_loop(rest, x_axis, magnitude_step(row, x_axis, value))

def magnitude(rows: +List<Row>, +x_axis: Bool, +previous: String) -> Result<&2, &2, String, String>:
  magnitude_loop(rows, x_axis, Done{previous})

# Numeric axes include zero and have a symmetric domain. The smallest positive
# six-place value keeps empty/all-zero data nondegenerate. Divide before scaling
# so the admitted decimal range does not overflow for large source values.
def offset_result(center: String, add: Bool, result: Result<&2, &2, String, String>) -> Result<&2, &2, String, String>:
  match add result:
    case _ Fail{reason}: Fail{reason}
    case True{} Done{value}: Decimal.arithmetic("+", center, value)
    case False{} Done{value}: Decimal.arithmetic("-", center, value)

def scaled_result(span: String, result: Result<&2, &2, String, String>) -> Result<&2, &2, String, String>:
  match result:
    case Fail{reason}: Fail{reason}
    case Done{ratio}: Decimal.arithmetic("*", ratio, span)

def numeric_coordinate(value: String, magnitude: String, center: String, span: String, add: Bool) -> Result<&2, &2, String, String>:
  offset_result(center, add, scaled_result(span, Decimal.arithmetic("/", value, magnitude)))

def x_coordinate(value: J.Json, magnitude: String, index: Nat, count: Nat) -> Result<&2, &2, String, String>:
  match value:
    case J.Number{number}: numeric_coordinate(number, magnitude, "240", "200", True{})
    case J.Text{text}: Done{Nat.show(Nat.add(40n, Nat.div(Nat.mul(index, 400n), Nat.max(1n, Nat.sub(count, 1n)))))}
    case _: Fail{"Chart x value is missing or is not text or numeric"}

def point_result(row: Row, x: Result<&2, &2, String, String>, y: Result<&2, &2, String, String>) -> Result<&2, &2, String, Point>:
  match x y:
    case Fail{reason} _: Fail{reason}
    case _ Fail{reason}: Fail{reason}
    case Done{left} Done{top}: Done{Point{row, left, top}}

def point(+row: Row, +x_magnitude: String, +y_magnitude: String, index: Nat, count: Nat) -> Result<&2, &2, String, Point>:
  Row{source, x, y} = row
  point_result(row, x_coordinate(x, x_magnitude, index, count), numeric_coordinate(y, y_magnitude, "120", "90", False{}))

def prepend_point(first: Result<&2, &2, String, Point>, rest: Result<&2, &2, String, +List<Point>>) -> Result<&2, &2, String, +List<Point>>:
  match first rest:
    case Fail{reason} _: Fail{reason}
    case _ Fail{reason}: Fail{reason}
    case Done{point} Done{points}: Done{point <> points}

def points(rows: +List<Row>, +x_magnitude: String, +y_magnitude: String, +index: Nat, +count: Nat) -> Result<&2, &2, String, +List<Point>>:
  match rows:
    case Nil{}: Done{Nil{}}
    case Con{+row, rest}:
      prepend_point(point(row, x_magnitude, y_magnitude, index, count), points(rest, x_magnitude, y_magnitude, 1n+index, count))

def values(kind: ChartKind, total: Nat, x_magnitude: String, y_magnitude: String, projected: Result<&2, &2, String, +List<Point>>) -> Result<&2, &2, String, Values>:
  match projected:
    case Fail{reason}: Fail{reason}
    case Done{points}: Done{Values{kind, points, total, x_magnitude, y_magnitude}}

def domains(+kind: ChartKind, +rows: +List<Row>, +total: Nat, x: Result<&2, &2, String, String>, y: Result<&2, &2, String, String>) -> Result<&2, &2, String, Values>:
  match x y:
    case Fail{reason} _: Fail{reason}
    case _ Fail{reason}: Fail{reason}
    case Done{+xm} Done{+ym}: values(kind, total, xm, ym, points(rows, xm, ym, 0n, List.length(&2, Row, rows)))

def admitted_rows(kind: ChartKind, total: Nat, selected: Result<&2, &2, String, +List<Row>>) -> Result<&2, &2, String, Values>:
  match selected:
    case Fail{reason}: Fail{reason}
    case Done{+rows}: domains(kind, rows, total, magnitude(rows, True{}, "0.000001"), magnitude(rows, False{}, "0.000001"))

def read_data(kind: ChartKind, +data: J.Json, +x_path: String, +y_path: String, paths_valid: Bool) -> Result<&2, &2, String, Values>:
  match data paths_valid:
    case J.Array{+rows} True{}: admitted_rows(kind, List.length(&2, J.Json, rows), read_rows(512n, rows, x_path, y_path))
    case _ _: Fail{"A chart requires an array and nonempty x/y field paths"}

def read_kind(found: Maybe<&2, ChartKind>, +attrs: J.Json) -> Result<&2, &2, String, Values>:
  match found:
    case None{}: Fail{"Unsupported chart kind; expected line-chart or bar-chart"}
    case Some{kind}:
      +x_path = J.text(J.get(attrs, "x"))
      +y_path = J.text(J.get(attrs, "y"))
      read_data(kind, J.get(attrs, "data"), x_path, y_path,
        Expression.path_valid(String.split(x_path, '.')) && Expression.path_valid(String.split(y_path, '.')))

def read(+attrs: J.Json) -> Result<&2, &2, String, Values>:
  read_kind(parse_kind(J.text(J.get(attrs, "@chart-kind"))), attrs)

# These commands define the visible geometry: line order is input order; every
# point has a marker, including a single-point line; each bar joins y to zero.
# Absolute coordinates avoid a second rounded subtraction for negative bars.
def line_commands(points: +List<Point>, first: Bool) -> String:
  match points first:
    case Nil{} _: ""
    case Con{Point{row, x, y}, rest} True{}: "M " ++ x ++ " " ++ y ++ " " ++ line_commands(rest, False{})
    case Con{Point{row, x, y}, rest} False{}: "L " ++ x ++ " " ++ y ++ " " ++ line_commands(rest, False{})

def point_commands(points: +List<Point>) -> String:
  match points:
    case Nil{}: ""
    case Con{Point{row, x, y}, rest}:
      "M " ++ x ++ " " ++ y ++ " m -2 0 l 4 0 m -2 -2 l 0 4 " ++ point_commands(rest)

def bar_commands(points: +List<Point>, +width: Nat) -> String:
  match points:
    case Nil{}: ""
    case Con{Point{row, x, y}, rest}:
      "M " ++ x ++ " 120 m -" ++ Nat.show(Nat.div(width, 2n)) ++ " 0 V " ++ y ++ " h " ++ Nat.show(width) ++ " V 120 Z " ++ bar_commands(rest, width)

def bar_width(points: +List<Point>) -> Nat:
  Nat.min(20n, Nat.max(1n, Nat.div(320n, Nat.max(1n, List.length(&2, Point, points)))))
