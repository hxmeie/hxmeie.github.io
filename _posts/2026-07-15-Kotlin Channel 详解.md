---
categories: [知识点]
title: Kotlin Channel 详解：它和 Flow 不是一个东西
date: 2026-07-15 11:31:00 +0800
pin: false
tags: [android, kotlin, channel]
keywords: [channel, kotlin协程, flow, rendezvous, conflated, 协程通信, csp]
description: Channel 和 Flow 是一个东西吗？本文从设计理念讲起，详解 Channel 的五种容量类型（RENDEZVOUS、BUFFERED、CONFLATED、UNLIMITED、指定容量）、溢出策略、close 与 cancel、produce、select 等全部核心机制，文末附高频面试题。
---

经常有人把 `Channel` 当成"Flow 的一种"，因为它们都出自 kotlinx.coroutines、都能传数据、还能互相转换。但**它们不是一个东西**：Flow 是"数据流"的声明式抽象，Channel 是"协程间通信"的并发原语。这篇文章先把两者的关系掰清楚，再把 Channel 的每一种类型、每一个关键机制讲透。

> 本文基于 kotlinx.coroutines 最新稳定版（1.10.x）整理，关键行为均对照官方文档与源码（`Channel.kt`、`BufferedChannel.kt`、`ConflatedBufferedChannel.kt`）。
{: .prompt-info }

## 一、Channel 和 Flow 是一个东西吗？

**不是。** 它们处在不同的抽象层次上，设计目标完全不同：

| 维度 | Flow | Channel |
| --- | --- | --- |
| 本质 | **数据流的声明式抽象**（描述"数据如何产生和加工"） | **协程间的通信管道**（并发原语，挂起版队列） |
| 理论渊源 | 响应式流（Reactive Streams） | CSP（Communicating Sequential Processes，通信顺序进程） |
| 冷/热 | 冷流为主（`flow {}`），有热流变体 | 天生是"热"的：值一旦 send 就存在了 |
| 消费语义 | 每个收集器一份完整数据（冷流）或多播（热流） | **点对点**：一个值只被**一个**接收者消费一次 |
| 使用方式 | 操作符链式加工（map/filter/…） | 命令式 send/receive |
| 完成 | 冷流会完成；热流永不完成 | 可 `close()`，有明确的完成语义 |
| 定位 | 业务数据流的主力 API | 底层构件：Flow 的很多能力靠它实现 |

两者的关系更像"**引擎与整车**"：`channelFlow`、`callbackFlow`、`flowOn`、`buffer`、`produceIn`、`receiveAsFlow` 这些 Flow 的 API，底层都是 Channel 在做协程间的数据中转。日常业务优先用 Flow；当你需要**精确控制"谁发、谁收、收几次"**的协程间通信时，才直接上 Channel。

概念上可以这样记：

- **Flow 是"流水线"**：描述数据从源头到消费的加工过程，收集时才运转；
- **Channel 是"传送带"**：连接两个（或多个）并发运行的工人，东西放上去就在那儿，谁先拿到归谁。

## 二、Channel 是什么

`Channel` 是协程之间传递数据的**并发安全管道**，概念上等价于一个**挂起版的 `BlockingQueue`**：

- `BlockingQueue.put()` 满了**阻塞线程** → `Channel.send()` 满了**挂起协程**；
- `BlockingQueue.take()` 空了**阻塞线程** → `Channel.receive()` 空了**挂起协程**。

阻塞变挂起，意味着等待期间线程可以去干别的活，这是 Channel 相对传统并发队列的根本优势。

### 2.1 三个接口

```kotlin
interface SendChannel<in E> {
    suspend fun send(element: E)      // 挂起发送
    fun trySend(element: E): ChannelResult<Unit> // 非挂起尝试发送
    fun close(cause: Throwable? = null): Boolean
}

interface ReceiveChannel<out E> {
    suspend fun receive(): E          // 挂起接收
    fun tryReceive(): ChannelResult<E>
    fun cancel(cause: CancellationException? = null)
}

interface Channel<E> : SendChannel<E>, ReceiveChannel<E>
```

