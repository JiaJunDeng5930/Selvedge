From Stdlib Require Import String.
Open Scope string_scope.
Inductive appearance := SystemAppearance | LightAppearance | DarkAppearance.
Definition appearance_name a := match a with SystemAppearance => "SystemAppearance" | LightAppearance => "LightAppearance" | DarkAppearance => "DarkAppearance" end.
Definition decode_appearance s := match s with "SystemAppearance"=>Some SystemAppearance|"LightAppearance"=>Some LightAppearance|"DarkAppearance"=>Some DarkAppearance|_=>None end.
