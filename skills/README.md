# Vendored Agent Skills

Third-party agent skills vendored into this repo so AI coding agents get the
same guidance on every machine. Symlinked into `.agents/skills/` for
auto-loading.

| Folder | Skill | Upstream | License |
|---|---|---|---|
| `swiftui/` | SwiftUI Expert (`swiftui-expert-skill`) | https://github.com/AvdLee/SwiftUI-Agent-Skill | See `swiftui/LICENSE` |
| `tvos/` | tvOS Design Guidelines | Derived from Apple's Human Interface Guidelines for tvOS (see `tvos/metadata.json` for source references) | Original prose in this repo |
| `xcode-project-setup/` | Xcode Project Setup | Written for this repo | MIT (repo license) |

## Updating

Re-vendor by replacing the folder contents wholesale and noting the upstream
commit/version in this table. Do not hand-edit vendored files — local changes
will be lost on the next update.
