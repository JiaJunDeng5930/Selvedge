import Base
import ./design.bend as D
import ./enclosure.bend as E

type Requirements is Type:
  Requirements{
    frames: {D.fact_content_layout() == D.FactContentLayout{E.Frame{E.ambient(0n, 0n), E.EmbeddedContent{4n}}, E.Frame{E.ambient(0n, 0n), E.SeparateFrames{E.Sections{}}}} : D.FactContentLayout}}

law evidence:
  Requirements
