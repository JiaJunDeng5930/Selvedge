From Stdlib Require Import Arith Lia.
From Selvedge.Browser Require Import Enclosure.

Theorem page_content_edges : spacing PageContent = Insets 24 24.
Proof. reflexivity. Qed.
Theorem page_sections_separation : separation Sections = 12.
Proof. reflexivity. Qed.
Theorem dialog_partition_edges part : inline_inset (partition part) = 24.
Proof. destruct part; reflexivity. Qed.
Theorem dialog_partitions_keep_distinct_block_edges :
  block_inset (partition Header) = 14 /\
  block_inset (partition Body) = 20 /\
  block_inset (partition Footer) = 12.
Proof. repeat split; reflexivity. Qed.
Theorem content_extent_contains_edges width height border area :
  width <= extent_width (required_extent width height border area) /\
  height <= extent_height (required_extent width height border area).
Proof. cbn. lia. Qed.
