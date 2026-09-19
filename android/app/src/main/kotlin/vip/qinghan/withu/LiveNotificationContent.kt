package vip.qinghan.withu

import java.util.Calendar

/**
 * 常驻下拉通知的内容组装。
 *
 * 通知在「没有课程会话」时的形态直接沿用**情侣卡片**的文案：调用方拿
 * `CoupleTimetableDisplayBuilder.build(context, snapshot.mine, now, snapshot.status)`
 * 算出卡片实际会渲染的那一列（只传 `mine`，所以只讲我自己的课），本文件负责把那份
 * 结果映射成通知的标题 / 正文 / 脚注。
 *
 * 放在文件顶层并用 `internal` 暴露，是为了能用普通 JVM 单测覆盖 —— 这一层不碰
 * Context，所有文案都由调用方从资源取好后传进来，与 `truncateIslandLine`、
 * `buildPromotedDetailLines` 的做法一致。
 */

/** 常驻通知空闲档位的内容。`title` 恒非空（可能是状态文案），正文与脚注可为空。 */
internal data class LiveIdleContent(
    val title: String,
    val bodyLines: List<String> = emptyList(),
    val footer: String = "",
) {
    /** 去重签名：与服务里缓存的上一帧比较，决定是否值得重新 notify。 */
    fun signature(): String = (listOf(title) + bodyLines + footer).joinToString("\u0000")
}

/**
 * 把情侣卡片「我这一列」的渲染结果映射成通知内容。
 *
 * 三档的取法（与卡片的视觉顺序一致）：
 * * 卡片给了 `Notice`（今天已结束、今天没有课程、周末没有课程、情侣模式不可用）
 *   → 用这条状态文案当标题，正文列卡片随后给出的课程（通常是明天的课）；
 * * 没有 `Notice`、有课程行 → 首行课程的课名当标题，正文是它自己的时间与地点；
 * * 什么都没有 → 退回 `emptyText`，再退回脚注，保证标题不空。
 */
internal fun buildLiveIdleContent(display: CoupleWidgetDisplay): LiveIdleContent {
    val courses = display.items.filterIsInstance<CoupleWidgetDisplayItem.Course>()
    val notice = display.items
        .filterIsInstance<CoupleWidgetDisplayItem.Notice>()
        .firstOrNull()
        ?.text
        ?.takeIf { it.isNotBlank() }

    val title = notice
        ?: courses.firstOrNull()?.let { liveCourseTitle(it.course) }
        ?: display.emptyText?.takeIf { it.isNotBlank() }
        ?: display.footerText

    val bodyLines = if (notice != null) {
        // 状态行已经占了标题，正文给卡片列的课程（多为明天的课），一行一节。
        courses.map { liveCourseSummaryLine(it.course) }
    } else {
        // 正在候课：正文拆成「时间」「地点」两行，与前档的课程名一起构成卡片的
        // 课名 / 时间 / 地点三段。
        courses.firstOrNull()?.let { liveCourseDetailLines(it.course) } ?: emptyList()
    }

    return LiveIdleContent(
        title = title,
        bodyLines = bodyLines.filter { it.isNotBlank() },
        footer = display.footerText,
    )
}

/** 课程行的主文案：优先简称，其次是全名 —— 与情侣卡片每一行的取法一致。 */
internal fun liveCourseTitle(course: CoupleWidgetCourse): String {
    return course.shortName?.takeIf { it.isNotBlank() } ?: course.name
}

/** 课程行的时间段，与卡片逐行显示的一致。时间缺失时返回空串。 */
internal fun liveCourseTimeRange(course: CoupleWidgetCourse): String {
    if (course.startTime.isBlank() || course.endTime.isBlank()) {
        return ""
    }
    return "${course.startTime} - ${course.endTime}"
}

/** 候课档正文：时间一行、地点一行。 */
internal fun liveCourseDetailLines(course: CoupleWidgetCourse): List<String> {
    return listOf(liveCourseTimeRange(course), course.location)
        .filter { it.isNotBlank() }
}

/** 一天的课程压成一行（状态文案下方的明天课程列表用）。 */
internal fun liveCourseSummaryLine(course: CoupleWidgetCourse): String {
    return listOf(liveCourseTitle(course), liveCourseTimeRange(course), course.location)
        .filter { it.isNotBlank() }
        .joinToString(" · ")
}

/**
 * 下一次需要重绘通知的「当天分钟点」，没有则返回 null（表示今天再无边界，等服务
 * 睡到跨天）。
 *
 * 边界取三处：进入候课窗口的 `start - lead`、上课的 `start`、下课的 `end`。取其中
 * 严格大于当前时刻的最小值。空闲档位据此长睡眠，避免每 60 秒白醒一次。
 */
