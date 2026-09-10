package vip.qinghan.withu

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveUpdateServiceLogicTest {
    @Test
    fun beforeClassQuickActionRestoresAfterClassEndWhenDue() {
        assertTrue(
            beforeClassQuickActionShouldRestoreAfterClassEnd(
                nowMillis = 1_700_000_000_000L,
                restoreAtMillis = 1_699_999_000_000L,
            )
        )
    }

    @Test
    fun beforeClassQuickActionDoesNotRestoreBeforeClassEnd() {
        assertFalse(
            beforeClassQuickActionShouldRestoreAfterClassEnd(
                nowMillis = 1_699_999_000_000L,
                restoreAtMillis = 1_700_000_000_000L,
            )
        )
    }

    @Test
    fun promotedApi36PlusDoesNotMirrorStatusIntoMiuiFocusHint() {
        assertFalse(
            liveShouldMirrorStatusIntoMiuiFocusHint(
                sdkInt = 36,
                shouldPromote = true,
            )
        )
    }

    @Test
    fun nonPromotedOrOlderBuildsKeepMiuiFocusHint() {
        assertTrue(
            liveShouldMirrorStatusIntoMiuiFocusHint(
                sdkInt = 35,
                shouldPromote = true,
            )
        )
        assertTrue(
            liveShouldMirrorStatusIntoMiuiFocusHint(
                sdkInt = 36,
                shouldPromote = false,
            )
        )
    }

    @Test
    fun quickActionButtonsNoneShowsNothing() {
        assertEquals(
            BeforeClassQuickActionButtons(),
            beforeClassQuickActionButtons(
                action = "none",
                silentCurrentlyActive = true,
                dndCurrentlyActive = true,
            ),
        )
    }

    @Test
    fun quickActionButtonsFlipToCancelWhenModeAlreadyActive() {
        // 静音未开 → 打开静音；已开 → 取消静音
        assertTrue(
            beforeClassQuickActionButtons(
                action = "silent",
                silentCurrentlyActive = false,
                dndCurrentlyActive = false,
            ).silentEnable
        )
        val active = beforeClassQuickActionButtons(
            action = "silent",
            silentCurrentlyActive = true,
            dndCurrentlyActive = false,
        )
        assertTrue(active.silentCancel)
        assertFalse(active.silentEnable)
        assertFalse(active.dndEnable)
        assertFalse(active.dndCancel)
    }

    @Test
    fun quickActionButtonsBothShowsIndependentToggles() {
        // both：静音已被（自动）打开，勿扰未开 → 一个取消按钮 + 一个打开按钮
        val mixed = beforeClassQuickActionButtons(
            action = "both",
            silentCurrentlyActive = true,
            dndCurrentlyActive = false,
        )
        assertTrue(mixed.silentCancel)
        assertFalse(mixed.silentEnable)
        assertTrue(mixed.dndEnable)
        assertFalse(mixed.dndCancel)

        val allActive = beforeClassQuickActionButtons(
            action = "both",
            silentCurrentlyActive = true,
            dndCurrentlyActive = true,
        )
        assertTrue(allActive.silentCancel)
        assertTrue(allActive.dndCancel)
        assertFalse(allActive.silentEnable)
        assertFalse(allActive.dndEnable)
    }

    @Test
    fun quickActionButtonsSignatureTracksStateFlip() {
        val inactive = beforeClassQuickActionButtons(
            action = "do_not_disturb",
            silentCurrentlyActive = false,
            dndCurrentlyActive = false,
        ).toString()
        val active = beforeClassQuickActionButtons(
            action = "do_not_disturb",
            silentCurrentlyActive = false,
            dndCurrentlyActive = true,
        ).toString()
        assertTrue(inactive != active)
    }

    @Test
    fun promotedFrameRequestsColorizedSoNotificationIsPromotable() {
        // AOSP 准入：hasPromotableCharacteristics() =
        // isColorizedRequested() && hasPromotableStyle()。置 false 会让
        // 非 CallStyle 的提升帧永远拿不到 FLAG_PROMOTED_ONGOING，
        // OPPO 流体云等标准提升面收不到卡片。
        assertTrue(liveShouldRequestColorizedForPromotion(shouldPromote = true))
    }

    @Test
    fun nonPromotedFrameKeepsUncolorizedSemantics() {
        // 仅状态栏 / 上课中不请求提升的帧：维持改动前的不可着色语义，
        // 把改动面收敛在「本该提升却没提升」的那一帧上。
        assertFalse(liveShouldRequestColorizedForPromotion(shouldPromote = false))
    }

    @Test
    fun surfaceBrandRecognizesXiaomiFamily() {
        assertEquals(LiveSurfaceBrand.XIAOMI, liveSurfaceBrand("Xiaomi", "Xiaomi"))
        assertEquals(LiveSurfaceBrand.XIAOMI, liveSurfaceBrand("Xiaomi", "Redmi"))
        assertEquals(LiveSurfaceBrand.XIAOMI, liveSurfaceBrand("Xiaomi", "POCO"))
        // 合成样本：旧实现只在 brand 一侧查 redmi/poco，manufacturer 侧命中时会漏判。
        assertEquals(LiveSurfaceBrand.XIAOMI, liveSurfaceBrand("Redmi", "unknown"))
    }

    @Test
    fun surfaceBrandRecognizesColorOsFamily() {
        assertEquals(LiveSurfaceBrand.COLOROS, liveSurfaceBrand("OPPO", "OPPO"))
        assertEquals(LiveSurfaceBrand.COLOROS, liveSurfaceBrand("realme", "realme"))
        assertEquals(LiveSurfaceBrand.COLOROS, liveSurfaceBrand("OnePlus", "OnePlus"))
    }

    @Test
    fun surfaceBrandIsCaseInsensitiveAndFallsBackToGeneric() {
        assertEquals(LiveSurfaceBrand.COLOROS, liveSurfaceBrand("oppo", "OPPO"))
        assertEquals(LiveSurfaceBrand.GENERIC, liveSurfaceBrand("Google", "google"))
    }
}
