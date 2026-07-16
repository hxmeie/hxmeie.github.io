---
categories: [知识点]
title: ThreadLocal 详解：最新 JDK 源码剖析、内存泄漏真相与 ScopedValue 新时代
date: 2026-07-16 16:38:00 +0800
pin: false
tags: [android, java, kotlin, threadlocal]
keywords: [threadlocal, threadlocalmap, 内存泄漏, 弱引用, inheritablethreadlocal, scopedvalue, 虚拟线程, aslooper, ascontextelement, 0x61c88647]
description: 基于最新 JDK 源码逐行剖析 ThreadLocal：ThreadLocalMap 的开放寻址与魔数 0x61c88647、Entry 弱引用设计与内存泄漏的真正原因、InheritableThreadLocal 与 TTL、Android Looper 与协程 asContextElement 实践，以及 JDK 25 正式转正的 ScopedValue 如何在虚拟线程时代取代 ThreadLocal，文末附高频面试问答。
---

`ThreadLocal` 大概是"每个人都会用、但很少有人真正读过源码"的类。它出现在无数面试题里：为什么 key 是弱引用？内存泄漏到底怎么发生的？为什么线程池必须 `remove()`？而在 2025 年之后，这个话题又多了一个新维度——**JDK 25 里 `ScopedValue` 正式转正（JEP 506），官方明确把它定位为虚拟线程时代 ThreadLocal 的继任者**。

这篇文章基于最新 JDK 源码（`ThreadLocal.java` 的核心实现自 JDK 8 以来基本稳定，本文对照 JDK 21/25 源码），从使用、源码、内存泄漏、跨线程传递讲到 Android 与 Kotlin 协程中的实践，最后聊聊 ScopedValue。文末附面试问答。

> 阅读本文需要基本的 Java 引用类型知识（强/软/弱/虚引用）。ThreadLocal 的设计本质是一场"用弱引用对抗内存泄漏"的攻防战，弱引用是理解全文的钥匙。
{: .prompt-info }

## 一、ThreadLocal 是什么

### 1.1 一句话定义

**`ThreadLocal` 提供"线程局部变量"：同一个 `ThreadLocal` 对象，每个线程读写的都是自己独立的副本，线程之间互不可见、互不干扰。**

它解决的不是"共享变量的同步问题"，而是**"让变量根本不共享"**——用空间换安全：

- 加锁（`synchronized` / `Lock`）：多个线程排队访问**同一份**数据，牺牲时间；
- `ThreadLocal`：每个线程持有**自己的一份**数据，牺牲空间，无锁无竞争。

### 1.2 典型使用场景

1. **非线程安全对象的复用**：`SimpleDateFormat` 是经典案例（非线程安全，又不想每次 new）；
2. **调用链上下文传递**：一次请求经过 N 层方法，把 traceId、用户身份、数据库连接、事务上下文放进 ThreadLocal，避免每层方法都加参数——Spring 的事务管理、MDC 日志上下文都是这么做的；
3. **框架级"每线程单例"**：Android 的 `Looper`、`Choreographer`，Java 的 `Random` 早期实现等。

### 1.3 基本使用

```kotlin
// 推荐用 withInitial 提供初始值（首次 get 时惰性调用）
private val dateFormat: ThreadLocal<SimpleDateFormat> =
    ThreadLocal.withInitial { SimpleDateFormat("yyyy-MM-dd HH:mm:ss") }

fun format(date: Date): String = dateFormat.get().format(date)
```

```java
ThreadLocal<String> traceId = new ThreadLocal<>();

traceId.set("req-10086");        // 只对当前线程可见
String id = traceId.get();       // 其他线程 get() 返回 null（或 initialValue）
traceId.remove();                // 用完清理 —— 线程池场景是必须的，后文详述
```

Kotlin 中还可以用扩展让它更顺手：

```kotlin
/**
 * ThreadLocal 委托属性扩展，允许用 var 语法读写线程局部变量。
 * Property delegate extension for ThreadLocal, enabling var syntax access.
 * @param thisRef 属性所属对象
 * @param property 属性元数据
 * @return T? 当前线程存储的值
 */
operator fun <T> ThreadLocal<T>.getValue(thisRef: Any?, property: KProperty<*>): T? = get()

operator fun <T> ThreadLocal<T>.setValue(thisRef: Any?, property: KProperty<*>, value: T?) = set(value)

// 使用：像普通变量一样读写，实际是线程隔离的
var currentUser: User? by ThreadLocal<User?>()
```

