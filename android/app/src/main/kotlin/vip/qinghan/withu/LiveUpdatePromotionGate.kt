package vip.qinghan.withu

/**
 * API 36 提升通知的准入判据（Live Updates / OPPO 流体云 / 小米超级岛标准通道）。
 *
 * 系统侧的闸门是 `Notification.hasPromotableCharacteristics()`（AOSP android-36
 * `Notification.java:3297`）。对**非 Ongoing CallStyle** 的通知它只要求两件事：
 *
 * ```java
 * return isColorizedRequested() && hasPromotableStyle();
 * ```
 *
 * - `isColorizedRequested()` 读的就是 `extras.getBoolean(EXTRA_COLORIZED)`
 *   （同文件 `:8091`），即 `Notification.Builder.setColorized(...)` 的入参；
 * - `hasPromotableStyle()` 放行 null / BigTextStyle / CallStyle / ProgressStyle
 *   （同文件 `:3280`），本应用的 ProgressStyle 与 BigTextStyle 都在其中。
 *
 * 所以**唯一会失败的闸门就是 EXTRA_COLORIZED**。历史上这里恒为
 * `setColorized(false)`，于是 `hasPromotableCharacteristics()` 永远是 false，
 * 系统永远不会给通知打 `FLAG_PROMOTED_ONGOING`：OPPO 流体云、原生 Android 16
 * 实时活动这些**标准提升表面永远看不到卡片**，而自检页只会报一句
 * 「通知不具备可提升特征」，看不出真正原因。小米侧因为有 `miui.focus.param`
 * 私有通道兜底，症状被掩盖，问题才一直没暴露。
 *
 * ⚠️ 与官方文档的冲突：官方《Create live update notifications》的准入清单里
 * 写的是 “Must NOT `setColorized` to `TRUE`”，与上面这段 AOSP 实现相反。
 * 此处以实机真正执行的代码为准，放行 `setColorized(true)`。风险已被限制在两处：
 *
 * 1. 本函数未伴随 `setColor(int)`，`color` 仍为 `COLOR_DEFAULT`；
 *    `Notification.isColorized()` 的注释明确 “the actual appearance of the
 *    notification may not be 'colorized'”，故**外观不变**；
 * 2. 若后续证实文档为准，回退点只有本函数一处。
 *
 * @param shouldPromote 本帧是否请求提升。`false` 时保持旧的不可着色语义，
 *   把改动面收敛到「原本就该提升却没提升」的那一帧上。
 * @return 传给 `Notification.Builder.setColorized(...)` 的值。
 */
internal fun liveShouldRequestColorizedForPromotion(shouldPromote: Boolean): Boolean =
    shouldPromote
