import Base
import ./source-frame-rules.bend as Rule

def Rule.evidence():
  Rule.Requirements{
    +snapshot => +tree => +roots => +policies => {==},
    +key => +bounds => +interaction => +rest => +elements => +viewport => {==},
    +key => +bounds => +interaction => +rest => {==},
    +physical => +value => +interaction => +rule => +demand => +height => +bounds => +canvas => +rest => {==},
    +physical => +value => +interaction => +rule => +bounds => +canvas => +direction => +children => +rest => {==},
    +world => +viewport => +elements => +focused => +tab_order => +native_focus => {==},
    +left => +top => +width => +height => {==},
    +key => +bounds => +interaction => +viewport => +observed => +visible => +enabled => +tab => +keyboard => +scroll => +measured => +hit => +paint => {==},
    +focused => +entries => +elements => +viewport => {==},
    +key => +element => +viewport => {==}}
