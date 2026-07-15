---
categories: [知识点]
title: Kotlin Flow 全面详解：冷流、StateFlow、SharedFlow 与 Channel
date: 2026-07-15 11:11:00 +0800
pin: false
tags: [android, kotlin, flow]
keywords: [flow, kotlin协程, stateflow, sharedflow, channel, snapshotflow, 冷流, 热流]
description: 一文讲透 Kotlin Flow 的所有类型：冷流 Flow、StateFlow、SharedFlow、Channel 的特性、原理与选型，附常用操作符、Compose 互转（snapshotFlow）、Android 实践与高频面试题。
---

在 Android 开发中，Flow 已经全面取代 RxJava 和 LiveData，成为官方推荐的响应式数据流方案。但 Flow 并不是单一的一个类，它是一个**家族**：冷流 `Flow`、热流 `StateFlow` / `SharedFlow`，以及协程间通信的 `Channel`。这篇文章会把每一类的特性、参数、底层行为和选型逻辑一次讲清楚。

> 本文基于 kotlinx.coroutines 最新稳定版（1.10.x）整理，关键行为均对照了官方源码与文档（`SharedFlow.kt`、`StateFlow.kt`、`Share.kt`）。
{: .prompt-info }

## 一、Flow 是什么

`Flow<T>` 是 Kotlin 协程库提供的**异步数据流**抽象：它按顺序发出多个值，并且可以在发射过程中挂起（suspend）。可以把它类比为：

- `List<T>`：一次性返回**多个**值，但是**同步**的；
- `suspend fun`：**异步**返回，但只有**一个**值；
- `Flow<T>`：**异步**地、**依次**发出**多个**值。

一个 Flow 管道由三部分组成：

```kotlin
flowOf(1, 2, 3)              // ① 生产者（发射器）：产生数据
    .map { it * 10 }         // ② 中间操作符：加工数据，返回新的 Flow
    .collect { println(it) } // ③ 消费者（收集器）：终端消费数据
```

理解 Flow 家族的第一把钥匙，是分清**冷流（Cold Flow）**和**热流（Hot Flow）**。

## 二、冷流 vs 热流

冷流（Cold Flow）
: **不收集就不生产**。每次调用 `collect` 都会重新执行一遍 flow 块内的代码，每个收集器拿到的是**独立、完整**的一份数据序列。就像点播视频，谁点谁看，从头播放。

热流（Hot Flow）
: **生产者独立于收集器存在**。数据的产生不依赖是否有人收集；多个收集器**共享同一个**数据源，新来的收集器只能看到订阅之后的数据（或配置的重放数据）。就像直播，中途进来只能从当前时刻看起。

| 维度 | 冷流（`Flow`） | 热流（`StateFlow`/`SharedFlow`） |
| --- | --- | --- |
| 生产时机 | 有收集器才开始执行 | 与收集器无关，随时可发射 |
| 多收集器 | 各自触发一次独立执行 | 共享同一份数据（多播） |
| 是否完成 | 发射完毕即完成 | 永不完成 |
| 典型来源 | 网络请求、数据库查询 | UI 状态、全局事件 |

## 三、冷流 Flow 详解

### 3.1 创建方式

```kotlin
// ① flow {} 构建器：最常用，块内可调用挂起函数
val pageFlow = flow {
    for (page in 1..3) {
        delay(100)        // 可以挂起
        emit("Page $page") // 发射值
    }
}

// ② flowOf：固定的一组值
val fixed = flowOf("A", "B", "C")

// ③ asFlow：集合/区间/序列转 Flow
val range = (1..5).asFlow()

// ④ channelFlow：允许在不同协程中并发 send（emit 不允许跨协程）
val merged = channelFlow {
    launch { send(loadFromCache()) }
    launch { send(loadFromNetwork()) }
}

// ⑤ callbackFlow：把回调 API 转成 Flow（最典型的实战场景）
fun locationFlow(): Flow<Location> = callbackFlow {
    val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            trySend(result.lastLocation) // 回调线程里用 trySend
        }
    }
    client.requestLocationUpdates(request, callback, looper)
    awaitClose { client.removeLocationUpdates(callback) } // 必须：收集取消时清理回调
}
```

