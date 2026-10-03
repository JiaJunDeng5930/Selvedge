# 0037: Platform font observations and shared layout intent

Font metrics depend on the platform and are therefore observed inputs. Bend uses the same text intent to compute layout and emit the document, avoiding a second set of size and breakpoint rules in JavaScript.

This change covers typography and allocation of the main regions. Its evidence does not establish complete layout of all content or a proof of the entire rendered pixel output.
