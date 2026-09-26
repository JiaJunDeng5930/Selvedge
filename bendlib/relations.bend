import Base

# Generated from quoted Rocq relation proofs; do not edit.
# Source copyright INRIA, CNRS and contributors; LGPL-2.1 (theory/LICENSE).
# Applications in ExportRelations.v only supply an existing theorem's premises.

type Closure<-A: Data, -R: @-x:A -> @-y:A -> Type, -x:A, -y:A> is Type:
  Step{edge: R(x, y)}
  Refl{same: {x == y : A}}
  Trans{-middle: A, left: Closure<A, R, x, middle>, right: Closure<A, R, middle, y>}

type Preorder<-A: Data, -R: @-x:A -> @-y:A -> Type> is Type:
  Preorder{reflexive: @-x:A -> R(x, x),
    transitive: @-x:A -> @-y:A -> @-z:A -> R(x, y) -> R(y, z) -> R(x, z)}

def rt_step(-A: Data, -R: @-x:A -> @-y:A -> Type, -x:A, -y:A, edge:R(x,y)) -> Closure<A,R,x,y>:
  Step{edge}

def rt_refl(-A: Data, -R: @-x:A -> @-y:A -> Type, -x:A) -> Closure<A,R,x,x>:
  Refl{{==}}

def rt_trans(-A: Data, -R: @-x:A -> @-y:A -> Type, -x:A, -y:A, -z:A,
  left:Closure<A,R,x,y>, right:Closure<A,R,y,z>) -> Closure<A,R,x,z>:
  Trans{y, left, right}

# Original source theorem: Stdlib.Relations.Operators_Properties.clos_rt_is_preorder
def clos_rt_is_preorder(~A_0: Data, ~R_1: @-__3:A_0 -> @-__4:A_0 -> Type) ->
  Preorder<A_0, (closure_x => closure_y => Closure<A_0, R_1, closure_x, closure_y>)>:
  Preorder{rt_refl(A_0, R_1), rt_trans(A_0, R_1)}

# Original source theorem: Stdlib.Relations.Operators_Properties.clos_rt_idempotent
def clos_rt_idempotent(~A_0: Data, ~R_1: @-__3:A_0 -> @-__4:A_0 -> Type, -x_8: A_0, -y_9: A_0, __10: Closure<A_0, (closure_x => closure_y => Closure<A_0, R_1, closure_x, closure_y>), x_8, y_9>) ->
  Closure<A_0, R_1, x_8, y_9>:
  match __10:
    case Step{r_64}: r_64
    case Refl{endpoint_equality}:
      %endpoint_equality : Closure<A_0, R_1, x_8, _>
      rt_refl(A_0, R_1, x_8)
    case Trans{y_69, c0_67, c1_66}: rt_trans(A_0, R_1, x_8, y_69, y_9, clos_rt_idempotent(~A_0, ~R_1, x_8, y_69, c0_67), clos_rt_idempotent(~A_0, ~R_1, y_69, y_9, c1_66))

# Source theorem application: ExportRelations.closure_map
def closure_map(~A_0: Data, ~B_1: Data, ~R_2: @-__14:A_0 -> @-__15:A_0 -> Type, ~S_3: @-__17:B_1 -> @-__18:B_1 -> Type, ~f_4: @__5:A_0 -> B_1, ~one_6: @-x_7:A_0 -> @-y_8:A_0 -> @__9:R_2(x_7, y_8) -> Closure<B_1, S_3, f_4(x_7), f_4(y_8)>, -x_10: A_0, -y_11: A_0, path_12: Closure<A_0, R_2, x_10, y_11>) ->
  Closure<B_1, S_3, f_4(x_10), f_4(y_11)>:
  match path_12:
    case Step{r_78}: one_6(x_10, y_11, r_78)
    case Refl{endpoint_equality}:
      %endpoint_equality : Closure<B_1, S_3, f_4(x_10), f_4(_)>
      rt_refl(B_1, S_3, f_4(x_10))
    case Trans{y_83, c0_81, c1_80}: rt_trans(B_1, S_3, f_4(x_10), f_4(y_83), f_4(y_11), closure_map(~A_0, ~B_1, ~R_2, ~S_3, ~f_4, ~one_6, x_10, y_83, c0_81), closure_map(~A_0, ~B_1, ~R_2, ~S_3, ~f_4, ~one_6, y_83, y_11, c1_80))

# Source theorem application: ExportRelations.closure_invariant
def closure_invariant(~A_0: Data, ~R_1: @-__14:A_0 -> @-__15:A_0 -> Type, ~P_2: @-__3:A_0 -> Type, ~one_4: @-x_5:A_0 -> @-y_6:A_0 -> @__7:P_2(x_5) -> @__8:R_1(x_5, y_6) -> P_2(y_6), -x_9: A_0, -y_10: A_0, path_11: Closure<A_0, R_1, x_9, y_10>, seed_12: P_2(x_9)) ->
  P_2(y_10):
  match path_11:
    case Step{r_140}: one_4(x_9, y_10, seed_12, r_140)
    case Refl{endpoint_equality}:
      %endpoint_equality : P_2(_)
      seed_12
    case Trans{y_145, c0_143, c1_142}: closure_invariant(~A_0, ~R_1, ~P_2, ~one_4, y_145, y_10, c1_142, closure_invariant(~A_0, ~R_1, ~P_2, ~one_4, x_9, y_145, c0_143, seed_12))
