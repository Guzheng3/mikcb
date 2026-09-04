# 情侣课表 4×2 桌面卡片复刻计划（2026-09-04）

> 状态：仅计划，未实施。  
> 目标项目：`mikcb`（Android 包名 `com.mutx163.qingyu`）。

## 1. 目标

在当前 Android 项目中重新实现一个外观与行为一致的“情侣课表”桌面小组件：

- 4×2，左右双列：左右名字不写死，由 withU 登录账号和绑定的伴侣作为参数传入。
- 不限制课程条数：按卡片高度显示，放不下的向下堆叠并支持滑动；今日课程结束后提示“今天没有课了”，接着显示明日课程。
- 当前进行中的课程高亮，并显示带休息段的进度条；高亮颜色可在设置中自定义。
- 支持空状态、底部统计文案、明暗模式颜色、多语文案。
- `CoupleTimetableStore` 保存 withU 已对接的真实账号、伴侣和课程数据，不使用模拟数据；登录/绑定成功后由 app 写入。

## 2. 最终文件清单

### 新建文件

| 文件 | 用途 |
|---|---|
| `android/app/src/main/kotlin/com/mutx163/qingyu/CoupleTimetableWidgetProvider.kt` | 小组件 Provider 核心逻辑 |
| `android/app/src/main/kotlin/com/mutx163/qingyu/CoupleTimetableStore.kt` | 保存/读取 withU 账号、伴侣、双方课程快照和高亮颜色设置 |
| `android/app/src/main/kotlin/com/mutx163/qingyu/CoupleTimetableViewsService.kt` | 可滚动课程列表的 RemoteViewsService + Factory |
| `android/app/src/main/res/layout/widget_couple_timetable.xml` | 4×2 双栏卡片主体布局 |
| `android/app/src/main/res/layout/widget_couple_course_item.xml` | 单节课条目布局 |
| `android/app/src/main/res/layout/widget_couple_course_divider.xml` | 课程间隔线 |
| `android/app/src/main/res/layout/widget_couple_today_ended_item.xml` | “今天没有课了”提示条目 |
| `android/app/src/main/res/xml/widget_couple_timetable_info.xml` | AppWidget 配置 |
| `android/app/src/main/res/drawable/widget_couple_bg.xml` | 卡片圆角背景 |
| `android/app/src/main/res/drawable/widget_couple_current_bg.xml` | 进行中课程圆角背景 |
| `android/app/src/main/res/drawable/widget_couple_heart.xml` | 心形 vector |
| `android/app/src/main/res/drawable/widget_couple_indicator.xml` | 课程左侧色条 |
| `android/app/src/main/res/drawable/widget_preview_couple_timetable.png` | 小组件预览图 |
| `android/app/src/main/res/font/pacifico_regular.ttf` | Pacifico 字体 |
| `android/app/src/main/res/font/pacifico.xml` | 字体资源定义 |

### 修改文件

| 文件 | 改动 |
|---|---|
| `android/app/src/main/res/values/colors.xml` | 增加 10 个 `widget_couple_*` 颜色 |
| `android/app/src/main/res/values-night/colors.xml` | 增加夜间版 `widget_couple_*` 颜色 |
| `android/app/src/main/res/values/widget_strings.xml` | 增加 3 个情侣课表字符串 |
| `android/app/src/main/res/values-en/widget_strings.xml` | 英文文案 |
| `android/app/src/main/res/values-ja/widget_strings.xml` | 日文文案 |
| `android/app/src/main/res/values-ko/widget_strings.xml` | 韩文文案 |
| `android/app/src/main/res/values-zh-rHK/widget_strings.xml` | 繁中（香港）文案 |
| `android/app/src/main/res/values-zh-rTW/widget_strings.xml` | 繁中（台湾）文案 |
| `android/app/src/main/AndroidManifest.xml` | 注册 receiver 与 `RemoteViewsService` |
| `android/app/src/main/kotlin/com/mutx163/qingyu/TodayWidgetSupport.kt` | `updateAll()` 加入情侣课表刷新 |
| `android/app/src/main/kotlin/com/mutx163/qingyu/HomeWidgetStorage.kt` | `rescheduleRefresh()` 加入情侣课表刷新时间 |

