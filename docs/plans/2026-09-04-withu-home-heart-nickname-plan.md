# withU 首页爱心 + 昵称重建方案

状态：仅计划，本轮不修改业务代码。

> 本方案只覆盖 Flutter 首页标题区。
> 不要与 `2026-09-04-couple-timetable-widget-plan.md` 混用；那是 Android 4x2 桌面小组件方案。

## 1. 目标

在现网 Flutter 项目中重建首页顶部「爱心 + 昵称」区域：

- 情侣模式开启且已登录时，首页顶部显示 `用户昵称 / ❤️ / 对方昵称`。
- withU 已登录时，昵称直接使用登录态返回的用户昵称和对方昵称。
- 未登录时，不显示爱心，爱心位置显示显式「登录」提示。
- 已登录时，点击标题区任意位置，在前两个课表之间切换。
- 长按标题区，打开情侣历史课表选择。
- 关闭情侣模式时，恢复旧版首页标题，不显示爱心和昵称。

## 2. 范围

只重建首页标题区：

- 现有 withU 登录页、设置入口、认证服务和课表服务继续沿用，不重新发明一套链路。
- 不展开服务器配置、后端契约和设置页交互细节。
- 历史课表现状缺失，属于本方案需要新增的独立工作项。

## 3. 现状核对

原始方案中的部分文件名和状态假设与当前代码不符，本计划以当前仓库为准：

1. 当前仓库实际文件是 `WithuCouple*` 命名：
   - `lib/services/withu_couple_auth_service.dart`
   - `lib/services/withu_couple_session_store.dart`
   - `lib/services/withu_couple_timetable_service.dart`
   - `lib/screens/withu_couple_login_screen.dart`
   - `lib/screens/couple_timetable_settings_screen.dart`

   原方案中的 `withu_session_provider.dart`、`withu_auth_service.dart`、`withu_login_screen.dart` 不存在，不能按原路径实现。

2. `TimetableSettings` 已有 `homeTitleStyle`，默认 `HomeTitleStyle.classic`。
   它没有 `coupleMode`。需要新增专用字段，默认值为 `true`，保持情侣课表默认开启。

3. `WithuCoupleSession` 只保存用户名、密码、session/csrf/token，不保存 `loggedIn`、`userNickname`、`partnerNickname`。
   `WithuCoupleAuthService.connect()` 返回 `WithuCoupleLoginResult`，其中才有 `user` 和 `partner`。
   恢复昵称不能直接从 session model 读取。

4. 首页当前 `_buildProfileSwitcherTrigger` 的行为是打开 profile 快速切换 sheet。
   情侣模式开启后，这个入口需要改成直接切换前两个 profile；关闭情侣模式时仍保留旧行为。

5. 当前没有 `CoupleTimetableRole`，也没有 `entriesFor(role)` 情侣历史服务。
   长按历史课表需要作为新增能力实现，不能当作现成能力使用。

6. `DancingScript` 字体已注册：
   - 字体文件：`assets/fonts/DancingScript-Variable.ttf`
   - `pubspec.yaml` family：`DancingScript`
   情侣标题的昵称文本可直接使用 `fontFamily: 'DancingScript'`。

## 4. 配置字段

在 `lib/models/timetable_settings.dart` 中：

- 新增 `coupleMode`：
  - 类型：`bool`
  - 默认值：`true`
  - 序列化 key：`coupleMode`
  - 加入 `defaults()`、`toJson()`、`fromJson()`、`copyWith()`
- 继续使用现有 `homeTitleStyle`：
  - `HomeTitleStyle.classic`
  - `HomeTitleStyle.brand`
- 显示规则：
  - `coupleMode == true` 才显示爱心区。
  - `homeTitleStyle` 只决定 classic/brand 排版，不决定是否显示。

## 5. 首页触发条件

入口保持 `lib/screens/timetable_screen.dart` 的 `_buildProfileSwitcherTrigger`。

```dart
if (!provider.settings.coupleMode) {
  // HomeTitleStyle.classic -> _buildLegacyClassicProfileSwitcherTrigger
  // HomeTitleStyle.brand   -> _buildLegacyBrandProfileSwitcherTrigger
}

// coupleMode == true:
// HomeTitleStyle.classic -> _buildClassicProfileSwitcherTrigger
// HomeTitleStyle.brand   -> _buildBrandProfileSwitcherTrigger
```

## 6. 首页 UI 规格

### 6.1 Classic 情侣标题

`_buildClassicProfileSwitcherTrigger` 返回情侣标题内容。

外层：

- `Semantics(label: '$leftName / $rightName', button: true)`。
- `GestureDetector`，key 固定为 `ValueKey('profile_switcher_trigger')`。
- `onTap`：直接切换前两个情侣课表。
- `onLongPress`：打开情侣历史课表选择。