> `flow {}` 内部有 emission 上下文检查，**禁止**切换协程/线程去 `emit`（会抛 `IllegalStateException`）；需要并发发射时必须用 `channelFlow` / `callbackFlow`，它们底层通过 Channel 中转，天然线程安全。
{: .prompt-warning }

### 3.2 冷流的核心特性

1. **惰性执行**：构建 Flow 不会运行任何代码，只有终端操作符（`collect`、`first`、`toList` 等）才会触发。
2. **每次收集独立执行**：collect 两次，`flow {}` 块就完整跑两遍。所以一个网络请求的 Flow 被两个页面 collect，会请求两次——这也是后面 `shareIn`/`stateIn` 存在的意义。
3. **顺序性**：默认情况下，上游 `emit` 一个值，要等下游处理完才会继续 `emit` 下一个（同一协程内同步接力）。
4. **协程取消协作**：collect 所在协程被取消，上游生产代码也随之取消，资源自动释放。
5. **上下文保存（Context Preservation）**：Flow 的执行上下文由收集方决定，上游想切线程只能用 `flowOn`。

### 3.3 常用中间操作符

```kotlin
flow.map { it * 2 }                  // 一对一变换（块内可挂起）
flow.filter { it % 2 == 0 }          // 过滤
flow.transform { emit(it); emit(-it) } // 一对多，自由发射
flow.take(2)                         // 只取前 N 个，随后取消上游
flow.distinctUntilChanged()          // 连续重复值去重
flow.debounce(300)                   // 防抖：搜索框输入场景
flow.sample(1000)                    // 采样：每秒取最新一个
flow.onEach { log(it) }              // 旁路观察，不改变数据
flow.onStart { emit(Loading) }       // 收集开始前先发一个值
flow.onCompletion { cause -> ... }   // 完成/取消/异常时回调
```

组合与展平：

```kotlin
flowA.zip(flowB) { a, b -> "$a-$b" }     // 一一配对，短的一方结束即结束
flowA.combine(flowB) { a, b -> "$a-$b" } // 任一方更新就用双方最新值重新计算
flow.flatMapConcat { inner(it) }          // 串行展平：上一个内部流完成才开始下一个
flow.flatMapMerge { inner(it) }           // 并发展平：多个内部流同时收集
flow.flatMapLatest { inner(it) }          // 新值到来立即取消旧的内部流（搜索场景标配）
```

### 3.4 线程切换：flowOn

`flowOn` 只改变**它上面**的操作符的执行上下文，下游（含 collect）仍在收集方的上下文：

```kotlin
flow { emit(queryDb()) }        // 在 IO 执行
    .map { heavyParse(it) }     // 在 IO 执行
    .flowOn(Dispatchers.IO)     // ↑ 以上切到 IO
    .onEach { updateUi(it) }    // 在收集方（如 Main）执行
    .collect()
```

注意：`flowOn` 改变上下文后，上下游会运行在**不同协程**中，中间自动引入了一个 Channel 缓冲，顺序性中的"同步接力"不再成立。

### 3.5 背压处理：buffer / conflate / collectLatest

冷流默认"生产一个消费一个"，当消费者慢于生产者时有三种策略：

```kotlin
flow.buffer(64)        // 加缓冲区：生产者不等消费者，先塞进缓冲，全部值都会被处理
flow.conflate()        // 合并：只保留最新值，消费者忙时中间值被丢弃
flow.collectLatest { } // 新值到来时取消尚未处理完的旧值处理块
```

三者的选择逻辑：**每个值都重要**（如埋点上报）用 `buffer`；**只关心最新状态**（如进度条）用 `conflate`；**处理过程本身应该被新值打断**（如根据输入渲染预览）用 `collectLatest`。

### 3.6 异常与重试

```kotlin
flow { emit(api.load()) }
    .retry(3) { it is IOException }   // 指定异常最多重试 3 次
    .catch { e -> emit(fallback) }    // 只捕获上游异常，可发射兜底值
    .collect { render(it) }
```