接口拆分的意义在于**权限收窄**：生产方只暴露 `SendChannel`，消费方只拿到 `ReceiveChannel`，各自都碰不到对方的能力——和 `MutableStateFlow` 对外暴露 `StateFlow` 是同一种封装思想。

### 2.2 基本用法

```kotlin
fun main() = runBlocking {
    val channel = Channel<Int>()
    launch {
        for (x in 1..5) channel.send(x * x)
        channel.close()               // 发完了，关闭通道
    }
    for (y in channel) println(y)     // for 循环持续接收，channel 关闭后自动退出
    println("Done!")
}
```

## 三、Channel 的五种容量类型

`Channel()` 工厂函数的完整签名：

```kotlin
public fun <E> Channel(
    capacity: Int = RENDEZVOUS,                              // 容量
    onBufferOverflow: BufferOverflow = BufferOverflow.SUSPEND, // 缓冲满时的策略
    onUndeliveredElement: ((E) -> Unit)? = null              // 元素未能送达时的回调
): Channel<E>
```

容量参数有四个特殊常量加一种普通值，共五种形态：

### 3.1 RENDEZVOUS（容量 0，默认）

```kotlin
val channel = Channel<Int>()  // 等价于 Channel(Channel.RENDEZVOUS)
```

Rendezvous 意为"会合"：**没有任何缓冲区**，`send` 和 `receive` 必须"碰头"才能完成交接——

- `send` 时没有等待中的接收者 → 发送者挂起，直到有人来 `receive`；
- `receive` 时没有等待中的发送者 → 接收者挂起，直到有人来 `send`。

特性与用途：

- **完全同步的交接**：每个元素的传递都意味着两个协程在同一时刻"握手"，天然形成两端速率的严格对齐（最强的背压）；
- 发送方永远不会"超前"于接收方，**不会有元素堆积**，也不会丢；
- 适合需要严格一对一同步的场景，如令牌传递、请求-应答式的协程协作。

### 3.2 CONFLATED（合并，只留最新）

```kotlin
val channel = Channel<Int>(Channel.CONFLATED)
```

**缓冲区大小为 1，且新值直接覆盖旧值**。`send` **永不挂起**：来了新值，旧值（若还没被取走）直接被挤掉。

```kotlin
val channel = Channel<Int>(Channel.CONFLATED)
channel.send(1)
channel.send(2)
channel.send(3)
println(channel.receive()) // 3 —— 1 和 2 被覆盖丢弃了
```

源码层面，`CONFLATED` 就是 `Channel(capacity = 1, onBufferOverflow = DROP_OLDEST)` 的快捷方式（且构造函数禁止 CONFLATED 与其他 onBufferOverflow 值组合，会抛 `IllegalArgumentException`）。

特性与用途：

- **只关心最新值**，中间状态可丢：进度更新、传感器读数、位置上报；
- 语义上非常接近 `StateFlow` 的合并行为，区别是 Channel 的值**取走就没了**（消费即删除），而 StateFlow 的 value 一直可读；
- 注意它**会丢数据**，事件类场景（每个事件都要处理）绝不能用。

### 3.3 BUFFERED（默认缓冲，64）

```kotlin
val channel = Channel<Int>(Channel.BUFFERED)
```

创建一个**默认容量**的缓冲通道。默认值是 **64**，可通过 JVM 系统属性 `kotlinx.coroutines.channels.defaultBuffer` 全局调整。若指定了 `onBufferOverflow` 为非 SUSPEND 策略，`BUFFERED` 的实际容量变为 1。

- 缓冲没满时 `send` 立即返回不挂起；满了才挂起（SUSPEND 策略下）；
- 是"我需要一点缓冲但不想拍脑袋定数字"时的合理默认。

### 3.4 指定容量（正整数）

```kotlin
val channel = Channel<Int>(capacity = 10)
```

明确指定缓冲区能存多少个元素。行为与 BUFFERED 相同，只是容量由你精确控制：

- 生产者最多"超前"消费者 `capacity` 个元素，超出后 `send` 挂起——这就是**基于容量的背压**；
- 容量的选择本质是**吞吐与内存/延迟的权衡**：容量越大，生产者越少被挂起（吞吐高），但堆积的数据越多。