## 3. 资源规格

### 3.1 颜色

`values/colors.xml` 增加：

```xml
<color name="widget_couple_bg">#FEF7FF</color>
<color name="widget_couple_current_bg">#F3F7FE</color>
<color name="widget_couple_text_primary">#2C3E50</color>
<color name="widget_couple_text_secondary">#5D6D7E</color>
<color name="widget_couple_shadow">#262C3E50</color>
<color name="widget_couple_text_hint">#808B96</color>
<color name="widget_couple_divider">#EAECEE</color>
<color name="widget_couple_left_accent">#3B82F6</color>
<color name="widget_couple_right_accent">#EC4899</color>
```

`values-night/colors.xml` 增加：

```xml
<color name="widget_couple_bg">#141218</color>
<color name="widget_couple_current_bg">#201F26</color>
<color name="widget_couple_text_primary">#F2F2F7</color>
<color name="widget_couple_text_secondary">#AEA9AF</color>
<color name="widget_couple_shadow">#59F2F2F7</color>
<color name="widget_couple_text_hint">#8E8E93</color>
<color name="widget_couple_divider">#2C2C2E</color>
<color name="widget_couple_left_accent">#64B5F6</color>
<color name="widget_couple_right_accent">#F48FB1</color>
```

### 3.2 文案

`values/widget_strings.xml` 增加：

```xml
<string name="widget_couple_timetable_name">情侣课表 4×2</string>
<string name="widget_couple_tomorrow_count">明日共 %1$d 节</string>
<string name="widget_couple_no_course_tomorrow">明日无课</string>
```

同时在其他语言版本同步：

| 语言 | `widget_couple_timetable_name` | `widget_couple_tomorrow_count` | `widget_couple_no_course_tomorrow` |
|---|---|---|---|
| `values-en` | Couple timetable 4×2 | %1$d classes tomorrow | No classes tomorrow |
| `values-ja` | カップル時間割 4×2 | 明日 %1$d コマ | 明日は授業なし |
| `values-ko` | 커플 시간표 4×2 | 내일 %1$d교시 | 내일 수업 없음 |
| `values-zh-rHK` | 情侶課表 4×2 | 明日共 %1$d 節 | 明日無課 |
| `values-zh-rTW` | 情侶課表 4×2 | 明日共 %1$d 節 | 明日無課 |

复用已有字符串：`widget_no_course_today`、`widget_today_ended_short`、`widget_today_count`。

### 3.3 drawable

`widget_couple_bg.xml`：

```xml
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <solid android:color="@color/widget_couple_bg" />
    <corners android:radius="18dp" />
</shape>
```

`widget_couple_current_bg.xml`：

```xml
<shape xmlns:android="http://schemas.android.com/apk/res/android"
    android:shape="rectangle">
    <solid android:color="@color/widget_couple_current_bg" />
    <corners android:radius="8dp" />
</shape>
```

`widget_couple_heart.xml`：

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="14dp"
    android:height="14dp"
    android:viewportWidth="24"
    android:viewportHeight="24">
    <path
        android:fillColor="#FF5C7A"
        android:pathData="M12,21.35l-1.45,-1.32C5.4,15.36 2,12.28 2,8.5C2,5.42 4.42,3 7.5,3c1.74,0 3.41,0.81 4.5,2.09C13.09,3.81 14.76,3 16.5,3C19.58,3 22,5.42 22,8.5c0,3.78 -3.4,6.86 -8.55,11.54L12,21.35z" />
