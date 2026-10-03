# 0036: Canonical data semantics and compilation inputs

Shared data semantics were independently authored in features and codecs, although the actual state primitives need one owner. Assembly projections now use generic `Component.local`, so `Domain` provides those primitives without knowing the assembled `World`.

The native build identity previously omitted the actual `transport.c` input and included browser-only inputs. Sharing the source graph parser makes its fingerprint follow the actual native import closure, foreign C input and compiler bytes. This compilation identity is independent of the durable journal identity.
