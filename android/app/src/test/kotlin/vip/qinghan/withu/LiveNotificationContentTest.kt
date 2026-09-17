package vip.qinghan.withu

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
