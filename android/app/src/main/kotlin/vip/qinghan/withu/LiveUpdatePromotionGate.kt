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
 * `setColorized(false)`，于是 `hasPromotableCharacteristics()` 永远是 false：
 * 自检页因此只会报一句「通知不具备可提升特征」，看不出真正原因。
 *
 * ⚠️ 但**该方法的返回值并不等于 ColorOS 的实际决定**（2026-09-18 实测更正）：
 * 本应用恒 `setColorized(false)`、该方法恒 false，通知却实实在在拿到了提升
 * —— 见下方两处客观判据。上面这段 AOSP 推导只解释「自检页为什么这么报」，
 * 不能拿来推断「提升到底成没成」。
 *
 * ⚠️ 自定义布局会被判不合格（2026-09-18 实机重测，方法可复现）：给通知挂
 * `setCustomContentView` 后，**系统不会给这条通知打 `FLAG_PROMOTED_ONGOING`，状态栏
 * 流体云胶囊也随之消失**；撤掉自定义布局、其余字段一字不改，胶囊立刻回来。所以 ColorOS
 * 的闸门确实比上面那段 AOSP 推导更严，**带自定义布局的通知不予提升**。
 *
 * 复现方法（当天没有课时也能做）：让**空闲常驻帧**临时按课前帧的写法申请提升
 * （`EXTRA_REQUEST_PROMOTED_ONGOING` + 非空 `setShortCriticalText` + `CATEGORY_PROGRESS`），
 * 它就是一条可随时造出来的提升帧；然后 A/B 两次安装对比，判据看两处——
 * `dumpsys notification --noredact` 里**当前** `NotificationRecord` 的 flags 有没有
 * `PROMOTED_ONGOING`（注意别读成 `mArchive` 里的历史记录），以及状态栏顶部有没有胶囊。
 *
 * ⚠️ 不要用 App 自检页判定这件事（2026-09-18 更正）：自检页那条「未满足上岛条件」
 * 的判据是 `hasPromotableCharacteristics() == false`，而该方法的实现是
 * `isColorizedRequested() && hasPromotableStyle()` —— 本应用恒为 `setColorized(false)`，
 * 于是它**永远**返回 false，这一行报错在任何时候都会亮，与挂没挂自定义布局无关。
 * 2026-09-17 那次就是拿它当证据，结论虽对、证据无效；本次改用了上面两处客观判据。
 * 同理，「系统永远不会给通知打 FLAG_PROMOTED_ONGOING」的旧说法也不成立 —— 本次实测
 * 在不挂自定义布局时该标志是打上的。
 *
 * 因此流体云卡片的版式**无法自绘**：字号、对齐、图标位置、行序都只能由系统模板决定，
 * 能控的只有往各字段里放什么内容（以及哪个内容进"标题"这个大字槽）。
 * 想要完整自定义排版只能走 OPPO 官方流体云接入（面向合作应用），或放弃上岛退回普通通知行。
 *
 * ⚠️ 与官方文档的冲突（2026-09-11 已定论）：官方《Create live update notifications》
 * 的准入清单写的是 “Must NOT `setColorized` to `TRUE`”，与上面这段 AOSP 实现相反。
 * 实机回归证明以官方文档为准——放行 `true` 会让通知彻底失去提升资格，
 * 详见下方 @return 的记录。
 *
 * @param shouldPromote 入参保留以固定调用点签名；回退后不再影响返回值。
 * @return 传给 `Notification.Builder.setColorized(...)` 的值，恒为 `false`。
 *
 * ⚠️ 实机回归（2026-09-11，OPPO PLA110 / ColorOS 16.1 / Android 16）：
 * 置 `true` 后流体云反而**不出卡片**，自检页报 `hasPromotableCharacteristics() == false`；
 * 而同机 v5.2.0.1（此处恒为 `false`）可正常上岛。可见 ColorOS 上官方文档
 * “Must NOT `setColorized` to `TRUE`” 才是实际生效的判据，AOSP 源码那套
 * `isColorizedRequested()` 推导在本机不成立。故回退为 `false`，不再按帧置 true。
 */
internal fun liveShouldRequestColorizedForPromotion(
    @Suppress("UNUSED_PARAMETER") shouldPromote: Boolean,
): Boolean = false

/**
 * 是否请求把当前阶段提升到实时活动表面（OPPO 流体云 / 小米超级岛 /
 * 原生 Android 16 实时活动）。
 *
 * 产品决定：**只有「上课前」上岛**。课中与临近下课一律不提升，改走普通通知——
 * 三个平台表面统一按此执行。
 *
 * 课中是否仍有普通通知由 `showNotificationDuringClass` 决定
 * （见 [LiveUpdateService.resolveStage] 与 `canDisplayDuringStage()`）；
 * 本判据只管「要不要上岛」，不决定阶段本身是否存在。
 *
 * 两类入参自然落在 false 一侧，无需特判：
 * - `duringClassStatusBar` 按定义只占状态栏，历史上就从不提升；
 * - `null` 是下课到 Service 自停之间最多 30 秒的窗口
 *   （`LiveUpdateService` ticker 里的 `endAtMillis + 30_000L`），
 *   旧实现的 `else -> true` 会在该窗口为空阶段请求提升。
 *
 * 该判据同时决定小米 `miui.focus.param` 是否拼装（见 `buildNotification`），
 * 因此对小米同样生效，不只是 ColorOS。
 */
internal fun liveShouldPromoteStage(stage: String?): Boolean = stage == "beforeClass"
