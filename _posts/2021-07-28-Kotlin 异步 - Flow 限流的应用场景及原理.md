---
categories: [转载, Android]
title: Kotlin 异步 - Flow 限流的应用场景及原理
date: 2021-07-28 10:00:00 +0800
pin: false
tags: [转载, android]
keywords: [Kotlin, Flow, 协程, 防抖, 限流]
---

> 本文转载自 [Kotlin 异步 | Flow 限流的应用场景及原理](https://juejin.cn/post/6989782281191686180)。版权归原作者所有，此处仅作个人学习备份。

异步数据流中的生产者可能会生产过多的数据，而消费者并不需要那么多，所以限流就有用武之地了。App 开发中有一些常见的限流场景，比如搜索框防抖、点击事件防抖、防过度刷新。这一篇就以这三个场景为线索探究一下如何实现及背后的原理

阅读本篇需要了解 Flow 的基础知识。关于这些知识的详细介绍可以点击[Kotlin 异步 | Flow 应用场景及原理](https://juejin.cn/post/6989032238079803429)，现援引如下：

1. 异步数据流可以理解为一条时间轴上按序产生的数据，它可用于表达**多个连续的异步过程**。
2. 异步数据流也可以用"生产者/消费者"模型来理解，生产者和消费者之间就好像有一条管道，生产者从管道的一头插入数据，消费者从另一头取数据。因为管道的存在，数据是有序的，遵循先进先出的原则。
3. Kotlin 中的`suspend`方法用于表达一个异步过程，而`Flow`用于表达多连续个异步过程。`Flow`是冷流，冷流不会发射数据，直到它被收集的那一刻，所以冷流是"声明式的"。
4. 当`Flow`被收集的瞬间，数据开始生产并被发射出去，通过流收集器`FlowCollector`将其传递给消费者。流和流收集器是成对出现的概念。流是一组按序产生的数据，数据的产生表现为通过流收集器发射数据，在这里流收集器像是流数据容器（虽然它不持有任何一条数据），它定义了如何将数据传递给消费者。
5. 异步数据流中，生产者和消费者之间可以插入**中间消费者**。中间消费者建立了流上的**拦截并转发**机制：新建下游流，它生产数据的方式是通过收集上游数据，并转发到一个带有发射数据能力的 lambda 中。拥有多个中间消费者的流就像"套娃"一样，下游流套在上游流外面。中间消费者通过这种方式拦截了原始数据，就可以对其做任意变换再转发给下游消费者。
6. 所有能触发收集数据动作的消费者称为**终端消费者**，它就像点燃鞭炮的星火，使得被若干个中间消费者套娃的流从外向内（从下游到上游）一个个的被收集，最终传导到原始流，触发数据的发射。
7. 默认情况下，流中生产和消费数据是在同一个线程中进行的。但可以通过`flowOn()`改变上游流执行的线程，这并不影响下游流所执行的线程。
8. `Flow`中生产和消费数据的操作都被包装在用 suspend 修饰的 lambda 中，用协程就可以轻松的实现异步生产，异步消费。

## 搜索框防抖

"在搜索框中输入内容，然后点击搜索按钮，经过一段等待，搜索结果以列表形式展现"。很久以前的 app 是这样进行搜索的。

现在搜索体验就要好很多了，不需要手动点击搜索按钮，输入内容后，搜索是自动触发。

为了实现这效果就得监听输入框内容的变化：

```
// 构建监听器
val textWatcher = object : android.text.TextWatcher {
    override fun afterTextChanged(s: Editable?) {}
    override fun beforeTextChanged(text: CharSequence?,start: Int,count: Int,after: Int) {}
    override fun onTextChanged(text: CharSequence?, start: Int, before: Int, count: Int) {
        search(text.toString())
    }
}
// 设置输入框内容监听器
editText.addTextChangedListener(textWatcher)
// 访问网络进行搜索
fun search(key: String) {}
```

这样实现有一个缺点，会进行多次无效的网络访问。比如搜索"kotlin flow"时，`onTextChanged()`会被回调 10 次，就触发了 10 次网络请求，而只有最后一次才是有效的。

优化方案也很容易想到，只有在用户停止输入时才进行请求。但并没有这样的回调通知业务层用户已经停止输入。。。

那就只能设置一个超时，即用户多久未输入内容后就判定已停止输入。

但实现起来还挺复杂的：得在每次输入框内容变化后启动超时倒计时，若倒计时归零时输入框内容没有发生新变化，则用输入框当前内容发起请求，否则将倒计时重置，重新开始倒计时。

在需求迭代中，会有时间去实现这么一个复杂的小功能？

还好 Kotlin 的 Flow 替我们封装了这个功能。

> 用流的思想重新理解上面的场景：输入框是流数据的生产者，其内容每变化一次，就是在流上生产了一个新数据。但并不是每一个数据都需要被消费，所以得做"限流"，即丢弃一切发射间隔过短的数据，直到生产出某个数据之后一段时间内不再有新数据。

Kotlin 预定义了一些限流方法，`debounce()`就非常契合当前场景。为了使用`debounce()`，得先把回调转换成流：

```
// 构建输入框文字变化流
fun EditText.textChangeFlow(): Flow<Editable> = callbackFlow {
    // 构建输入框监听器
    val watcher = object : TextWatcher {
        override fun afterTextChanged(s: Editable?) {} 
        override fun beforeTextChanged( s: CharSequence?, start: Int, count: Int, after: Int ) { }
        // 在文本变化后向流发射数据
        override fun onTextChanged( s: CharSequence?, start: Int, before: Int, count: Int ) { 
            s?.let { offer(it) }
        }
    }
    addTextChangedListener(watcher) // 设置输入框监听器
    awaitClose { removeTextChangedListener(watcher) } // 阻塞以保证流一直运行
}
```

为 EditText 扩展了一个方法，用于构建一个输入框文字变化流。

其中`callbackFlow {}`是系统预定义的顶层方法，它用于将回调组织成流。只需要在其内部构建回调实例并注册之，然后在生产数据的回调方法中调用`offer()`发射数据即可。当前场景中，将输入框每次文字变化作为流数据发射出去。

`callbackFlow { lambda }`中最后一句`awaitClose {}`是必不可少的，它阻塞了当前协程，保证流不会结束，即让流一直存活处于等待数据状态，否则 lambda 一执行完毕，流就会关闭。

然后就可以像这样使用：

```
editText.textChangeFlow() // 构建输入框文字变化流
    .filter { it.isNotEmpty() } // 过滤空内容，避免无效网络请求
    .debounce(300) // 300ms防抖
    .flatMapLatest { searchFlow(it.toString()) } // 新搜索覆盖旧搜索
    .flowOn(Dispatchers.IO) // 让搜索在异步线程中执行
    .onEach { updateUi(it) } // 获取搜索结果并更新界面
    .launchIn(mainScope) // 在主线程收集搜索结果

// 更新界面
fun updateUi(it: List<String>) {}
// 访问网络进行搜索
suspend fun search(key: String): List<String> {}
// 将搜索关键词转换成搜索结果流
fun searchFlow(key: String) = flow { emit(search(key)) }
```

其中`filter()`是流的中间消费者：

```
public inline fun <T> Flow<T>.filter(crossinline predicate: suspend (T) -> Boolean): Flow<T> = transform { value ->
    if (predicate(value)) return@transform emit(value)
}
```

filter() 利用`transform()`构建了一个下游流，它会收集上游数据，并且通过`predicate`过滤之，只有满足条件的数据才会被发射。关于`transform()`的详细解释可以点击[Kotlin 进阶 | 异步数据流 Flow 的使用场景](https://juejin.cn/post/6989032238079803429)。

其中的`flatMapLatest()`也是中间消费者，flatMap 的意思是将上游流中的一个数据转换成一个新的流，当前场景下即是将 key 通过网络请求转换成搜索结果`Flow<List<String>>`。lateest 的意思是如果一个新的搜索请求到来时，上一个请求还未返回，则取消之，即总是展示最新输入内容的搜索结果。

`flatMapLatest()`源码如下：

```
public inline fun <T, R> Flow<T>.flatMapLatest(@BuilderInference crossinline transform: suspend (value: T) -> Flow<R>): Flow<R> =
    transformLatest { emitAll(transform(it)) }
    
public fun <T, R> Flow<T>.transformLatest(@BuilderInference transform: suspend FlowCollector<R>.(value: T) -> Unit): Flow<R> =
    ChannelFlowTransformLatest(transform, this)

internal class ChannelFlowTransformLatest<T, R>(
    private val transform: suspend FlowCollector<R>.(value: T) -> Unit,
    flow: Flow<T>,
    context: CoroutineContext = EmptyCoroutineContext,
    capacity: Int = Channel.BUFFERED,
    onBufferOverflow: BufferOverflow = BufferOverflow.SUSPEND
) : ChannelFlowOperator<T, R>(flow, context, capacity, onBufferOverflow) {
    override fun create(context: CoroutineContext, capacity: Int, onBufferOverflow: BufferOverflow): ChannelFlow<R> =
        ChannelFlowTransformLatest(transform, flow, context, capacity, onBufferOverflow)

    override suspend fun flowCollect(collector: FlowCollector<R>) {
        assert { collector is SendingCollector }
        flowScope {
            var previousFlow: Job? = null
            // 收集上游数据
            flow.collect { value ->
                // 1. 若新数据到来，则取消上一次
                previousFlow?.apply {
                    cancel(ChildCancelledException())
                    join()
                }
                // 2. 启动协程处理当前数据
                previousFlow = launch(start = CoroutineStart.UNDISPATCHED) {
                    collector.transform(value)
                }
            }
        }
    }
}
```

在收集数据时，每次都会启动新协程执行数据变换操作，并记录协程的 Job，待下一个数据到来时，取消上一次的 Job。

demo 场景中的`launchIn()`是一个终端消费者：

```
// 启动协程并在其中收集数据
public fun <T> Flow<T>.launchIn(scope: CoroutineScope): Job = scope.launch {
    collect() 
}
// 用空收集器收集数据
public suspend fun Flow<*>.collect(): Unit = collect(NopCollector)

// 空收集器是一个不会再向下游发射数据的 FlowCollector
internal object NopCollector : FlowCollector<Any?> {
    override suspend fun emit(value: Any?) {
        // does nothing
    }
}
```

使用 launchIn() 将启动协程收集数据这一细节隐藏在了内部，所以就可以使外部代码保持简洁的链式调用。下面这两段代码是等价的：

```
mainScope.launch {
    editText.textChangeFlow() 
        .filter { it.isNotEmpty() } 
        .debounce(300) 
        .flatMapLatest { searchFlow(it.toString()) } 
        .flowOn(Dispatchers.IO) 
        .collect { updateUi(it) }
}

editText.textChangeFlow() 
    .filter { it.isNotEmpty() } 
    .debounce(300) 
    .flatMapLatest { searchFlow(it.toString()) }
    .flowOn(Dispatchers.IO) 
    .onEach { updateUi(it) } 
    .launchIn(mainScope)
```

但由于 launchIn() 不会再向下游发射数据，所以它一般配合`onEach {}`一起使用来完成消费数据。

## 点击事件防抖

app 中点击事件响应逻辑一般是弹出界面或是网络请求。

如果用飞快的速度连续点击两次，就会弹出两个界面或是请求了两次网络。

为了避免这种情况的方法，需要做点击事件防抖，即在一定时间间隔内只响应第一次点击事件。可以这样实现：

```
val FAST_CLICK_THRSHOLD = 300

fun View.onDebounceClickListener( block: (T) -> Unit ) {
    // 如果不是快速点击，则响应点击逻辑
    setOnClickListener { if (!it.isFastClick) block() }
}

// 判断是否快速点击
fun View.isFastClick(): Boolean {
    val currentTime = SystemClock.elapsedRealtime()
    if (currentTime - this.triggerTime >= FAST_CLICK_THRSHOLD) {
        this.triggerTime = currentTime
        return false
    } else {
        return true
    }
}

// 记录上次点击时间
private var View.triggerTime: Long
    get() = getTag(R.id.click_trigger) as? Long ?: 0L
    set(value) = setTag(R.id.click_trigger, value)
```

做了 3 个扩展，完成了点击事件防抖。将每次有效点击的时间保存在 View 的 tag 中，每次点击时都判断当前时间和上次时间差，如果超过阈值则允许点击。

> 用流的思想重新样理解这个场景：每个点击事件都是流上的新数据。要对流做限流，即发射第一个数据，然后抛弃时间窗口中紧跟其后的所有数据，直到新的时间窗口到来。

很遗憾，Kotlin 未提供系统级实现，但自定义一个也很简单：

```
fun <T> Flow<T>.throttleFirst(thresholdMillis: Long): Flow<T> = flow {
    var lastTime = 0L // 上次发射数据的时间
    // 收集数据
    collect { upstream ->
        // 当前时间
        val currentTime = System.currentTimeMillis()
        // 时间差超过阈值则发送数据并记录时间
        if (currentTime - lastTime > thresholdMillis) {
            lastTime = currentTime
            emit(upstream)
        }
    }
```

throttleFirst() 使用`flow {}`构建了一个下游流并且收集了上游数据，只有当两次数据时间差超过阈值时，才发射数据。

然后将点击事件组织成流：

```
fun View.clickFlow() = callbackFlow {
    setOnClickListener { offer(Unit) }
    awaitClose { setOnClickListener(null) }
}
```

就可以像这样使用：

```
view.clickFlow()
    .throttleFirst(300)
    .onEach { // 点击事件响应 }
    .launchIn(mainScope)
```

## 防过度刷新

想象这样一个场景：百万级别的直播间，有一个展示最近加入观众的列表。每个新观众加入，都通过回调 onUserIn(uid: String) 通知，需通过 uid 请求网络拉取用户信息并更新在观众列表中。

对于百万级别的直播间，每一秒可能有成百上千的观众加入，若不做限制，每秒几百上千次的网络访问就很离谱。

产品端给出的限流方案：每一秒钟刷新一次列表，且只展示这一秒内最后加入直播间的那个人。

> 用流重新理解这个场景：onUserIn() 回调是流数据的生产者。要做限流，即在每个固定时间间隔内，只发射最后的 1 个数据，并丢弃其余的数据。

kotlin 提供了系统级别的实现`sample()`：

```
// 将回调转换成流
fun userInFlow() = callbackFlow {
    val callback = object : UserCallback() {
        override fun onUserIn(uid: String) { offer(uid) }
    }
    setCallback(callback)
    awaitClose { setCallback(null) }
}

// 观众列表限流
userInFlow()
    .sample(1000)
    .onEach { fetchUser(it) }
    .flowOn(Dispatchers.IO)
    .onEach { updateAudienceList() }
    .launchIn(mainScope)
```

（这个实现犯了一个和上篇倒计时 Flow 同样的错误，看出来了吗？后续篇章会详细分析）

## 总结

用异步数据流的思想理解下面这些场景，使得问题求解变得简单：

1. 搜索框防抖：丢弃一切发射间隔过短的数据，直到生产出某个数据之后一段时间内不再有新数据。
2. 点击事件防抖：发射第一个数据，然后抛弃时间窗口中紧跟其后的所有数据，直到新的时间窗口到来。
3. 在每个固定时间间隔内，只发射最后的 n 个数据，并丢弃其余的数据。

可以从两个维度区别上述限流方案：

1. 发射数据是否有固定时间间隔。
2. 新的数据是否会导致重启倒计时。

| 限流方案 | 固定间隔 | 重启倒计时 |
| --- | --- | --- |
| 搜索框防抖 | false | true |
| 点击事件防抖 | false | false |
| 防过度刷新 | true | false |

* 只要输入连续不停止，则永远也不会发送数据。所以输入框防抖发射数据是没有固定时间间隔的。搜索框防抖会重启倒计时，而且是每一个新数据的到来都会触发重新倒计时。
* 只要不发生点击事件，数据就不会发射。所以点击事件防抖发射数据是没有固定时间间隔的。点击事件防抖中，第一个数据产生时，倒计时开始，它并不会因为后续事件的到来而重新倒计时，在倒计时内除第一个数据外的其他数据都被抛弃。
* 不管有没有新数据，每个固定的时间间隔内都会发射一个新数据，防过度刷新时有固定时间间隔的。
