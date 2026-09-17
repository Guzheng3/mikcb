package vip.qinghan.withu

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
 * 课程是否已经上完（用于判断「今天已结束」而不是「正在候课」）。
 *
 * 结束时间缺失时按「没上完」处理：宁可多显示一档候课，也不要提前把课当成上完。
 */
internal fun liveCourseHasEnded(course: CoupleWidgetCourse, nowMinutes: Int): Boolean {
    val end = CoupleTimetableDisplayBuilder.parseClockMinutes(course.endTime) ?: return false
    return nowMinutes >= end
}
