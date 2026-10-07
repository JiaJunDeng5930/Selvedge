import Base
import ../recovery-rules.bend as Rule
import ../frontend-utility-rules.bend as UtilityRules
import ../source-frame-rules.bend as FrameRules
import ./frontend-utility.bend as UtilityProof
import ./source-frame.bend as FrameProof

def Rule.evidence():
  Rule.Requirements{
    UtilityRules.evidence(),
    FrameRules.evidence(),
    +capacity => +lifecycle => +world => +font => {==},
    +capacity => +lifecycle => +font => {==},
    +world => +purpose => +engine => +legacy => +serial => +anchors => +lifecycle => +displayed => {==},
    +frame => +legacy => +serial => +anchors => +lifecycle => +world => +semantic => +scope => +basis => +old => {==},
    +world => +purpose => +engine => +round => +glyph_only => +state => {==},
    +purpose => +engine => +round => +legacy => +serial => +anchors => +displayed => +reason => {==},
    +frame => +state => {==},
    +first => +rest => +frame => +legacy => +serial => +anchors => +lifecycle => +displayed => {==},
    +state => {==},
    +state => {==},
    +input => +state => {==}}
