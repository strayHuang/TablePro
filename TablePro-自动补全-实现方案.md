# TablePro SQL 自动补全改造 — 实现方案

> 目标代码库：`/tmp/tablepro-80`（TablePro v0.80.0，AGPLv3，macOS，自编译重签版）
> 方案性质：纯 app 侧改造为主，唯一例外是 MSSQL 插件的查询语句；**不修改任何 `TableProPluginKit` 结构体布局**（ABI）

---

## 1. 背景与需求汇总

用户在 SQL 编辑器自动补全上提出四条需求，外加一条附带项：

| 编号 | 需求 | 现状 |
|------|------|------|
| R1 | 内置函数提示**按当前数据库方言过滤**（SQL Server 上不应出现 `CURRENT_DATE`） | 通用目录全量列出，无减法 |
| R2 | 所有函数接受补全时**带出全部固定参数**（按最大参数形态） | 只插入 `name()`，签名仅作展示 |
| R3 | 窗口函数 `row_number() OVER()` 的 **`OVER()` 内两个参数（`PARTITION BY` / `ORDER BY`）也要列出** | `OVER(...)` 是展示文案，从不插入 |
| R4 | 打完 `row_number()` 敲 `over` **应有提示** | `OVER` 不在任何子句白名单，永远不可补全 |
| R5 | 提示表名/字段名时**显示表与字段的备注** | 列已通（部分引擎）、表断链；SQL Server 取不到 |
| R6 | 写 JOIN `ON`（含其后续 `AND/OR`）时，**自动列出可整条补全的关联条件**（如 `t1.docentry = t2.docentry`），点选即插入整条；按外键 / 同名+主键 / 同名 / int·bigint 生成与排序 | `.on` 只给单列与关键字，**无关联条件项** |
| R7 | 表名/字段名的**备注直接显示在候选行的右侧**（一行内即可看到，无需移动焦点） | 备注仅在获得焦点的下方预览面板显示，不直观（修正 D5） |

**已定决策**：
- R1 采用**方案 A**（app 侧标记 + 过滤），不触碰插件协议 `SQLDialectDescriptor`。
- R2/R3 骨架**参数全写**，可选参数按最大形态带出。
- R4 接受函数后，光标若落在窗口子句内则**自动弹出候选**（`PARTITION BY` / `ORDER BY`）。
- 光标停点：**本期支持多停点**，接受骨架后可用 Tab / Shift-Tab 在各参数间跳转。
- 预览面板**加宽**：按 字段 50 / 类型 20 / 备注 30 的字符长度计算面板宽度，备注不再单行硬截断。

---

## 2. 现状与根因（证据）

### 2.1 函数目录与插入（R1 / R2 / R3）

