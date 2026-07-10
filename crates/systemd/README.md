# systemd

<!-- selvedge-package-readme
package: selvedge-systemd
freshness_commit: 592f95539c225023a2f2d66f8096a3f85ac304ee
-->

This crate owns the root-CLI systemd boundary for the Selvedge server unit.

Use it to validate the configured `selvedge-server` unit name, query unit status with the configured operation timeout, request unit start with the configured operation timeout, and wait for systemd to report `Active` or `Failed`.

`wait_service_active` polls until the configured timeout. If the caller drops the returned future, polling stops and no `SystemdError` is returned.

This crate does not install, write, or modify unit files. It does not treat systemd `Active` as server readiness, stop the server, check localhost endpoints, send business commands, or access router/events/client-sync mailboxes.

## Package State Machine

The diagram records the package-level observable states and transition paths. Each edge label names the concrete condition checked at this package boundary.

```mermaid
flowchart TD
  Start([systemd backend call])
  ValidateUnit[Validate configured unit name]
  Query[Run systemctl status query]
  StartUnit[Run systemctl start]
  Wait[Poll until active, failed, or timeout]
  Active[Return Active]
  Inactive[Return Inactive or Starting]
  Failed[Return Failed]
  Timeout[Return operation timeout]
  CommandError[Return process or UTF-8 error]
  ValidationError[Return unit validation error]

  Start -->|status query is requested| ValidateUnit
  Start -->|start request is requested| ValidateUnit
  Start -->|wait_service_active is requested| ValidateUnit
  ValidateUnit -->|unit name is accepted by configured policy| Query
  ValidateUnit -->|unit name is empty or violates policy| ValidationError
  Query -->|systemctl reports active| Active
  Query -->|systemctl reports inactive or activating| Inactive
  Query -->|systemctl reports failed| Failed
  Query -->|process spawn, exit, output, or decode fails| CommandError
  ValidateUnit -->|start request has valid unit| StartUnit
  StartUnit -->|systemctl start exits successfully| Wait
  StartUnit -->|process spawn, exit, output, or decode fails| CommandError
  Wait -->|poll observes active before deadline| Active
  Wait -->|poll observes failed before deadline| Failed
  Wait -->|deadline expires before active or failed| Timeout
  Wait -->|caller drops returned future| Inactive
```
