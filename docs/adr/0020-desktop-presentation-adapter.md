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
This change deliberately leaves every Bend source untouched. In particular, a
task label remains the native task label; the browser does not invent a title by
reading messages that the native presentation did not expose.

The browser owns only display mechanics: choosing which existing composer form
is visible, expanding settings, sizing the editor, following scroll position,
opening panels, and managing keyboard focus. Submitting an action still passes
through the same native resolver. An old enabled control is not authorization.

## Evidence

`npm run test:browser` drives the native kernel, SQLite, HTTP/SSE fixture and an
isolated Chrome profile. It checks pointer reachability for menus, settings and
approval actions, Enter/Shift+Enter/IME behavior, mobile navigation, modal focus,
stable streaming DOM and retained drafts. Screenshots cover light/dark, desktop,
mobile, details and permission requests. Those are browser-boundary checks, not
formal proofs about DOM layout or a commercial model.
