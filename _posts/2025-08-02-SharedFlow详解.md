---
categories: [知识点]
title: SharedFlow 详解
date: 2025-07-27 13:47:00 +0800
pin: false
last_modified_at: 2025-08-02 15:30:00 +0800
tags: [android]
keywords: [flow,SharedFlow]
---

在 Kotlin 协程中，`SharedFlow` 是一种非常强大且灵活的**热流 (Hot Flow)**，它旨在解决 `BroadcastChannel` 的一些痛点，并提供比 `StateFlow` 更通用的多播能力。你可以把它看作是 `StateFlow` 和 `Channel` 的结合体，拥有它们各自的优点，并在此基础上提供了更精细的控制。

------


## SharedFlow 核心特性详解

`SharedFlow` 就像一个广播电台，它的生产者不断地“播放”数据，而多个“听众”（收集器）可以同时“收听”这些数据。即使新的听众中途加入，他们也可以选择从某个历史点开始“收听”（如果配置了重放）。

### 1. 热流 (Hot Flow)

- **独立于收集器存在**：与冷流 (`Flow`) 不同，`SharedFlow` 的生产者即使在没有活跃收集器的情况下也会继续运行并发出值。
- **立即发送**：当一个收集器开始收集时，它会立即收到 `SharedFlow` 根据其配置（如重放）所拥有的最新值或历史值。

### 2. 多播 (Multicast)

- **多个订阅者**：`SharedFlow` 允许多个协程同时收集同一个流。每个订阅者都会收到相同的事件序列（或根据重放配置收到部分历史事件）。
- **事件广播**：这使得 `SharedFlow` 非常适合作为事件总线或在多个组件之间广播数据更新。

### 3. 可配置的重放 (Replay)

- **`replay` 参数**：这是 `SharedFlow` 最强大的特性之一。当你创建 `MutableSharedFlow` 时，可以指定 `replay` 参数，它表示 `SharedFlow` 会保留多少个最近发出的值。
- **新订阅者的行为**：当一个新的收集器开始收集时，它会首先收到这些被重放的历史值，然后才开始接收新的值。
- **默认 `replay = 0`**：这意味着默认情况下，`SharedFlow` 不会重放任何历史值。新订阅者只会收到它订阅之后发出的值。
- **用途**：非常适用于“粘性事件”或当新加入的订阅者需要立即获取当前状态的场景（例如，网络连接状态，但又不需要像 `StateFlow` 那样始终保持一个“值”）。

### 4. 可配置的缓冲区 (Buffer)

- **`extraBufferCapacity` 参数**：除了重放缓冲区之外，`SharedFlow` 还有一个“额外缓冲区”。这个缓冲区用于存储那些已经发出但尚未被所有订阅者处理的值。
- **背压处理**：如果订阅者处理值的速度跟不上生产者的速度，这些值会暂时存储在额外缓冲区中。当缓冲区满时，`send()` 操作会根据 `onBufferOverflow` 策略进行处理。
- **`onBufferOverflow` 策略**：定义当缓冲区溢出时如何处理新发出的值：
  - **`SUSPEND` (默认)**：发送操作会挂起，直到缓冲区有空间。这提供了背压机制。
  - **`DROP_OLDEST`**：丢弃缓冲区中最旧的值，为新值腾出空间。
  - **`DROP_LATEST`**：丢弃新发出的值，不将其添加到缓冲区。

### 5. 单向性 (Unidirectionality)

- `MutableSharedFlow` 具有 `emit()` 方法用于发送值。
- `SharedFlow` 接口则只提供 `collect()` 方法用于收集值。这强制了生产者和消费者之间的分离，提供了更好的封装。

### 6. 永不完成

- 与 `Flow` 不同，`SharedFlow` 和 `StateFlow` 一样，永远不会“完成”。它会持续运行并发出值，直到被垃圾回收。

### 7. 对比 `StateFlow` 和 `Channel`

- **VS `StateFlow`**：
  - `StateFlow` 总是持有一个**当前值**，并且只重放**最新的一个值** (`replay = 1`)，且会自动**去重**。
  - `SharedFlow` 更通用，可以重放**多个**值 (`replay >= 0`)，不强制持有“当前值”概念（除非 `replay = 1`），且默认**不去重**（除非手动实现）。
  - `StateFlow` 是 `SharedFlow` 的一个特例：`MutableStateFlow` 本质上就是 `MutableSharedFlow(replay = 1, onBufferOverflow = DROP_OLDEST)`，并增加了去重功能。
- **VS `Channel`**：
  - `Channel` 通常是**点对点**的通信（一个元素只被一个消费者接收）。
  - `SharedFlow` 是**多播**的（一个元素可以被所有活跃消费者接收）。
  - `Channel` 可以关闭并表示完成；`SharedFlow` 不会完成。

------



## SharedFlow 典型使用场景

`SharedFlow` 的灵活性使其适用于多种场景，尤其是需要广播事件或共享不可变状态的场景：

