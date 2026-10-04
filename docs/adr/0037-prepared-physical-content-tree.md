# 0037: Prepare physical content before assigning presentation

Layout previously preceded construction of the actual content. Wrappers added
during rendering meant that reasoning over semantic children could not constrain
the physical content tree finally emitted.

Construct and retain the actual base and overlay content before assigning
presentation properties, then use that same cached content for final output.
This gives presentation allocation a stable object to constrain.

Derive the fixed application shell and root through one constructor. Allowing an
arbitrary prepared state to supply the root would remove the Canvas and scope
guarantees for arbitrary scenes.

Body organization and physical MainStructure express different decisions.
Overview therefore retains every organization, while production preparation and
allocation share the selection of MainStructure.

Shell selection returns style properties. A uniform shape-preserving operation
applies them, so this operation cannot change content. Selecting whole nodes by
String would also require the checker to infer complementary string branches.

The cost is retaining the physical content. Connecting actual spatial demand to
allocation remains a separate step; this change does not establish complete
viewport fit.
