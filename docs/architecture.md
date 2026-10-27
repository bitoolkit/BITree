# 代码结构与数据流

各功能放在同名目录：`schedule`、`agenda`、`academics`、`classrooms`、`school`、`wencui` 和 `updates`。功能的页面与表单位于各自的 `ui/`；跨功能控件、主题和动效位于 `lib/ui/`。通用异步、文件和平台访问位于 `lib/core/`。

`main.dart` 创建依赖。`AppController` 负责组合模块、启动和外观设置。各功能控制器拥有自己的状态，页面通过 Flutter 的 `ListenableBuilder` 监听所需模块；功能更新不会经过根控制器转发给整个应用。

## 保存和同步

课表由 `TimetableController` 管理，日程由 `AgendaController` 管理，学业数据由 `AcademicController` 管理。页面提交操作，控制器先保存，再发布新状态；存储失败时保留原状态。学业读取使用 `LatestRequest`，切换账号后，旧读取不会覆盖新账号的数据。

```mermaid
flowchart LR
  UI[页面操作] --> Controller[功能控制器]
  Controller --> Store[功能 Store]
  Store --> File[JsonFile 原子写入]
  Store --> Widget[保存后刷新 Android 小组件]
  Controller --> View[监听该模块的页面]
```

`SchoolController` 负责登录状态、同步操作、请求繁忙状态和错误反馈。成功获取课表、DDL、考试或成绩后，交给相应功能控制器合并并保存。`SchoolAccess` 负责会话生命周期、取消和直连失败后的 WebVPN 重试；`SchoolSession` 负责 HTTP、Cookie 与响应读取。乐学和新延河课堂沿用可校外直连的访问方式。

数据仍使用 `schedule.json`、`agenda.json`、`academics.json` 和原有 JSON 字段；凭据与 Cookie 仍使用原有系统安全存储。DDL 同步保留本地编辑、删除标记和已完成状态，并接收平台完成状态。恢复已删除 DDL 是独立操作。

## 日程视图

日程页提供列表与横向多泳道时间轴，共用类型筛选，读取同一个 `AgendaController`，不混入课表课程。列表保留未完成／已完成分页；时间轴将两种状态同表排布，不按完成状态分配泳道，已完成或已结束条目仍沿用弱化样式。视图模式通过 `SharedPreferencesAsync` 的 `agendaViewMode` 保存，缺省为列表；缩放和浏览位置不写入日程文件。切换视图保留本次浏览位置，离开日程页后再进入会将时间轴定位到今日 12:00 居中。

`agenda/timeline_layout.dart` 负责纯时间区间与泳道分配：普通日程采用真实起止时间；DDL 右端为 `dueAt`，可见条固定屏幕宽度、左侧渐隐，额外预留截止前三天的虚拟区间。布局同时检查虚拟区间与可见条，三天不是 DDL 的真实持续时长，也不会保存到模型。全天 DDL 的右端沿用模型定义，为对应日期次日零点。

时间轴以视口中心时间和连续缩放比例计算坐标，不创建覆盖历史与未来的巨大滚动画布。默认一天一格，最多一小时一格；基准格宽为 48～84 逻辑像素。平移没有预设日期边界，只绘制可见区域附近的网格和条目。表头标签固定在对应时间格的中上方，以完整文字绘制并在视口边缘自然裁切，不贴靠屏幕边缘或变成省略号。当前时间线单独在前景绘制，覆盖日程条但不拦截交互，也不绘制圆点。条目单击复用日程详情弹层，编辑、删除、同步后由功能控制器通知刷新。

操作方式：拖动或普通滚轮横向浏览时间，双指捏合、`Ctrl + 滚轮` 或滑条连续缩放；上下拖动、`Shift + 滚轮` 或拖动滚动条浏览泳道。单指或鼠标拖动释放后，使用 Flutter 的摩擦物理模拟继续滑行；缩放、新输入、隐藏视图或离开页面时停止惯性，触控板自身的惯性输入不额外叠加甩动。「今天」按钮回到今日居中。时间轴不包在完成状态的 `SwipePager` 内，避免横向时间导航触发状态切页。

## 空教室查询

页面只负责显示控件、日期选择和登录验证界面。`ClassroomController` 管理查询输入、结果和取消：更换校区或日期会取消旧查询，等待其资源结束后执行新查询；教学楼和时段筛选直接复用已获取的数据。

`ClassroomRepository` 持有教室数据缓存。同账号的教学楼目录缓存一天，占用情况缓存五分钟；相同查询共享进行中的请求。切换账号或退出登录会清空缓存，刷新目录也会清空占用缓存。取消或失败的结果不会缓存。

## 手势与布局

- `SwipePager` 统一鼠标与触摸分页，拖过半页即报告新页，程序切页不报告中间页。
- `SwipeActionTile` 使用原生 `Dismissible` 处理手势和滑出；保存失败回到原位。行的增删尺寸动画由 `AnimatedSliverChildren` 统一处理。
- `PullToRevealList` 管理下拉手势和展开状态，`RevealScrollController` 在布局阶段同步内容高度与滚动位置。用户重新拖动时解除滚动保持，直接接管滚动。
- `AppMenuAnchor` 使用原生 `RawMenuAnchor` 管理焦点与菜单生命周期，统一面板的开合动效。菜单高度取触发器上下的实际可用空间。
- `SheetLayout`、`EditorSheet` 和主题共同约束弹层尺寸、固定操作区与可滚动内容。地图的缩放、绘制和命中测试由 `WencuiFloorMap` 管理。

## 验证

`test/support/test_app.dart` 使用真实功能控制器，只将存储和平台边界替换为内存实现。测试覆盖菜单、滑动、展开与收回、不同窗口和字体大小、请求取消、同步合并、账号切换以及真实文件存储格式。

```sh
dart format lib test
flutter analyze --no-pub lib test
flutter test --no-pub
```

架构划分参考 [Flutter 官方建议](https://docs.flutter.dev/app-architecture/recommendations)、[Compass 的数据层](https://github.com/flutter/samples/tree/main/compass_app/app/lib/data) 和 [Wonderous 的功能状态组织](https://github.com/gskinnerTeam/flutter-wonderous-app/tree/main/lib/logic)，具体边界按本项目的离线存储和学校登录流程确定。
