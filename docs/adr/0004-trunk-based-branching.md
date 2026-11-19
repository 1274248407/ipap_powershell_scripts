# 采用单主干分支模型，不采用 GitFlow

**Status**: accepted（2026-11-20）

## 背景

项目一度同时存在三条长期分支，其中两条已完全合并、只剩漂移：

```
dev                       落后 main 137 个提交，独有提交 0
feat/sampler-restructure  落后 main 5 个提交，  独有提交 0
main
```

同时这个仓库没有任何 CI（无 `.github/`），测试与打包都靠本地 `.\build.ps1`；
发布是 `-Task Release -Bump`，由脚本完成版本校验、tag、push 与 `gh release`。
需要回答：是否改用 nvie《A successful Git branching model》的 GitFlow。

## 决策

采用单主干（trunk-based）：**只有 `main` 一个长期分支**，其余分支短命、合并即删。

1. `main` 必须始终能通过 `.\build.ps1 -Task Pack`（Build + Analyze + Test）。
2. 改动走短生命周期分支（`feat/...`、`fix/...`），几天内合并回 `main`；1–2 个提交的小改直接提交 `main`。
3. 发布只从 `main` 打 tag：`.\build.ps1 -Task Release -Bump patch|minor|major`；不建 release 分支、不做发布冻结。
4. 热修直接在 `main` 上修并升 patch，不建 hotfix 分支、不做双向回合并。
5. 合并后删除分支，只保留 tag。

## 考虑过的替代方案

- **完整 GitFlow**（`master` + `develop` 两条永久分支，加 feature / release / hotfix 三类限时分支）：
  它的价值在于多人并行开发时的功能隔离、发布前的冻结窗口、以及同时维护多个线上版本；
  本项目是单人开发、无 CI、只有一个用户且永远用最新版，这三项都不成立。
  采用它等于为不存在的并行与多版本维护付出合并纪律的成本，并会把「长期分支」制度化为常态——
  而本仓库已经用两条死分支证明了这种常态只会积累漂移。
- **`main` + `dev` 双主干（GitFlow-lite）**：省掉 release/hotfix，但仍多一道合并；
  对单人项目没有收益，只增加「这行改动该进哪条分支」的判断成本。
- **直接把所有改动提交到 `main`、完全不用分支**：也可行，但不利于「一个任务一组提交」的回退；
  保留短命分支成本几乎为零，因此保留。

## 依据

- nvie 在原文顶部 2020-03-05 的补充说明里明确写道：持续交付的软件应改用更简单的流程（如 GitHub flow），
  GitFlow 适合「explicitly versioned」或「需要同时支持多个线上版本」的软件。
  本项目虽然按 SemVer 发版，但**不维护多个线上版本**，只满足前半句、不满足后半句。
- 发布纪律无需靠分支保证：`build.ps1` 已有 `Assert-VersionReady`（SemVer 格式、tag 未占用、
  必须大于上一个版本 tag）与 `-Task Pack` 的强制依赖链（Build → Analyze → Test）。

## 影响

- 已删除 `dev` 与 `feat/sampler-restructure`（本地与远端），两者独有提交均为 0，历史全部保留在 `main`。
- 规则写入 `AGENTS.md` 的「Git 分支与发布」段，随每次改代码一起被读到。
- 若将来出现多人协作、或多版本并行维护的真实需求，再按 GitFlow 的 release / support 分支补充，
  不需要现在就预置。
