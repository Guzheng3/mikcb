# 情侣课表二开方案（2026-09-01）

> 目标是在不恢复旧情侣课表代码的前提下，重建一套新的、更轻的情侣课表能力。qingyu 继续作为本地课表主应用，withU 只负责登录鉴权和课表快照同步。

## 1. 产品定位

- 功能名：情侣课表。
- 旧实现：不恢复、不引用、不兼容旧数据结构。
- 数据主权：双方仍各自维护自己的本地课表，对方课表只读展示。
- 同步范围：默认同步课程、作息设置和当前周；任务、考试、私密日程默认不同步。
- 服务器定位：withU 只保存每人的课表快照和同步状态，不做课表合并计算。

## 2. 技术边界

| 侧 | 复用 | 新增 |
|---|---|---|
| withU | `desktop.php` 登录、会话、CSRF、伴侣关系 | 课表快照存储与 API |
| qingyu | `TimetableProfile`、`TimetableProvider`、同步快照框架、桌面卡片刷新 | withU 客户端、同步服务、情侣课表 UI |
| 本地存储 | `flutter_secure_storage` 保存 Cookie/CSRF/服务器地址 | 情侣课表展示设置与缓存 |

## 3. withU 新增内容

### 3.1 数据表

| 表 | 用途 |
|---|---|
| `couple_timetable_snapshots` | 保存用户当前激活课表的快照 |
| `couple_timetable_sync_state` | 保存每人共享开关、版本号、最近同步时间 |

建议字段：`user_id`、`profile_id`、`payload_json`、`payload_sha256`、`schema_version`、`revision`、`created_at`、`updated_at`。以 `user_id + profile_id` 建唯一键，避免同一人多份课表互相覆盖。

### 3.2 API

| 方法 | 接口 | 说明 |
|---|---|---|
| GET | `/api/couple_timetable.php?action=status` | 返回双方共享状态和最新版本号 |
| GET | `/api/couple_timetable.php?action=pull` | 拉取对方课表快照 |
| POST | `/api/couple_timetable.php?action=push` | 上传当前激活课表快照 |
| POST | `/api/couple_timetable.php?action=settings` | 修改共享范围和可见性 |
| POST | `/api/couple_timetable.php?action=disconnect` | 停止共享并清理快照 |

要求：

1. 仅 `user1` / `user2` 可用。
2. 写操作必须走 withU 现有 CSRF 校验。
3. 服务端校验 `$auth->getPartner()`，不能允许用户拉取非伴侣课表。
4. 快照大小限制 2 MB，失败时返回明确错误码。
5. 保留最近 N 个版本或至少上一次快照，便于排查覆盖问题。

## 4. qingyu 改造点

### 4.1 服务层

| 模块 | 职责 |
|---|---|
| `WithuAuthService` | 登录、bootstrap、登出、Cookie/CSRF 持久化 |
| `WithuApiClient` | 统一处理超时、401、CSRF 过期和错误映射 |
| `CoupleTimetableSyncService` | 把激活课表转成共享快照、上传、拉取对方快照 |
| `CoupleTimetableProvider` | 管理登录态、对方课表缓存、同步状态和可见性 |

### 4.2 数据转换

1. 从当前 `TimetableProfile` 取 `courses/settings/currentWeek`。
2. 生成带 `schemaVersion` 和 `revision` 的快照 JSON。
3. 对方快照在本地转换成只读的 `TimetableProfile` 视图。
4. 对方课表不写入用户自己的课表列表，不参与本机编辑。

## 5. 情侣课表功能

### 5.1 核心功能

| 功能 | 说明 |
|---|---|
| 课表快速切换 | 课表界面提供「我的 / TA」切换入口，一键切换查看对方课表 |
| 当前周同频 | 切换后仍停留在用户当前选择的日期和周次，方便对照同一天 |

### 5.2 首期不做

首期不做合并视图、共同空闲计算、约会建议、冲突提醒、下课问候和课程变化提醒。先把“我能稳定看到 TA 的课”做好。

## 6. 桌面卡片方案

### 6.1 数据接入

1. 复用现有 `HomeWidgetStorage` 快照机制。
2. 在快照里新增 `couple` 节点：登录用户的 withU 用户名、伴侣的 withU 用户名、双方今日课表和主题色。
3. 卡片端不做网络请求，只读原生快照，避免锁屏刷新和网络不稳定。
4. 复用现有 AlarmManager + WorkManager 双保险刷新。

### 6.2 卡片交互与样式

| 样式 | 尺寸 | 内容 |
|---|---|---|
| 双列今日 | 4x1 或 4x2 | 同一天的两列课表；列头直接显示 withU 用户名：左侧登录用户，右侧伴侣 |
| 双人紧凑 | 2x1 | 同一天的两个人下一节课概览；概览旁显示对应 withU 用户名 |

列头不显示「我的 / TA 的」文案，直接用 withU 用户名标识两侧。

点击行为：

1. 点击登录用户名列或其课表区域，打开课表页并定位到我的课表。
2. 点击伴侣用户名列或其课表区域，打开课表页并定位到 TA 的课表。
3. 两边都使用同一天的日期和周次。

## 7. 分期落地

| 阶段 | 内容 | 估算 |
|---|---|---|
| P0 | withU 表结构和 API，Qingyu 登录接入 | 1-2 天 |
| P1 | 当前课表上传、对方课表拉取、只读展示 | 1-2 天 |
| P2 | 课表页「我的 / TA」快速切换 | 0.5 天 |
| P3 | 桌面卡片双列展示和分区点击 | 1 天 |

## 8. 验证清单

1. withU：未登录、非情侣角色、无伴侣、CSRF 缺失、超限快照均返回明确错误。
2. qingyu：登录、上传、拉取、登出、服务器地址错误均有可读提示。
3. 课表：对方课表不会出现在“我的课表管理”列表；切换入口能在两个课表间一键往返。
4. 桌面卡片：点击左右两个区域分别打开我的课表和 TA 的课表；无网络时仍能显示最后一次同步结果。
5. `flutter analyze` 和 `flutter test` 通过。

## 9. 主要风险

1. 两人学校作息不同，两个课表各自按自己的时间渲染，不做节次合并。
2. 学期开始日期不同，需要各自按 `semesterStartDate` 换算周次。
3. 课表包含隐私信息，默认只共享课程，不共享任务和考试。
4. 自建服务可能使用 HTTP，需要在设置里明确提示风险并建议 HTTPS。