## 二、源码剖析：数据到底存在哪

### 2.1 最容易搞反的一点：Map 在 Thread 里，不在 ThreadLocal 里

很多人的直觉模型是：`ThreadLocal` 内部有一个 `Map<Thread, T>`，以线程为 key 存值。**早期 JDK（1.3 之前的设计雏形）确实类似这样，但现代 JDK 完全相反**：

```java
// java.lang.Thread —— 每个线程对象自己持有一个 map
public class Thread implements Runnable {
    /* ThreadLocal values pertaining to this thread. This map is maintained
     * by the ThreadLocal class. */
    ThreadLocal.ThreadLocalMap threadLocals = null;

    // InheritableThreadLocal 用的是另一个独立的 map
    ThreadLocal.ThreadLocalMap inheritableThreadLocals = null;
}
```

真实结构是：**每个 `Thread` 持有一个 `ThreadLocalMap`，map 的 key 是 `ThreadLocal` 对象本身，value 是存的值**。

```
Thread A ──> ThreadLocalMap A ──> { tlUser: userA, tlTrace: "req-1" }
Thread B ──> ThreadLocalMap B ──> { tlUser: userB, tlTrace: "req-2" }
                                     ↑ key 是同一个 ThreadLocal 实例
```

这个"倒转"的设计有三个好处：

1. **无锁**：map 归线程私有，只有本线程访问，天然线程安全，不需要任何同步；
2. **生命周期正确**：线程死了，它的 map 随线程对象一起被回收，数据不会残留在某个全局结构里；
3. **容量合理**：map 的条目数 = 该线程用到的 ThreadLocal 个数（通常很少），而不是"全局线程数"。

### 2.2 get / set 的完整流程

```java
// java.lang.ThreadLocal（JDK 21/25，节选）
public T get() {
    return get(Thread.currentThread());
}

private T get(Thread t) {
    ThreadLocalMap map = getMap(t);          // 拿到当前线程的 threadLocals
    if (map != null) {
        ThreadLocalMap.Entry e = map.getEntry(this); // 以 this（ThreadLocal 自己）为 key 查找
        if (e != null) {
            @SuppressWarnings("unchecked")
            T result = (T) e.value;
            return result;
        }
    }
    return setInitialValue(t);               // map 不存在或没有条目 → 走 initialValue()
}

public void set(T value) {
    Thread t = Thread.currentThread();
    ThreadLocalMap map = getMap(t);
    if (map != null) {
        map.set(this, value);
    } else {
        createMap(t, value);                 // 首次 set 时才创建 map（惰性）
    }
}
```

流程非常直白：`get`/`set` 永远先拿**当前线程**的 map，再以 **ThreadLocal 实例自身**为 key 操作。所谓"线程隔离"没有任何魔法，纯粹是因为**不同线程拿到的是不同的 map**。

### 2.3 ThreadLocalMap：一个为 ThreadLocal 定制的哈希表

`ThreadLocalMap` 是 `ThreadLocal` 的静态内部类，它**不是** `HashMap`，而是一个高度定制的哈希表，有三个显著特点：

**特点一：Entry 继承 WeakReference，key 是弱引用**

```java
static class Entry extends WeakReference<ThreadLocal<?>> {
    /** The value associated with this ThreadLocal. */
    Object value;

    Entry(ThreadLocal<?> k, Object v) {
        super(k);      // key（ThreadLocal 对象）被弱引用持有
        value = v;     // value 是普通强引用
    }
}
```

这是整个类设计中最精妙、也是面试问得最多的一处，第三章专门展开。

**特点二：开放寻址 + 线性探测，而不是拉链法**

`HashMap` 用"数组 + 链表/红黑树"（拉链法）解决哈希冲突；`ThreadLocalMap` 用**开放寻址**：如果算出的槽位被占了，就顺着数组往后找下一个空位（线性探测）。

```java
private void set(ThreadLocal<?> key, Object value) {
    Entry[] tab = table;
    int len = tab.length;
    int i = key.threadLocalHashCode & (len - 1);  // 定位槽位

    // 槽位被占 → 线性探测向后找
    for (Entry e = tab[i]; e != null; e = tab[i = nextIndex(i, len)]) {
        if (e.refersTo(key)) {        // 找到同 key → 覆盖
            e.value = value;
            return;
        }
        if (e.refersTo(null)) {       // 遇到"key 已被 GC"的过期条目 → 原地替换并顺带清理
            replaceStaleEntry(key, value, i);
            return;
        }
    }
    tab[i] = new Entry(key, value);
    int sz = ++size;
    // 清理不出过期条目且超过阈值（容量的 2/3）→ 扩容为 2 倍
    if (!cleanSomeSlots(i, sz) && sz >= threshold)
        rehash();
}
```

