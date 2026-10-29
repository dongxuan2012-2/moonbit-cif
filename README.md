# moonbit-cif

原生 MoonBit CIF 1.1 / CIF 2.0 源码保真解析、标准不确定度词元和诊断库。模块 `dongxuan2012/cif`，候选项目，本地可用，尚未发布 Mooncakes，也不表示换题或赛事验收获批。

源码仓库：[dongxuan2012-2/moonbit-cif](https://github.com/dongxuan2012-2/moonbit-cif)。模块名和原作者署名保持不变。

把 CIF 输入变成可定位的嵌套值/表格，提取 `1.5423(12)`，把外部计算结果只替换回指定值，并保留其余字节、注释、引号和换行。核心不实现通用误差传播或230空间群；现有库的作者不是本项目参赛者。

## 运行

需要 MoonBit；本次验证 moon 0.1.20260920、moonc v0.10.14。Node 运行 JS，moonrun 运行 Wasm-GC。Unicode normalization 是显式的纯 MoonBit 依赖，版本固定在 moon.mod。

GitHub Actions 使用官方 `0.10.14+7d59c7ec9` Linux SDK/core 发行包和 Node.js `24.11.0`；`scripts/setup-ci.sh` 校验固定 SHA256，并仅在 runner 临时目录安装。CI 执行双后端 check/build/test、四个 Lunar 消费者、追加行的外部 Lunar 接收，以及文件预览、HTML 审阅和实际写出后的散列与值核对。每次运行的真实结论见仓库 [Actions](https://github.com/dongxuan2012-2/moonbit-cif/actions)。

```sh
moon check --deny-warn --target js
moon build --deny-warn --target js
moon test --deny-warn --target js
moon check --deny-warn --target wasm-gc
moon build --deny-warn --target wasm-gc
moon test --deny-warn --target wasm-gc
moon run cmd/demo
```

PowerShell 检视真实文件（最后一个参数是文本，不是路径）：

```powershell
$text = Get-Content -LiteralPath fixtures/cod-2002926.cif -Raw
moon run cmd/inspect --target js -- $text
```

外部库接入示例是独立模块，workspace连接本地库，不依赖尚未发布的远程 cif 包：

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

需要查看相邻列或注释时，可加`--source`显式指定源文件：先核对其原始字节SHA256及每个原字面量的UTF-8区间，再按原跨度重放全部替换片段，核对完整预计结果的SHA256和字节数。页面同时提供原文与预计结果的上下文，均保留前后最多各一行；同一行的多项修改按组合后的结果展示。预计结果中的高亮是本项替换片段（含其空白），不是重新解析的AST跨度。原换行与字符保留；源文/跨度不符、原区间重叠或预计身份不一致均在创建页面前失败。

示例不重新解析CIF、不修改源CIF、不执行apply、不记录批准；合法性仍由生产预览和实际写出的核心路径验证，上下文及字节核对也不是批准。页面保留的预计散列可用于后续`--expect-result-sha256`，实际写出仍以磁盘回执为准。例如：

```sh
node review-preview.mjs work/sample.preview.json work/sample.context.html --source sample.cif
```

需要约束最终结果时，可在`apply`输出路径后加`--expect-result-sha256 SHA256`，例如传入预览的`planned.sha256`。完整计划验证后、创建输出前，程序比较全部预计UTF-8字节的散列；不匹配则返回错误，不写文件。参数须为64个十六进制字符，可用大写；成功的`disk.expectedResultSha256`回显规范小写值，实际`disk.sha256`仍来自写出后的读回。不提供选项时保留原行为。它约束结果字节而非计划文件内容，同结果的计划重排仍可通过；这不是批准、签名或锁，也不保证后续磁盘操作成功。

输出路径必须尚不存在，不能原地覆盖；程序独占创建、写入/刷新、逐字节回读并返回实际SHA256。输入文件始终不写入，未选字节及BOM/CRLF不归一化。失败返回非零退出码和`ok:false`的JSON；处理中的新输出会尝试清理，清理失败会写明。它不承诺崩溃原子性、并发编辑锁或gzip输入。编译一次后可从任意工作目录运行生成的JS：`node /absolute/path/to/main.js query /absolute/input.cif /absolute/scope.json`；生成路径见`moon build --target js`后的`_build/js/debug/build/`。

在`examples/file-workflow`运行`node tests/output-preservation.mjs`可验证文件保护合同（需要MoonBit和Node.js≥22.3）。回归启动真实CLI，检查源散列过期、预计结果散列不符和已有输出路径时的退出码、JSON及调用前后文件字节；合法对照与独立手写的完整CIF预期逐字节比较，并核对磁盘回执。测试仅使用`work/`内新建的临时目录，成功后清理；GitHub Actions执行同一回归。

同目录运行`node tests/saved-preview.mjs`可验证保存预览的独立HTML消费者。回归以固定BOM/CRLF、中文UTF-8及手写完整预计字节和转义上下文为预期，检查`--source`下的源散列、预计散列/字节数、重叠拒绝、同一行多项修改的组合上下文，以及离线两参数模式。非法保存件不创建页面、不更改已有页面或源CIF；合法保存件也沿用页面必须为新路径的现有约束。成功回执仍为`writesCifFiles:false`、`approvesEdits:false`。这是实际进程/文件和HTML内容回归，不表示浏览器视觉认证；CI执行同一命令。

`node tests/plan-targets.mjs`通过真实文件CLI验证保存计划的目标选择与整批拒绝。固定小CIF和JSON计划覆盖缺失/歧义ID、合法前项后的非法CIF值，以及已有目标时的文件保护；合法单项和四ID对照均与独立手写的完整输出字节比较。样本保持`A/a`区分、引用`?/.`可作ID而裸缺失标记不作ID、复合值不展平等原语义。测试不传预计结果散列选项，直接核计划拒绝、磁盘回执和文件/目录前后字节；CI执行同一命令，不新增生产输入限制。

`node tests/catalog-consumer.mjs`提供可运行的目录消费链：调用者明确选定固定样本的frame/loop/ID列，下游用真实目录的`name`/`tags`和query的ID/源散列建立计划，执行现有apply，再catalog/query回读。独立手写CIF、完整输出和目录/同行JSON预期核对中文名称、原始BOM/CRLF、UTF-8半开字节跨度及单列中的嵌套List/Table；复合值各算一个cell。另核pair-only目录的空loop及误作loop查询时的拒绝，输入始终保持原字节。CI执行同一消费链；产品不自动选择ID，也不增加格式或改变missing-marker政策。

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

## 独立验证与可重放资料

implementation-03历史验证包含12项双后端测试（内部每个字节切分点验证），以及12份输入的24次跨后端参考对比：9份固定COMCIFS资料、1份真实COD结构、2份自写输入。文本协议以COMCIFS固定C测试的静态期望断言为仲裁，其他语义用PyCifRW 5.0.1；没有声称编译/运行过C参考实现。另对四类坏输入进行独立拒绝对比。最终实际命令、退出码、源码身份和首次失败留在执行回执目录，不把样本全通过宣传为全标准认证。

可重放参考对比（将工作目录和moon路径换成本机路径）：

```sh
python -m pip install --target work/oracle PyCifRW==5.0.1
python scripts/fetch_reference.py --out work/reference
python scripts/reference_check.py --corpus work/reference/samples --oracle-path work/oracle --expectations work/reference/comcifs-text-expectations.c --moon /path/to/moon --output work/reference/result.json
```

第三方参考样本不放进MIT产品源码。`fetch_reference.py` 的数据目录、C期望断言和许可证必须一起保存；参见 [THIRD_PARTY.md](THIRD_PARTY.md)。不做mmCIF字典语义校验、DDL/dREL执行、单位推断、晶胞几何或空间群展开。


深入修复05：补齐CIF1未引用右方括号保留规则，修复单值重写夹带块/帧/注释的边界，以及半值邻点错误进位。新增11个定向测试组，其中数值期望来自Python Decimal.from_float/ROUND_HALF_UP的210个半值邻点与跨位案例；另覆盖双模式分块、UTF-8前缀/折行、partial loop及缺失/溢出不确定度桥接。旧样本成绩保持为历史证据，不重复下载或冒称为本轮新执行。精确命令和本轮记录位于deep-repair-05-20261028回执目录。

深入修复06：修复CIF2名称被括号错误截断、最短版本头EOF误拒及正文BOM误接收，新增7组双端回归；包含带标点名称/loop、规范化重复名称、编辑保真和各字节切分点。固定COMCIFS容器名及最小文件资料、独立PyCifRW对比、仓库外Lunar消费者、修复前后源码与编译产物身份记录在deep-repair-06-max-20261028回执目录。沿用05轮未改动数值代码的历史验证。

深入修复08：修复注释被过滤后掩盖缺失分隔的问题；保留合法容器/表键注释、EOF尾注释及词内`#`。新增7组双端定向验证，并覆盖UTF-8预算恰好命中/超限、错误后关闭状态、Value高度127/128/129与后续字段恢复。独立预期、实际外部消费者及源码/构建身份见deep-repair-08-max-20261028；07轮无源码修复，其审查结果仍为历史证据。

功能拓展09：新增按原AST跨度进行的原子批量改写及`examples/lunar-batch`真实消费者。生态核查已确认已有mbt-crystal晶体工具和BioSeqs CIF/mmCIF读写；此处的贡献是保留未选字节的多值修改验证与应用，不重复实现晶体几何或通用不确定度代数。使用场景、候选取舍、独立字节拼接/语义读回、错误及兼容性结果见feature-09-max-20261028回执。

拓展10补齐原值选择：提供跨Pair/loop的按标签列查询和显式save frame范围，Lunar批量示例改用新接口，输出保持一致。新的外部消费者以Unicode等价名称选帧，取得原跨度、调用Lunar、原子写回并独立读回；补充复杂替换审查未发现新批量缺陷。定向验证及身份记录见deep-repair-10-max-20261028。

拓展11提供严格的同loop行投影及选择性Lunar示例，避免把独立的等长列当成同行。所选行的Value可直接构造原子批量修改，旧列查询仍保留部分行；新接口与既有作用域回归、原跨度、独立co-loop/字节及语义读回记录见deep-repair-11-max-20261028。

拓展12提供精确保留字符串内容的`format_string`及Lunar计算加说明的同批写回示例。已有编辑器继续接收原始CIF字面量，解析/数值/同行查询实现保持不变；空文本、缺失外观、引号/多行/长Unicode文本、独立解码和原字节读回见deep-repair-12-max-20261028。

拓展14增加独立的本地文件工作流例程，支持按帧/loop查询、散列绑定的ID修改计划、新文件写出及字节回读。库和旧例程源码未改，13轮的嵌套/两次编辑审查仍为历史证据；真实文件、输入/已有输出保留、错误路径及身份记录见deep-repair-14-max-20261028。

拓展16补齐陌生文件的只读`catalog`入口，列出块/帧、Pair和独立loop分组，供用户明确构造查询与计划。使用原跨度、独立结构/计数及实际catalog→query→apply→catalog回读证据见deep-repair-16-max-20261028；不新增核心API或改变原输入接受规则。

拓展18增加不写文件的`preview`计划预览，完整复用原子批量验证后返回目标回执和预计UTF-8字节/散列。预览与实际输出的独立字节核对、只读守卫及错误路径见deep-repair-18-max-20261028；不新增核心API、计算引擎或计划模板推断。

拓展19为`apply`增加可选的预计结果散列约束，在写出前拒绝与调用者期望不同的结果，原命令行为保留。计划变化、同结果计划、零修改副本及真实磁盘回执的证据见deep-repair-19-max-20261028；散列匹配不表示批准或写入完成。
