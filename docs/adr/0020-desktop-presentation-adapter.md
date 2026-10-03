# 0020: Follow the installed desktop presentation in the Web adapter

## Reference

The inspected application was `openai-codex-electron` version `26.917.71314`,
installed in `ChatGPT.app/Contents/Resources/app.asar`. The local Codex Low Energy
launcher points to that application. `Codex Web GPT.app` is a separate launcher,
not the reference conversation interface.

Relevant application assets were inspected before changing this adapter:

- `app-shared-fa570b9eb9dd.css`: system font, neutral surface/text/border tokens,
  control sizes and radii; `app-initial-e8ceb32eb626.css`: conversation width.
- `user-message-e36f9e2dfe24.js` and `user-message-8b0705662651.css`: compact user
  bubbles and visually hidden conversation role headings.
- `thread-scroll-layout-27da424d79e0.js` and its CSS, the local-conversation page
  assets, and `composer-utility-bar-a9b94a95b731.js`: conversation/footer separation,
  compact controls, menus and side-panel presentation.

The extracted resources remain local research material in `.workpad`. No
application bundle, font or copied component is added to the repository.

## Decision

Replace the bespoke green branding, promotional new-task heading and large form
layout with the reference's neutral presentation and compact controls. Reuse the
existing native field bindings, action labels, availability and event payloads.
Keep the established incremental Markdown renderer and DOM reconciliation.

Do not add a terminal, file browser, Git controls, account catalog or task
lifecycle interpretation merely because the reference application has them.
The current scope is set by [ADR 0025](0025-native-conversation-and-desktop-source.md)
and [ADR 0026](0026-browser-executed-bend-ui.md).
