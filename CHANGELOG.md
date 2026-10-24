# Changelog

## [0.3.0](https://github.com/venkatamutyala/dotfiles/compare/v0.2.0...v0.3.0) (2026-10-24)


### Features

* **claude:** OpenTofu expert and long-running command rules ([#15](https://github.com/venkatamutyala/dotfiles/issues/15)) ([51e300d](https://github.com/venkatamutyala/dotfiles/commit/51e300dd430766e63c876c22f3fcc209ba053cd5))

## [0.2.0](https://github.com/venkatamutyala/dotfiles/compare/v0.1.0...v0.2.0) (2026-10-24)


### Features

* **claude:** add a /design agent team for feature design ([#14](https://github.com/venkatamutyala/dotfiles/issues/14)) ([3607128](https://github.com/venkatamutyala/dotfiles/commit/360712881747f3f92c866987b3fea542c41056cc))
* **claude:** harden /review with safety rules, pinned refs, and a Decisions list ([#12](https://github.com/venkatamutyala/dotfiles/issues/12)) ([f8d9f69](https://github.com/venkatamutyala/dotfiles/commit/f8d9f6933c5caea9860030c17f2ed71380ae3f88))

## [0.1.0](https://github.com/venkatamutyala/dotfiles/compare/v0.0.1...v0.1.0) (2026-10-24)


### Features

* **claude:** add /ship skill and a status line ([5be7125](https://github.com/venkatamutyala/dotfiles/commit/5be7125d9b56f1731d1d3e7e1177f38bd1fec704))
* **claude:** add code-review preferences to global CLAUDE.md ([791eee6](https://github.com/venkatamutyala/dotfiles/commit/791eee6d82fb5215825efb9681659c467ace0903))
* **claude:** add git, secret-scan, and data-safety rules to global CLAUDE.md ([63d4a80](https://github.com/venkatamutyala/dotfiles/commit/63d4a80c6a7b1f3862af2f723d450d95f4cb8df8))
* **claude:** add read-only domain-expert for technologies without an expert ([6af66da](https://github.com/venkatamutyala/dotfiles/commit/6af66da5f30b0a83ca014db6f0f651b05c57e121))
* **claude:** add review/build agent team with domain experts ([a7b26c4](https://github.com/venkatamutyala/dotfiles/commit/a7b26c43f65be0c54242a6140b5655611ceeaf53))
* **claude:** create AGENTS.md + CLAUDE.md for repos missing agent docs ([11cc40d](https://github.com/venkatamutyala/dotfiles/commit/11cc40da68e7eaf549677b04a6ced233f73428be))
* **claude:** install ~/.claude config tree from claude/ manifest ([d003bcb](https://github.com/venkatamutyala/dotfiles/commit/d003bcbcda42fc536c83a6a5e9ca812739536165))
* **claude:** let domain-expert pull in as many related experts as needed ([f8ebe94](https://github.com/venkatamutyala/dotfiles/commit/f8ebe94a7a44177463bf34250e0e3a2f737b5144))
* **claude:** let domain-expert pull in experts for related technologies ([e1f2a76](https://github.com/venkatamutyala/dotfiles/commit/e1f2a766f2a61ec1d3cdcc959d3d757d854a10e9))
* **claude:** let experts pulled in by domain-expert pull in their own ([3e0116f](https://github.com/venkatamutyala/dotfiles/commit/3e0116fc091dd67c313a7e242ec243657f970b96))
* **claude:** load secret guardrails only outside --yolo ([c7f95a5](https://github.com/venkatamutyala/dotfiles/commit/c7f95a5048296cf0f73afbc938fc88cf76881a0a))
* **claude:** prefer simple code, minimal comments, concise PRs ([d9a69fa](https://github.com/venkatamutyala/dotfiles/commit/d9a69faead27ba5af8710521a116f03b134a8244))
* **claude:** run Claude's Bash tool under bash; mount from /workspaces/glueops ([bca8824](https://github.com/venkatamutyala/dotfiles/commit/bca88240590e9832e309ab2cc7ac3a8492307255))
* **claude:** secret-scan commits and pushes with a hook ([#10](https://github.com/venkatamutyala/dotfiles/issues/10)) ([1b05405](https://github.com/venkatamutyala/dotfiles/commit/1b05405e52e980e5f94643be5a27e3a52591c609))
* run cde-init first (if present) before installing dotfiles ([#5](https://github.com/venkatamutyala/dotfiles/issues/5)) ([76264c2](https://github.com/venkatamutyala/dotfiles/commit/76264c212f400d1d1493f427305af0b99a37f2af))


### Bug Fixes

* isolate cde-init from the curl|zsh pipe; skip it on dry-run ([#6](https://github.com/venkatamutyala/dotfiles/issues/6)) ([686997a](https://github.com/venkatamutyala/dotfiles/commit/686997ac76f06e023bca66febfd3f946f5318895))
