From Stdlib Require Import String Bool NArith.
Open Scope string_scope.

Inductive role :=
| GlobalNavigation (compact : bool)
| GlobalNavigationEntry (selected compact : bool)
| CompactHeader | CompactWorkScope (title : string) (count : N)
| CompactNavigationMenu | CompactNavigationEntry (selected : bool)
| WorkTabs | WorkTab (selected : bool) | WorkTabGroup
| WorkOverviewButton (count : N) | WorkChoiceRow
| Navigation | NavigationHeader | NavigationEntry (selected : bool)
| NavigationCollection | NavigationSection
| Main | Heading | PrimaryButton | DestructiveButton | SelectedButton
| ComposerActions | DialogActions | Timeline | Activity
| UserMessage | AssistantMessage | Composer | Approval | Toolbar | CodeBlock
| ApprovalQueue | Section | Dialog | Menu | Details | Card | Button | Field
| Content | Alert.

Definition role_name value :=
  match value with
  | GlobalNavigation _ => "global-navigation"
  | GlobalNavigationEntry _ _ => "global-navigation-entry"
  | CompactHeader => "compact-header" | CompactWorkScope _ _ => "compact-work-scope"
  | CompactNavigationMenu => "compact-navigation-menu"
  | CompactNavigationEntry _ => "compact-navigation-entry"
  | WorkTabs => "work-tabs" | WorkTab _ => "work-tab" | WorkTabGroup => "work-tab-group"
  | WorkOverviewButton _ => "work-overview-button" | WorkChoiceRow => "work-choice-row"
  | Navigation => "navigation" | NavigationHeader => "navigation-header"
  | NavigationEntry _ => "navigation-entry" | NavigationCollection => "navigation-collection"
  | NavigationSection => "navigation-section" | Main => "main" | Heading => "heading"
  | PrimaryButton => "primary-button" | DestructiveButton => "destructive-button"
  | SelectedButton => "selected-button" | ComposerActions => "composer-actions"
  | DialogActions => "dialog-actions" | Timeline => "timeline" | Activity => "activity"
  | UserMessage => "user-message" | AssistantMessage => "assistant-message"
  | Composer => "composer" | Approval => "approval" | Toolbar => "toolbar"
  | CodeBlock => "code-block" | ApprovalQueue => "approval-queue" | Section => "section"
  | Dialog => "dialog" | Menu => "menu" | Details => "details" | Card => "card"
  | Button => "button" | Field => "field" | Content => "content" | Alert => "alert"
  end.