`catch` 的关键语义是**异常透明性**：它只能捕获**上游**的异常，`collect` 块里的异常它管不着——这是刻意设计，避免异常被悄悄吞掉。下游异常要么用 `try/catch` 包住 collect，要么把消费逻辑挪进 `onEach` 再 `catch`。

## 四、StateFlow 详解

`StateFlow` 是**持有单一状态值**的热流，为"可观察的状态"这一场景特化。

### 4.1 核心特性

- **永远有值**：创建 `MutableStateFlow(initialValue)` 必须给初始值，任何时刻都能通过 `.value` 同步读写。
- **新订阅者立即收到当前值**：replay 固定为 1，订阅即回放最新状态。
- **自动去重**：新值与旧值 `equals` 相等时不会下发。所以它天然不适合做事件——连续两次相同事件会被吞掉。
- **合并（Conflation）**：只保留最新值。收集器处理慢时中间状态直接跳过，UI 场景正合适（用户只关心最终画面）。
- **永不完成**：collect 一个 StateFlow 的协程永远不会自己结束，必须由外部（生命周期/作用域）取消。
- **线程安全**：`.value` 的更新是原子的；需要"读-改-写"原子性时用 `update {}`：

```kotlin
private val _uiState = MutableStateFlow(CounterState(count = 0))
val uiState: StateFlow<CounterState> = _uiState.asStateFlow()

fun increment() {
    _uiState.update { it.copy(count = it.count + 1) } // CAS 循环，多线程安全
}
```

### 4.2 与 SharedFlow 的关系（源码视角）

官方源码（`StateFlow.kt`）明确说明：StateFlow 是 SharedFlow 的一个特化版本，行为上等价于：

```kotlin
val shared = MutableSharedFlow<Int>(
    replay = 1,
    onBufferOverflow = BufferOverflow.DROP_OLDEST
)
shared.tryEmit(initialValue)                 // 保证有初始值
val state = shared.distinctUntilChanged()    // 加上去重
```

即：**StateFlow = SharedFlow(replay=1, DROP_OLDEST) + 初始值 + 去重**。但 StateFlow 的内部实现是独立的、更轻量的（直接存一个 value，不维护环形缓冲区），并且不支持 `resetReplayCache()`。

## 五、SharedFlow 详解

`SharedFlow` 是最通用的热流：**多播事件流**，一个值发出后所有活跃订阅者都能收到。它就是为取代已废弃的 `BroadcastChannel` 而设计的。

### 5.1 三个构造参数

```kotlin
public fun <T> MutableSharedFlow(
    replay: Int = 0,                 // 向新订阅者重放最近 N 个值
    extraBufferCapacity: Int = 0,    // replay 之外的额外缓冲容量
    onBufferOverflow: BufferOverflow = BufferOverflow.SUSPEND // 缓冲满时 emit 的策略
): MutableSharedFlow<T>
```

**replay（重放）**

- `replay = 0`（默认）：新订阅者只能收到订阅之后发出的值，适合一次性事件；
- `replay = 1`：新订阅者收到最近一个值，类似粘性事件 / LiveData 行为（但不去重）；
- `replay = n`：回放最近 n 个历史值。

**extraBufferCapacity（额外缓冲）**

总缓冲容量 = `replay + extraBufferCapacity`。只要缓冲有空位，`emit` 就**不挂起**。

**onBufferOverflow（溢出策略）**

- `SUSPEND`（默认）：缓冲满时 `emit` 挂起，等最慢的订阅者消费——这就是背压；
- `DROP_OLDEST`：丢最旧的值，塞入新值；
- `DROP_LATEST`：直接丢掉新值。

非 `SUSPEND` 策略要求 `replay > 0` 或 `extraBufferCapacity > 0`，否则构造时抛 `IllegalArgumentException`。

