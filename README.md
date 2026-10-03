# ConMa

ConMa (Construction Management)

iOS app for small and mid-size contractors: jobs, progress, costs, payments, crew.

- Spec: `docs/superpowers/specs/`
- Plans: `docs/superpowers/plans/`
- Setup for CI, signing and TestFlight: `docs/SETUP.md`

## Layout

- `Packages/Domain` — pure Swift business rules (tested on Linux)
- `Packages/Data` — GRDB/SQLite persistence
- `Packages/DesignSystem` — SwiftUI tokens and components
- `Packages/Features` — screens (MVVM)
- `App/` — thin app target, generated with XcodeGen (`project.yml`)
