From Stdlib Require Import String List.
From Selvedge.Adapters Require Import Common ProviderCatalog.
Import ListNotations.
Open Scope string_scope.
Definition defaults := JObject [
  ("provider",JString "chatgpt");("endpoint",JString "https://api.openai.com/v1/responses");
  ("auth_file",JString "auth/chatgpt.json");("issuer",JString "https://auth.openai.com");
  ("timeout_ms",JNumber "300000")].
Definition audio_contract := JObject [
  ("client_id",JString "app_EMoamEEZ73f0CkXaXp7hrann");
  ("scopes",JString "openid profile email offline_access api.connectors.read api.connectors.invoke");
  ("auth_file",JString "auth/chatgpt-audio.json");("callback_port",JNumber "1455");
  ("refresh_interval_ms",JNumber "691200000")].
Definition contract := JObject [
  ("login_timeout_ms",JNumber "600000");("maximum",JNumber "1048576");
  ("namespace",JString ProviderCatalog.local_tool_namespace);
  ("resource",JString "https://api.openai.com/v1");
  ("scopes",JString "openid profile email offline_access resource.invoke chatgpt.tokens.use.direct");
  ("default",defaults);("audio",audio_contract)].
