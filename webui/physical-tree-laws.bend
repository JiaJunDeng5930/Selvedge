import Base
import ./renderer.bend as R
import ./document.bend as Doc
import ./design.bend as D
import ./layout.bend as Layout
import ../core/composition.bend as Composition

# The observation erases styles, retaining attributes, every content payload,
# event, key, portal target, and the complete ordered physical child tree.

def source(prepared: D.PreparedSurface) -> D.Surface:
  D.PreparedSurface{surface, base, overlays} = prepared
  surface

type Requirements is Type:
  Requirements{
    interpreter: @+value:Doc.Node -> @+placements:+List<D.NodePlacement> -> {Doc.structure(R.apply_placements(value, placements)) == Doc.structure(value) : Doc.Node},
    placement: @+prepared: D.PreparedSurface -> @+layout: D.Layout -> {Doc.document_structure(R.place(prepared, layout)) == Doc.document_structure(R.prepared_document(prepared)) : Doc.Document},
    identity: @+surface: D.Surface -> {source(R.prepare(surface)) == surface : D.Surface},
    allocation: @+parameters: D.LayoutParameters -> @+recipe: Composition.Recipe -> @+main: D.Box -> {D.frame_structure(Layout.main_frame(parameters, recipe, main)) == D.main_structure(recipe) : D.MainStructure}}

law evidence:
  Requirements