- 候选来源 `SQLKeywords.functionItems()`（`SQLKeywords.swift:315-319`）：把 `allFunctions` 全量映射为补全项，**无方言过滤**。
- 聚合点 [SQLCompletionProvider.functionItems()](file:///tmp/tablepro-80/TablePro/Core/Autocomplete/SQLCompletionProvider.swift#L137-L150)：`SQLKeywords.functionItems()` + 插件方言函数，**只做加法去重，没有排除**。
- 插入固定为 `name()`：[SQLCompletionItem.function](file:///tmp/tablepro-80/TablePro/Core/Autocomplete/SQLCompletionItem.swift#L304-L319)
  ```swift
  let insertText = signature != nil ? "\(name)()" : name
  ```
  → 弹窗右栏显示 `signature`（`detail`），但落库永远是 `name()`。
- 片段展开仅支持收藏夹：[SQLCompletionInsertion.resolve](file:///tmp/tablepro-80/TablePro/Core/Autocomplete/SQLCompletionInsertion.swift#L20-L27) 只对 `.favorite` 走 `SQLSnippetMarker`。
- 窗口函数签名含 `OVER(...)`（[SQLKeywords.swift#L248-L260](file:///tmp/tablepro-80/TablePro/Core/Autocomplete/SQLKeywords.swift#L248-L260)），因上条而永不插入。

**关键事实**：`SQLKeywords` 各分组的 `signature` **大多已经是具体参数骨架**（如 `SUBSTRING(str, start, len)`、`ROUND(n, decimals)`、`LAG(expr, offset, default) OVER(...)`），因此 R2 的数据活比预期小，主要是**规范化 + 接线**，而非从零编写。

### 2.2 `OVER` 不可补全（R4）

- `.select` 白名单无 `OVER`：[SQLCompletionProvider.swift#L254-L257](file:///tmp/tablepro-80/TablePro/Core/Autocomplete/SQLCompletionProvider.swift#L254-L257)
- `.window` 白名单无 `OVER`：[SQLCompletionProvider.swift#L448-L454](file:///tmp/tablepro-80/TablePro/Core/Autocomplete/SQLCompletionProvider.swift#L448-L454)
- 大表 `SQLKeywords.keywords` 含 `"OVER"`，但**该数组不参与补全**（仅 `KeywordUppercaseHelper` 用于大小写改写）。
- `.window` 上下文本身可达（`OVER (` 输入后由结构性正则命中：[SQLContextAnalyzer.swift#L220-L221](file:///tmp/tablepro-80/TablePro/Core/Autocomplete/SQLContextAnalyzer.swift#L220-L221)），但按触发策略在空前缀下被压制（[SQLCompletionTriggerPolicy.swift#L24-L39](file:///tmp/tablepro-80/TablePro/Core/Autocomplete/SQLCompletionTriggerPolicy.swift#L24-L39)）。

### 2.3 表 / 字段备注（R5）

- 协议与模型层**都具备** `comment`：`PluginColumnInfo.comment`（[#L45](file:///tmp/tablepro-80/Plugins/TableProPluginKit/PluginColumnInfo.swift#L45)）、`PluginTableInfo.comment`（[#L8](file:///tmp/tablepro-80/Plugins/TableProPluginKit/PluginTableInfo.swift#L8)）、app `TableInfo.comment`（[QueryResult.swift#L127](file:///tmp/tablepro-80/TablePro/Models/Query/QueryResult.swift#L127)）。
- **列**已接线：`columnCompletionItems` 传 `col.comment`（[SQLSchemaProvider.swift#L560-L575](file:///tmp/tablepro-80/TablePro/Core/Autocomplete/SQLSchemaProvider.swift#L560-L575)）→ 进入 `documentation`（[SQLCompletionItem.swift#L288-L292](file:///tmp/tablepro-80/TablePro/Core/Autocomplete/SQLCompletionItem.swift#L288-L292)）→ 弹窗预览面板渲染（[SuggestionPreviewView.swift#L22-L27](file:///tmp/tablepro-80/Packages/TableProEditor/Sources/TableProEditorKit/CodeSuggestion/View/SuggestionPreviewView.swift#L22-L27)）。
- **表**断链：`tableCompletionItems()` / `tableCompletionItems(inSchema:)` 映射时丢掉 comment（[#L467-L472](file:///tmp/tablepro-80/TablePro/Core/Autocomplete/SQLSchemaProvider.swift#L467-L472) / [#L514-L520](file:///tmp/tablepro-80/TablePro/Core/Autocomplete/SQLSchemaProvider.swift#L514-L520)）；`SQLCompletionItem.table(_:isView:)` 无 comment 参数（[#L242-L249](file:///tmp/tablepro-80/TablePro/Core/Autocomplete/SQLCompletionItem.swift#L242-L249)）。
- **引擎差异**：
  - PostgreSQL 已取到表/列备注（`obj_description` [PostgreSQLSchemaQueries.swift#L181](file:///tmp/tablepro-80/Plugins/PostgreSQLDriverPlugin/PostgreSQLSchemaQueries.swift#L181)、`col_description` [#L541](file:///tmp/tablepro-80/Plugins/PostgreSQLDriverPlugin/PostgreSQLSchemaQueries.swift#L541)/[#L592](file:///tmp/tablepro-80/Plugins/PostgreSQLDriverPlugin/PostgreSQLSchemaQueries.swift#L592)）。
  - SQL Server **未取**：表列表只读 `TABLE_NAME/TABLE_TYPE`（[MSSQLSchemaQueries.swift#L188-L194](file:///tmp/tablepro-80/Packages/TableProCore/Sources/TableProMSSQLCore/MSSQLSchemaQueries.swift#L188-L194)），列查询 `columnSelectList` 无 `MS_Description`（[#L252-L268](file:///tmp/tablepro-80/Packages/TableProCore/Sources/TableProMSSQLCore/MSSQLSchemaQueries.swift#L252-L268)）；`MS_Description` 仅在单表元数据 `fetchTableMetadata` 读到（[MSSQLPluginDriver+Schema.swift#L336-L357](file:///tmp/tablepro-80/Plugins/MSSQLDriverPlugin/MSSQLPluginDriver+Schema.swift#L336-L357)）。
- 预览面板现为**单行 + 尾部截断**（`.lineLimit(1)`：[SuggestionPreviewView.swift#L26](file:///tmp/tablepro-80/Packages/TableProEditor/Sources/TableProEditorKit/CodeSuggestion/View/SuggestionPreviewView.swift#L26)）；弹窗内容宽度现按 label+detail 长度封顶 64 字符、下限 280（[SuggestionContentView.swift#L101-L114](file:///tmp/tablepro-80/Packages/TableProEditor/Sources/TableProEditorKit/CodeSuggestion/View/SuggestionContentView.swift#L101-L114)）。

---

## 3. 设计决策

| 编号 | 决策 | 理由 |
|------|------|------|
| D1 | R1 采用**方案 A**：`SQLKeywords` 条目加方言标记，`functionItems()` 按 `databaseType/dialect` 过滤。**不改 `SQLDialectDescriptor`**。 | 17 个官方预编译内置插件，改协议结构体 = ABI 崩溃风险 |
| D2 | 函数 `signature` 规范化后**直接作为 `insertText`**；展示 `detail` 沿用同一文本。 | 一处改动、展示与插入天然一致 |
| D3 | 窗口函数骨架改写为 `fn(...) OVER (PARTITION BY ;; ORDER BY ;; )`。 | 满足「参数全写」，两个参数可见 |
| D4 | 光标停点**扩展为多停点**：`SQLSnippetMarker` 支持多个 `;;`，接受骨架后 Tab / Shift-Tab 在参数间跳转，初始光标落**第一个**参数。 | 已确认纳入本期 |
| D5 | 表/字段备注**数据**接线：表侧补 `comment` 参数；SQL Server 由 MSSQL 插件补查询。（显示方式见 D9） | 复用现成数据链路 |
| D6 | 预览面板**加宽**并按三列长度计算：字段 50 + 类型 20 + 备注 30（字符宽），备注允许 1~2 行。 | 用户指定尺寸 |
| D7 | 触发策略**豁免 `.window`**（空前缀不再压制），并在接受骨架后**程序化重新触发**候选，使 `OVER (` 内自动弹出参数。 | 满足「自动弹出候选」 |
| D8 | R6 形态为 **ON 直接给「整条关联条件」** `t1.col = t2.col`（可整条插入，**非单列排序**）；tier：外键=0 / 同名+主键=1 / 同名=2 / `int·bigint`=3；AND 续接 ON 也生成且**排除已用对**；T10 真实外键取数**必做**。 | 用户修正：要整条可补全，不是排单列 |
| D9 | 备注显示改到**候选行内右侧**（改 `CodeSuggestionLabelView` 行渲染），不再依赖获得焦点的预览面板；表/列项不再喂 `documentation` 以免重复，函数/收藏仍走预览面板。行内备注尾部截断（`commentCharacterBudget=30`）。 | 用户要求一目了然，修正 D5 |

### D1 方言标记形态

给函数条目增加方言标签（默认 `universal`）：

```swift
enum SQLFunctionDialect { case universal, mysql, postgres, mssql, oracle, sqlite }
// 条目： (name, signature, doc, dialect)
```

判定不再依赖 `doc` 文案里的 "(MySQL)"、"(PostgreSQL)" 提示，而是显式字段；过滤时保留 `universal` + 命中当前 `databaseType` 的项。

### D2/D3 骨架规范

- `OVER(...)` → `OVER (PARTITION BY ;; ORDER BY ;; )`（两个停点）。
- 保留现成的具体参数骨架；仅以下两类特殊处理：
  - **变参**（`CONCAT(str1, str2, ...)`、`COALESCE(v1, v2, ...)`、`GREATEST` 等）：保留 `...`（"最大参数"对变参不成立）
  - **无参/关键字形态**（`CURRENT_DATE`、`NOW()`、`PI()`）：按原样
- `EXTRACT(field FROM source)`、`CAST(expr AS type)`、`POSITION(substr IN str)`：原样保留（引擎语法如此）

### D4 多停点语法

`;;` 复用为**每个停点**的标记；`SQLSnippetMarker.expand` 返回**全部停点偏移**（UTF-16）+ 去掉标记后的插入文本，编辑器按顺序 Tab / Shift-Tab 跳转。

---

## 4. 实现任务

### T1 · 函数目录规范化与方言标记（R1 + R2 数据）

**文件**：`TablePro/Core/Autocomplete/SQLKeywords.swift`

- 把 8 个函数分组（`aggregateFunctions` / `dateTimeFunctions` / `stringFunctions` / `numericFunctions` / `nullFunctions` / `conversionFunctions` / `windowFunctions` / `jsonFunctions`）的元组从 `(name, signature, doc)` 扩展为 `(name, signature, doc, dialect)`。
- 逐条标注方言：`universal` / `mysql` / `postgres` / `mssql` / `oracle`。
  - 例：`CURDATE/CURTIME/SYSDATE/UTC_*`、`DAYOFWEEK/DAYOFMONTH/DAYOFYEAR/WEEK/QUARTER/DATE_ADD/DATE_SUB/DATE_FORMAT/STR_TO_DATE/UNIX_TIMESTAMP/FROM_UNIXTIME/LAST_DAY/MAKEDATE/MAKETIME` → MySQL 系；`STRING_AGG/DATE_TRUNC/AGE/SPLIT_PART/INITCAP/JSON_BUILD_*/JSONB_*/JSON_EACH/ROW_TO_JSON/JSON_AGG/JSONB_AGG` → PostgreSQL；`NVL` → Oracle。
  - `CURRENT_DATE` **保留但在 SQL Server 上被过滤掉**（R1 的直接验收点）。
- 窗口函数：`OVER(...)` 改写为 `OVER (PARTITION BY ;; ORDER BY ;; )`（D3）。
- 更新 `allFunctions` 与 `functionItems()`（`SQLKeywords.swift:315-319`）以适配新元组类型。

**验收**：每条函数都有方言标记；窗口函数 `signature` 含 `OVER (PARTITION BY ;; ORDER BY ;; )`。

### T2 · 按方言过滤（A1 / R1）

**文件**：`TablePro/Core/Autocomplete/SQLCompletionProvider.swift`

- `functionItems()` 拼装时按 `cachedDialect` / `databaseType` 过滤：仅保留 `universal` + 命中当前方言的条目。
- 复用现有缓存失效路径（`setDatabaseType` 已清 `cachedFunctionItems`），过滤结果一并缓存。

**验收**：SQL Server 下不再出现 `CURRENT_DATE`/`CURDATE`/`DATE_FORMAT`；PostgreSQL 下不出现 `CURDATE`。

### T3 · 函数插入骨架 + 多停点（R2 / D4）

**文件**：`SQLCompletionItem.swift`、`SQLCompletionInsertion.swift`、`SQLSnippetMarker.swift`、`SQLCompletionProvider.swift`、`Packages/TableProEditor/.../CodeSuggestion/*`（编辑器侧）

- **T3a（骨架插入）**
  - `SQLCompletionItem.function(_:signature:...)`：`insertText` 由 `"\(name)()"` 改为**规范化骨架**（直接用 `signature`，见 D2）。
  - `SQLCompletionInsertion.resolve(for:)`：对**函数项**也走 `SQLSnippetMarker.expand`（当前仅 `.favorite`）；无 `;;` 时退回旧逻辑（括号内 / 末尾）。
- **T3b（多停点）**
  - `SQLSnippetMarker.expand` 支持**多个 `;;`**：返回 `(text, cursorOffsets: [Int])`（并保留对 `.favorite` 的兼容：恰一个停点）。
  - `SQLCompletionInsertion.Resolution` 增加 `cursorOffsets`（首停点即初始光标）。
  - 编辑器侧（`TableProEditorKit/CodeSuggestion`）：应用补全后注册**停点会话**，Tab 前进 / Shift-Tab 后退；需定位现有"应用补全并设置光标"的入口并在其后挂接。
- 兼容：无签名（纯 `name`）或关键字形态的函数行为不变；单停点与零停点均按旧行为。

**验收**：
- 接受 `SUBSTRING` → 插入 `SUBSTRING(str, start, len)`，光标落 `str`，Tab 依次跳 `start`、`len`。
- 接受 `LAG` → 插入 `LAG(expr, offset, default) OVER (PARTITION BY  ORDER BY  )`，光标落 `expr`，Tab 可跳到 `PARTITION BY` / `ORDER BY` 位置。

### T4 · `OVER` 关键字可达（R4）

**文件**：`TablePro/Core/Autocomplete/SQLCompletionProvider.swift`

- 把 `OVER` 加入表达式子句的关键字白名单：`.select`（[#L254-L257](file:///tmp/tablepro-80/TablePro/Core/Autocomplete/SQLCompletionProvider.swift#L254-L257)）、`.where_/.and/.having`、`.orderBy`、`.groupBy`。

**验收**：`SELECT row_number() ` 后敲 `ov`，候选出现 `OVER`。

### T5 · 表 / 字段备注显示 + 预览面板加宽（R5 / D6）

**文件**：`SQLCompletionItem.swift`、`SQLSchemaProvider.swift`、`SuggestionPreviewView.swift`、`SuggestionContentView.swift`

- `SQLCompletionItem.table(_:isView:comment:)` 增加 `comment` 参数；有备注时写入 `documentation`（复用现有 `docParts` 拼接风格）。
- `tableCompletionItems()` / `tableCompletionItems(inSchema:)` 映射时带上 `$0.comment`。
- **宽度按 D6 计算**：弹窗内容宽度改为按 `字段 50 + 类型 20 + 备注 30`（字符宽）计算，并设屏占比上下限（避免超宽 / 过窄）。
- **预览面板放宽**：`SuggestionPreviewView` 的 `.lineLimit(1)` → 备注按 30 字符宽、允许 1~2 行，不再尾部硬截断。

**验收**：PostgreSQL 下，表名候选底部显示表备注、列候选显示字段备注，且面板宽度足够容纳"长字段名 + 类型 + 备注"。

### T6 · SQL Server 备注取数（R5，插件侧）

**文件**：`Packages/TableProCore/Sources/TableProMSSQLCore/MSSQLSchemaQueries.swift`、`Plugins/MSSQLDriverPlugin/MSSQLPluginDriver+Schema.swift`

- 表列表 `tables(in:)`（[#L188-L194](file:///tmp/tablepro-80/Packages/TableProCore/Sources/TableProMSSQLCore/MSSQLSchemaQueries.swift#L188-L194)）左连 `sys.extended_properties`（`major_id = object_id AND minor_id = 0 AND name='MS_Description'`）取出表备注。
- 列查询 `columnSelectList`（[#L252-L268](file:///tmp/tablepro-80/Packages/TableProCore/Sources/TableProMSSQLCore/MSSQLSchemaQueries.swift#L252-L268)）左连 `sys.extended_properties`（`major_id = object_id AND minor_id = column_id AND name='MS_Description'`）取出字段备注。
- 解析层把新列映射进 `PluginTableInfo.comment` / `PluginColumnInfo.comment`（**字段已存在，不改布局**）。
- 注意：加列后同步 `allColumns` 的列索引常量（表格名索引在 [#L247](file:///tmp/tablepro-80/Packages/TableProCore/Sources/TableProMSSQLCore/MSSQLSchemaQueries.swift#L247)）。
- MSSQL 插件在 `~/Library/Application Support/TablePro/Plugins/`，可自行重编；**其余 17 个内置插件在 `Contents/PlugIns/`，一律不动**。

**验收**：SQL Server 下，带 `MS_Description` 的表/字段在候选中显示备注。

### T8 · 函数接受后自动弹出窗口参数（R4 · 自动）

**文件**：`Core/Autocomplete/SQLCompletionTriggerPolicy.swift`、`Core/Autocomplete/SQLCompletionProvider.swift`、编辑器侧应用补全入口

- **触发策略豁免**：`suppressesEmptyPrefix` 的放行列表加入 `.window`（[#L30-L36](file:///tmp/tablepro-80/TablePro/Core/Autocomplete/SQLCompletionTriggerPolicy.swift#L30-L36)），使 `OVER (` 内空前缀也能弹。
- **接受后重新触发**：应用补全（插入骨架）后，如果新光标落在会"自动开列表"的子句（`.window` / `.select` 等），**程序化再请求一次候选**并展开弹窗。需在编辑器侧"应用补全→设置光标"之后补一个"再次请求建议"的钩子。
- 与 T3b 的停点会话协同：首停点即 `PARTITION BY` 位置，弹窗应同时可用。

**验收**：接受 `row_number()`（带 `OVER(...)` 骨架）后，无需手动输入，弹窗立即列出 `PARTITION BY` / `ORDER BY`。

### T7 · 测试与验证

**文件**：`TableProTests/Core/Autocomplete/*`

- 单测：方言过滤（不同 `databaseType` 下函数集合断言）。
- 单测：`SQLCompletionInsertion.resolve` 对函数骨架的**多停点偏移**断言（UTF-16）。
- 单测：`SQLSnippetMarker.expand` 多 `;;` 的解析（含 0 / 1 / n 个停点）。
- 单测：MSSQL 查询字符串钉桩（参考现有 `MSSQLSchemaQueriesTests.swift`）。
- 手工：SQL Server 连接验证 `row_number()` 自动带 `OVER(PARTITION BY/ORDER BY)` 且自动弹候选、`SUBSTRING` 参数全出、Tab 跳转、`OVER` 可补全、表/字段备注显示与面板宽度。
- 构建：`xcodegen` + `xcodebuild`（Release 约 11 分钟）。

### T9 · ON 关联条件项生成（R6 · 启发式 + AND 续接，零取数）

**数据来源**：`context.tableReferences`（同域全部表）+ 各表 `ColumnInfo`（已缓存，含 `isPrimaryKey` / `typeName`）。**不新增任何取数**。

**改动**：
- 新增纯逻辑生成器（建议新文件 `TablePro/Core/Autocomplete/JoinConditionProvider.swift`，可单测）：由各表列（+ 可选 FK，见 T10）产出 `t1alias.c1 = t2alias.c2` 条件项，并按 tier（外键0 / 同名+主键1 / 同名2 / int·bigint3）排序、两向生成、去重、上限裁剪。
- `SQLContextAnalyzer`：`scanLinearClause` 遇 `AND/OR` 时继续回溯找**支配子句**，**仍返回 `.and`**（保持既有断言不变）；支配子句为 `ON` 时 `SQLContext` 增记 `andContinuesJoin = true`。
- `SQLCompletionProvider`：`.on` 分支**保留原单列候选**并**追加关联条件项（置顶）**；`.and` 分支在 `andContinuesJoin == true` 时同样追加（并排除已用对 `x = y`）。

**验收**：见第 8 章。

### T10 · JOIN 关联条件项 · 外键元数据（R6 · 必做）

**范围**：接入真实外键使 tier0 精确；元数据缺失时自动回退 T9 的同名/PK/int 启发式。

**改动**：
- `SQLSchemaProvider.ColumnMetadataSource` 增可选闭包 `fetchForeignKeys: (table, schema) -> [ForeignKeyInfo]`（app 内部结构体，**非插件协议，零 ABI 风险**）。
- `SQLSchemaProvider` 增 FK LRU 缓存 + `getForeignKeys(for:schema:)`（**镜像 `getColumns`**：LRU + in-flight 去重 + await；首个 `.on` 按键触发一次取数，其后命中缓存）。
- `SchemaProviderRegistry.getOrCreate` 接线 `metadataProvider.withMetadataDriver { $0.fetchForeignKeys(table:schema:) }`。

**验收**：FK 命中时 `o.customer_id = c.id` 精确置顶（tier0）；缓存未热时退化为 T9 启发式，行为不劣化。

### T11 · 备注行内显示（R7 · 修正 D5）

**勘查结论**：
- 候选行渲染在 `Packages/TableProEditor/Sources/TableProEditorKit/CodeSuggestion/View/CodeSuggestionLabelView.swift`，当前只画 **图标 + 名称 + 类型(detail)**，不发 `documentation`。
- 备注（`documentation`）目前只喂 `SuggestionPreviewView`（**焦点依赖**，即用户所说"要移焦点才在下面显示"）。
- `SuggestionContentView.contentWidth` 已按「字段 50 + 类型 20 + 备注 30」计算宽度 → **备注列空间已预留**，行内加备注不会挤爆。

**改动**：
- `SQLSuggestionEntry`（`QueryCompletionAdapter.swift:275`）：表/列项把 comment 传给**行内备注**属性，且把 `documentation` 置 nil（避免预览面板重复）；函数/收藏项保持 `documentation`（预览不变）。
- `CodeSuggestionEntry` 增 `var inlineNote: String?`（默认 nil）；`CodeSuggestionLabelView` 在 `detail` 右侧渲染 `inlineNote`（secondary 色、尾部截断、留间距）。
- 表项 `comment`、列项 `comment` 均走该通路（列项 default/PK 等信息仍在 detail）。

**边界**：备注为空 → 不占位；过长 → 尾部截断省略号。

**验收**：无需移动焦点，候选行右侧即见备注（表名/字段名各自右侧）。

---

## 5. 风险与约束

1. **ABI 红线**：`TableProPluginKit` 任何结构体布局不得改动。`PluginColumnInfo.comment` / `PluginTableInfo.comment` **已存在**，T6 只是填值，安全。R1 方案 A 全落在 app 侧 `SQLKeywords`，安全。
2. **内置插件**：`/Applications/TablePro.app/Contents/PlugIns/` 下 17 个为官方预编译，改动其协议或重编会崩，方案已规避。
3. **触发策略改动**：T8 豁免 `.window` 会改变"用户零输入不弹窗"的既有行为——需确认在 `OVER (` 内在**未打字**时弹窗不打扰（弹窗内容为短列表，风险可控）。
4. **多停点复杂度**：T3b 触及编辑器包（`TableProEditorKit`），需新增停点会话状态并处理"用户离开该行/改字后失效"，属于本方案**复杂度最高的部分**。
5. **变参函数**：`CONCAT/COALESCE/GREATEST/LEAST/JSON_OBJECT...` 的 "最大参数" 无法穷举，保留 `...`。
6. **宽度计算**：D6 的 50/20/30 为字符宽，实际像素需乘字体宽并设屏占比上限，防止超宽。

---

## 6. 任务顺序与依赖

```
T1（数据规范化 + 方言标记）
  ├─→ T2（方言过滤 R1）
  └─→ T3a（骨架插入 R2）─→ T3b（多停点 D4）
                              └─→ T8（自动弹出 R4）
T4（OVER 可达 R4，独立小改，可与 T3 并行）
T5（表备注接线 + 面板加宽 R5）
  └─→ T6（MSSQL 取数 R5）
  └─→ T11（备注行内显示 R7 · 修正 D5）
T9（ON 关联条件项·启发式 R6，零取数，独立一线）
  └─→ T10（FK 元数据·必做 R6）
T7（测试/验证，贯穿）
```

先做 **T1**（地基，R1/R2 共用），再 **T2 / T3a / T3b**，随后 **T4 + T8**；R5 走 **T5 → T6 → T11** 一线；R6 走 **T9 → T10** 独立一线，**仅在 `.on`（及其 AND/OR 续接）追加关联条件项**，不影响其他子句。全部完成后统一 `xcodebuild` 并做一次真机手工验证。

---

## 7. 决策落定记录

| 原未决项 | 结论 |
|---------|------|
| 预览面板是否放宽 | **加宽**，按 字段 50 / 类型 20 / 备注 30 计算宽度，备注允许 1~2 行（D6 / T5） |
| 窗口函数接受后是否自动弹候选 | **要**，豁免 `.window` 压制并在接受后重新触发（D7 / T8） |
| 多停点 Tab 跳转是否纳入本期 | **纳入**（D4 / T3b） |

---

## 8. R6 · ON 自动列出「可整条补全」的 JOIN 关联条件（设计）

### 8.1 需求（修正后）

光标在 `ON`（及其后续 `AND`/`OR`）时，候选列表**直接给出关联条件整条**，形如 `t1.docentry = t2.docentry`；选中即把**整条条件**写入语句（`insertText` 为整条，而非单个列名）。关联条件由同域各表之间的关系推断得出。

> 修正说明：最初理解为「对单列候选排序」，实际为「**生成整条关联条件候选**」。规则（外键 / 同名+主键 / 同名 / int·bigint）不变，但作用对象从「单列排序」改为「**关联条件对的生成与排序**」。

### 8.2 可行性（基础设施，已验证）

- `SQLCompletionItem.insertText` **可不同于 `label`**（`SQLCompletionItem.swift:74,100`）。
- 「多 token 整条插入」的接受路径已存在：`QueryCompletionAdapter.swift:191-200` 以 `resolution.text` 整体替换，并处理 `;;` 光标停点（函数骨架已用）。
- 因此关联条件项只需：`label = "o.customer_id = c.id"`、`insertText` 同值、`kind = .column`、`detail = 关系类型`。**无需新增插入机制**。

### 8.3 关联条件对（pair）生成

对同域内每对表 (T1, T2)（按别名限定）扫描两表列，产出候选 `T1alias.c1 = T2alias.c2`：

| tier | 判定 | 对应用户规则 |
|------|------|-------------|
| 0 | **外键**：T1.c1 外键 → T2.c2（或反向） | 「外键肯定是第一位」 |
| 1 | **同名且一方为主键** | 「字段名相同有一个是主键就直接第二」 |
| 2 | **同名**（无主键条件） | 「字段名完全一样的列靠前」 |
| 3 | **int/bigint 兜底**：两列均为 `int`/`bigint`（含 PG 别名 `integer`/`int4`/`int8`），**且列名相似**（Q5） | 「推断一下数字 int 类的列一起」 |

- **单向生成**（修正）：每对条件只输出一次，方向为 `T1alias.c1 = T2alias.c2`（`FROM` 表在左、JOIN 表在右），不再输出镜像的 `T2alias.c2 = T1alias.c1`。原「两向都生成」会让同一关联关系以别名交换的形态出现两次。
- `sortPriority`：tier0=5 / tier1=12 / tier2=19 / tier3=26（`JoinConditionProvider.tierPriorities`），再**减去 `label` 长度**以抵消 `calculateScore` 末尾的「短名优先」长度项 —— 该项幅度大于 tier 间距，会把更长的低 tier 条件反超（实测 `t1.Memo = t2.Memo` 排在了 `t1.DocEntry = t2.DocEntry` 之前）。抵消后同 tier 内有效分一致、跨 tier 由 tier 决定，PK 恒在首位。全部低于单列候选的优先级，使关联条件整体置顶；**复用现有 `rankResults` 及其评分公式**。
- **条件项禁用 fuzzy 子序列匹配**（`SQLCompletionItem.allowsFuzzyMatch = false`）：整条条件文本过长，任意短词几乎都是它的子序列；否则输入 `and` 会把列表缩到恰好拼出 a-n-d 的那一条（并因两向而显示成 2 条）。仅保留锚定前缀与包含匹配。

### 8.4 与单列候选的关系（已拍板 Q4）

**保留**原单列候选（不破坏既有行为与测试），关联条件项**置顶**（tier 优先）。

### 8.5 上限与去重（已拍板 Q5）

- **tier3 int/bigint 兜底：仅当两列名「相似」时才生成对，其余不生成**。相似判定：忽略大小写与 `_id`/`Id` 后缀后相等，或一方为另一方的前缀/包含关系。
- 关联条件项总数 ≤ 上限（建议 12），tier 高者优先。
- **已用对排除**：`AND/OR` 续接 ON 时，语句中已写出的 `x = y` 不再列出。

### 8.6 降级与边界

- 无 schema / 无缓存：不生成条件项，退化为原单列行为。
- 派生表（无 `isPrimaryKey`/`typeName`）：`typeName` 缺失则跳过 tier3 判定，其余照常。
- `WHERE` / `HAVING` 的 `AND` **不受影响**。
- **不**改 `TableProPluginKit`、**不**改 `rankResults` 公式。

### 8.7 AND/OR 续接（必做）

`SQLContextAnalyzer.scanLinearClause` 遇 `AND/OR` 时继续回溯找**支配子句**（**仍返回 `.and`**，以保持 `SQLClauseDetectionTests` 第 34/35/56/94/150 行等既有断言不变）；若支配子句为 `ON`，在 `SQLContext` 标记 `andContinuesJoin = true`；provider 在 `.and` 且该标记时同样生成关联条件项（并排除已用对，8.5）。

### 8.8 FK 取数（T10 必做）

`ColumnMetadataSource` 增 `fetchForeignKeys` 闭包；`SQLSchemaProvider` 增 FK LRU 缓存 + `getForeignKeys(for:schema:)`（镜像 `getColumns`）；`SchemaProviderRegistry` 接线 `driver.fetchForeignKeys(table:schema:)`。

### 8.9 涉及文件与改动点

| 文件 | 改动 |
|------|------|
| `TablePro/Core/Autocomplete/JoinConditionProvider.swift`（新增） | 纯逻辑：由各表列 + FK 生成 `t1.col = t2.col` 条件项（tier 排序 + 单向 + 去重 + 上限 + 禁 fuzzy） |
| `TablePro/Core/Autocomplete/SQLCompletionItem.swift` | 增 `allowsFuzzyMatch` 字段（默认 `true`），条件项置 `false` |
| `TablePro/Core/Autocomplete/SQLCompletionProvider.swift` | `.on` 及 `.and(andContinuesJoin)` 分支追加关联条件项（置顶）；`filterByPrefix` 尊重 `allowsFuzzyMatch` |
| `Packages/TableProEditor/.../View/SuggestionContentView.swift` | 弹窗宽度按真实字宽测量（字段 50 字母 / 类型 20 字母 / 备注 30 汉字预算） |
| `TablePro/Core/Autocomplete/SQLContextAnalyzer.swift` | `scanLinearClause` 支持 AND/OR 支配子句识别；`SQLContext` 增 `andContinuesJoin` |
| `TablePro/Core/Autocomplete/SQLSchemaProvider.swift` | T10：FK LRU 缓存 + `getForeignKeys` |
| `TablePro/Core/Services/Query/SchemaProviderRegistry.swift` | T10：接线 `fetchForeignKeys` |
| `TableProTests/Core/Autocomplete/JoinConditionProviderTests.swift`（新增） | tier 生成 / 单向 / 排序不受 label 长度影响 / 禁 fuzzy / 去重 / 上限 / 降级 |
| `TableProTests/Core/Autocomplete/SQLContextAnalyzerJoinAndTests.swift`（新增） | `ON … AND` → `andContinuesJoin=true`；`WHERE … AND` → 不变 |

### 8.10 验收标准

- `SELECT * FROM orders o JOIN customers c ON |` → 顶部出现 `o.customer_id = c.id`（tier0），**可整条插入**。
- 同一关联关系**只出现一次**：不再出现别名镜像的 `c.id = o.customer_id`。
- 同名 PK 条件项（tier1）恒在仅同名的条件项（tier2）**之前**，不受列名长度影响。
- `... ON t1.DocEntry = t2.DocEntry and` 中间态：**不再**出现与 `and` 无关（靠 fuzzy 子序列命中的）条件项；输入空格后恢复完整条件列表。
- `... ON o.id = c.order_id AND |` → 续接仍给条件项，且**排除** `o.id = c.order_id`。
- 两表同名 PK → tier1 条件项；仅同名 → tier2；无关联 → tier3 int 兜底（受上限）。
- `... WHERE a = 1 AND |` → 候选与排序**逐字不变**。
- 弹窗宽度按真实字宽测量：字段列最多 50 字母、类型列最多 20 字母、备注列最多 30 汉字；`t1.DocEntry = t2.DocEntry` 之类长条件不再被截断，中文备注按汉字宽度留位。
- 既有 autocomplete 单测全绿；新增两个测试文件全绿。

### 8.11 已拍板

- **Q1** 外键第 1、同名+主键第 2，**不并列**。
- **Q2** int 兜底**仅 `int` / `bigint`**。
- **Q3** **要**真实外键取数（T10 必做）+ `ON` 后的 `AND/OR` 也要提示。
- **Q4** **保留**原单列候选，关联条件项**置顶**。
- **Q5** tier3 int 兜底**仅列名相似**才生成对，其余不生成。