internal fun liveNextBoundaryMinutes(
    nowMinutes: Int,
    coursesToday: List<CoupleWidgetCourse>,
    leadMinutes: Int,
): Int? {
    return coursesToday
        .flatMap { course ->
            val start = CoupleTimetableDisplayBuilder.parseClockMinutes(course.startTime)
            val end = CoupleTimetableDisplayBuilder.parseClockMinutes(course.endTime)
            listOfNotNull(
                start?.minus(leadMinutes.coerceAtLeast(0)),
                start,
                end,
            )
        }
        .filter { it > nowMinutes }
        .minOrNull()
}

/**
 * 通知时间字段的基准时刻（`setWhen` 的入参）。
 *
 * 指到**当天零点**并配合 `setUsesChronometer(true)` + 正计时，SystemUI 会把这一格
 * 渲染成**带秒的时钟**（`15:26:31`），每秒自走，不依赖 App 进程 —— 与倒计时同样的
 * 「进程被冻住也还在走」，但读数是当前时间，不会和正文里的「最近下课 / 整节下课」
 * 重复成一个页面两个倒计时。
 *
 * 只覆盖课中两档（`duringClass` / `duringClassStatusBar`）：课前档是提升态
 * （流体云），那一档不开时间字段，也不该把 `when` 挪走。
 *
 * ⚠️ 每天 00:00–00:59 这一小时会退化成 `mm:ss`（显示 `26:31` 而不是 `00:26:31`）：
 * Chronometer 在小时位为 0 时不渲染小时，这是它自身的格式规则，换基准值绕不过去。
 * 课表场景（早八到晚十）碰不到，因此接受。
 */
internal fun liveSystemClockBaseMillis(
    stage: String?,
    showCountdown: Boolean,
    nowMillis: Long,
): Long? {
    if (!showCountdown) {
        return null
    }
    if (stage != "duringClass" && stage != "duringClassStatusBar") {
        return null
    }
    return startOfDayMillis(nowMillis)
}

/** 当天零点（本机时区）。用于给系统时钟式倒计时打基准。 */
internal fun startOfDayMillis(nowMillis: Long): Long {
    return Calendar.getInstance().apply {
        timeInMillis = nowMillis
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }.timeInMillis
}

/**
 * 课前那帧的下拉正文（折叠行）：**课名 · 地点**。
 *
 * 折叠行只有一行额度，原来那串「状态 · 时间区间 · 地点 · 教师」会被系统截断，而
 * 课名在折叠态里根本不出现 —— 它只在展开态的 bigText 与流体云卡片上，等于不点箭头
 * 就看不到这节课叫什么。改成课名打头、地点跟随，两个短字段一行装得下；时间与教师
 * 挪到摘要行（[summaryText] 那一侧），信息不减。
 *
 * 这一层只算下拉文本，不碰 `title` 与 `bigText` —— 流体云卡片读的正是后两者，
 * 因此文案改动不会影响上岛。
 *
 * @param fallbackParts 课名与地点都缺失时的兜底清单（正常课表不会走到）。
 */
internal fun buildPromotedShadeText(
    courseName: String,
    location: String,
    fallbackParts: List<String>,
): String {
    val primary = listOf(courseName, location)
        .filter { it.isNotBlank() }
        .joinToString(" · ")
    if (primary.isNotBlank()) {
        return primary
    }
    return fallbackParts.filter { it.isNotBlank() }.joinToString(" · ")
}

/**
 * 自绘折叠卡片的正文行分配（最多三行）。
 *
 * 空闲档在「今天已结束 / 今天没课」时会列明天的课，一节一行；卡片只有三个正文槽位，
 * 超出的部分压进第三行（那行自己会按宽度省略），比整条丢掉好。
 */
internal fun liveCardLines(bodyLines: List<String>): List<String> {
    val lines = bodyLines.filter { it.isNotBlank() }
    if (lines.size <= 3) {
        return lines
    }
    return lines.take(2) + lines.drop(2).joinToString("  ")
}

/**
 * 课程是否已经上完（用于判断「今天已结束」而不是「正在候课」）。
 *
 * 结束时间缺失时按「没上完」处理：宁可多显示一档候课，也不要提前把课当成上完。
 */
internal fun liveCourseHasEnded(course: CoupleWidgetCourse, nowMinutes: Int): Boolean {
    val end = CoupleTimetableDisplayBuilder.parseClockMinutes(course.endTime) ?: return false
    return nowMinutes >= end
}
