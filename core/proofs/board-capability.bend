import Base
import ../board-capability-laws.bend as Rule
import ../ui-world.bend as View
import ../user-input.bend as U
import ../../BOARD.bend as B
import ../../MODEL.bend as M

def card_opens_details(+id: Nat, card: B.Card, route: U.Route, now: U32, world: M.World()) ->
  {Rule.opening(View.card_scene(id, card, route, now, world)) ==
    U.Activate{U.OpenPanel{U.CardDetails{id}, "card/" ++ Nat.show(id)}} : U.Input}:
  B.Card{revision, draft, task, archived, created, updated, enrichment, error, pinned} = card
  {==}

def Rule.evidence():
  Rule.Requirements{card_opens_details, +view => +search => +status => +priority => +date => +assignee => +creator => +project => +labels => +parent => +state => {==}, +id => +title => +status => +selected => +open => +parent => +state => {==}, parent => state => {==}, +reason => {==}, +revision => +draft => +task => +archived => +created => +updated => +enrichment => +error => +pinned => +parent => {==}, +parent => state => {==}, id => revision => state => {==}, +id => +revision => +name => +profile => +reasoning => +instructions => +settings => +concurrency => +edit => +parent => +world => +session => +services => {==}}