为什么选开放寻址？因为 ThreadLocalMap 的预期条目数很少（一个线程通常只用几个 ThreadLocal），开放寻址在小容量、低冲突场景下**缓存友好、无链表节点开销**，更合适。

**特点三：魔数 0x61c88647 —— 黄金分割散列**

每个 ThreadLocal 实例的哈希值不是来自 `hashCode()`，而是由一个全局原子计数器按固定步长递增生成：

```java
private final int threadLocalHashCode = nextHashCode();

private static AtomicInteger nextHashCode = new AtomicInteger();

/** 连续生成的哈希值之间的差值 —— 黄金分割数 */
private static final int HASH_INCREMENT = 0x61c88647;

private static int nextHashCode() {
    return nextHashCode.getAndAdd(HASH_INCREMENT);
}
```

`0x61c88647` ≈ 2³² × (√5 - 1) / 2，即 **2³² 乘以黄金分割比**。以这个步长递增并对 2 的幂取模，产生的序列会**近乎完美地均匀散布在数组上**（斐波那契散列），大幅减少线性探测的冲突次数。这是 Knuth《计算机程序设计艺术》里的经典技巧。

## 三、内存泄漏的真相：一场精心设计的攻防

### 3.1 先画清楚引用链

使用 ThreadLocal 时的完整引用关系（实线强引用，虚线弱引用）：

```
栈上引用 threadLocalRef ──强──> ThreadLocal 实例
                                     ↑
                                     ┆弱（Entry 的 key）
                                     ┆
Thread ──强──> ThreadLocalMap ──强──> Entry ──强──> value
（线程存活期间一直可达）
```

### 3.2 为什么 key 要设计成弱引用

反过来想：**如果 key 是强引用**会怎样？

你的代码里 `threadLocalRef = null` 之后（比如持有它的对象被销毁），ThreadLocal 实例本应被回收。但线程还活着 → map 还活着 → Entry 强引用着 key → **ThreadLocal 实例永远无法回收**，它对应的 value 更无法回收。只要线程不死（线程池里的线程基本不死），这份内存就永久泄漏，而且你的代码**没有任何手段能补救**——你已经没有这个 ThreadLocal 的引用了，连 `remove()` 都调不了。

**把 key 设为弱引用后**：外界强引用断开 → 下次 GC 时 ThreadLocal 实例被回收 → Entry 的 key 变成 `null`（术语叫 stale entry，过期条目）。此时 value 还被 Entry 强引用着，但 ThreadLocalMap 在后续的 `set()` / `get()` / `remove()` 操作中**探测到 key 为 null 的条目就会顺手清除它**（`expungeStaleEntry`），value 随之释放。

所以正确的理解是：

> **key 用弱引用不是"造成"内存泄漏的原因，而是"缓解"内存泄漏的手段**。它把"必然的、无法补救的泄漏"降级成了"临时的、可被自愈机制清理的滞留"。
{: .prompt-tip }

### 3.3 那泄漏到底何时发生

自愈机制有个前提：**你得继续操作这个 map**（任意 ThreadLocal 的 set/get/remove 都可能触发清理）。泄漏发生在这条链全部成立时：

1. 线程长期存活（**线程池是重灾区**：核心线程跑完任务不销毁）；
2. ThreadLocal 外部强引用已断开，Entry 成为 stale entry；
3. 这个线程**之后再也没有**触发过 ThreadLocalMap 的清理路径；
4. value 对象本身很大，或者数量多（每个线程泄漏一份）。

Android 上还有一个变种：**value 意外持有 Activity/Fragment 引用**时，即使只"滞留"到下次清理，也足以让重量级对象跨越配置变更存活，造成实打实的泄漏。

### 3.4 正确姿势

```java
ExecutorService pool = Executors.newFixedThreadPool(8);
ThreadLocal<RequestContext> ctx = new ThreadLocal<>();

pool.execute(() -> {
    ctx.set(buildContext());
    try {
        handleRequest();        // 任务逻辑
    } finally {
        ctx.remove();           // ★ 必须清理：线程即将归还线程池，带着数据回去就是脏数据 + 泄漏
    }
});
```

三条纪律：