</vector>
```

`widget_couple_indicator.xml`：

```xml
<shape xmlns:android="http://schemas.android.com/apk/res/android">
    <solid android:color="#FFFFFF" />
    <corners android:radius="10dp" />
    <size android:width="4dp" android:height="40dp" />
</shape>
```

`widget_preview_couple_timetable.png`：直接复用原项目现有图片。

### 3.4 字体

`res/font/pacifico.xml`：

```xml
<font-family xmlns:android="http://schemas.android.com/apk/res/android">
    <font
        android:font="@font/pacifico_regular"
        android:fontStyle="normal"
        android:fontWeight="400" />
</font-family>
```

## 4. 布局规格

### 4.1 `widget_couple_timetable.xml`

外层：`LinearLayout`，id `widget_card`，`match_parent`，背景 `@drawable/widget_couple_bg`，垂直方向，padding `10dp/7dp/10dp/7dp`。

顶部横向行（`wrap_content`）：

- `FrameLayout` id `widget_couple_left_name_container`，weight 1
  - `ImageView` id `widget_couple_left_name`，`layout_gravity="end|center_vertical"`
- `ImageView` id `widget_couple_heart`，14dp×14dp，左右 margin 6dp，src 心形
- `FrameLayout` id `widget_couple_right_name_container`，weight 1
  - `ImageView` id `widget_couple_right_name`，`layout_gravity="start|center_vertical"`

下部横向行（weight 1，marginTop 5dp）：

- 左列 `LinearLayout` id `widget_couple_left_column`，weight 1
  - 可滚动 `ListView` id `widget_couple_left_list`，weight 1
  - 空状态 `TextView` id `widget_couple_left_empty`，默认 `gone`
  - 底部文案 `TextView` id `widget_couple_left_footer`，9sp，maxLines 1
- 右列 `LinearLayout` id `widget_couple_right_column`，weight 1，marginLeft 8dp
  - 可滚动 `ListView` id `widget_couple_right_list`，weight 1
  - 空状态 id `widget_couple_right_empty`
  - 底部文案 id `widget_couple_right_footer`

### 4.2 `widget_couple_course_item.xml`

横向 `LinearLayout`，id `widget_couple_course_root`，`match_parent`，`center_vertical`，paddingHorizontal 4dp，paddingTop/Bottom 4dp：

- 左侧色条 `ImageView` id `widget_couple_course_indicator`，4dp 宽、`match_parent` 高，上下 margin 2dp，src `widget_couple_indicator`
- 右侧内容列（weight 1，marginStart 6dp）：
  - 课名 `TextView` id `widget_couple_course_name`：12sp bold，主色，maxLines 1
  - `RelativeLayout`：
    - 地点 id `widget_couple_course_location`：10sp，次色，`toStartOf` 时间
    - 时间 id `widget_couple_course_time`：10sp，次色，`alignParentEnd`
  - 进度条 `ImageView` id `widget_couple_course_progress`：3dp 高，`match_parent` 宽，默认 `gone`

### 4.3 `widget_couple_course_divider.xml`

`ImageView`，`match_parent` 宽，1dp 高，marginHorizontal 6dp，marginTop/Bottom 2dp，背景 `@color/widget_couple_divider`。

### 4.4 `widget_couple_today_ended_item.xml`

`TextView`，`match_parent` 宽，`wrap_content` 高，上下 padding 4dp，居中，11sp，颜色 `widget_couple_text_hint`，文案 `@string/widget_today_ended_short`。

## 5. AppWidget 配置

`widget_couple_timetable_info.xml`：

```xml
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:description="@string/widget_couple_timetable_name"
    android:initialLayout="@layout/widget_couple_timetable"
    android:minWidth="250dp"
    android:minHeight="110dp"
    android:previewImage="@drawable/widget_preview_couple_timetable"
    android:previewLayout="@layout/widget_couple_timetable"
    android:resizeMode="horizontal|vertical"
    android:targetCellWidth="4"
    android:targetCellHeight="2"
    android:updatePeriodMillis="0"
    android:widgetCategory="home_screen" />