> 源码中一个容易被忽略的关键点（`SharedFlow.kt` 文档原文强调）：**缓冲溢出只在"存在至少一个跟不上的订阅者"时才会发生**。没有任何订阅者时，`emit` 永不挂起，只有最近 `replay` 个值被保留，其余直接丢弃——溢出策略此时完全不生效。这就是"SharedFlow 在无订阅者时发的事件会丢"的根本原因。
{: .prompt-warning }

### 5.2 emit vs tryEmit

- `emit(value)`：挂起函数，缓冲满且策略为 `SUSPEND` 时挂起；
- `tryEmit(value)`：非挂起，塞不进去就返回 `false`。在非协程环境（如系统回调）里常用，但配置为纯 `SUSPEND`（无缓冲）的 SharedFlow 调 `tryEmit` 只要有订阅者在处理就可能失败，需要配合 `extraBufferCapacity` 使用。

### 5.3 订阅者感知

`MutableSharedFlow` 暴露 `subscriptionCount: StateFlow<Int>`，可以据此感知"有没有人在听"，实现按需启停上游：这也是 `shareIn` 的 `SharingStarted.WhileSubscribed` 的实现基础。另外 `resetReplayCache()` 可清空重放缓存（StateFlow 不支持）。

### 5.4 典型场景：一次性事件

```kotlin
// ViewModel
private val _events = MutableSharedFlow<UiEvent>()   // replay=0：事件不粘
val events = _events.asSharedFlow()

fun onSaveClicked() {
    viewModelScope.launch { _events.emit(UiEvent.ShowToast("已保存")) }
}

// UI
lifecycleScope.launch {
    repeatOnLifecycle(Lifecycle.State.STARTED) {
        viewModel.events.collect { event -> /* 处理事件 */ }
    }
}
```

注意上面 5.1 的坑：页面在后台时（STARTED 之下）collect 被停掉，此刻 `emit` 的事件因为**没有订阅者**会直接丢失。对不允许丢失的事件（如导航），更稳妥的做法是用 `Channel(BUFFERED)` + `receiveAsFlow()`，Channel 会把事件存到有人来取为止。

## 六、Channel 详解

`Channel` 不是 Flow 的子类型，但它是 Flow 家族绕不开的一员：**协程之间的并发安全通信管道**，概念上就是一个挂起版的 `BlockingQueue`。

### 6.1 核心特性

- **点对点（Unicast）**：一个值只会被**一个**接收者消费，天然"不粘、不重、不丢"（相对于活跃的接收者而言），与 SharedFlow 的多播形成互补；
- **公平分发**：多个协程同时 `receive` 时按 FIFO 轮流拿到值；
- **可以关闭**：`close()` 后 `for (x in channel)` 循环正常退出，这一点与永不完成的热流不同；
- **挂起语义**：空了 `receive` 挂起，满了 `send` 挂起。

### 6.2 四种容量类型

```kotlin
Channel<Int>(Channel.RENDEZVOUS)  // 容量 0（默认）：send 与 receive 必须"会合"
Channel<Int>(Channel.BUFFERED)    // 默认 64 的缓冲
Channel<Int>(capacity = 10)       // 指定容量
Channel<Int>(Channel.CONFLATED)   // 只保留最新值，旧值被覆盖
Channel<Int>(Channel.UNLIMITED)   // 无限缓冲（注意内存）
```

### 6.3 与 Flow 的桥接

```kotlin
private val _navigation = Channel<NavEvent>(Channel.BUFFERED)
val navigation = _navigation.receiveAsFlow() // 转成 Flow 给 UI collect

fun goDetail(id: Long) {
    viewModelScope.launch { _navigation.send(NavEvent.Detail(id)) }
}
```

`receiveAsFlow()` 得到的 Flow 依然是点对点语义：多个收集器会**瓜分**事件而不是各收到一份。这恰好是一次性事件想要的——事件只被处理一次，且无人收集时事件在缓冲里等着，不会丢。

## 七、冷流转热流：shareIn 与 stateIn

Repository 层返回的通常是冷流（数据库/网络），如果多个订阅者直接 collect 会重复执行上游。`shareIn` / `stateIn` 把冷流"升温"成共享的热流：

