export const viewports = [
  { id: 'desktop', width: 1440, height: 900, textScale: 100 },
  { id: 'marked', width: 1245, height: 588, textScale: 100 },
  { id: 'mid', width: 900, height: 720, textScale: 100 },
  { id: 'compact', width: 629, height: 588, textScale: 100 },
  { id: 'narrow', width: 320, height: 568, textScale: 100 },
  { id: 'short', width: 844, height: 390, textScale: 100 },
  { id: 'large', width: 420, height: 720, textScale: 200 },
];

const states = names => names.trim().split(/\s+/);

export const groups = {
  navigation: {
    title: 'Workspace navigation', script: 'navigation.mjs',
    states: states(`works-single desktop-sidebar compact-header global drawer-all drawer-global drawer-works
      works-many work-tree project-actions-revealed project-actions branches-collapsed project-collapsed
      task-selected rename-work rename-work-empty desktop-collapsed new-work-created work-renamed`),
  },
  conversation: {
    title: 'Conversation', script: 'conversation.mjs',
    states: states(`main audit-expanded code-wrap voice side task-details task-actions fork compact attachment
      preview upload-error approval blank-conversation streaming unfinished-reply failed-tool`),
  },
  properties: {
    title: 'New task and properties', script: 'properties.mjs',
    states: states(`creation task-environment-options permissions permissions-custom permissions-policy
      permissions-filesystem permissions-network permissions-source model model-effort model-settings model-source
      workspace directory project project-search project-editor`),
  },
  projects: {
    title: 'Projects and search', script: 'workspace.mjs',
    states: states(`projects project-new project-list-menu project project-edit project-directory-browser
      project-source project-details-menu project-delete history-empty history-results`),
  },
  board: {
    title: 'Task board', script: 'workspace.mjs',
    states: states(`board board-new-card board-filters board-settings board-archive board-card-details
      board-card-menu board-card-edit board-card-move board-card-link board-card-delete`),
  },
  graphs: {
    title: 'Task graphs', script: 'workspace.mjs',
    states: states('graphs graph-new graph-edit graph-menu graph-delete'),
  },
  shared: {
    title: 'Shared UI', script: 'workspace.mjs',
    states: states('shared-empty shared-populated shared-source'),
  },
  settings: {
    title: 'Settings', script: 'settings.mjs',
    states: states(`general instructions instructions-dirty title-prompts models profile-new profile-new-responses
      profile-new-responses-details profile-new-account profile-new-account-details profile-new-web profile-new-web-details
      profile-saved profile-saved-remove profile-long profile-long-remove model-access model-access-enabled model-access-details
      evaluator-new evaluator-new-details evaluator-saved connectors server-new server-new-details server-saved connection-new
      connection-new-list connection-saved extensions plugin-new plugin-new-details plugin-saved sources sources-list tasks
      cloud cloud-list cloud-details context limits limits-record service relay relay-error`),
  },
};