### 3.5 UNLIMITED（无限缓冲）

```kotlin
val channel = Channel<Int>(Channel.UNLIMITED)
```

缓冲区不设上限（内部链表缓冲，直到内存耗尽）。

- `send` **永不挂起**，也永不丢数据；
- 代价是**失去背压**：消费者慢于生产者时数据无限堆积，存在 OOM 风险；
- 适合确定数据量有限、或必须在非协程环境无脑塞入的场景（此时 `trySend` 一定成功）。

### 3.6 五种类型速查表

| 类型 | 容量 | send 行为 | 会丢数据吗 | 典型场景 |
| --- | --- | --- | --- | --- |
| `RENDEZVOUS`（默认） | 0 | 无接收者等待则挂起 | 不丢 | 严格同步交接 |
| `CONFLATED` | 1（覆盖） | 永不挂起 | **丢旧值** | 进度/最新状态 |
| `BUFFERED` | 64（可配） | 满了才挂起 | 不丢 | 通用缓冲 |
| 指定容量 `n` | n | 满了才挂起 | 不丢 | 精确控制背压 |
| `UNLIMITED` | ∞ | 永不挂起 | 不丢（但可能 OOM） | 不容丢失且无法挂起的场景 |

> "会丢数据吗"一栏均指 `onBufferOverflow = SUSPEND`（默认）下的行为。缓冲类通道也可以显式传 `DROP_OLDEST` / `DROP_LATEST` 改变溢出行为，见下一节。
{: .prompt-tip }

## 四、onBufferOverflow：溢出策略

与 `SharedFlow` 共用同一个枚举 `BufferOverflow`，决定缓冲满时 `send` 的行为：

- **`SUSPEND`（默认）**：挂起发送者，等出空位——提供背压，保证不丢；
- **`DROP_OLDEST`**：丢缓冲里最旧的值，新值入队，`send` 不挂起；
- **`DROP_LATEST`**：直接丢弃要发送的新值，`send` 不挂起。

```kotlin
// 只保留最近 10 条日志，写入方永不被拖慢
val logChannel = Channel<String>(capacity = 10, onBufferOverflow = BufferOverflow.DROP_OLDEST)
```

## 五、onUndeliveredElement：别让资源泄漏

Channel 的元素可能**永远无法送达**：通道被 cancel 时缓冲里还有值、`send` 挂起期间协程被取消、接收者拿到值前自己被取消……如果元素持有资源（文件句柄、Bitmap、网络连接），这些值就会带着资源无声消失。

`onUndeliveredElement` 回调专门兜底这种情况：

```kotlin
val channel = Channel<Resource>(
    capacity = Channel.BUFFERED,
    onUndeliveredElement = { resource -> resource.close() } // 没送到就地释放
)
```

只要一个元素被成功 send 过、但最终没有被任何接收者正常消费（通道取消/关闭异常/接收方取消），该回调就会被调用。传递资源类对象时强烈建议配置。

## 六、close 与 cancel：不是一回事

**`close()`——发送端的"温柔收尾"**：

- 表示"不会再有新元素了"，相当于向队尾插入一个关闭标记；
- **已在缓冲区里的元素仍然可以被接收完**；
- 关闭后再 `send` 抛 `ClosedSendChannelException`；元素取完后再 `receive` 也抛该类异常（或 `close(cause)` 传入的异常）；
- `for (x in channel)` 循环在取完剩余元素后正常结束。

**`cancel()`——接收端的"立即掀桌"**：

- 立刻终止通道，**缓冲区中尚未消费的元素全部丢弃**（配置了 `onUndeliveredElement` 会对每个被丢元素回调）;
- 之后任何 send/receive 都失败。

一句话：**close 是"卖完下班"，cancel 是"店铺爆破"**。优雅收尾用 close，快速放弃用 cancel。

安全接收可以用 `receiveCatching()`，它返回 `ChannelResult`，通道关闭时不抛异常而是返回失败结果：

```kotlin
val result = channel.receiveCatching()
result.onSuccess { println("收到 $it") }
      .onClosed { println("通道已关闭: $it") }
```