1. **`ThreadLocal` 声明为 `private static final`**——让 ThreadLocal 实例本身与类同生命周期，从根上避免"外部引用断开产生 stale entry"的第一步（泄漏的主要形态就只剩忘记 remove 的 value）；
2. **线程池场景 `try/finally` 中 `remove()`**——既防泄漏，也防**脏数据**：下一个任务复用这个线程时 `get()` 会拿到上一个任务的残留值，这往往比泄漏更致命（用户 A 的请求读到用户 B 的身份）；
3. **value 不要持有 Activity/Context/View** 等重量级、有生命周期的对象。

## 四、跨线程传递：InheritableThreadLocal 与 TTL

### 4.1 InheritableThreadLocal：只在"创建子线程"那一刻复制

`ThreadLocal` 的值严格线程私有，子线程拿不到父线程的值。`InheritableThreadLocal` 补上了这个场景：

```java
InheritableThreadLocal<String> traceId = new InheritableThreadLocal<>();
traceId.set("req-1");

new Thread(() -> {
    System.out.println(traceId.get()); // "req-1" —— 创建线程时从父线程复制过来
}).start();
```

原理很简单：`Thread` 构造函数里会检查父线程（即调用 new Thread 的线程）的 `inheritableThreadLocals`，不为空就**浅拷贝**一份给子线程。注意两个坑：

- **只在 `new Thread()` 时复制一次**，之后父线程再 set 新值，子线程看不到；
- **对线程池无效**——线程池的线程早就创建好了，提交任务时不会重新复制。这正是它在实际项目中几乎不够用的原因。

### 4.2 TransmittableThreadLocal：线程池场景的事实标准

