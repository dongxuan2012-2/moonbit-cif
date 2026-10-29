# moonbit-cif

原生 MoonBit CIF 1.1 / CIF 2.0 源码保真解析、标准不确定度词元和诊断库。模块标识为 `dongxuan2012-2/cif`，版本 0.1.0，支持 JS 与 Wasm-GC。

源码仓库：[dongxuan2012-2/moonbit-cif](https://github.com/dongxuan2012-2/moonbit-cif)。当前维护及申报账号为 [dongxuan2012-2](https://github.com/dongxuan2012-2)；软件版权、依赖作者和数据来源分别按 [LICENSE](LICENSE) 与 [THIRD_PARTY.md](THIRD_PARTY.md) 保留。

把 CIF 输入变成可定位的嵌套值/表格，提取 `1.5423(12)`，把外部计算结果只替换回指定值，并保留其余字节、注释、引号和换行。核心负责 CIF 语法、原跨度和词元桥接；通用误差传播由外部库负责，晶体空间群运算属于其他领域工具。

## 运行

使用 MoonBit 工具链：moon 0.1.20260920、moonc 0.10.14。Node 运行 JS，moonrun 运行 Wasm-GC；文件例程要求 Node.js≥22.3。Unicode normalization 是显式的纯 MoonBit 依赖，版本固定在 moon.mod。

GitHub Actions 使用官方 `0.10.14+7d59c7ec9` Linux SDK/core 发行包和 Node.js `24.11.0`；`scripts/setup-ci.sh` 校验固定 SHA256，并仅在 runner 临时目录安装。CI 执行双后端 check/build/test、四个 Lunar 消费者、追加行的外部 Lunar 接收，以及文件预览、HTML 审阅和实际写出后的散列与值核对。每次运行的真实结论见仓库 [Actions](https://github.com/dongxuan2012-2/moonbit-cif/actions)。

```sh
moon check --deny-warn --target js
moon build --deny-warn --target js
moon test --deny-warn --target js
moon check --deny-warn --target wasm-gc
moon build --deny-warn --target wasm-gc
moon test --deny-warn --target wasm-gc
moon run cmd/demo --target js
```

PowerShell 检视真实文件（最后一个参数是文本，不是路径）：

```powershell
$text = Get-Content -LiteralPath examples/file-workflow/sample.cif -Raw -Encoding UTF8
moon run cmd/inspect --target js -- $text
```

外部库接入示例是独立模块，通过各自的 `moon.work` 引用本地库。自有工程的 `moon.mod` 引用 `dongxuan2012-2/cif@0.1.0`，`moon.pkg` 导入 `dongxuan2012-2/cif`，并在 `moon.work` 中加入此仓库路径；完整配置见 `examples/value-reader`。源码分发与接入命令如下：

```sh
cd examples/lunar
moon run . --target js
moon run . --target wasm-gc
```

它调用真实的 LunarUncertainty `MeasuredQuantity::checked_from_parts` 和 `scale`，输出 `_length 3.0846(24)`。适配器由调用方明确选米为单位；缺失u不会变成零，相关性/单位/传播规则由外部库与调用方负责。

批量计算并保留原始排版的示例：在 `examples/lunar-batch` 运行 `moon run . --target js` 或 `--target wasm-gc`。它用同一份原AST中的标量与loop单元格构造修改集，调用真实Lunar `scale(2.0)`，一次写回3个测量结果；注释、行序、未知值`?`及没有给出u的`4.200`保持原样。示例的`*_m`字段由调用方明确使用米，不作字典单位推断。

示例通过 `file.find_values("BATCH", "_LENGTH_M")` 直接取得列，省去按列下标遍历loop。若数据在save frame中，可用 `file.find_values("batch", "_length_m", frame="run1")`；块/帧参数省略`data_`/`save_`。返回原Value及其跨度，直接交给批量编辑器。

按ID选择部分行时，用 `file.find_loop_rows("batch", ["_sample_id", "_length_m"], frame="run1")` 取得同一loop的同行原Value，结果列顺序与请求一致。不同loop中等长的两列不能直接推断同行关系。`examples/lunar-selective` 可在JS/Wasm-GC运行：它通过Unicode帧名查询，按ID只计算B/D，保留A/C、块内同名值及另一loop，打印源文、改写结果与原行跨度的JSON。

计算后写入用户说明文字时，先用 `format_string(text, version=file.version)` 编成字符串字面量，再交给 `replace_values`；不要直接拼接引号。`examples/lunar-annotated` 可在JS/Wasm-GC运行，它在同一批中写入B/D的真实Lunar结果和处理说明，包含混合引号、多行分号内容及作为文字的`?`。打印JSON便于读回原文、替换片段及原跨度。

## 向原 loop 追加一条逻辑行

`file.append_loop_row(target, cells, expected_source=source, newline="\r\n")` 返回 `Result[String, String]`。调用者明确选取原 `Entry::Loop`，按原表头顺序传入恰好一行、已经编码的单值片段；说明文字先用 `format_string(text, version=file.version)` 编码。分号文本、跨行字符串及 CIF2 List/Table 各算一个单元格，一条逻辑行可以占多条物理行。

```moonbit
let file = @cif.parse_string(source).unwrap()
let target = file.blocks[0].entries[0] // 调用者已明确选择的 loop
let appended = file.append_loop_row(
  target, ["B", "2.500(3)", "."], expected_source=source, newline="\r\n",
).unwrap()
```

源快照须完全相同，包括 BOM、原换行和未归一化的 Unicode。接口以同版本重新解析有效原文，要求见证的表头、值、词元及跨度恰好匹配唯一实际 loop，且已有行非空完整、表头规范互异；从相同源文另一次解析取得的结构相同见证也等价。它不推断 ID，也不检查新旧 ID 是否重复。

插入点位于最后一个旧值之后，越过原注释与空白，到下一个结构词元之前或 EOF。每个新单元格用所选 LF 或 CRLF 分隔，默认 LF；前缀尚未结束一行时补上该分隔符。所有原字节保持顺序不变，片段内部的原换行也不改写。接口复用单值验证，再验证完整结果及仅增加一行的结构；源文过期、见证不符、宽度错误、夹带额外结构或值外注释、非法编码、最终上下文冲突、既有行长/深度预算超限均返回 Err。文件对象、见证和输入数组不变，只返回完整文本；磁盘写出由调用者负责。

可运行的固定测量交接示例：

```sh
cd examples/append-row
moon run . --target js
node verify.mjs
```

生产者把 96 字节的 BOM/CRLF 原文中的 A 行保留，在偏移 82 追加独立手写的 16 字节 `B\r\n2.500(3)\r\n.\r\n`，输出完整 112 字节。`verify.mjs` 与事先固定的完整期望及前缀/插入/后缀逐字节比较，实际新建输出、读回，再将 `examples/append-receiver` 复制到 checkout 外的独立 MoonBit 包读取该文件。接收器仅用公共解析/查询/测量 API 和真实 Lunar 依赖，核对两行原序及 B 的值 2.5、不确定度 0.003；米由调用者声明。回执保留文件和编译产物身份。这是运行时交接示例，尚无实际实验室请求或外部采用证据；文件工作流的既有计划和命令不变。

## 移除一条明确选择的原记录

`file.remove_loop_row(target, row, expected_source=source)` 返回 `Result[String, String]`，`row` 是所选原 loop 的零起始逻辑行索引。源快照须完全相同；`target` 是与有效同版本原文唯一匹配的完整 `Entry::Loop` 结构见证，相同源文另一次解析得到的等价见证也可使用。索引须在范围内，删除后须至少保留一条完整行；接口不猜 ID、不决定哪些记录应剔除。

```moonbit
let file = @cif.parse_string(source).unwrap()
let target = file.blocks[0].frames[0].entries[0] // 调用者已选定的原 loop
let curated = file.remove_loop_row(target, 1, expected_source=source).unwrap()
```

仅删除所选行各个顶层 Value 的 UTF-8 区间，其余所有字节按原序保留，不添加分隔符。单元格内的引号、跨行文本、复合值及复合值内注释属于删除范围；范围外空白和注释保留，因此可能留下空行或只有注释的行。一条逻辑行不等于一条物理行，也不会据此裁掉整条物理行。最终同版本解析检查保留的原词元/值、映射后的字节位置和仅减一行的结构；删除跨行值造成保留内容拼成超长行等上下文/预算错误时返回 Err。源文件对象和见证不变，返回完整文本或错误，不执行磁盘写入。

在 `examples/curate-loop` 运行 `node verify.mjs` 可重放真实文件接收。生产者从传入路径读取 CIF，按示例中明确的已知布局/索引剔除记录；验证脚本写入新文件并读回，再交给 checkout 外的公共 API/真实 Lunar 接收器。独立手写 CIF2 样本240→210字节，保留范围外的注释和 A/C 的2/u0.01、4/u0.02；CIF1样本87→61字节，移除带分号文本的X行并保留Y的1.25/u0.005。米及剔除策略由调用者声明，库不判定异常值。另一个输入变体核对无关原字段也保留，生产者没有回放固定输出。此例不新增文件工作流命令或通用计划；自编接收器不代表第三方采用。

## 补入一条缺失的处理说明

`file.add_pair(scope, name, fragment, expected_source=source)` 向明确选择的原块或帧增加一个尚不存在的 Pair，返回 `Result[String, String]`。源快照完全相同，`scope` 须与有效同版本原文中的唯一 Container 结构匹配；相同源文另次解析的等价见证也可用。`name` 是一个合法数据名，在该作用域的直属 Pair/loop 表头中须按既有规范名称匹配规则互异；其他块/帧可以已有同名字段。已有字段用原替换接口处理。

```moonbit
let file = @cif.parse_string(source).unwrap()
let scope = file.blocks[0].frames[0] // 调用者明确选择的原帧
let note = @cif.format_string("已核对", version=file.version).unwrap()
let annotated = file.add_pair(scope, "_processing_note", note, expected_source=source).unwrap()
```

`fragment` 是一个已编码值，说明文字复用 `format_string`，不拼接引号。插入点在原作用域头之后，越过原前导空白/注释，位于首个原有效词元或EOF之前；新数据名和值各占自己的行，新增分隔符为LF，必要时补一个前导LF。所有旧字节保持原序，包括原BOM/CRLF、缩进、注释、数值和引号；保留的缩进可能成为空行。验证合法数据名、单值、直接作用域重名及完整同版本结果，并检查只增加一个Pair和原条目/帧/块/跨度的对应关系。返回完整文本或Err，原对象不变，不执行磁盘写入、不推断字典或单位。

在 `examples/provenance-pair` 运行 `node verify.mjs` 可重放真实文件接收：生产者从路径读取原CIF，按示例已知布局选择帧或块，通过新接口创建调用者的 `_processing_note`。验证脚本写出并读回完整文件，交给checkout外的公共API/真实Lunar接收器核对新增说明及全部原量值。独立手写CIF2为166→195字节，在原注释后插入29字节；CIF1为50→87字节，保留EOF注释和原缩进。还以另一原字段的输入变体核对完整输出，防止常量回放。默认接收目录在checkout父目录，可用 `CIF_EXAMPLE_RECIPIENT_ROOT` 指向另一个可写外部目录。此例不新增通用文件命令或编辑计划；自编接收器不代表第三方采用。

## 任意本地文件的查询与批量写出

`examples/file-workflow` 是独立的 Node.js >=22.3 / JS 命令行例程，通过文件路径读取UTF-8 CIF1/CIF2和JSON计划，输入内容不放进命令行参数。核心库仍支持JS/Wasm-GC；旧`cmd/inspect`仍接收文本。

```powershell
cd examples/file-workflow
moon run . --target js -- catalog sample.cif
moon run . --target js -- query sample.cif scope.json
$cifForecast = moon run . --target js -- preview sample.cif sample-plan.json | ConvertFrom-Json
if (-not $cifForecast.ok) { throw $cifForecast.error }
$cifForecast | ConvertTo-Json -Depth 20
New-Item -ItemType Directory -Force work | Out-Null
$cifForecast | ConvertTo-Json -Depth 30 | Set-Content work/sample.preview.json -Encoding utf8
node review-preview.mjs work/sample.preview.json work/sample.review.html
```

打开`work/sample.review.html`审阅内容。决定写出时，使用同一输入与计划，并将保留的预计散列传给写出命令：

```powershell
moon run . --target js -- apply sample.cif sample-plan.json work/sample.output.cif --expect-result-sha256 $cifForecast.planned.sha256
```

随附样本的计划已绑定其SHA256，结果只新建`work/sample.output.cif`；再次运行前须另选未存在的输出路径。

不知道文件中的名称时，先运行`catalog INPUT.cif`。它只读文件并打印JSON：`blocks`及其`frames`的`name`可直接用于查询配置，`header`保留原始`data_`/`save_`拼写；`loops`逐组给出列名、列/单元格/行数和原UTF-8跨度，复合值仍算一个单元格；`pairs`给出标签及标签/值跨度。用户明确选择一个loop和其中的ID列，程序不猜ID、不拼接不同loop，也不把Pair当作loop列。Pair-only或无块的合法文件会如实给出空数组。无配置即可发现块/帧/列名，然后建立查询配置，例如：

```json
{"block":"lab","frame":"run1","idTag":"_sample_id","columns":["_length_m","_note"]}
```

`query INPUT.cif SCOPE.json` 返回`sourceSha256`、请求列顺序、同行的解码值/原字面量/种类及UTF-8跨度。省略`frame`查块，省略`columns`只查ID列。将返回的SHA256和外部算好的结果写入计划：

```json
{"block":"lab","frame":"run1","idTag":"_sample_id","sourceSha256":"复制query返回的完整散列","edits":[{"id":"B","tag":"_length_m","cif":"4.200(60)"},{"id":"B","tag":"_note","text":"processed B"}]}
```

再运行`apply INPUT.cif PLAN.json NEW_OUTPUT.cif`。每项只能选`cif`或`text`：前者是已编码的单值CIF片段，后者交给`format_string`；程序不执行计算表达式。标签/块/帧沿用库的名称匹配；ID按解码后的标量文字区分大小写，裸`?`/`.`不作ID。所选ID须恰好匹配一行，目标列须与ID列同loop，不能修改ID列。输入散列变化、缺失/歧义ID、重复目标或任一非法替换均在创建输出前失败。空`edits`可在范围/散列校验后生成原样副本。

写出前可先运行`preview INPUT.cif PLAN.json`。它复用`apply`的全部目标选择、替换和最终上下文验证，返回原跨度/字面量、替换片段、请求的作用域，以及`planned.sha256`和`planned.bytes`，不创建文件（`writesFiles:false`）。空计划返回原文的预计身份；组合后超长的行等最终上下文错误也会拒绝。确认同一输入与计划后再执行`apply`，其`disk`回执是实际写出/读回证据；`preview`的`planned`只代表预期结果，不证明磁盘写入成功，也不锁定后续文件或计划。

同目录的`node review-preview.mjs PREVIEW.json NEW_REVIEW.html [--source INPUT.cif]`可将保存的成功预览生成为独立HTML审阅页。它展示作用域、ID/标签、原跨度、原字面量、替换片段及源/预计结果散列；CIF中的`<...>`、`&...;`等内容按文字显示。页面路径须尚不存在，空编辑计划也可展示；输入不是成功的无写入预览时返回错误。默认只读取预览JSON，保留离线用法。

需要查看相邻列或注释时，可加`--source`显式指定源文件：先核对其原始字节SHA256及每个原字面量的UTF-8区间，再按原跨度重放全部替换片段，核对完整预计结果的SHA256和字节数。页面同时提供原文与预计结果的上下文，均保留前后最多各一行；同一行的多项修改按组合后的结果展示。预计结果中的高亮是本项替换片段（含其空白），不是重新解析的AST跨度。审阅页的字面量、片段与上下文将CR、LF、CRLF各按一个物理换行显示，HTML文字中的换行统一为LF；跨高亮边界组成的CRLF仍只显示一次。源CIF、保存的预览JSON、原字节跨度与散列保持原样，页面文字不用于恢复原始换行字节。源文/跨度不符、原区间重叠或预计身份不一致均在创建页面前失败。

示例不重新解析CIF、不修改源CIF、不执行apply、不记录批准；合法性仍由生产预览和实际写出的核心路径验证，上下文及字节核对也不是批准。页面保留的预计散列可用于后续`--expect-result-sha256`，实际写出仍以磁盘回执为准。例如：

```sh
node review-preview.mjs work/sample.preview.json work/sample.context.html --source sample.cif
```

`node tests/review-browser.mjs`用已安装的Chromium运行六份独立字节预期：CR分行、CR字面量/替换、两端高亮边界，以及LF/CRLF对照。它实际执行preview、审阅HTML和受散列约束的apply，再比较浏览器中每个字符的行位置与行高，保存原始命令输出、页面、截图、观察副本和编译身份。可用`CIF_REVIEW_BROWSER`指定浏览器，缺失时明确失败；不用个人浏览器配置或下载浏览器。这是有限换行排版回归，既有保存预览的拒绝及离线契约另由`tests/saved-preview.mjs`覆盖。CI步骤及证据边界见[CI-PLAN.md](CI-PLAN.md)。

需要约束最终结果时，可在`apply`输出路径后加`--expect-result-sha256 SHA256`，例如传入预览的`planned.sha256`。完整计划验证后、创建输出前，程序比较全部预计UTF-8字节的散列；不匹配则返回错误，不写文件。参数须为64个十六进制字符，可用大写；成功的`disk.expectedResultSha256`回显规范小写值，实际`disk.sha256`仍来自写出后的读回。不提供选项时保留原行为。它约束结果字节而非计划文件内容，同结果的计划重排仍可通过；这不是批准、签名或锁，也不保证后续磁盘操作成功。

输出路径必须尚不存在，不能原地覆盖；程序独占创建、写入/刷新、逐字节回读并返回实际SHA256。输入文件始终不写入，未选字节及BOM/CRLF不归一化。失败返回非零退出码和`ok:false`的JSON；处理中的新输出会尝试清理，清理失败会写明。它不承诺崩溃原子性、并发编辑锁或gzip输入。编译一次后可从任意工作目录运行生成的JS：`node /absolute/path/to/main.js query /absolute/input.cif /absolute/scope.json`；生成路径见`moon build --target js`后的`_build/js/debug/build/`。

在`examples/file-workflow`运行`node tests/output-preservation.mjs`可验证文件保护合同（需要MoonBit和Node.js≥22.3）。回归启动真实CLI，检查源散列过期、预计结果散列不符和已有输出路径时的退出码、JSON及调用前后文件字节；合法对照与独立手写的完整CIF预期逐字节比较，并核对磁盘回执。测试仅使用`work/`内新建的临时目录，成功后清理；GitHub Actions执行同一回归。

同目录运行`node tests/saved-preview.mjs`可验证保存预览的独立HTML消费者。回归以固定BOM/CRLF、中文UTF-8及手写完整预计字节和转义上下文为预期，检查`--source`下的源散列、预计散列/字节数、重叠拒绝、同一行多项修改的组合上下文，以及离线两参数模式。非法保存件不创建页面、不更改已有页面或源CIF；合法保存件也沿用页面必须为新路径的现有约束。成功回执仍为`writesCifFiles:false`、`approvesEdits:false`。这是实际进程/文件和HTML内容回归，不表示浏览器视觉认证；CI执行同一命令。

`node tests/plan-targets.mjs`通过真实文件CLI验证保存计划的目标选择与整批拒绝。固定小CIF和JSON计划覆盖缺失/歧义ID、合法前项后的非法CIF值，以及已有目标时的文件保护；合法单项和四ID对照均与独立手写的完整输出字节比较。样本保持`A/a`区分、引用`?/.`可作ID而裸缺失标记不作ID、复合值不展平等原语义。测试不传预计结果散列选项，直接核计划拒绝、磁盘回执和文件/目录前后字节；CI执行同一命令，不新增生产输入限制。

`node tests/catalog-consumer.mjs`提供可运行的目录消费链：调用者明确选定固定样本的frame/loop/ID列，下游用真实目录的`name`/`tags`和query的ID/源散列建立计划，执行现有apply，再catalog/query回读。独立手写CIF、完整输出和目录/同行JSON预期核对中文名称、原始BOM/CRLF、UTF-8半开字节跨度及单列中的嵌套List/Table；复合值各算一个cell。另核pair-only目录的空loop及误作loop查询时的拒绝，输入始终保持原字节。CI执行同一消费链；产品不自动选择ID，也不增加格式或改变missing-marker政策。

Pair-only文件或只需按标签读取值时，可用`values INPUT.cif SCOPE.json`。范围文件为`{"block":"pairs","tags":["_length_m","_note"]}`，可另给`frame`。它复用公开的`find_values`，返回`mode:"values"`、完整原文件`sourceSha256`、版本、所给范围和`selections:[{"tag":...,"values":[...]}]`；每个值含解码`value`、`kind`、原`literal`与UTF-8跨度。Pair返回一个值，loop列按源序返回全部单元格，复合值保持一个整体；各标签独立查询，不拼行、不猜ID。请求顺序及重复标签保留，空`tags`返回空分组，缺失范围/标签返回空值数组；名称匹配沿用公开API。`tags`须为字符串数组，原CIF须完整合法且为UTF-8。

命令只输出JSON（`writesFiles:false`），不创建CIF或修改输入/已有输出；保存stdout时由调用者选择文件路径。旧`query`仍只投影同一loop的ID与列，原Pair-only拒绝及apply的新路径写出约束不变。`value`是语义视图，不自动转换数字、missing或单位；带引号的`?`与裸`?`可通过`kind`/`literal`区分。

`cd examples/value-reader && node verify.mjs`重放两份独立CIF1/CIF2文件到完整JSON，再把真实JSON路径交给独立公开包：接收器核对整文件散列及每个字面量的源字节跨度，重新解析提取值，通过`UncertaintySink`实际交给固定版本Lunar。米由调用者明确选择；引用的missing标记、裸missing和List不被当成量值。还覆盖空/缺失范围、坏输入的只读拒绝、旧query/apply及已有输出保护。公开API原本已可编程读取这些值；本次增加文件CLI入口与可重放接收链，不主张新科学或查询算法、第三方采用。

### 追加一条文件记录

`append INPUT.cif ROW.json NEW_OUTPUT.cif [--expect-result-sha256 SHA256]` 将已有纯文本追加 API 接到真实文件路径。先用 `catalog` 明确选择原块/帧/loop；行文件绑定该输入的完整 `sourceSha256`，`headers` 必须复制所选 loop 的全部表头，保持原顺序和原拼写。块/帧仍使用已有名称匹配，`frame` 可省略。下面是四列行文件的形状，散列须取自实际输入：

```json
{"block":"实验","frame":"批次","sourceSha256":"复制catalog返回的完整散列","headers":["_sample_id","_length_m","_note","_meta"],"cells":[{"cif":"R"},{"cif":"6.250(12)"},{"text":"late R"},{"cif":"[3 {'x':4}]"}],"newline":"\n"}
```

`cells` 每项只能提供 `cif` 或 `text`，数量须与表头一致。`cif` 是一个已编码值，`text` 复用目标版本的 `format_string`；复合值和多行文本各算一个单元格。新增分隔符默认 LF，也可显式选 CRLF；旧 BOM/换行和所有旧字节保持原序。此命令没有 ID 选择或重复 ID 限制，不推断单位。实际源散列、完整作用域/表头、版本、行宽、片段或最终上下文不符都在创建输出前拒绝。

例如在本目录用随附的新文件样本运行（输出路径须尚不存在）：

```sh
moon run . --target js -- append tests/append/cif2-source.cif tests/append/cif2-row.json NEW_OUTPUT.cif
node tests/append-file.mjs
```

成功 JSON 的 `mode` 为 `append`，记录实际原块/帧名称、表头及原 loop 跨度、追加前后行数、编码后的新单元格和 `disk` 的实际字节数/SHA256/读回结果。可选结果散列与 `apply` 共用同一检查及现有独占写出路径。输入和已有目标不写入；新目标创建后写入、刷新或读回失败时尝试删除，删除失败会在错误中明确报告，可能留下新文件；不承诺崩溃事务或并发锁。共享写出验证保持既有 apply 回执及语义。

`tests/append-file.mjs` 编译真实 CLI，从另一工作目录按绝对路径执行 catalog→append→catalog，并将物理输出交给 checkout 外复制的 `examples/file-append-receiver`。新的独立手写 CIF2 样本为279→312字节，插入偏移225、增加33字节，保留其他块/帧和四列原行；CIF1为77→103字节，在无末换行的EOF注释后增加26字节。真实 Lunar 接收新值6.25/u0.012和7/u0.025，米由接收者声明。回归核对完整独立输出、前缀/插入/后缀、结构跨度、错误前后文件，以及故障注入下的读回/清理后果，并保留源码、编译JS及原始输出身份。接收器由本项目自编，这证明可运行文件交接，不代表第三方或实验室已采用。CI执行同一链，不重复计算旧固定String示例为新的功能。

## 公共库用法

```moonbit
let file = @cif.parse_string("data_lab\n_length 1.5423(12) # comment\n").unwrap()
let value = file.find("lab", "_length").unwrap()
let measured = value.measurement().unwrap()
assert_eq(measured.to_cif_string(), "1.5423(12)")
assert_eq(measured.uncertainty, Some(0.0012))
let rewritten = file.replace_value(value, @cif.format_su(1.6, 0.002).unwrap()).unwrap()
```

完整公共接口由 `moon info` 生成在 `pkg.generated.mbti`。`parse_string` / `CifParser::parse_string` 返回严格 Result；`parse_report` 同时返回部分AST、原词元、原输入及诊断。`raw_data` 保存无法归入语法节点的词元，整个原始切片始终在file.source，不把恢复结果冒充合法文件。

批量写回使用 `file.replace_values([(valueA, "10.00(2)"), (valueB, "20")])`。所有Value都取自同一份原AST，可任意排序；标量、loop单元格、save frame及嵌套值均可选择。一次验证全部替换和最终上下文，重复/重叠选择（含父容器及其子值）、外来值或任一非法替换均返回Err。空修改集返回原文；调用者的数组与文件对象不改变。有效原文件保证最终文件仍合法，部分恢复文件沿用单值编辑的局部修复语义。这里只原子返回完整文本，不执行磁盘写入或事务。

- `CifFile` → blocks → entries (`Pair` / `Loop`)，支持独立save frames。
- `Container::find_values(tag)` 与 `CifFile::find_values(block, tag, frame?="")` 统一查询标量/loop列，名字沿用canonical caseless规则。返回当前范围内按源码顺序排列的原Value数组，不展平List/Table单元格、不自动转换测量；空帧参数查块内条目，指定帧则仅查该帧。缺失范围/标签返回空数组。旧`find`保持仅查块内Pair的行为。
- 部分恢复文件的列查询只返回实际存在的单元格，不补齐缺行；非法重复标签的匹配值也按源码顺序保留。查询不表示文件合法，仍须查看ParseReport诊断。返回数组是新数组，Value保持已有AST表示；这不是可增删行的实时表格代理。
- `Container::find_loop_rows(tags)` / `CifFile::find_loop_rows(block, tags, frame?="")` 返回`Result[Array[Array[Value]], String]`：请求列须非空且按规范互异，全部来自唯一一个表头无重复、行数非空完整的loop。按源码行序、请求列序投影；跨loop、标量广播、缺列/范围、不完整或歧义loop均返回Err，不补行或拼接独立列。复合单元格及原跨度保留；这是所选loop的结构检查，不代替ParseReport的整体有效性判断。
- `Value` 为 `Scalar` / `List` / `Table`；`Token` 同时保留kind、raw、解码text和Span。
- `format_string(text, version?=Cif2)` 返回单个带引号/文本字段的CIF字符串片段；空字符串、`?`、`.`和数字外观均保持字符串。按目标版本选择合法引用形式，CIF2必要时使用前缀/折行文本协议保护分号行并限制物理行长度。输入须为LF规范文本；CR/CRLF、Auto、非法字符或无法用所选CIF1形式精确保留的文字返回Err，不作静默归一化。返回片段可能带必要的前后换行，最终上下文仍由编辑器检查；它不是整文件序列化器。
- `CifStream::feed(Bytes)` 发出稳定的完整词元；`finish()` 检查UTF-8尾部和全文件结构。必须finish，不能仅依据中间词元判断合法。
- `rewrite_original` 返回逐字保留的源文本；`replace_value` 验证来源成员、UTF-8边界和单个替换值后只更改选定区间；拒绝夹带额外块/帧、值外注释，并检查合法原文件中的词法上下文冲突。复合值内部的合法注释仍可保留。不是任意新AST的通用文件生成器。
- `replace_values` 按原始UTF-8跨度应用多个互不重叠的修改，仅改变选中区间；其余字节（含BOM、注释、原数字、引号和CRLF）保留。整体检查会拒绝多个单独合法修改合起来造成的超长物理行。单值接口复用同一验证路径；批量接口不插入/删除loop行、数据名或数据块。
- `SuReal` 保留原decimal lexeme，Double/value和uncertainty只是可选有限近似。`uncertainty_digits` 区分未提供u与存在但不可投影的u。`?`与`.`有独立状态；带引号的相同文本仍是字符串。
- `format_su` 格式化有限外部计算结果：默认u两位有效数字，可选1..9位；半值远离零，处理跨位进位和负decimal places的指数表示。按输入binary64的精确有理值进行十进制舍入（使用标准库BigInt，不先做浮点加半或缩放除法）；缩放后整数超过2^53或尺度不可表示时返回Err。零u单独表示为`value(0)`，不把未知u推断为0。
- `UncertaintySink` 是可选下游转换接口。此库不保存协方差、不推断独立性、不执行SuReal代数，不声称通用GUM实现。超出Double投影的合法数字仍可原样解析/写回；发送到数值sink则返回Err。

## 版本与诊断规则

Auto以开头版本头选择CIF2，否则CIF1。可显式指定Version。支持CIF2列表/表、三引号、分号文本的前缀/折行协议；反斜杠在普通/引号文本中是字面字符，**没有所谓九种JSON式CIF转义**。遵循COMCIFS测试材料接受列表第一值贴近左方括号的写法。STAR2只是格式渊源，不声明支持STAR的嵌套loop、global、ref-table和转义；CIF2与STAR2不能混用。

名字用Unicode 16 canonical caseless matching（NFD → full default casefold → NFD）；CIF1限制ASCII及名字长度。保留原名字大小写用于源码与JSON视图。物理行上限2048字符。`inspect_json`输出语义视图，不替代带原词元的AST。

CIF2块名、帧名和数据名可包含方括号/花括号；这些字符在未引用数据值中仍受限。BOM只允许出现在文件开头。最短版本头可直接在EOF结束：采用正式语法的file-heading规则及COMCIFS最小文件测试；规范§3.3文字要求0后有空白，EOF边界以这两项可执行/形式依据处理。

注释不能在普通值后凭空开始分隔：引号、文本字段或复合值后接注释，通常须先有空白。CIF2容器开头及表键冒号后允许直接注释；文件正式语法允许紧贴最终值、结束于EOF的尾注释（此处与COMCIFS扫描器的更严格处理不同，保留正式语法的合法输入）。词元内部的`#`仍按原字符串保留。

Span是原UTF-8字节的半开区间；行列从1起，列计Unicode标量，tab占一列，CRLF算一次换行。BOM的字节仍保留在偏移中；首次物理行的列包含BOM，后续行不受影响。编辑器如需UTF-16/显示列，应另外转换。

| Code | 含义 |
|---|---|
| E001 | 未闭合单/双/三引号 |
| E002 | 未闭合分号文本 |
| E003 | loop无表头、无值或不足完整行 |
| E004 | 语法、字符集、重复名字/键等错误；字节流编码错误亦以前缀E004返回 |
| E005 | 明确资源预算：嵌套超过128或流字节预算超限 |

恢复保留不完整loop的全部值，不补齐单元格；按已识别词元在下一数据名/数据块继续，字符串内部的data_不会被当同步点。未闭合文本会吃到EOF并报告，不猜测作者本意。最多收集100条诊断。嵌套预算按Value层数计：根值为第1层，标量叶也占1层，最多128层；此计数规则及限制未改变。流默认16MiB的UTF-8字节预算可配置，恰好达到预算仍可完成；预算或编码终止错误后不能继续feed/finish。解析保留全部源码/词元/AST，**不是恒定内存流**。当前feed会重扫前缀，极细分块最坏二次时间；无吞吐保证。

## 验证与参考资料

[CI-PLAN.md](CI-PLAN.md) 列出完整验证流程。GitHub Actions 对 JS/Wasm-GC 执行严格检查、构建和测试，并运行公开包 Lunar 消费者、真实文件交接与输出保护、保存预览及浏览器物理换行回归。编译产物、实际输入输出与源码身份分别记录；运行结论见仓库 [Actions](https://github.com/dongxuan2012-2/moonbit-cif/actions)。

文件读取接收链可在 `examples/value-reader` 运行 `node verify.mjs`：两份完整 CIF1/CIF2 文件输出 values JSON，再交给独立公共包读取并送入真实 Lunar；调用者明确选择米。源码中的固定预期同时检查值、种类、字面量、跨度、只读拒绝及旧 query/apply 的输出保护。浏览器验证限定于所列换行样本。

可选参考工具可将给定 COMCIFS/COD 资料与 PyCifRW 5.0.1 进行对比，文本协议使用固定 C 测试中的静态期望：

```sh
python -m pip install --target work/oracle PyCifRW==5.0.1
python scripts/fetch_reference.py --out work/reference
python scripts/reference_check.py --corpus work/reference/samples --oracle-path work/oracle --expectations work/reference/comcifs-text-expectations.c --moon /path/to/moon --output work/reference/result.json
```

参考数据、C 期望及各自许可证应一同保存；这些比较用于明确样本的语义核对，软件不提供全标准认证。参考样本与运行时 SDK、依赖缓存均不作为 MIT 原创源码分发。

## 项目归属、许可与边界

当前模块为 `dongxuan2012-2/cif`，维护及申报账号为 `dongxuan2012-2`，仓库为 [dongxuan2012-2/moonbit-cif](https://github.com/dongxuan2012-2/moonbit-cif)。源码按本地 workspace 方式集成；模块命名空间与仓库归属不改写原软件的版权或上游作者历史。

原创软件遵循根 [LICENSE](LICENSE) 的 MIT 许可及其原署名。Unicode 映射遵循 [UNICODE-LICENSE.txt](UNICODE-LICENSE.txt)；规范化与可选 Lunar 依赖遵循各自 Apache-2.0 许可。COD 与 COMCIFS 等数据/参考资料的来源、署名和独立许可见 [THIRD_PARTY.md](THIRD_PARTY.md)。

本库的范围为 CIF 语法、源保真、诊断与测量词元桥接；不执行 STAR2 扩展、mmCIF 字典语义、DDL/dREL、单位/协方差推断、晶胞几何或空间群展开。流式接口保留全源并重扫前缀；文件写出例程使用新路径并读回，不提供原地覆盖、gzip 或崩溃事务。