内部结构：

```text
[左昵称 + 选中点] [渐变线] [已登录爱心 / 未登录登录提示] [渐变线] [右昵称 + 选中点]
```

昵称块：

- 左右各 `Padding(horizontal: 8)`。
- 上方 `Text`，`fontSize: 22`，`height: 1`，`letterSpacing: 0`。
- 选中 `FontWeight.w700`，未选中 `FontWeight.w400`。
- 选中颜色 `#EF4444`，未选中颜色使用当前 foreground 的 0.62 透明度。
- `maxLines: 1`，`TextOverflow.ellipsis`。
- 下方 2dp 间距，再放 6x6 圆点。
- 圆点颜色：选中 `#EF4444`，未选中 `Colors.transparent`。

渐变线：

- `width: 28`，`height: 1`。
- `LinearGradient([#F87171, #EF4444])`。
- 左右各 `Padding(horizontal: 6)`。

未登录：

- 不渲染 `Icons.favorite_rounded` 爱心图标。
- 爱心位置显示「登录」提示按钮。
- key：`ValueKey('withu_heart_login_trigger')`。
- 文案使用 `l10n.withuLoginConfirm`，颜色 `#EF4444`。
- 点击进入现有 `WithuCoupleLoginScreen`。
- 尺寸和点击区与已登录爱心保持一致。

已登录：

- key 仍为 `ValueKey('withu_heart_login_trigger')`。
- `Icon(Icons.favorite_rounded, size: 20, color: #EF4444)`。
- 爱心不单独绑定 `GestureDetector`，点击交给外层统一切换。

昵称来源：

- 左：直接使用 withU 登录态返回的用户昵称。
- 右：直接使用 withU 登录态返回的对方昵称。
- `我`、`她` 只作为接口异常返回空字符串时的防御性兜底，不作为正常登录态的展示值。

选中态：

- `profiles` 有数据且 `activeProfileId == profiles.first.id` 时，左侧选中。
- `profiles.length > 1 && activeProfileId == profiles[1].id` 时，右侧选中。

### 6.2 Brand 情侣标题

`_buildBrandProfileSwitcherTrigger`：

- 外层 `GestureDetector`，key 仍为 `profile_switcher_trigger`。
- `onTap`、`onLongPress` 与 classic 相同。
- `Column(mainAxisSize: min, crossAxisAlignment: center)`：
  - 第一行：与 classic 相同的爱心/昵称内容。
  - 第二行：
    - 未登录：不额外显示登录提示，第一行已隐藏爱心并显示「登录」提示。
    - 已登录：显示当前 profile 名；没有名字则显示 `l10n.switchProfileHint`。
  - 第二行样式：`body.sm`、`mutedForeground`、`FontWeight.w500`。

### 6.3 旧版标题

`coupleMode == false` 时保留现网行为：

- classic：显示 `timetableAppName`，点击打开 profile 快速切换 sheet。
- brand：主标题 `timetableAppName` + 副标题当前 profile 名或 `switchProfileHint`。
- 不显示情侣爱心和昵称区。

## 7. 点击与长按行为

### 7.1 切换情侣课表

触发区域：

- 已登录：标题区整体可点，包括昵称、渐变线和爱心。
- 未登录：「登录」按钮单独进入登录页；昵称和渐变线仍由外层统一切换。
- 爱心已登录时不能放独立 `GestureDetector`，否则会吃掉点击事件。

切换逻辑：

- `profiles.length < 2`：提示 `switchProfileHint`，不切换。
- 当前是 `profiles.first.id` 时切到 `profiles[1].id`，否则切回第一个。
- 成功：触发 `HapticFeedback.selectionClick()` 和樱花掉落。
- 失败：显示 `switchProfileHint` 错误提示。

### 7.2 历史课表

长按标题区：

1. 弹出 `HyperosSheet`：
   - `左昵称 / 我的历史课表`
   - `右昵称 / 她的历史课表`
2. 根据选择读取 `CoupleTimetableRole.mine` 或 `CoupleTimetableRole.hers` 的记录。
3. 无记录显示 `noHistoryRecords`；有记录显示可恢复列表。

当前没有这个服务。实现时需要新增：

- `CoupleTimetableRole`
- 历史条目模型
- `entriesFor(role)` 或等价查询
- 持久化和恢复入口

这项能力可以与首页 UI 一起交付，也可以单独拆成 follow-up；最终方案不能把它标成“已有实现”。

## 8. withU Provider

新增 `WithuCoupleSessionProvider`，不要使用不存在的 `WithuSessionProvider`：

公开状态：