```kotlin
val user: StateFlow<User?> = repository.observeUser()   // 冷流
    .stateIn(
        scope = viewModelScope,
        started = SharingStarted.WhileSubscribed(5000),
        initialValue = null
    )
```

`SharingStarted` 三种启动策略：

- `Eagerly`：作用域启动即开始收集上游，永不停止；
- `Lazily`：第一个订阅者出现才开始，之后永不停止；
- `WhileSubscribed(stopTimeoutMillis)`：有订阅者才收集，最后一个订阅者离开 `stopTimeout` 毫秒后停止上游。**`WhileSubscribed(5000)` 是 Android 官方推荐值**：屏幕旋转（订阅者短暂消失又回来）不会重启上游，而真正退到后台超过 5 秒则停止收集、节省资源。

`shareIn` 同理，只是产出 `SharedFlow`（可配 replay），不要求初始值。源码（`Share.kt`）中 `WhileSubscribed` 停止时发出 `STOP_AND_RESET_REPLAY_CACHE` 命令的话，stateIn 会把值重置回 `initialValue`，shareIn 则清空重放缓存。

## 八、一张总表

| 特性 | Flow（冷流） | StateFlow | SharedFlow | Channel |
| --- | --- | --- | --- | --- |
| 冷/热 | 冷 | 热 | 热 | 热 |
| 初始值 | 无 | **必须有** | 无 | 无 |
| 新订阅者收到 | 完整重新执行 | 当前值 | 最近 replay 个 | 缓冲中未消费的 |
| 多收集器 | 各自独立执行 | 多播，都收到 | 多播，都收到 | **瓜分**（一人一个） |
| 去重 | 手动 `distinctUntilChanged` | **自动** | 不去重 | 不去重 |
| 无订阅者时发射 | 不会发生（惰性） | 更新 value | 只留 replay，其余丢弃 | 存入缓冲，不丢 |
| 会完成吗 | 会 | 永不 | 永不 | `close()` 后完成 |
| 背压 | buffer/conflate | 合并（只留最新） | onBufferOverflow 策略 | 容量满则 send 挂起 |
| 典型用途 | 网络/数据库等一次性异步序列 | UI 状态 | 全局多播事件 | 一次性事件、生产者-消费者 |

选型口诀：**状态用 StateFlow，多播事件用 SharedFlow，不容丢失的单消费事件用 Channel，一切数据源头用冷流再按需 stateIn/shareIn**。

## 九、Android 实践要点

1. **安全收集**：View 体系用 `repeatOnLifecycle(Lifecycle.State.STARTED)`，Compose 用 `collectAsStateWithLifecycle()`，避免后台期间白白消费资源（`launchWhenStarted` 已废弃，它只是挂起而非取消，上游仍在生产）。
2. **对外只读**：ViewModel 内部持有 `MutableStateFlow`/`MutableSharedFlow`，对外通过 `asStateFlow()`/`asSharedFlow()` 暴露只读接口。
3. **StateFlow vs LiveData**：StateFlow 有初始值、不感知生命周期（需配合 repeatOnLifecycle）、支持全套操作符、不依赖 Android 框架可纯 JVM 测试；LiveData 自带生命周期感知但能力有限。新代码一律推荐 Flow 体系。
4. **Room / DataStore** 原生返回冷流，`Flow<List<Entity>>` 在表变化时自动重新发射，配合 `stateIn` 即成 UI 状态源。

## 十、Compose 中的 Flow：snapshotFlow 与状态互转

Compose 有自己的一套可观察体系——快照状态（`State<T>` / `mutableStateOf`），它和 Flow 是**两个方向都需要互转**的关系：

```text
Flow ──collectAsState / collectAsStateWithLifecycle──▶ Compose State
Compose State ──snapshotFlow──▶ Flow
```

### 10.1 snapshotFlow：把 Compose State 变成 Flow

`snapshotFlow` 是 Compose runtime 提供的构建器，签名很简单：

```kotlin
fun <T> snapshotFlow(block: () -> T): Flow<T>
```

它把 block 里**读取到的快照状态**转成一条**冷流**：

