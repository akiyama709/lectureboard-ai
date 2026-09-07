# Documentation index

## Product and design

- [Project roadmap](../ROADMAP.md)
- [開発ロードマップ](roadmap-ja.md)
- [macOS MVP technical design（日本語）](technical-design-ja.md)
- [Detailed technical design（日本語）](technical-design-detailed-ja.md)
- [Product requirements（日本語）](product-requirements-ja.md)
- [Product requirements（English）](product-requirements-en.md)
- [Architecture](architecture.md)
- [Development plan](development-plan.md)
- [Context-aware board planning（日本語）](context-aware-board-planning-ja.md)
- [Contextual board engine](contextual-board-engine.md)
- [Board-plan JSON Schema](board-plan.schema.json)

## Interface design

- [Screen design ver.1.3](design/screen-design-v1.3.md)
- [Interactive mock-up ver.1.3](design/interactive-mockup-v1.3.html)

## Privacy and open-source publication

- [Privacy and security](privacy-and-security.md)
- [プライバシー・セキュリティ設計](privacy-security-ja.md)
- [v1.0.0 release checklist](v1-release-checklist.md) — authoritative completion and release gates
- [v1.0.0 supported environment](supported-environment.md) — narrow first-release support contract and explicit exclusions
- [User guide](user-guide.md)／[利用案内](user-guide-ja.md) — install，permissions，first lecture，export，fallback，update及びuninstall
- [公開前ユーザー受入確認](user-acceptance-ja.md) — exact candidateを所有者自身のPPTX複製物で確認する非公開資料保護手順
- [No-fee v1 distribution process](no-fee-release-process.md) — authoritative packaging, publication, and public-byte verification order
- [Optional Developer ID distribution process](release-process.md) — retained for a possible future signed and notarized distribution
- [Versioning](versioning.md) — repository, bundle, build-number, and release-date consistency
- [初回GitHubリポジトリ公開記録](github-publication-ja.md) — historical initial-publication record; not the v1 release procedure
- [Initial open-source repository checklist](open-source-release-checklist.md) — historical initial-publication checklist

## Architecture decision records

The [`adr`](adr/) directory records the platform, overlay, context, AI-provider, grounding, license, public-v1 completion, visual-observation workflow, and fail-closed runtime-boundary decisions.

- [ADR 0008 — Post-identity frame timeout](adr/0008-post-identity-frame-timeout.md)
- [ADR 0009 — User-confirmed slide-canvas boundary](adr/0009-user-confirmed-slide-canvas-boundary.md)
- [ADR 0010 — Fail-closed production-overlay boundary](adr/0010-fail-closed-production-overlay-boundary.md)
- [ADR 0011 — Bound one-shot samples to the current visual-change candidate](adr/0011-bound-dense-change-fresh-samples.md)
- [ADR 0012 — Managed slide-show candidate and role challenge](adr/0012-causal-managed-slideshow-binding.md)
- [ADR 0013 — No-fee public v1 distribution](adr/0013-no-fee-public-v1-distribution.md)
- [ADR 0014 — Visual-only observation workflow for public v1](adr/0014-visual-observation-workflow.md)

## Local development handoff

- [`local-development-macos-ja.md`](local-development-macos-ja.md) — macOSでのローカル環境構築手順
- [`local-codex-handoff-ja.md`](local-codex-handoff-ja.md) — iPhone上の設計会話からローカルCodexへの引継ぎ
