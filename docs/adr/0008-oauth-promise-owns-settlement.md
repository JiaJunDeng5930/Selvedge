# Keep one owner for OAuth callback settlement

Status: accepted

## Context

The login listener may receive several HTTP requests while the user is opening
the authorization page or the accepted code is being exchanged. Its callback
Promise is awaited once before the authorization-code exchange and credential
publication. Resolving or rejecting that Promise again cannot repeat this
continuation.

A separate `received` flag crossed the native callback adapter and required
duplicate callbacks to return HTTP 409. This mirrored part of the Promise state;
it did not own the exchange or prevent a second credential write. Some rejected
callbacks settled the Promise without setting the flag at all.

## Decision

Let the callback Promise own login settlement. Keep the callback adapter's
request admission, including method, target, origin, state and issued client.
Keep signature, nonce and PKCE verification in the OpenID client. Remove the
duplicate-receipt state, its encoded observation and its HTTP 409 theorem.

A later HTTP callback receives the ordinary admission result, but cannot
replace the first settlement or start another exchange. The listener closes
when the owned login completes or fails. This uses the language's
[shared resolution guard](https://tc39.es/ecma262/2025/multipage/control-abstraction-objects.html#sec-createresolvingfunctions)
instead of implementing a second settlement policy.