```

## 6. Provider 逻辑规格

### 6.1 数据类

```kotlin
private data class CoupleWidgetBreak(
    val startTime: String,
    val endTime: String,
)

private data class CoupleWidgetCourse(
    val name: String,
    val location: String,
    val startTime: String,
    val endTime: String,
    val breaks: List<CoupleWidgetBreak> = emptyList(),
)

private data class CoupleWidgetProgressSegment(
    val weight: Float,
    val progress: Float,
    val isBreak: Boolean = false,
)

private data class CoupleWidgetDisplayCourse(
    val course: CoupleWidgetCourse,
    val isOngoing: Boolean = false,
    val progressSegments: List<CoupleWidgetProgressSegment> = emptyList(),
)

private sealed class CoupleWidgetDisplayItem {
    data class Course(val course: CoupleWidgetDisplayCourse) : CoupleWidgetDisplayItem()
    data class TodayEndedNotice(val textRes: Int = R.string.widget_today_ended_short) : CoupleWidgetDisplayItem()
}

private data class CoupleWidgetDisplay(
    val items: List<CoupleWidgetDisplayItem>,
    val emptyTextRes: Int,
    val footerText: String,
)
```

### 6.2 数据来源（withU 已对接）

- 名字、课程和高亮颜色都不写死在 Provider 里：`updateAll` 从 `CoupleTimetableStore` 读取 withU 登录账号、绑定伴侣、双方课程和高亮颜色设置。
- withU 已对接：登录/绑定成功后，由 app 把当前账号、绑定伴侣、双方真实课程和高亮颜色设置写入 `CoupleTimetableStore`；卡片只读这份真实数据，不使用测试课程。
- 课程字段：名称、地点、开始时间、结束时间、休息段列表。
- 高亮颜色字段：左列默认 `widget_couple_left_accent`，右列默认 `widget_couple_right_accent`；设置里修改后覆盖默认值。

### 6.3 渲染流程

`updateAll(context)`：

1. 通过 `AppWidgetManager` + `ComponentName` 获取所有 widget id。
2. 逐个调用 `updateWidget`。

`updateWidget`：

1. 创建 `RemoteViews(context.packageName, R.layout.widget_couple_timetable)`。
2. 设置左侧名字位图、右侧名字位图、心形位图。
3. 左列设置“打开登录账号课表”的 PendingIntent，右列设置“打开伴侣课表”的 PendingIntent，两个 Intent 都携带目标账号参数。
4. 整卡热区默认使用登录账号侧 Intent；如果不需要整卡热区，可只保留左右两列热区。
5. 从 store 读取左列/右列高亮颜色，作为参数调用 `bindColumn` 绑定左右两列。
6. `updateAppWidget`。

`buildLaunchPendingIntent(context, appWidgetId, targetAccount)` 在现有 `TodayWidgetSupport.buildLaunchPendingIntent` 基础上增加目标账号参数：

- 左列传 `myName`（当前 withU 登录账号）。
- 右列传 `partnerName`（绑定伴侣账号）。
- 仍保留 `EXTRA_WIDGET_LAUNCH` 和 `appWidgetId`，MainActivity/Flutter 读取目标账号后打开对应课表。

`bindColumn`：

1. 调用 `buildDisplay` 计算显示数据。
2. 将显示数据写入 `CoupleTimetableStore`（按 appWidgetId + 左右侧）。
3. 设置底部 footer 文案和空状态文案。
4. 无任何课程时：隐藏列表，显示空状态。
5. 有课程时：显示列表，`setRemoteAdapter` 指向 `CoupleTimetableViewsService`。
6. `RemoteViewsFactory` 按条目类型渲染：课程条目或“今天没有课了”提示条目。
7. 课程条目：使用设置中的高亮颜色设置背景、进度条和进度位图。
8. 列表不限制条数，按卡片高度显示，放不下的向下滚动。

`buildDisplay`：

1. 过滤今日课程：`endTime > now`。
2. 进行中课程优先，其次按开始时间、结束时间排序。
3. 有剩余课程：返回全部今日课程条目，footer 为 `今日共 N 节`。
4. 无剩余课程且今日原本有课：列表第一项插入“今天没有课了”提示，后面接全部明日课程。
5. 无剩余课程且今日无课：空状态用 `widget_no_course_today`，后面仍可接明日课程。
6. footer：明日课程存在用 `明日共 N 节`，否则 `明日无课`。

### 6.4 位图生成

`createNameBitmap`：

- Pacifico 字体，13sp，主色。
- 阴影：2dp 半径、0 水平偏移、1dp 垂直偏移、`widget_couple_shadow`。
- 按文本测量宽度，padding 1.5dp。

`createHeartBitmap`：

- 16dp 正方形位图。
- 用 `Path` 画心形（Material heart path）。
- 填充色 `widget_couple_right_accent`。

`createProgressBitmap`：

- 220dp × 4dp 位图。
- 底色 `widget_couple_divider`。
- 进度色为对应列高亮色：优先用设置值，未设置时用默认 accent。
- 圆角为高度一半。
- 按休息段切分：上课段画进度，休息段在边界画竖线标记。
- 休息段标记色 `widget_couple_current_bg`，宽 1.2dp。

### 6.5 可滚动列表（RemoteViewsService）

`CoupleTimetableViewsService` 继承 `RemoteViewsService`，`onGetViewFactory` 返回 `CoupleTimetableViewsFactory`：

1. Factory 从 `CoupleTimetableStore` 读取该 appWidgetId 对应列的 `CoupleWidgetDisplay`。
2. `getCount()` 返回 `items.size`。
3. `getViewAt()` 按条目类型渲染：
   - `Course`：使用 `widget_couple_course_item.xml`。
   - `TodayEndedNotice`：使用 `widget_couple_today_ended_item.xml`。
4. 课程条目之间插入 divider；列表不取前 N 条，全部交给 ListView 滚动。

`updateWidget` 中通过 `views.setRemoteAdapter(R.id.widget_couple_left_list, serviceIntent)` 和右列对应 id 接入。

### 6.6 刷新策略（1 分钟轮询）

情侣课表不按课程事件精确调度，改用固定 1 分钟轮询；轮询只做轻量更新，不整卡重绘。

`findNextRefreshAtMillis(nowMillis)` 直接返回 `nowMillis + 60_000`，保证每分钟都会检查一次。

每分钟 tick：

1. 从 `CoupleTimetableStore` 读取当前状态，不调用 withU 网络接口。
2. 有进行中课程且高亮课程没变：只重新生成进度条位图，用 `partiallyUpdateAppWidget` 更新对应课程条目的进度条；名字、心形、列表、footer、空状态都不重绘。
3. 高亮课程变了（课程开始/下课、休息段开始/结束）：调用 `updateAll(context)` 整卡刷新。
4. 日期跨到明天或今日课程全部结束：调用 `updateAll(context)` 整卡刷新，让“今天没有课了”和明日课程生效。
5. 无任何变化：跳过绘制，只安排下一分钟轮询。

整卡刷新只发生在：withU 登录/绑定、课程数据或高亮颜色变化、高亮课程切换、今日结束/次日切换。

课程上完/切换时不做任何动画：`updateAll` 直接重建列表并替换内容，旧课程消失、下一节高亮、进度条归零都立即生效；今日结束后直接插入“今天没有课了”+明日课程。

## 7. 集成点

### 7.1 AndroidManifest.xml

在现有 widget receiver 区域增加：

```xml
<receiver
    android:name=".CoupleTimetableWidgetProvider"
    android:label="@string/widget_couple_timetable_name"
    android:exported="true">
    <intent-filter>
        <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
    </intent-filter>
    <meta-data
        android:name="android.appwidget.provider"
        android:resource="@xml/widget_couple_timetable_info" />
