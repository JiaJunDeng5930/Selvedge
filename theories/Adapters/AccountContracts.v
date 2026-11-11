From Stdlib Require Import String List NArith.
From Selvedge.Adapters Require Import Common.
Import ListNotations.
Open Scope string_scope.
Definition defaults := JObject [
  ("provider",JString "chatgpt");("endpoint",JString "https://chatgpt.com/backend-api/codex/responses");
  ("auth_file",JString "auth/chatgpt.json");("issuer",JString "https://auth.openai.com");
  ("timeout_ms",JNumber "300000")].
Definition client_id := JString "app_EMoamEEZ73f0CkXaXp7hrann".
Definition scopes := JString "openid profile email offline_access api.connectors.read api.connectors.invoke".
Definition originator := JString "selvedge".
Definition callback_path := JString "/auth/callback".
Definition device_login_timeout_ms : N := 900000%N.
Definition contract := JObject [
  ("login_timeout_ms",JNumber "600000");("device_login_timeout_ms",number device_login_timeout_ms);
  ("maximum",JNumber "1048576");
  ("client_id",client_id);("originator",originator);
  ("callback_path",callback_path);("callback_ports",JArray [JNumber "1455";JNumber "1457"]);
  ("refresh_interval_ms",JNumber "691200000");("default",defaults)].
