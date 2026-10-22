# Selvedge 本地续做交接（临时资料）

本目录仅用于本次交接。用户已明确授权临时提交原本不应进入仓库的审查记录。最终交付前必须按末尾步骤移除整个目录，不能把它变成长期项目文档或第二份进度表。

## 已提交的起点

- 工作分支：`rework/rocq-domain-model`。继续此分支，不另开空白迁移。
- 最新源码提交：`3f10b0930b4d2b6c46e83ed349b5596cdea2a131`，修复队列非空时仍允许修改执行配置的问题。
- 上一源码提交：`340f42ad8a3a021ea729b824a72c362e315752b7`，修复 TaskGraph 安装后 Work 归属证明的编译问题。
- 原 Bend 参照提交：`acfbe86d8181415fd887c323cbba6495509d280f`，恰好 682 个文件，只读参考。
- 原任务中提及的 `6834161` 已是当前分支的祖先，不要退回那个提交。旧参考工作树自身的 HEAD 也不能替代固定参照提交。

## 进度与审查记录

`file-ledger.json` 是当前总表快照：**415/682 完成，267 pending**。pending 中 69 项已有单文件审查记录，198 项尚未逐项核对。总表的文件集合已与固定参照提交的 682 个路径逐一比对，相等。

完成数表示原文件职责已核对并完整承接，包括由当前数据表示或结构构造直接保证的职责；不表示整个产品、所有 UI 或最新全部浏览器场景已验收。没有代码变更的核对不需要空提交。

- `status=complete` 才计入完成数；`checked_individually=true` 只表示有过单文件审查，不能当作通过。
- `missing_requirements` 保存尚未闭合的职责；`audit_observations` 保存差异或待核实观察，不能机械地全部实现成新需求。
- 不因旧类型、辅助函数、同名定理或 Actual/Spec 双实现不存在就认定丢失需求。旧的重复规格和结构性字段隔离证明不应重新造回来。
- `harness/transport/wire.bend` 在收到用户交接要求后中断，已经保存发现；不是完整通过。
- 早先“空 summary_text 会被接受”的报告是误报，已经更正。当前 `receive_source` 的 `Some (String head tail)` 分支只接受非空字符串。
- 本轮开始前已有 307 个完成标记；当前总表继续累积到 415。239 是更早的恢复基线，不要用恢复规则覆盖现有总表，也不要导入历史上“整库迁移完成”的标记。

原 `.workpad/ui-remigration/` 的全部 113 个文件保存在 `private-records/ui-remigration.tar.gz`，归档内容已逐文件校验字节相等。它们含旧观察、实验、截图和 trace，属于历史证据；不能用其中旧的成功声明覆盖当前总表和验证记录。

## 已做的验证

源码提交 `3f10b093`：

- `bun run check` 成功：114 个模块检查，4 个执行目标，1027 个定理及 11 个生产入口在全局上下文中闭合，119 个 JavaScript 语法检查。
- 经真实 `Kernel.request` 公开入口执行 configure → create_idle → freeze → send → configure_task_execution。修复前接受修改，修复后返回 `task_busy`。临时实验及前后日志保存在 `verification/`。
- 该修复只补充 `Tasks.quiescent` 的空队列条件；没有增加永久的实现镜像测试，也没有关闭其余任务证明缺项。

以下浏览器结果对应上一源码提交 `340f42ad`，没有把它们冒充为新提交上的重跑结果：

```sh
bun test --timeout 30000 tests/ui-original-workflows.test.mjs tests/browser-workflows.test.mjs
# 7 pass, 0 fail
bun test --timeout 30000 tests/ui-migration-boundaries.test.mjs
# 3 pass, 0 fail
```

后面三项真实浏览器验收分别覆盖：目录准备期间继续捕获已提交内容且保留新草稿和导航；支持控件随测量空间压缩、堆叠及恢复；profile 从 catalog 消失后仍显示已存 ID 和 reasoning。更早“111 个模块、五个执行目标”的快照不能当作当前结果。所有本次验证日志位于 `verification/`。

## 尚未闭合的重点