</receiver>

<service
    android:name=".CoupleTimetableViewsService"
    android:permission="android.permission.BIND_REMOTEVIEWS"
    android:exported="true" />
```

### 7.2 TodayWidgetSupport.updateAll()

在方法末尾加入：

```kotlin
CoupleTimetableWidgetProvider.updateAll(context)
```

### 7.3 HomeWidgetStorage.rescheduleRefresh()

在 `buildList` 中加入：

```kotlin
add(CoupleTimetableWidgetProvider.findNextRefreshAtMillis(nowMillis))
```

这样情侣课表会固定每 1 分钟进入一次统一刷新调度；数据变化时调用 `updateAll(context)` 立即刷新，并重新 `rescheduleRefresh(context)` 安排下一分钟。

### 7.4 withU 名称与课表数据入口

1. Flutter/withU 登录和绑定成功后，调用 `CoupleTimetableStore.save(context, myName, partnerName, myCourses, partnerCourses, myHighlightColor, partnerHighlightColor)`。
2. 设置页修改高亮颜色后，同样写入 `CoupleTimetableStore`。
3. `CoupleTimetableWidgetProvider.updateAll()` 从 store 读取，把名字、课程和高亮颜色作为参数传入 `updateWidget` / `bindColumn`。
4. 数据未就绪时显示占位（如“我 / TA”或隐藏名字），不写死 `govex` / `xoveg`。
5. store 数据变化后调用 `TodayWidgetSupport.updateAll(context)` 和 `HomeWidgetStorage.rescheduleRefresh(context)`（数据变化时立即刷新，不等 1 分钟轮询）。
6. 点击左列/右列时，Intent 分别携带登录账号和伴侣账号，Flutter 打开对应账号的课表。

## 8. 复刻步骤

1. **资源层**：新增 15 个文件（含“今天没有课了”提示条目）+ 修改 11 个文件（颜色、drawable、字体、布局、xml、字符串、Manifest、刷新入口）。
2. **数据层**：实现 `CoupleTimetableStore`，提供 withU 账号、伴侣、课程快照和高亮颜色设置的读写。
3. **Provider 层**：编写 `CoupleTimetableWidgetProvider.kt`，渲染与刷新全部走参数/Store，不写死名字和条数。
4. **列表层**：实现 `CoupleTimetableViewsService` + Factory，让课程列表可滚动。
5. **注册层**：`AndroidManifest.xml` 注册 receiver 和 RemoteViewsService。
6. **集成层**：修改 `TodayWidgetSupport.updateAll()` 和 `HomeWidgetStorage.rescheduleRefresh()`，并接入 withU 写入入口。
7. **构建验证**：`flutter build apk --debug` 或 Gradle 构建，确认资源 ID 和编译无误。

## 9. 验证清单

1. 桌面添加“情侣课表 4×2”小组件，预览图正常。
2. 左右名字来自 withU 登录账号/绑定伴侣，不写死 `govex` / `xoveg`。
3. 课程条数不限制，超出卡片高度可向下滚动。
4. 今日无课时显示空状态。
5. 今日课程结束后先显示“今天没有课了”，再接着显示明日课程。
6. 进行中的课程高亮并显示进度条，休息段边界正确。
7. 设置页修改高亮颜色后，进行中课程背景和进度条立即使用新颜色。
8. 点击左列打开登录账号课表，点击右列打开伴侣课表；不带目标账号时默认打开登录账号课表。
9. 每 1 分钟轮询；进行中课程不变时只更新进度条，课程/日期切换时整卡刷新且直接生效、无动画。
10. 夜间模式颜色正确。
11. 中文、英文、日文、韩文、繁中文案正确。
