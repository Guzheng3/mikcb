package vip.qinghan.withu

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * 快照状态是 Dart 与原生之间的约定字符串：Dart 侧
 * `CoupleTimetableWidgetStatusX.value` 生成，这边 [CoupleWidgetStatus.from] 解析。
 *
 * 两端各有一份映射，拼错任何一处都不会报错——`from` 会静默退化成 [CoupleWidgetStatus.OK]，
 * 卡片于是画成一张没有课程也没有文案的空卡，用户只看到空白。所以这里把字符串钉死。
 */
class CoupleWidgetStatusTest {

    @Test
    fun `from maps every wire value the Dart side emits`() {
        assertEquals(CoupleWidgetStatus.OK, CoupleWidgetStatus.from("ok"))
        assertEquals(CoupleWidgetStatus.COUPLE_MODE_OFF, CoupleWidgetStatus.from("couple_mode_off"))
        assertEquals(CoupleWidgetStatus.NOT_LOGGED_IN, CoupleWidgetStatus.from("not_logged_in"))
        assertEquals(CoupleWidgetStatus.NOT_BOUND, CoupleWidgetStatus.from("not_bound"))
    }

    @Test
    fun `from falls back to OK for missing or unknown value`() {
        // 旧版本写下的快照没有 status 字段；将来新增的状态值也不该让卡片停在
        // 不可用态，所以未知值一律按可用处理。
        assertEquals(CoupleWidgetStatus.OK, CoupleWidgetStatus.from(null))
        assertEquals(CoupleWidgetStatus.OK, CoupleWidgetStatus.from(""))
        assertEquals(CoupleWidgetStatus.OK, CoupleWidgetStatus.from("some_future_status"))
    }
}