- **冷流**：被 collect 时才运行 block，先发射一次当前计算结果；
- **自动追踪依赖**：block 内读到的所有 `State` 对象都会被记录，其中任何一个变化时重新执行 block；
- **自带去重**：新结果与上次 `equals` 相等时不发射，行为等同于 `distinctUntilChanged()`；
- **合并（conflated）**：状态高频变化时只保证收到最新值，中间值可能被跳过——与 StateFlow 的合并语义一致。

典型场景：把 UI 状态的变化接入 Flow 操作符管道。比如列表滚动埋点：

```kotlin
val listState = rememberLazyListState()

LazyColumn(state = listState) { /* ... */ }

LaunchedEffect(listState) {
    snapshotFlow { listState.firstVisibleItemIndex } // State 读值 → Flow
        .map { index -> index > 0 }
        .distinctUntilChanged()
        .filter { it }
        .collect { analytics.sendScrolledPastFirstItemEvent() }
}
```

再比如搜索框防抖——`TextFieldState` 是快照状态而不是 Flow，想用 `debounce` 就得先过一道 `snapshotFlow`：

```kotlin
LaunchedEffect(Unit) {
    snapshotFlow { textFieldState.text }
        .debounce(300)
        .collectLatest { query -> viewModel.search(query.toString()) }
}
```

> block 应当是**纯读取**，不要在里面写状态或做副作用；副作用放到 collect 里。另外 `snapshotFlow` 必须在协程里收集，在 Compose 中通常放在 `LaunchedEffect` 内。
{: .prompt-tip }

### 10.2 反方向：Flow 变成 Compose State

- **`collectAsStateWithLifecycle()`**（Android 推荐）：来自 `lifecycle-runtime-compose`，感知生命周期，界面进入后台（低于 STARTED）时自动停止收集，回前台再恢复——等价于 View 体系里的 `repeatOnLifecycle`。ViewModel 暴露的 `StateFlow` 在 Compose 中一律用它收集。
- **`collectAsState()`**：`compose-runtime` 自带、跨平台（KMP 可用），但**不感知生命周期**，App 在后台时仍持续收集。只在非 Android 平台或明确不需要生命周期语义时使用。

```kotlin
val uiState by viewModel.uiState.collectAsStateWithLifecycle()
```

- **`produceState`**：更底层的通用桥梁，把任意异步来源（Flow、LiveData、回调、suspend 函数）转成 `State<T>`。它启动一个协程，向 `value` 赋值即触发重组；key 变化时旧协程取消、新协程重启。事实上 `collectAsState` 内部就是用它实现的：

```kotlin
@Composable
fun loadNetworkImage(url: String, repo: ImageRepository): State<Result<Image>> =
    produceState<Result<Image>>(initialValue = Result.Loading, url, repo) {
        val image = repo.load(url)   // 协程体内可调用挂起函数
        value = image?.let { Result.Success(it) } ?: Result.Error
    }
```

- **`collectAsLazyPagingItems()`**：Paging 3 专用，把 `Flow<PagingData<T>>` 转成 LazyColumn 可直接消费的分页数据。

### 10.3 一张互转速查表

| API | 方向 | 特点 |
| --- | --- | --- |
| `snapshotFlow {}` | State → Flow | 冷流、自动追踪依赖、去重、合并 |
| `collectAsStateWithLifecycle()` | Flow → State | 生命周期感知，Android 首选 |
| `collectAsState()` | Flow → State | 跨平台，不感知生命周期 |
| `produceState` | 任意异步源 → State | 通用桥梁，key 变化自动重启 |
| `collectAsLazyPagingItems()` | Flow\<PagingData\> → 分页列表 | Paging 3 专用 |

## 十一、高频面试题

**Q1：冷流和热流的本质区别是什么？**

答：区别在于**生产者与收集器的关系**。冷流的生产代码在 collect 时才执行，每个收集器触发一次独立执行，数据是"按需生产、每人一份"；热流的生产独立于收集器，数据"只有一份"，所有收集器共享，错过就（可能）没有了。冷流会完成，热流永不完成。类比：冷流是点播，热流是直播。

