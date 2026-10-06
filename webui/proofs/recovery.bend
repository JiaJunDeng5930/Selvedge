import Base
import ../recovery-rules.bend as Rule

def Rule.evidence():
  Rule.Requirements{
    +capacity => +reason => +font => {==},
    capacity => message => font => {==},
    {==},
    +state => {==},
    +state => {==}}
