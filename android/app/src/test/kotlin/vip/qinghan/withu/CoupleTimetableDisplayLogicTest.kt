package vip.qinghan.withu

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 情侣卡片空态的两处判断：今天是否已结束、文案占多高。
 *
 * 这两条决定卡片上「今天课程已结束」这条文案落到哪里——是整列居中，还是
 * 像其他空态一样贴在列首。渲染层没法在没有设备的情况下断言，所以把判断本身
 * 纯函数化后钉在这里。
 */
class CoupleTimetableDisplayLogicTest {

    // --- isEmptyEndedNotice --------------------------------------------------

    @Test
    fun `today ended with nothing left for tomorrow is the centred notice`() {
        assertTrue(
            CoupleTimetableDisplayBuilder.isEmptyEndedNotice(
                hasRemainingCourse = false,
                todayCourseCount = 4,
                tomorrowCourseCount = 0,
            ),
        )
    }

    @Test
    fun `tomorrow has courses keeps the notice above the list`() {
        // 明日有课时文案要给课程让位：上方一条 Notice，下方明日课程。
        assertFalse(
            CoupleTimetableDisplayBuilder.isEmptyEndedNotice(
                hasRemainingCourse = false,
                todayCourseCount = 4,
                tomorrowCourseCount = 2,
            ),
        )
    }

    @Test
    fun `a day without any course is not the ended notice`() {
        // 今天本来没课 → 文案是「今天没有课程」，与「已结束」不是一回事。
        assertFalse(
            CoupleTimetableDisplayBuilder.isEmptyEndedNotice(
                hasRemainingCourse = false,
                todayCourseCount = 0,
                tomorrowCourseCount = 0,
            ),
        )
    }

    @Test
    fun `a course still to come is not the ended notice`() {
        assertFalse(
            CoupleTimetableDisplayBuilder.isEmptyEndedNotice(
                hasRemainingCourse = true,
                todayCourseCount = 4,
                tomorrowCourseCount = 0,
            ),
        )
    }

    // --- emptyRowHeightPx ---------------------------------------------------

    @Test
    fun `centred notice fills the column so the text lands in the middle`() {
        val height = CoupleTimetableSizingSupport.emptyRowHeightPx(
            availableListHeightPx = 240f,
            courseRowHeightPx = 52f,
            endedNotice = true,
        )

        assertEquals(240f, height, 0f)
    }

    @Test
    fun `other empty states keep one course row at the top of the column`() {
        val height = CoupleTimetableSizingSupport.emptyRowHeightPx(
            availableListHeightPx = 240f,
            courseRowHeightPx = 52f,
            endedNotice = false,
        )

        assertEquals(52f, height, 0f)
    }
}
