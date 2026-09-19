package vip.qinghan.withu

import java.util.Calendar
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveNotificationContentTest {
    private fun course(
        name: String = "生物化学",
        shortName: String? = null,
        location: String = "高博学楼326",
        startTime: String = "22:10",
        endTime: String = "22:13",
    ) = CoupleWidgetCourse(
        id = name,
        name = name,
        shortName = shortName,
        location = location,
        startSection = 1,
        endSection = 1,
        startTime = startTime,
        endTime = endTime,
    )

    private fun display(
        items: List<CoupleWidgetDisplayItem>,
        footer: String = "今日课程 还剩1/2节",
        empty: String? = null,
    ) = CoupleWidgetDisplay(items = items, footerText = footer, emptyText = empty)

    // --- buildLiveIdleContent ------------------------------------------------

    @Test
    fun idleContentUsesNextCourseAsTitleWithTimeAndLocationAsBody() {
        // 候课档：标题是课名（优先简称），正文是「时间」「地点」两行。
        val content = buildLiveIdleContent(
            display(
                items = listOf(
                    CoupleWidgetDisplayItem.Course(course(shortName = "生化"), isOngoing = false),
                ),
            ),
        )

        assertEquals("生化", content.title)
        assertEquals(listOf("22:10 - 22:13", "高博学楼326"), content.bodyLines)
        assertEquals("今日课程 还剩1/2节", content.footer)
    }

    @Test
    fun idleContentPrefersNoticeTextAsTitleAndListsCoursesBelow() {
        // 今天已结束：卡片会在课程行上方插一条 Notice，通知用这条状态文案当标题，
        // 正文列卡片随后给出的课（这里是明天的课）。
        val content = buildLiveIdleContent(
            display(
                items = listOf(
                    CoupleWidgetDisplayItem.Notice("🌙 今日课程已结束"),
                    CoupleWidgetDisplayItem.NoticeDivider,
                    CoupleWidgetDisplayItem.Course(
                        course(name = "大学物理", shortName = "大物", startTime = "08:00", endTime = "09:40"),
                        isOngoing = false,
                    ),
                ),
                footer = "明日共 1 节",
            ),
        )

        assertEquals("🌙 今日课程已结束", content.title)
        assertEquals(listOf("大物 · 08:00 - 09:40 · 高博学楼326"), content.bodyLines)
        assertEquals("明日共 1 节", content.footer)
    }

    @Test
    fun idleContentFallsBackToEmptyTextWhenThereAreNoItems() {
        // 今天没有课（或周末没有课）：卡片没有课程行也没有 Notice，只有居中空态文案。
        val content = buildLiveIdleContent(
            display(
                items = emptyList(),
                footer = "明日无课",
                empty = "🍵 今天没有课程",
            ),
        )

        assertEquals("🍵 今天没有课程", content.title)
        assertTrue(content.bodyLines.isEmpty())
        assertEquals("明日无课", content.footer)
    }

    @Test
    fun idleContentFallsBackToUnavailableTextWhenCoupleCardIsOff() {
        // 情侣卡片不可用时卡片返回的 emptyText 就是不可用文案，通知照搬，不做降级。
        val content = buildLiveIdleContent(
            display(items = emptyList(), footer = "", empty = "未开情侣模式，暂不可使用"),
        )

        assertEquals("未开情侣模式，暂不可使用", content.title)
        assertTrue(content.bodyLines.isEmpty())
        assertEquals("", content.footer)
    }

    @Test
    fun idleContentFallsBackToFooterSoTitleIsNeverBlank() {
        // 极端情况：卡片什么都没给。标题不能是空串，否则通知会出现一行空白。
        val content = buildLiveIdleContent(display(items = emptyList(), footer = "明日无课"))

        assertEquals("明日无课", content.title)
        assertTrue(content.bodyLines.isEmpty())
    }

    @Test
    fun idleContentSkipsBlankBodyLines() {
        // 地点为空时正文只剩时间一行，不能留空行（空行会被系统当成正文占位）。
        val content = buildLiveIdleContent(
            display(items = listOf(CoupleWidgetDisplayItem.Course(course(location = ""), false))),
        )

        assertEquals("生物化学", content.title)
        assertEquals(listOf("22:10 - 22:13"), content.bodyLines)
    }

    @Test
    fun idleContentSignatureChangesWhenAnyLineChanges() {
        val first = buildLiveIdleContent(
            display(items = listOf(CoupleWidgetDisplayItem.Course(course(), false))),
        )
        val second = buildLiveIdleContent(
            display(
                items = listOf(CoupleWidgetDisplayItem.Course(course(location = "教3-401"), false)),
            ),
        )

        assertTrue(first.signature() != second.signature())
        assertEquals(first.signature(), first.copy().signature())
    }

    // --- 课程行格式化 ---------------------------------------------------------

    @Test
    fun courseTitlePrefersShortNameAndIgnoresBlankOne() {
        assertEquals("生化", liveCourseTitle(course(shortName = "生化")))
        assertEquals("生物化学", liveCourseTitle(course(shortName = "   ")))
        assertEquals("生物化学", liveCourseTitle(course(shortName = null)))
    }

    @Test
    fun courseTimeRangeIsBlankWhenEitherBoundaryIsMissing() {
        assertEquals("22:10 - 22:13", liveCourseTimeRange(course()))
        assertEquals("", liveCourseTimeRange(course(startTime = "")))
        assertEquals("", liveCourseTimeRange(course(endTime = "")))
    }

    @Test
    fun courseSummaryLineJoinsTitleTimeAndLocation() {
        assertEquals(
            "生化 · 22:10 - 22:13 · 高博学楼326",
            liveCourseSummaryLine(course(shortName = "生化")),
        )
        assertEquals("生化 · 22:10 - 22:13", liveCourseSummaryLine(course(shortName = "生化", location = "")))
    }

    // --- liveNextBoundaryMinutes --------------------------------------------

    @Test
    fun nextBoundaryIsBeforeClassWindowStartWhenItIsStillAhead() {
        // 10:00 时，14:00 的课、窗口 20 分钟 → 下一个边界是 13:40（进入候课窗口）。
        val boundary = liveNextBoundaryMinutes(
            nowMinutes = 10 * 60,
            coursesToday = listOf(course(startTime = "14:00", endTime = "15:40")),
            leadMinutes = 20,
        )

        assertEquals(13 * 60 + 40, boundary)
    }

    @Test
    fun nextBoundaryIsClassStartOnceWindowAlreadyOpened() {
        // 13:50 已经进窗口，13:40 那个边界过期，下一个边界应是上课时刻 14:00。
        val boundary = liveNextBoundaryMinutes(
            nowMinutes = 13 * 60 + 50,
            coursesToday = listOf(course(startTime = "14:00", endTime = "15:40")),
            leadMinutes = 20,
        )

        assertEquals(14 * 60, boundary)
    }

    @Test
    fun nextBoundaryIsClassEndWhileClassIsOngoing() {
        // 课中：开始时刻已过，下一个边界是下课 15:40，醒来后切到下一节的候课档。
        val boundary = liveNextBoundaryMinutes(
            nowMinutes = 14 * 60 + 30,
            coursesToday = listOf(course(startTime = "14:00", endTime = "15:40")),
            leadMinutes = 20,
        )

        assertEquals(15 * 60 + 40, boundary)
    }

    @Test
    fun nextBoundaryPicksNearestAcrossCourses() {
        val boundary = liveNextBoundaryMinutes(
            nowMinutes = 8 * 60,
            coursesToday = listOf(
                course(name = "第一节", startTime = "10:00", endTime = "11:40"),
                course(name = "第二节", startTime = "08:30", endTime = "10:00"),
            ),
            leadMinutes = 20,
        )

        assertEquals(8 * 60 + 10, boundary)
    }

    @Test
    fun nextBoundaryIsNullWhenTodayIsDone() {
        // 今天的课全部结束 → 没有边界，服务应睡到跨天。
        val boundary = liveNextBoundaryMinutes(
            nowMinutes = 20 * 60,
            coursesToday = listOf(course(startTime = "14:00", endTime = "15:40")),
            leadMinutes = 20,
        )

        assertNull(boundary)
    }

    @Test
    fun nextBoundaryIgnoresCoursesWithUnparseableTime() {
        val boundary = liveNextBoundaryMinutes(
            nowMinutes = 10 * 60,
            coursesToday = listOf(
                course(name = "坏数据", startTime = "", endTime = ""),
                course(name = "正常", startTime = "14:00", endTime = "15:40"),
            ),
            leadMinutes = 20,
        )

        assertEquals(13 * 60 + 40, boundary)
    }

    @Test
    fun nextBoundaryTreatsNegativeLeadAsZero() {
        // 窗口为 0（不提前提醒）时边界就是上课时刻本身，不能因为减去负数而跑到过去。
        val boundary = liveNextBoundaryMinutes(
            nowMinutes = 13 * 60 + 50,
            coursesToday = listOf(course(startTime = "14:00", endTime = "15:40")),
            leadMinutes = 0,
        )

        assertEquals(14 * 60, boundary)
    }

    // --- liveCourseHasEnded -------------------------------------------------

    @Test
    fun courseHasEndedAtItsEndMinute() {
        assertTrue(liveCourseHasEnded(course(endTime = "15:40"), nowMinutes = 15 * 60 + 40))
        assertFalse(liveCourseHasEnded(course(endTime = "15:40"), nowMinutes = 15 * 60 + 39))
    }

    @Test
    fun courseWithoutEndTimeIsNeverTreatedAsEnded() {
        // 结束时间缺失时宁可多显示一档候课，也不要提前把课当成已上完。
        assertFalse(liveCourseHasEnded(course(endTime = ""), nowMinutes = 23 * 60 + 59))
    }

    // --- liveSystemClockBaseMillis -------------------------------------------

    private fun localMillis(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        second: Int,
    ): Long = Calendar.getInstance().apply {
        clear()
        set(year, month - 1, day, hour, minute, second)
    }.timeInMillis

    @Test
    fun duringClassUsesStartOfDayAsClockBase() {
        // 基准是当天零点 → 正计时读数就是墙上时钟（15:26:31），且带秒。
        val now = localMillis(2026, 9, 18, 15, 26, 31)
        val base = liveSystemClockBaseMillis(
            stage = "duringClass",
            showCountdown = true,
            nowMillis = now,
        )

        assertEquals(localMillis(2026, 9, 18, 0, 0, 0), base)
        assertEquals(15 * 3600_000L + 26 * 60_000L + 31_000L, now - requireNotNull(base))
    }

    @Test
    fun statusBarStageAlsoUsesClockBase() {
        val now = localMillis(2026, 9, 18, 8, 5, 9)

        assertEquals(
            localMillis(2026, 9, 18, 0, 0, 0),
            liveSystemClockBaseMillis(
                stage = "duringClassStatusBar",
                showCountdown = true,
                nowMillis = now,
            ),
        )
    }

    @Test
    fun clockBaseIsTruncatedToWholeMinute() {
        // 毫秒/秒位必须清零，否则系统时钟会从一个非整秒的偏移开始走。
        val base = requireNotNull(
            liveSystemClockBaseMillis(
                stage = "duringClass",
                showCountdown = true,
                nowMillis = localMillis(2026, 9, 18, 23, 59, 59) + 999L,
            ),
        )

        assertEquals(0L, base % 60_000L)
        // 跨天边界：23:59:59.999 的基准仍是当天零点。
        assertEquals(localMillis(2026, 9, 18, 0, 0, 0), base)
    }

    @Test
    fun beforeClassNeverRequestsSystemClock() {
        // 提升态（流体云）保持原样：卡片内容只能由 App 填，这一档不碰 when。
        assertNull(
            liveSystemClockBaseMillis(
                stage = "beforeClass",
                showCountdown = true,
                nowMillis = localMillis(2026, 9, 18, 9, 55, 0),
            ),
        )
    }

    @Test
    fun idleAndUnknownStagesDoNotRequestSystemClock() {
        val now = localMillis(2026, 9, 18, 12, 0, 0)

        assertNull(liveSystemClockBaseMillis(null, showCountdown = true, nowMillis = now))
        assertNull(liveSystemClockBaseMillis("idle", showCountdown = true, nowMillis = now))
    }

    @Test
    fun countdownSwitchOffSuppressesSystemClock() {
        // 「显示倒计时」关掉时，这一格整体不出现 —— 时钟也不给。
        assertNull(
            liveSystemClockBaseMillis(
                stage = "duringClass",
                showCountdown = false,
                nowMillis = localMillis(2026, 9, 18, 12, 0, 0),
            ),
        )
    }

    // --- buildPromotedShadeText ----------------------------------------------

    @Test
    fun promotedShadeTextLeadsWithCourseNameThenLocation() {
        // 课前折叠行：课名打头 —— 否则不点箭头根本看不到这节课叫什么。
        assertEquals(
            "生物化学 · 高博学楼326",
            buildPromotedShadeText(
                courseName = "生物化学",
                location = "高博学楼326",
                fallbackParts = listOf("19:55 - 19:58", "赵玲,王三矫"),
            ),
        )
    }

    @Test
    fun promotedShadeTextSkipsBlankFields() {
        assertEquals(
            "生物化学",
            buildPromotedShadeText("生物化学", "", listOf("19:55 - 19:58")),
        )
        assertEquals(
            "高博学楼326",
            buildPromotedShadeText("", "高博学楼326", listOf("19:55 - 19:58")),
        )
    }

    @Test
    fun promotedShadeTextFallsBackWhenCourseHasNoNameOrDefaultLocation() {
        // 课名与地点都缺时退回完整清单，宁可长也不要把正文留空。
        assertEquals(
            "即将上课 · 19:55 - 19:58 · 赵玲,王三矫",
            buildPromotedShadeText(
                courseName = "",
                location = "",
                fallbackParts = listOf("即将上课", "19:55 - 19:58", "赵玲,王三矫"),
            ),
        )
    }

    @Test
    fun promotedShadeTextCanBeEmptyWhenNothingIsKnown() {
        assertEquals(
            "",
            buildPromotedShadeText("", "", listOf("", "  ")),
        )
    }

    // --- liveCardLines --------------------------------------------------------

    @Test
    fun liveCardLinesKeepsUpToThreeLines() {
        assertEquals(emptyList<String>(), liveCardLines(emptyList()))
        assertEquals(listOf("08:00 - 09:40"), liveCardLines(listOf("08:00 - 09:40")))
        assertEquals(
            listOf("第一节", "第二节", "第三节"),
            liveCardLines(listOf("第一节", "第二节", "第三节")),
        )
    }

    @Test
    fun liveCardLinesPacksOverflowIntoThirdLine() {
        // 卡片只有三个正文槽位：多出来的课程行压进第三行，而不是整条丢掉。
        assertEquals(
            listOf("第一节", "第二节", "第三节  第四节"),
            liveCardLines(listOf("第一节", "第二节", "第三节", "第四节")),
        )
    }

    @Test
    fun liveCardLinesDropsBlankEntries() {
        assertEquals(
            listOf("第一节", "第二节"),
            liveCardLines(listOf("第一节", "", "  ", "第二节")),
        )
    }

    // --- parseClockMinutes（复用卡片解析，锁住行为） ---------------------------

    @Test
    fun clockMinutesParsingMatchesCoupleCardBehaviour() {
        assertEquals(22 * 60 + 10, CoupleTimetableDisplayBuilder.parseClockMinutes("22:10"))
        assertEquals(0, CoupleTimetableDisplayBuilder.parseClockMinutes("00:00"))
        assertNull(CoupleTimetableDisplayBuilder.parseClockMinutes("24:00"))
        assertNull(CoupleTimetableDisplayBuilder.parseClockMinutes("22:60"))
        assertNull(CoupleTimetableDisplayBuilder.parseClockMinutes("2200"))
    }
}
