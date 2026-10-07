import Base
import ./CONTRACT.bend as Rule

def Rule.evidence():
  Rule.Requirements{
    +ticket => +origin => +code => +message => {==},
    ticket => origin => {==},
    ticket => origin => {==},
    +surface => {==},
    +ticket => +origin => +code => +message => +content => +key => +semantic => +label => +role =>
      +conversation => +children => +rest => +overlays => +scope => {==}}