**Q2：StateFlow 和 SharedFlow 什么关系？分别用在什么场景？**

答：StateFlow 是 SharedFlow 的特化：行为等价于 `MutableSharedFlow(replay = 1, onBufferOverflow = DROP_OLDEST)` 再加初始值和 `distinctUntilChanged` 去重。StateFlow 用于**状态**——永远有值、只关心最新、相同值不重复通知（如 UI 状态）；SharedFlow 用于**事件**——可以没有值、每个都算数、需要多播（如全局登出通知）。判断标准：这份数据"迟到的观察者需要立刻拿到最新快照吗？"需要就是状态，用 StateFlow。

**Q3：为什么 StateFlow 不适合做一次性事件？**

答：三个原因：① 自动去重——连续两次相同事件（如两次点击都要弹同一个 Toast）第二次不会下发；② 粘性——配置更改后 UI 重新订阅会再次收到旧事件，导致 Toast 重复弹出、导航重复触发；③ 合并——快速连发的事件可能被跳过。事件应该用 `replay = 0` 的 SharedFlow 或 Channel。

**Q4：SharedFlow 的三个构造参数分别控制什么？无订阅者时 emit 会怎样？**

答：`replay` 控制新订阅者能回放多少历史值；`extraBufferCapacity` 是重放之外的缓冲，总缓冲 = 两者之和，缓冲有空位时 `emit` 不挂起；`onBufferOverflow` 控制缓冲满时的行为（SUSPEND 挂起 / DROP_OLDEST 丢旧 / DROP_LATEST 丢新）。关键细节：**溢出只在存在跟不上的订阅者时发生**；没有订阅者时 `emit` 永不挂起，只保留最近 replay 个值，其余直接丢弃。所以 `replay = 0` 的 SharedFlow 在页面处于后台（收集被 repeatOnLifecycle 停掉）时发出的事件会永久丢失。

**Q5：那不能丢的一次性事件（比如导航）该怎么发？**

答：用 `Channel(BUFFERED)` + `receiveAsFlow()`。Channel 的语义是点对点：事件在缓冲里一直等到有接收者来取，不会因为"当时没人订阅"而丢失；且一个事件只会被消费一次，即使将来有多个收集器也不会重复处理。相比之下 SharedFlow 无订阅者会丢事件，StateFlow 有粘性会重复处理，都不满足"恰好一次"的要求。

**Q6：flowOn 和 withContext 在 Flow 里怎么用？为什么 flow 块里不能直接 withContext 后 emit？**

答：Flow 有"上下文保存"原则：collect 运行在收集方的上下文，上游要切线程只能用 `flowOn`，且 `flowOn` 只影响它上方的操作符。`flow {}` 块内禁止在别的上下文中 `emit`（运行时抛 `IllegalStateException`），因为 emit 和 collect 本质是同一协程内的函数接力，跨上下文调用会破坏这一模型的线程安全假设。确实需要并发/跨协程发射时，用 `channelFlow`/`callbackFlow`，它们底层用 Channel 中转。

**Q7：buffer、conflate、collectLatest 有什么区别？**

答：都是解决"生产快、消费慢"的：`buffer` 加缓冲让生产者不等消费者，**所有值最终都会被处理**；`conflate` 只保留最新值，消费者忙时中间值被丢弃，**处理不被打断但会跳值**；`collectLatest` 新值一到就**取消**还没处理完的旧值处理块，适合处理逻辑本身应被新数据作废的场景。记法：不丢用 buffer，跳值用 conflate，打断用 collectLatest。

**Q8：catch 操作符能捕获 collect 里的异常吗？**

答：不能。`catch` 遵循"异常透明性"，只捕获**上游**（它之前的 flow 块和操作符）抛出的异常。collect 块属于下游，其异常会正常向外抛。若想统一处理，把消费逻辑写进 `onEach`，让 `catch` 位于其后，最后用 `collect()`（无参）或 `launchIn(scope)` 触发。