## 七、produce、pipeline 与扇入扇出

### 7.1 produce 构建器

`produce` 把"启动协程 + 创建通道 + 结束时自动关闭"打包成一个生产者模式的标准写法，返回 `ReceiveChannel`：

```kotlin
fun CoroutineScope.produceSquares(): ReceiveChannel<Int> = produce {
    for (x in 1..5) send(x * x)
}   // 块结束时通道自动 close，协程失败时自动以异常关闭

fun main() = runBlocking {
    produceSquares().consumeEach { println(it) } // consumeEach 消费完毕自动 cancel 通道
}
```

它是 Channel 世界里的 `flow {}`——事实上 `Flow.produceIn(scope)` 就是把 Flow 转成 `produce` 出来的通道。

### 7.2 管道（Pipeline）

多个 produce 串起来，每一级都是独立协程，形成并发流水线：

```kotlin
fun CoroutineScope.numbers() = produce { var x = 1; while (true) send(x++) }
fun CoroutineScope.square(input: ReceiveChannel<Int>) = produce {
    for (x in input) send(x * x)
}

val pipeline = square(numbers())   // numbers → square 两级并发流水线
```

这正是 Flow 中 `flowOn`/`buffer` 底层做的事情：切上下文后上下游变成两个协程，中间用 Channel 接起来。

### 7.3 扇出（Fan-out）：多个消费者分担

多个协程从**同一个** Channel receive，元素被**瓜分**（一人一个），天然实现工作队列/负载均衡：

```kotlin
val tasks = Channel<Task>()
repeat(4) { workerId ->               // 4 个 worker 竞争消费
    launch { for (task in tasks) process(workerId, task) }
}
```

多个接收者挂起等待时，Channel 按 **FIFO 公平**分发：先来排队的接收者先拿到值。注意扇出场景要用 `for` 循环而不是 `consumeEach`——后者在任一消费者取消时会 cancel 整个通道，影响其他消费者。

### 7.4 扇入（Fan-in）：多个生产者汇聚

多个协程向**同一个** Channel send，天然实现多路事件汇聚：

```kotlin
val channel = Channel<String>()
launch { sendString(channel, "foo", 200L) }
launch { sendString(channel, "BAR!", 500L) }
repeat(6) { println(channel.receive()) }
```

### 7.5 select：同时等多个通道

`select` 表达式可以同时挂起等待多个通道（以及 Job/Deferred/超时），哪个先就绪就走哪个分支：

```kotlin
select<Unit> {
    fizz.onReceive { value -> println("fizz -> $value") }
    buzz.onReceive { value -> println("buzz -> $value") }
    onTimeout(300) { println("超时") }
}
```

挂起函数与 select 子句的对应关系：`send`→`onSend`、`receive`→`onReceive`、`receiveCatching`→`onReceiveCatching`、`delay`→`onTimeout`。多个子句同时就绪时**偏向排在前面的**（可用 `selectUnbiased` 改为随机公平）。

## 八、Android 实战：Channel 的正确出场时机

### 8.1 一次性事件（最常见）

不容丢失、只处理一次的事件（导航、Toast、SnackBar），用 `Channel + receiveAsFlow`：

```kotlin
class MyViewModel : ViewModel() {
    private val _events = Channel<UiEvent>(Channel.BUFFERED) // 缓冲：无人收集时事件不丢
    val events = _events.receiveAsFlow()                     // 转 Flow 给 UI

    fun onSaveClicked() {
        viewModelScope.launch { _events.send(UiEvent.NavigateBack) }
    }
}

// UI 侧
lifecycleScope.launch {
    repeatOnLifecycle(Lifecycle.State.STARTED) {
        viewModel.events.collect { handle(it) }
    }
}
```

为什么它比 SharedFlow/StateFlow 更适合这个场景：

- **页面在后台时事件不丢**：collect 被 repeatOnLifecycle 停掉期间，事件安静地躺在缓冲里，回前台立刻补发（`replay=0` 的 SharedFlow 此时会直接丢事件）；
- **不粘**：消费掉就没了，旋转屏幕重新订阅不会重复弹 Toast、重复导航（StateFlow/`replay=1` 的 SharedFlow 会）；
- **恰好一次**：即使误开多个收集器，一个事件也只会被其中一个消费。

