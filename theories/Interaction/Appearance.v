From Stdlib Require Import String.
Open Scope string_scope.
Inductive appearance := SystemAppearance | LightAppearance | DarkAppearance.
Definition appearance_name a := match a with SystemAppearance => "system" | LightAppearance => "light" | DarkAppearance => "dark" end.
Definition decode_appearance s := match s with "system"=>Some SystemAppearance|"light"=>Some LightAppearance|"dark"=>Some DarkAppearance|_=>None end.
