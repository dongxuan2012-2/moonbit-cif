# CIF 源保真与标准不确定度工具库

本项目面向材料数据平台、晶体研究人员和批量计算工具作者，将晶体信息文件（CIF）变成可定位、可审阅、可局部改写的数据。使用者可以读取实验文件，选择测量或说明字段，把外部计算结果写回指定位置，并保留其余原文。

模块：`dongxuan2012-2/cif`，版本 0.1.0。当前维护及申报账号为 [dongxuan2012-2](https://github.com/dongxuan2012-2)，源码仓库为 [dongxuan2012-2/moonbit-cif](https://github.com/dongxuan2012-2/moonbit-cif)。源码通过本地 MoonBit workspace 集成；软件版权与依赖、数据的上游署名分别按 LICENSE 和 THIRD_PARTY.md 保留。

## 使用场景与能力

- **解析与定位**：解析 CIF1.1/CIF2 数据块、loop、save frame 及 CIF2 嵌套 List/Table，保留原词元并提供错误诊断和恢复。跨度是 UTF-8 半开字节区间，行列按 Unicode 标量计数，CRLF 计一次物理换行。
- **明确范围的读取**：按块、帧和标签查询原 Value，使用 Unicode 规范无大小写匹配。同一 loop 的同行投影保留请求列序；独立标签查询不拼接不同 loop 或广播标量。文件 values 入口可读取 Pair-only 文件及 loop 列，返回值、种类、原字面量和跨度，不猜 ID、单位或行关系。
- **测量词元桥接**：提取数值与标准不确定度，保留原 decimal lexeme、指数和有效零。未知、不适用、未给不确定度和引号字符串分别处理；超出有限 Double 投影的合法数值仍可保留原文。格式化针对给定 binary64 值半离零舍入，缩放整数超出 2^53 时返回错误。
- **源保真的局部改写**：按同一原语法树跨度单项或批量替换，拒绝重复、重叠、外来值和非法片段；整批及最终上下文验证后返回完整文本。未选字节、注释、引号和换行保留。
- **有限结构编辑**：向明确原 loop 追加一行、移除一条明确记录且至少保留一行，或向明确块/帧补入一个缺失 Pair。操作绑定完整源快照和结构见证，验证完整结果及结构变化；不推断 ID、字典、单位或异常值策略，核心 API 不执行磁盘写入。
- **说明文字编码**：将 LF 文字编码成所选 CIF1/CIF2 版本的单值字符串，保持空串及文字形式的问号、句点。无法无损表示的内容、CR/CRLF 新文字和非法字符明确返回错误。
- **文件审阅与写出**：catalog 发现结构，query/values 读取，preview 完整验证修改计划，独立 HTML 展示原文和预计组合结果，apply/append 独占新建输出并逐字节读回。原源散列绑定输入，可选预计结果散列约束输出；预览、人工审阅和真实磁盘回执分别表达各自结果。

## 实现与接入

MoonBit 承担解析、查询、测量桥接与编辑验证，核心支持 JS 和 Wasm-GC。Node.js≥22.3 宿主负责文件读写和散列，HTML 生成器是独立 JS 消费者。Unicode 规范化和可选 Lunar 单位/不确定度库直接复用；单位、相关性和传播策略由调用方决定。

从本仓库集成时，消费者 moon.mod 引用 `dongxuan2012-2/cif@0.1.0`，moon.pkg 导入 `dongxuan2012-2/cif`，moon.work 加入本仓库路径。各独立示例提供完整配置：

| 示例 | 可重放的用途 |
| --- | --- |
| examples/lunar、lunar-batch、lunar-selective、lunar-annotated | 实际 Lunar 量值计算、按原跨度选值及批量写回，支持 JS/Wasm-GC |
| examples/file-workflow | 真实文件的结构发现、只读值查询、ID 计划预览、HTML 审阅与新路径写出 |
| examples/value-reader | 实际 CIF1/CIF2 文件产生完整 values JSON，再交给独立公共包核对源散列/跨度、解析片段并接收真实 Lunar 量值 |
| examples/append-row、curate-loop、provenance-pair | 追加测量记录、剔除指定记录和补充缺失说明后的完整文件交接 |

例如进入 examples/file-workflow 运行 `moon run . --target js -- catalog sample.cif` 查看结构；进入 examples/value-reader 运行 `node verify.mjs` 重放文件读取与公共包接收链。完整参数、数据语义、写出保护和其他示例命令见 [README.md](README.md)。

## 设计特点与验证

项目关注原跨度选值、未选字节保留、完整结果验证，以及外部计算、明确计划和人工审阅之间的文件交接。通用 CIF 读写、Pair 创建和表行操作也由其他工具提供；本项目以源快照/结构见证和原始字节保真约束这些有限操作，不主张新的科学算法或通用误差传播模型。

[CI-PLAN.md](CI-PLAN.md) 定义双后端严格检查、构建、测试和实际消费者验证。固定独立输入/完整输出用于核对语义、跨度、原始字节与错误路径；实际运行时记录源码、编译产物和物理输入输出身份。HTML 审阅核对保存预览的源/预计身份，按原物理行显示并高亮替换片段。页面和散列匹配不替代人工批准；具体样本的浏览器回归不等同完整跨浏览器认证。真实同提交结论见仓库 [Actions](https://github.com/dongxuan2012-2/moonbit-cif/actions)。

## 范围与许可

本库不执行 STAR2 扩展、DDL/dREL、mmCIF 字典语义、单位或协方差推断、晶胞几何和空间群展开。流式接口保留全源并重扫前缀，不保证恒定内存；文件例程限定 UTF-8、新路径，不提供 gzip、原地覆盖或崩溃事务。示例为本项目自编公开包消费者，证明相应路径可运行，不代表外部机构采用。

原创软件遵循根 [LICENSE](LICENSE) 的 MIT 许可及原版权署名；Unicode 映射、规范化、可选 Lunar 依赖和参考数据保留各自许可证与作者。详见 [THIRD_PARTY.md](THIRD_PARTY.md) 与 [UNICODE-LICENSE.txt](UNICODE-LICENSE.txt)。模块与当前仓库账号一致，仓库维护/申报归属不改写原创版权、上游来源或 Git 作者历史。