`receiveAsFlow()` 与 `consumeAsFlow()` 的区别：前者允许先后存在多个收集器（瓜分元素），后者独占通道、收集器取消时直接 cancel 通道，二者都不能有并发的多个收集器。

### 8.2 任务队列 / 削峰

把点击、上报等突发操作塞进 Channel，由单一 worker 顺序消费，天然串行化，避免并发竞争：

```kotlin
private val clickChannel = Channel<ClickAction>(Channel.UNLIMITED)
init {
    viewModelScope.launch {
        for (action in clickChannel) handleSerially(action) // 严格按序、一次一个
    }
}
```

### 8.3 什么时候不要用 Channel

- **状态**（需要"最新值可随时读"）→ `StateFlow`；
- **广播**（所有订阅者都要收到）→ `SharedFlow`；
- **数据加工管道**（map/filter/重试）→ 冷流 `Flow`。

Channel 的舞台就两个词：**点对点**、**恰好一次**。

## 九、高频面试题

**Q1：Channel 和 Flow 是一个东西吗？它们是什么关系？**

答：不是。Flow 是**数据流的声明式抽象**（源自响应式流思想），描述数据如何产生与加工，以冷流为主，同一冷流每个收集器各自触发一次完整执行；Channel 是**协程间通信的并发原语**（源自 CSP 模型），本质是挂起版的阻塞队列，点对点传递，一个值只被一个接收者消费一次，且可以 close。二者是"整车与引擎"的关系：`channelFlow`、`callbackFlow`、`flowOn`、`buffer` 等 Flow API 底层都靠 Channel 做协程间中转。业务上优先 Flow，需要精确控制"谁发谁收、只收一次"时用 Channel。

**Q2：Channel 有哪几种容量类型？分别什么行为？**

答：五种。① `RENDEZVOUS`（默认，容量 0）：无缓冲，send/receive 必须会合，双方严格同步；② `CONFLATED`：容量 1 且新值覆盖旧值，send 永不挂起，只保留最新值，会丢中间值；③ `BUFFERED`：默认 64 的缓冲（可用系统属性 `kotlinx.coroutines.channels.defaultBuffer` 调整），满了 send 挂起；④ 指定容量 n：精确控制生产者最多超前多少；⑤ `UNLIMITED`：无限缓冲，send 永不挂起、不丢值，但失去背压、有 OOM 风险。

**Q3：CONFLATED Channel 和 StateFlow 都"只留最新值"，有什么区别？**

答：三点。① 消费语义：CONFLATED Channel 的值**取走就没了**（点对点、消费即删除），StateFlow 的 value **一直可读**且所有订阅者都能收到（多播）；② StateFlow 有初始值且自动去重，Channel 都没有；③ StateFlow 永不完成，Channel 可以 close。本质区别还是"事件管道"和"状态容器"的区别：CONFLATED Channel 是只保留最新一条的传送带，StateFlow 是实时更新的公告牌。

**Q4：close() 和 cancel() 有什么区别？**

答：`close()` 是**发送端**的优雅收尾：插入关闭标记，缓冲里已有的元素仍可被接收完，之后 `for` 循环正常退出、再 receive 抛 `ClosedSendChannelException`（有 cause 时抛 cause）。`cancel()` 是**接收端**的立即终止：缓冲中未消费的元素全部丢弃，通道彻底作废。丢弃元素时若配置了 `onUndeliveredElement` 会对每个未送达元素回调，用于释放资源。需要不抛异常的接收可用 `receiveCatching()` 判断 `ChannelResult`。

**Q5：send 和 trySend 有什么区别？trySend 什么时候会失败？**