1. **全局保持证明**：History 的 MODEL/PROOF/README，以及 harness 的 INVARIANTS/LAWS、protocol commit 等，仍缺实际 `Packet.packet` 上的完整关系性质。候选世界有效性和输出回滚不能代替跨转换历史/身份保留、操作及票据关联、取消权和 effect authority；不要用 trace 等式替代。
2. **审批**：最新四条用户纯文本、每条最多 4096 个 Unicode 码点的摘录实现已有，`harness/approval/MODEL.bend` 仍 pending，尚缺该摘录要求对应的实际入口验收。最新静态审查还发现 approval outcome 的 `reason` 被设为可选且允许空串，原协议要求非空；该发现未做专门入口实验。
3. **侧对话模型上下文**：创建侧对话没有把“父任务独立继续、关闭窗口不回传、只有显式 return 才回传”等初始指引送入 provider history。实际返回机制和动态父生命周期观察已有，不能把后者当作这段指引的替代。
4. **命令目录**：多个原命令说明被弱化为命令名；任务板附件参数的 item 字段结构/必填 id 未完整暴露。总表也记录了 U32/时间戳差异，先判断其当前领域意义，不要仅为恢复旧机器字宽限制而加分支。
5. **传输准入**：context/reasoning 的成功与失败字段合并为 optional 联合 schema，可能接受跨分支字段；remote probe 也接受 command-only 字段。wire 审查另报告 remote configuration 缺少 root-task-creation 限制，审查中断前尚未完成整条宿主授权路径实验。
6. **UI**：测量支持控件的三个入口已通过上述浏览器测试，但旧物理 Markdown policy/class/CSS 变量接线、32×32 toggle 点击区、焦点可见性恢复、工具提示/不可用原因、部分项目上下文与对话框顺序、周期性时间刷新、样式声明顺序等仍有未闭合项。详见总表，不重新开放全部已经闭合的文件。
7. **证明缺项**：任务生命周期/选定历史来源、侧上下文最终 dispatch 捕获、任务图整批投递、Worktree 初始化/共享和 Board 回调/启动组合等仍有记录。区分非平凡语义保证与由 record 更新或类型直接保证的性质，不补重复规格或无意义的同名定理。

provider 固定 44 个原文件的独立复核已经完成，不重新检查整个固定块。原布局分配器/probe 等由 ADR 0058、0062 明确淘汰；不要恢复那套引擎或其专属证明。

## 本地接续

先取得本分支最新提交。源码和临时交接资料使用两个独立提交，后续清理资料时必须保留源码修复。

```sh
mkdir -p .workpad/reconstruction
cp .handoff/rocq-migration/file-ledger.json .workpad/reconstruction/file-ledger.json
tar -xzf .handoff/rocq-migration/private-records/ui-remigration.tar.gz -C .workpad
```

恢复后以忽略的 `.workpad/reconstruction/file-ledger.json` 为唯一当前进度表；本目录保持交接快照，不同步维护第二份表。

按 `toolchain.json` 准备工具链。`scripts/bootstrap.sh` 要求 Bun 和 opam 已存在；旧环境的 `.workpad/reconstruction/env.sh` 不具有本地可移植性。使用现有构建器，不混拷其他快照的 `.vo`。

```sh
bash scripts/bootstrap.sh
bun run check
bun test --timeout 30000 tests/ui-original-workflows.test.mjs tests/browser-workflows.test.mjs
bun test --timeout 30000 tests/ui-migration-boundaries.test.mjs
```

用户要求继续多子代理并发：使用 **Luna 6、Max**，不要使用 6.1 子代理；每次只核对一个原文件，按用户原话交代核对要求，不添加额外流程，不要求返回迁移位置，只报告是否完整及遗漏需求。只在确实存在遗漏时修复；完成小块及时提交、推送，并及时报告 n/682。

本轮平台要求模型覆盖只能搭配 `fork_turns=none`，因此 Luna 子代理采用该方式；这与早先 full-history 要求的限制已明确反馈过。本地如有同样限制，也应明确说明，不能静默换成 6.1。交接时没有继续运行的子代理。

## 最终必须清理

AGENTS.md 的常规要求仍是私有记录留在忽略的 `.workpad/`；本次临时提交是用户专门授权的交接例外。

确认进度已在 `.workpad/` 保存后，最终交付或合并前执行：

```sh
git rm -r .handoff/rocq-migration
git commit -m "chore(migration): remove temporary continuation records"
```

最终检查 `git ls-files .handoff` 没有输出，并确保最终 PR 的差异不含本目录。默认 squash 合并，使临时交接资料不进入主分支的最终内容和 squash 提交；不要为了清理资料而回退或撤销独立的源码修复提交。最终产物不提交 ledger、旧实验、日志、截图、trace、临时交接文档或性能报告。