1. **一次性事件 (One-Shot Events)**：当需要从 ViewModel 向 UI 发送一次性事件时（例如，显示 Toast 消息、导航事件、弹出 Snackbar），`SharedFlow` 是一个理想选择，特别是当 `replay` 为 0 时。如果配置了 `replay = 1`，它也可以模拟 `LiveData` 的粘性事件行为。

   ```kotlin
   // ViewModel
   private val _events = MutableSharedFlow<MyEvent>()
   val events: SharedFlow<MyEvent> = _events.asSharedFlow()
   
   fun onUserClickedSomething() {
       viewModelScope.launch {
           _events.emit(MyEvent.ShowToast("Button clicked!"))
       }
   }
   
   // UI (Fragment/Activity)
   lifecycleScope.launch {
       repeatOnLifecycle(Lifecycle.State.STARTED) {
           viewModel.events.collect { event ->
               when (event) {
                   is MyEvent.ShowToast -> Toast.makeText(context, event.message, Toast.LENGTH_SHORT).show()
               }
           }
       }
   }
   ```

2. **共享不可变数据流**：当多个组件需要监听同一个不可变数据流时，例如实时更新的配置信息、网络连接状态、用户登录状态等。

3. **事件总线 (Event Bus)**：在应用程序的不同部分之间传递事件，实现松散耦合。

4. **取代 `BroadcastChannel`**：`BroadcastChannel` 已经被弃用，官方推荐使用 `SharedFlow` 来实现其功能。

------



## 创建和使用 SharedFlow

### 创建 MutableSharedFlow

```kotlin
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.delay

fun main() = runBlocking {
    // 创建一个 MutableSharedFlow，不重放历史值，没有额外缓冲区，默认 SUSPEND 策略
    val eventFlow = MutableSharedFlow<String>()

    // 创建一个 MutableSharedFlow，重放最近的 2 个值，额外缓冲区容量为 5，当缓冲区满时丢弃最旧的值
    val stickyEventFlow = MutableSharedFlow<String>(
        replay = 2,
        extraBufferCapacity = 5,
        onBufferOverflow = kotlinx.coroutines.channels.BufferOverflow.DROP_OLDEST
    )

    // 作为 SharedFlow 公开，只读
    val publicEventFlow: SharedFlow<String> = eventFlow.asSharedFlow()

    // 生产者发送事件
    val producerJob = launch {
        println("Producer starts emitting...")
        eventFlow.emit("Event 1")
        delay(100)
        eventFlow.emit("Event 2")
        delay(100)
        eventFlow.emit("Event 3") // 只有 Event 3 会被订阅者 1 收到 (因为它没有重放)
        delay(100)
        stickyEventFlow.emit("Sticky 1")
        delay(10)
        stickyEventFlow.emit("Sticky 2")
        delay(10)
        stickyEventFlow.emit("Sticky 3") // Sticky 2 和 Sticky 3 会被订阅者 2 收到 (replay=2)
    }

    // 订阅者 1 (立即订阅)
    val collector1 = launch {
        println("Collector 1 started...")
        publicEventFlow.collect { event ->
            println("Collector 1 received: $event")
        }
    }

    delay(250) // 等待一些事件发出

    // 订阅者 2 (延迟订阅，观察 replay 效果)
    val collector2 = launch {
        println("Collector 2 started...")
        stickyEventFlow.collect { event ->
            println("Collector 2 received (sticky): $event")
        }
    }

    delay(200) // 等待更多事件和收集
    producerJob.cancel()
    collector1.cancel()
    collector2.cancel()
}
```

------



## SharedFlow 的关键参数和其影响

- **`replay`**:
  - `replay = 0` (默认): 最常用于一次性事件。新收集器只会收到订阅后发出的值。
  - `replay = 1`: 类似于 `StateFlow`，新收集器会收到最新发出的一个值。但与 `StateFlow` 不同，它不提供自动去重。
  - `replay > 1`: 新收集器会收到最近 `replay` 数量的历史值。
- **`extraBufferCapacity`**:
  - 定义了在所有收集器处理完之前可以缓冲多少个值。
  - 如果 `replay + extraBufferCapacity` 为 0，则 `emit` 操作是挂起的，直到有收集器准备好接收。
- **`onBufferOverflow`**:
  - `SUSPEND` (默认): 如果缓冲区满了，`emit` 会挂起。这提供了背压，确保所有事件都被处理。
  - `DROP_OLDEST`: 丢弃缓冲区中最老的值，为新值腾出空间。适合于那些不需要处理所有中间状态，只关心最新状态的场景（例如，UI 更新）。
  - `DROP_LATEST`: 丢弃新发出的值。这可能会导致数据丢失，应谨慎使用。

------



## 总结

`SharedFlow` 是 Kotlin 协程中一个非常通用的热流实现，它结合了 `StateFlow` 的状态共享能力和 `Channel` 的事件传递能力，并通过 `replay` 和 `onBufferOverflow` 参数提供了高度的灵活性。

- 当你需要**多播事件**给多个订阅者时。
- 当你需要**重放历史事件**给新的订阅者时。
- 当你需要实现**一次性事件**（如 Toast、导航）且不希望它们像 `StateFlow` 那样保持“当前值”时。
- 当你需要替换已废弃的 `BroadcastChannel` 时。

`SharedFlow` 都是一个比 `StateFlow` 或 `Channel` 更优或更灵活的选择。理解并善用其配置参数是发挥其强大功能，构建健壮和响应式并发应用程序的关键。