答：`send` 是挂起函数，缓冲满（SUSPEND 策略）时挂起等空位；`trySend` 非挂起，立即返回 `ChannelResult`，塞不进去返回失败。`trySend` 失败的情况：通道已满且策略为 SUSPEND（如 RENDEZVOUS 通道没有正在等待的接收者时）、通道已关闭。它的价值在**非协程环境**（系统回调、监听器）里向通道投递数据——`callbackFlow` 里回调线程用 `trySend` 就是这个原因；如果既想不挂起又不想失败，配 `UNLIMITED` 或 `DROP_OLDEST`。

**Q6：ViewModel 的一次性事件为什么推荐 Channel 而不是 SharedFlow？**

答：一次性事件要求"**不丢、不重、恰好处理一次**"。`replay=0` 的 SharedFlow 在无订阅者时（页面后台、collect 被 repeatOnLifecycle 停掉）发出的事件**直接丢失**；`replay=1` 或 StateFlow 又是粘性的，旋转屏幕重新订阅会**重复触发**（Toast 弹两次、导航执行两次）。而 `Channel(BUFFERED).receiveAsFlow()`：无人收集时事件存在缓冲里不丢，回前台补发；消费后即删除不粘；点对点保证只被处理一次。三个要求全部满足。

**Q7：什么是扇入、扇出？Channel 的扇出为什么天然是负载均衡？**

答：扇出（fan-out）是多个协程从同一个 Channel 接收，每个元素只被其中一个消费者拿到，多个挂起等待的接收者按 FIFO 公平轮流获得元素，天然形成工作队列/负载均衡——处理快的 worker 自然多领任务。扇入（fan-in）是多个协程向同一个 Channel 发送，多路数据汇聚到一个消费者。注意扇出时消费者要用 `for (x in channel)` 而非 `consumeEach`，后者在单个消费者取消时会 cancel 整个通道，殃及其他消费者。

**Q8：onUndeliveredElement 是干什么的？什么场景必须配？**

答：它是元素"未能送达"时的清理回调：元素成功 send 进通道，但最终没有被任何接收者正常消费——通道被 cancel 时缓冲里还有值、接收者在拿到值和处理值之间被取消、send 挂起中被取消等——回调会对每个这样的元素执行。当元素持有需要显式释放的资源（文件句柄、Bitmap、Socket、数据库连接）时必须配置，否则这些资源会随着被丢弃的元素静默泄漏。

**Q9：select 表达式是什么？和 Channel 怎么配合？**

答：`select` 可以**同时挂起等待多个通道/协程的事件**，哪个先就绪就执行哪个分支，类似 Go 的 select 或 NIO 的 Selector。每个挂起函数都有对应的 select 子句：`receive`→`onReceive`、`send`→`onSend`、`receiveCatching`→`onReceiveCatching`、`delay`→`onTimeout`。典型用途：同时监听多个数据源取最先到达者、给 receive 加超时、缓冲满时优雅降级。默认多个子句同时就绪时偏向靠前的分支，`selectUnbiased` 可改为随机选择。

**Q10：produce 是什么？它和 flow {} 像在哪、差在哪？**

答：`produce` 是 Channel 侧的生产者构建器：启动一个协程执行块内的 `send`，返回 `ReceiveChannel`，块正常结束自动 close、异常结束以异常关闭，是"协程 + 通道 + 自动收尾"的打包。它和 `flow {}` 的相似点是都封装了生产逻辑；本质差异是**温度与执行模型**：`produce` 调用即启动协程开始生产（热，需要 `CoroutineScope`，数据只有一份，多个接收者瓜分），`flow {}` 只是描述（冷，不需要 scope，谁 collect 谁触发一次独立执行）。`Flow.produceIn(scope)` 可以把冷流转成 produce 通道，`ReceiveChannel.receiveAsFlow()` 反向转回 Flow。

## 参考

- [Kotlin 官方文档：Channels](https://kotlinlang.org/docs/channels.html)
- [Kotlin 官方文档：Select expression](https://kotlinlang.org/docs/select-expression.html)
- [kotlinx.coroutines 源码：Channel.kt / BufferedChannel.kt](https://github.com/Kotlin/kotlinx.coroutines/tree/master/kotlinx-coroutines-core/common/src/channels)
- 姊妹篇：[Kotlin Flow 全面详解](/posts/Kotlin-Flow-全面详解/)
