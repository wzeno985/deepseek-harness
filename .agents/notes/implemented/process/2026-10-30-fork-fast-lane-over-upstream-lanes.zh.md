# Agent Note: fork 采用快速 lane 取代上游 PR lane

Status: implemented

[English](2026-10-30-fork-fast-lane-over-upstream-lanes.md) | 中文

## 问题

本仓库的拉取请求 lane 指向组织自有的 runner 池——[CI](../../../../.github/workflows/ci.yml) 的 `dsh-ubuntu-24-04-16core` 与 [CI Windows](../../../../.github/workflows/ci-windows.yml) 的 `dsh-windows-2025-16core`——另有若干 workflow 依赖组织集成或密钥:`issue-policy`、`issue-lifecycle`、`weighted-approval`、`pr-check-*`、Cloudflare 预览构建,以及真实 API 的 e2e 套件。个人 fork 一项都不具备:每个 lane 都会在一个该账号无法提供的标签上无限排队,而集成类 workflow 一启动即失败。

这个 fork 不是草稿副本。它的用途是让本项目自有的门禁跑在真实改动上,因此它需要一个真正能在个人账号所拥有的硬件上执行的拉取请求信号,同时把上游 lane 的定义保留到"容量可用时启用其中一个即可"的程度。

## 决策

四部分:托管兜底、单一快速 lane、advisory 基准 lane，以及仓库级禁用。

- **托管兜底。** `ci.yml`(四个 job)与 `ci-windows.yml`(三个 job)的最终兜底解析为 `ubuntu-24.04` 与 `windows-2025`。`blacksmith` 与 `selfhosted` 分支保持不变,因此任何上游 lane 在重新启用其 workflow 后即可按原样运行在托管容量上。
- **快速 lane。** [Fork fast checks](../../../../.github/workflows/fork-fast-checks.yml) 运行在 `ubuntu-24.04`:先执行 `pnpm run check:ci:static`(验证脚本门禁集),再执行 `scripts/ci-workflow.spec.ts`。实测墙钟约八分钟(两次运行分别为 8m03s 与 8m22s)。
- **Advisory 基准。** `node-24-bench` 在本 fork 上带 `continue-on-error: true`。共享托管池上的实测中位数超过最紧的预算:`conversation-fold/streaming-reasoning-leading-whitespace-16384` 为 82.55 毫秒与 87.48 毫秒,预算 80 毫秒;4096 用例为 30.82 毫秒,预算 30 毫秒。
- **仓库级禁用。** workflow 的启用状态是仓库元数据,不是文件内容。保持启用:`fork-fast-checks` 与 `pr-check-on-base-branch`(后者各 job 由变量门控,报为 skipped)。禁用:`ci`、`ci-windows`、`ci-python`、`e2e`、`ci-master`、`sandbox`、`build-preview-cloudflare`、`issue-lifecycle`、`issue-policy`、`weighted-approval`、`weighted-approval-review-event`、`pr-check-after-approve`、`pr-check-on-head-branch`、`release`、`release-vendor`。

该状态会在没有提交的情况下漂移:在网页界面启用某个 workflow,或在默认分支上修改某个 workflow 文件,都会恢复已禁用的 workflow。快速 lane 才是本意信号,所以当某个拉取请求开始跑超出预期的重 lane 时,需要重新核对启用清单,而不是给 workflow 写新代码。

## 守护 spec 的耦合

`scripts/ci-workflow.spec.ts` 钉住了本决策所改动的属性:Linux 与 Windows lane 的兜底标签,以及 `node-24-bench` 不是 advisory 这一点。因此本 fork 的断言只在这些位置与上游不同,且每处都在文件内说明了原因。

静态门禁集是一组验证脚本,从不加载 `scripts/**/*.spec.ts`,所以 workflow 或守护断言的回归只会进入单测 lane。该 lane 在本 fork 已禁用,这就是快速 lane 直接运行 `scripts/ci-workflow.spec.ts` 而不依赖 `check:ci:static` 的原因。

## 曾考虑的替代方案

- **在 `ci.yml` 内裁剪 job。** 否决:守护 spec 钉住了每个 job 的 `if` 与兜底标签,裁剪就会改写守护断言,并掩盖"上游 lane 仍按原样运行"这一事实。独立 workflow 让两件事同时成立。
- **用环境变量缩放基准预算。** 否决:基准契约要求预算为审过的源常量,并禁止环境变量覆盖,因此本 fork 无法在运行时调整预算。
- **改 workflow 文件来删掉重 lane。** 否决:启用状态是仓库元数据,删 job 只会为一个仓库级禁用已经能给到的结果增加持久的文件分叉。
- **在快速 lane 里跑整个 `scripts/` 套件。** 否决:该套件是按更大规格 runner 校准的,本地并行负载在单独运行可通过的 spec 中产生了 21 个无关失败。守护 spec 才是真正击中本 fork 的那一类不变量。
- **注册笔记本自建 runner。** 暂缓:现代笔记本的单线程性能足以恢复基准门禁,但公开 fork 会在任何已注册 runner 上执行拉取请求代码,而笔记本会休眠。

## 后果

换来的是:每个拉取请求都能在个人账号拥有的容量上、约八分钟内得到真实信号;上游 lane 定义保持可原样运行;守护 spec 让本 fork 的 CI 配置保持诚实。

代价是:单测、覆盖率、快照、Windows、Python 与基准 lane 不再门控任何东西。它们本可捕获的回归,只会在其 workflow 被重新启用或套件在本地运行时才浮现,而快速 lane 刻意只覆盖一类不变量而非整个套件。

这一代价的具体实例:advisory 基准改动合入时没有同步守护 spec,随后在默认分支上失败,原因是没有启用的 lane 会加载 `scripts/**/*.spec.ts`。后续提交修正了该断言,并把该 spec 移入快速 lane。

## 测试

- `pnpm exec vitest run scripts/ci-workflow.spec.ts` — 68 项全部通过,本地与合并后的默认分支均如此。
- `fork / static` — 托管 `ubuntu-24.04` 上 8m03s 与 8m22s,第二次运行包含守护 spec 步骤。