| 成员 | 含义 |
|---|---|
| `session` | `WithuCoupleSession?`，原始凭证会话 |
| `isLoggedIn` | 远端登录态是否有效 |
| `isRestoring` | 是否正在恢复会话 |
| `userNickname` | 登录态返回的用户昵称；仅接口异常返回空字符串时兜底 `我` |
| `partnerNickname` | 登录态返回的对方昵称；仅接口异常返回空字符串时兜底 `她` |

恢复流程：

1. 防止重复恢复。
2. 用现有 `WithuCoupleSessionStore.load()` 读取本地凭证。
3. 有凭证时，通过现有 `WithuCoupleAuthService` 调用 bootstrap/登录态校验。
4. 成功后保存 `user` 和 `partner` 的展示昵称。
5. 失败时保持未登录，隐藏爱心并显示「登录」提示；`我/她` 只作为异常数据兜底。
6. 状态变化后调用 `notifyListeners()`。

登录、退出和服务器配置继续由现有登录链路处理。新增 Provider 可以持有并复用现有 `WithuCoupleAuthService`，不应复制一套认证逻辑。

## 9. 启动注入

`lib/main.dart`：

- 在 `MultiProvider` 中注册：

```dart
ChangeNotifierProvider(create: (_) => WithuCoupleSessionProvider())
```

- 在 `AppEntryScreen.initState` 中调用：

```dart
unawaited(context.read<WithuCoupleSessionProvider>().restoreSession());
```

## 10. 文件清单

| 文件 | 类型 | 改动 |
|---|---|---|
| `lib/screens/timetable_screen.dart` | 修改 | 首页情侣标题切换器、爱心/登录按钮/昵称 UI、点击长按行为 |
| `lib/models/timetable_settings.dart` | 修改 | 新增 `coupleMode` 默认值和序列化 |
| `lib/providers/withu_couple_session_provider.dart` | 新增 | withU 登录态、昵称和会话恢复 |
| `lib/services/withu_couple_auth_service.dart` | 沿用 | withU 认证服务 |
| `lib/services/withu_couple_session_store.dart` | 沿用 | withU 凭证存储 |
| `lib/services/withu_couple_timetable_service.dart` | 沿用 | withU 情侣课表服务 |
| `lib/screens/withu_couple_login_screen.dart` | 沿用 | withU 登录页 |
| `lib/screens/couple_timetable_settings_screen.dart` | 沿用 | 情侣模式入口 |
| `lib/main.dart` | 修改 | 注册 Provider、启动恢复会话 |
| `lib/l10n/*.arb` 及生成文件 | 修改 | 首页相关文案 |
| 历史课表支持文件 | 新增 | `CoupleTimetableRole`、`entriesFor(role)`、持久化 |

## 11. 文案表

| key | 中文 |
|---|---|
| `coupleModeTitle` | 情侣模式 |
| `withuLoginConfirm` | 登录 |

需要按项目现有 l10n 生成流程同步所有语言，不只改中文。

## 12. 测试验收

参考 `test/widgets/timetable_switcher_test.dart`：

1. 首页点击标题可在两个情侣课表间直接切换。
2. 默认未登录时不显示爱心，显示「登录」提示。
3. `coupleMode=false` 后恢复旧版标题，情侣爱心和昵称消失。
4. 已登录且 `homeTitleStyle=brand` 时，首页显示当前 profile 名和 withU 对方昵称。
5. 长按标题打开历史课表，出现「我的历史课表」「她的历史课表」。
6. 未登录时不渲染爱心图标，爱心位置显示「登录」提示，点击进入现有 withU 登录页。
7. 已登录时显示爱心和昵称，点击爱心可切换课表。
8. 已登录时点击昵称、渐变线等标题区任意位置也可切换。
9. 默认 `coupleMode=true`，情侣课表默认开启；显式关闭后恢复旧版标题。
10. 历史能力实现前，长按不能引用不存在的 `CoupleTimetableRole`。

## 13. 重建步骤

1. 沿用现有 `WithuCouple*` 登录链路，不复制不存在的旧文件路径。
2. 在 `main.dart` 注册 `WithuCoupleSessionProvider` 并调用 `restoreSession()`。
3. 在 `TimetableSettings` 增加 `coupleMode`，默认 `true`，补齐序列化和 `copyWith`。
4. 复制并调整首页 classic/brand/legacy 分支；情侣模式改直接切换，旧模式保持快速切换 sheet。
5. 实现爱心/昵称内容：已登录爱心 + 昵称，未登录「登录」按钮。
6. 实现切换、长按历史 sheet 和樱花掉落。
7. 补齐历史课表角色与服务，或单独列入后续任务。
8. 同步 l10n 文案，跑首页 widget 测试。

完成后只验证 UI 是否符合本方案，不改其他业务代码。
