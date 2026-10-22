From Stdlib Require Import Arith.

(** Content edges and relationships are independent of paint and control state. *)
Inductive profile := IconControl | TextControl | OptionControl | NavigationRow
| Field | SearchField | Composer | EmbeddedEditor | Card | Menu | UserMessage
| Details | Navigation | Approval | CodeBlock | Lane | ArchiveGroup | PageContent.
Record insets := Insets { inline_inset : nat; block_inset : nat }.
Definition spacing value := match value with
| IconControl => Insets 4 4 | TextControl | NavigationRow => Insets 8 4
| OptionControl | Menu | Navigation | Lane => Insets 8 8
| Field => Insets 8 6 | SearchField => Insets 8 4
| Composer => Insets 12 0 | EmbeddedEditor => Insets 0 0
| Card | Approval | CodeBlock => Insets 12 12
| UserMessage => Insets 12 8 | Details => Insets 16 16
| ArchiveGroup => Insets 2 2 | PageContent => Insets 24 24 end.

Inductive part := Header | Body | Footer.
Definition partition value := Insets 24 (match value with
| Header => 14 | Body => 20 | Footer => 12 end).

Inductive relationship := NavigationRows | MenuItems | InlineControls
| ComposerControls | CardSections | Cards | BoardColumns | DialogSections
| DialogActions | Sections | Messages.
Definition separation value := match value with
| NavigationRows | MenuItems | InlineControls => 4
| ComposerControls | CardSections => 8
| Cards | DialogActions | Sections => 12
| BoardColumns | DialogSections | Messages => 16 end.

Record extent := Extent { extent_width : nat; extent_height : nat }.
Definition required_extent content_width content_height border area :=
  Extent (content_width + 2 * (border + inline_inset area))
    (content_height + 2 * (border + block_inset area)).
