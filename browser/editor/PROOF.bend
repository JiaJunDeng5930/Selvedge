import Base
import ./CONTRACT.bend as Rule
import ./MODEL.bend as Model

def Rule.composing_enter(owner, selection, shift, alt, modified, enabled, pending):
  {==}

def composition_guard(enter: Bool, key_code: U32, shift: Bool, alt: Bool, modified: Bool) ->
  {Model.native_key_ready((enter && False{}) && Bool.not(U32.is_eq(key_code, 229)), shift, alt, modified) ==
    Model.NativeKey{None{}, False{}} : Model.NativeKey}:
  match enter:
    case False{}: {==}
    case True{}: {==}

def Rule.native_composition_retains_default(keyboard, key_code, shift, alt, modified):
  composition_guard(String.eq(keyboard, "Enter"), key_code, shift, alt, modified)

def ime_guard(enter: Bool, composing: Bool, shift: Bool, alt: Bool, modified: Bool) ->
  {Model.native_key_ready((enter && Bool.not(composing)) && False{}, shift, alt, modified) ==
    Model.NativeKey{None{}, False{}} : Model.NativeKey}:
  match enter composing:
    case False{} _: {==}
    case True{} True{}: {==}
    case True{} False{}: {==}

def Rule.native_ime_retains_default(keyboard, composing, shift, alt, modified):
  ime_guard(String.eq(keyboard, "Enter"), composing, shift, alt, modified)

def Rule.native_enter_preserves_modifiers(key_code, shift, alt, modified, ordinary):
  Equal.cong(Bool, Model.NativeKey,
    ime => Model.native_key_ready(Bool.not(ime), shift, alt, modified),
    U32.is_eq(key_code, 229), False{}, ordinary)

def Rule.native_other_key_retains_default(keyboard, composing, key_code, shift, alt, modified, other):
  Equal.cong(Bool, Model.NativeKey,
    enter => Model.native_key_ready((enter && Bool.not(composing)) && Bool.not(U32.is_eq(key_code, 229)), shift, alt, modified),
    String.eq(keyboard, "Enter"), False{}, other)

def Rule.binding_evidence():
  Rule.BindingRequirements{
    +key => +editor => +entry => +value => +choices => {==},
    +key => {==}}