**Q9：shareIn / stateIn 的作用？WhileSubscribed(5000) 里的 5000 是什么讲究？**

答：它们把冷流转为热流共享，避免多个订阅者各自重复触发上游（如同一个数据库查询执行多次）。`SharingStarted.WhileSubscribed(5000)` 表示有订阅者才收集上游，最后一个订阅者离开 5 秒后停止。5000 毫秒是 Android 官方推荐值，目的是**跨越配置更改**：屏幕旋转时订阅者会消失又立刻回来，5 秒宽限期内上游不重启、重放缓存不丢；而真正退到后台超过 5 秒（超过系统 ANR 感知的前后台切换间隔）就停止上游省资源。

**Q10：Channel 和 SharedFlow 怎么选？**

答：看**消费语义**。Channel 是点对点：一个值只被一个接收者消费一次，可关闭，无人接收时值在缓冲里等待——适合任务队列、不容丢失的一次性事件；SharedFlow 是多播：一个值所有活跃订阅者都收到，永不完成，无订阅者时值（除 replay 外）被丢弃——适合广播型事件、共享数据流。一句话：要"恰好一次"用 Channel，要"人人都收到"用 SharedFlow。

**Q11：Compose 里的 snapshotFlow 是什么？它是冷流还是热流？**

答：`snapshotFlow { block }` 是 Compose runtime 提供的构建器，把 block 中**读取的快照状态（Compose `State`）**转成一条**冷流**——collect 时才执行 block 并发射初始值，之后 block 里读过的任何 State 变化都会触发重新计算并发射。它自带两个特性：**去重**（新结果与上次 equals 相等不发射，等同 `distinctUntilChanged`）和**合并**（高频变化只保证最新值）。典型用途是把 UI 状态接入 Flow 操作符管道，如 `snapshotFlow { listState.firstVisibleItemIndex }` 做滚动埋点、`snapshotFlow { textFieldState.text }.debounce(300)` 做搜索防抖。它与 `collectAsState` 正好互为反方向：`collectAsState` 是 Flow → State，`snapshotFlow` 是 State → Flow。

**Q12：collectAsState 和 collectAsStateWithLifecycle 有什么区别？**

答：两者都把 Flow 收集为 Compose `State` 并在新值到来时触发重组。区别在于生命周期：`collectAsState` 属于 `compose-runtime`、跨平台可用，但只跟随组合的生命周期——只要 Composable 还在组合中，即使 App 退到后台它也持续收集，浪费资源；`collectAsStateWithLifecycle` 来自 `lifecycle-runtime-compose`，在生命周期低于 STARTED 时自动停止收集、回前台恢复，语义等同于 `repeatOnLifecycle(STARTED)`，是 Android 官方推荐。配合上游的 `stateIn(WhileSubscribed(5000))`，页面退后台 5 秒后整条数据管道都会停下来。

**Q13：StateFlow 与 LiveData 的区别？**

答：① StateFlow 必须有初始值，LiveData 可以没有；② LiveData 自带生命周期感知，观察者在非活跃状态自动不接收，而 StateFlow 需要配合 `repeatOnLifecycle`/`collectAsStateWithLifecycle` 手动保证；③ StateFlow 支持完整的 Flow 操作符链和 `flowOn` 线程控制，LiveData 变换能力有限且回调在主线程；④ StateFlow 属于 kotlinx.coroutines，纯 Kotlin 可在任何层（domain/data）使用并做 JVM 单测，LiveData 依赖 Android 框架；⑤ 两者都是粘性、去重、只留最新值的。官方新架构指南已全面推荐 Flow。

## 参考

- [Kotlin 官方文档：Asynchronous Flow](https://kotlinlang.org/docs/flow.html)
- [kotlinx.coroutines 源码：SharedFlow.kt / StateFlow.kt / Share.kt](https://github.com/Kotlin/kotlinx.coroutines/tree/master/kotlinx-coroutines-core/common/src/flow)
- [Android 官方指南：StateFlow 与 SharedFlow](https://developer.android.com/kotlin/flow/stateflow-and-sharedflow)