阿里开源的 [TTL（transmittable-thread-local）](https://github.com/alibaba/transmittable-thread-local) 解决线程池传值：它的思路是**把"复制时机"从"创建线程时"改到"提交任务时"**——用 `TtlRunnable.get(task)` 包装任务，提交时快照当前线程的上下文，执行时回放到工作线程，执行完恢复现场。Java 后端做全链路 traceId 透传基本都靠它（或同思路的方案）。

## 五、Android 与 Kotlin 协程中的 ThreadLocal

### 5.1 Android 最经典的 ThreadLocal：Looper

`Looper` 的"每个线程最多一个 Looper"就是用 ThreadLocal 实现的：

```java
// android.os.Looper（节选）
static final ThreadLocal<Looper> sThreadLocal = new ThreadLocal<Looper>();

private static void prepare(boolean quitAllowed) {
    if (sThreadLocal.get() != null) {
        throw new RuntimeException("Only one Looper may be created per thread");
    }
    sThreadLocal.set(new Looper(quitAllowed));
}

public static @Nullable Looper myLooper() {
    return sThreadLocal.get();
}
```

`Looper.myLooper()` 在任何线程调用，拿到的都是**本线程**的 Looper——`Handler` 默认绑定当前线程消息队列、"不能在子线程更新 UI"的检查，根子上都源于这个 ThreadLocal。类似的还有 `Choreographer`（每线程一个编舞者实例）。

### 5.2 协程中的大坑：挂起点前后线程可能不同

协程挂起恢复后**可能换了线程**，而 ThreadLocal 的值跟着线程走，不跟着协程走：

```kotlin
val requestId = ThreadLocal<String>()

launch(Dispatchers.IO) {
    requestId.set("req-1")
    println(requestId.get())  // "req-1"，此刻在 IO 线程 A
    delay(100)                // 挂起 → 恢复后可能被调度到 IO 线程 B
    println(requestId.get())  // ❌ 可能是 null，也可能是线程 B 上别的协程留下的脏值
}
```

官方解法是 **`asContextElement()`**：把 ThreadLocal 的值提升为协程上下文的元素，协程每次在某个线程上开始/恢复执行时自动 set，挂起/让出时自动恢复线程原值：

```kotlin
val requestId = ThreadLocal<String>()

// 值绑定到协程上下文，跟着协程走而不是跟着线程走
launch(Dispatchers.IO + requestId.asContextElement(value = "req-1")) {
    println(requestId.get())  // "req-1"
    delay(100)
    println(requestId.get())  // ✅ 依然 "req-1"，即使已经换了线程
}
```

注意：`asContextElement` 捕获的是**启动那一刻的值**；协程体内再调用 `threadLocal.set()` 修改，不会写回上下文，挂起恢复后会丢——需要变更就用新值再启动子协程（`withContext(requestId.asContextElement("req-2"))`）。这是 MDC 日志上下文接入协程的标准方式（`kotlinx-coroutines-slf4j` 的 `MDCContext` 就是这么实现的）。

## 六、ScopedValue：ThreadLocal 的官方继任者

### 6.1 为什么需要新东西

JDK 21 带来了虚拟线程（Virtual Threads）：一个 JVM 里可以同时存在**上百万个**虚拟线程。这直接放大了 ThreadLocal 的所有历史包袱：

1. **内存成本**：每个线程一份副本，百万虚拟线程 = 百万份拷贝；
2. **无约束的可变性**：任何能拿到 ThreadLocal 的代码都能 `set()`，数据流向无法追踪；
3. **生命周期不可控**：忘记 remove 的问题在海量短命虚拟线程下更难管理；
4. **继承成本**：`InheritableThreadLocal` 在创建每个子线程时都要复制整个 map。

### 6.2 ScopedValue 的用法

`ScopedValue` 在 JDK 25 正式转正（JEP 506，此前从 JDK 20 起孵化/预览了多轮）。它的核心理念是：**值不可变 + 作用域受限 + 结构化**。

```java
public class RequestHandler {
    // 声明：类似 ThreadLocal，但没有 set 方法
    private static final ScopedValue<User> CURRENT_USER = ScopedValue.newInstance();

    void handle(Request req) {
        User user = authenticate(req);
        // 绑定值并限定作用域：只在 run 的动态范围内可读，run 结束自动失效
        ScopedValue.where(CURRENT_USER, user)
                   .run(() -> processRequest(req));
        // 这里 CURRENT_USER 已不可访问 —— 不存在"忘记 remove"
    }

    void processRequest(Request req) {
        // 调用链上任意深度的方法都能读到，无需层层传参
        User user = CURRENT_USER.get();
        // CURRENT_USER 没有 set() —— 想"改"只能在内层重新 where 绑定新值，外层不受影响
    }
}
```

与 ThreadLocal 的关键对比：

| 维度 | ThreadLocal | ScopedValue |
|---|---|---|
| 可变性 | 任意时刻可 `set()` | 绑定后不可变，只能内层重新绑定 |
| 生命周期 | set 后一直存在，直到 remove/线程死亡 | 严格限定在 `run()` 的动态作用域内，自动失效 |
| 泄漏风险 | 忘记 remove 即泄漏/脏数据 | 结构上不可能泄漏 |
| 子线程继承 | InheritableThreadLocal，创建时复制 | 配合 `StructuredTaskScope` 自动继承，**零复制**（共享不可变值） |
| 虚拟线程成本 | 每线程一份 map | 极轻量，为百万级虚拟线程设计 |

### 6.3 对 Android/Kotlin 开发者的意义

短期内 Android 开发者用不上 ScopedValue（Android 的 Java 支持跟进 JDK 25 尚需时日），但它的设计思想值得对照理解：**"不可变值 + 结构化作用域"正是 Kotlin 协程 `CoroutineContext` 早就采用的模型**——`withContext(element) { ... }` 的行为几乎就是 `ScopedValue.where(...).run(...)`：内层绑定、作用域结束自动还原、外层不可见。可以说协程的上下文设计提前多年验证了这条路线。

## 七、高频面试问答

**Q1：ThreadLocal 的实现原理？数据存在哪里？**

数据存在**线程自己身上**：每个 `Thread` 对象持有一个 `ThreadLocalMap` 字段，map 的 key 是 ThreadLocal 实例（弱引用），value 是存的值。`get()/set()` 都是先取当前线程的 map，再以 ThreadLocal 自身为 key 操作。线程隔离的本质是"不同线程操作不同的 map"，因此全程无锁。注意方向别说反：不是 ThreadLocal 里有个以 Thread 为 key 的 map。

**Q2：ThreadLocalMap 和 HashMap 有什么区别？**

① 冲突解决：ThreadLocalMap 用开放寻址 + 线性探测（条目少、缓存友好），HashMap 用拉链法（链表/红黑树）；② key 引用强度：ThreadLocalMap 的 Entry 继承 `WeakReference`，key 是弱引用，HashMap 是强引用；③ 哈希来源：ThreadLocalMap 用全局计数器按魔数 `0x61c88647`（黄金分割数）递增生成哈希，使条目均匀散布；④ ThreadLocalMap 在 set/get/remove 过程中会顺带清理 key 已被 GC 的过期条目。

**Q3：为什么 Entry 的 key 用弱引用？这是内存泄漏的原因吗？**

恰恰相反，弱引用是**缓解**泄漏的手段。若 key 为强引用：外部引用断开后，只要线程存活，map → Entry → key 这条强引用链会让 ThreadLocal 对象永远无法回收，且没有任何补救手段。key 为弱引用时，外部引用断开 → GC 回收 ThreadLocal → Entry 的 key 变 null（stale entry）→ 后续任何 set/get/remove 操作探测到它都会连 value 一起清除。弱引用把"必然且无解的泄漏"降级为"可自愈的临时滞留"。

**Q4：那内存泄漏到底怎么发生的？怎么避免？**

条件是同时满足：线程长期存活（线程池）+ stale entry 已产生 + 该线程之后不再触发 map 的清理路径 + value 较大。此时 value 被 Entry 强引用，无人清理。避免：① ThreadLocal 声明为 `private static final`；② 线程池场景务必 `try/finally` 中 `remove()`；③ value 不持有 Activity 等重量级对象。`remove()` 同时还防**脏数据**——线程复用时下个任务读到上个任务的残留值，危害常大于泄漏。

**Q5：0x61c88647 是什么？为什么用它？**

ThreadLocal 的哈希值由全局 `AtomicInteger` 以 `0x61c88647` 为步长递增生成。该数 ≈ 2³² × 黄金分割比（斐波那契散列），以它为步长的序列对 2 的幂取模能近乎均匀地散布在数组中，最大限度减少开放寻址的探测冲突。

**Q6：InheritableThreadLocal 的原理和局限？**

`new Thread()` 时，构造函数把父线程的 `inheritableThreadLocals` 浅拷贝给子线程，实现父传子。局限：只在创建线程那一刻复制一次，之后父线程的修改不可见；**对线程池无效**（线程早已创建，提交任务不触发复制）。线程池场景用阿里 TTL——把复制时机改到"提交任务时"：包装 Runnable，提交时快照、执行时回放、执行完恢复。

**Q7：Android 里哪些地方用了 ThreadLocal？**

最典型是 `Looper`：`sThreadLocal` 保证每个线程最多一个 Looper，`Looper.myLooper()`、Handler 绑定当前线程消息队列都基于它；`Choreographer` 同理。此外 Compose 的 `CompositionLocal`、协程的 `CoroutineContext` 在"隐式上下文传递"的思想上与 ThreadLocal 同源，但实现机制完全不同（沿组合树/协程结构传递，而非沿线程）。

**Q8：协程里能直接用 ThreadLocal 吗？**

不能直接用：协程挂起恢复后可能换线程，ThreadLocal 的值跟线程走，会丢失或读到其他协程的脏值。正确做法是 `threadLocal.asContextElement(value)` 把值放进协程上下文——协程在任何线程上恢复执行时自动 set，挂起时自动还原线程原值。注意它捕获的是启动时的快照，协程内 `set()` 的修改不会保留到挂起之后。

**Q9：ScopedValue 是什么？和 ThreadLocal 什么关系？**

JDK 25 正式特性（JEP 506），官方定位的 ThreadLocal 继任者，面向虚拟线程时代。三大差异：**不可变**（无 set，只能 `ScopedValue.where(key, value).run { }` 绑定，内层可重新绑定但不影响外层）、**作用域受限**（run 结束自动失效，结构上杜绝忘记 remove）、**继承零成本**（配合 StructuredTaskScope 共享不可变值，无需复制）。它的模型与 Kotlin 协程的 `withContext(element)` 高度相似——协程上下文提前验证了这条设计路线。

**Q10：ThreadLocal 声明为 static 会有问题吗？为什么反而推荐 static？**

推荐 `private static final`。ThreadLocal 实例本身很小（真正的数据在各线程的 map 里），static 让它与类同生命周期，避免了"实例级 ThreadLocal 随宿主对象销毁产生 stale entry"这条泄漏路径的起点。需要警惕的不是 static 的 ThreadLocal 对象，而是各线程 map 里未 remove 的 value。

---

## 参考资料

- [OpenJDK：ThreadLocal.java 源码](https://github.com/openjdk/jdk/blob/master/src/java.base/share/classes/java/lang/ThreadLocal.java)
- [JEP 506: Scoped Values（JDK 25 正式版）](https://openjdk.org/jeps/506)
- [JEP 444: Virtual Threads](https://openjdk.org/jeps/444)
- [alibaba/transmittable-thread-local](https://github.com/alibaba/transmittable-thread-local)
- [Kotlin 官方文档：Thread-local data 与 asContextElement](https://kotlinlang.org/docs/coroutine-context-and-dispatchers.html#thread-local-data)
