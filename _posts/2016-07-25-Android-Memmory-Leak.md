---
categories: [Blog]
title: Android 内存泄漏案例和解析
date: 2016-07-25 10:08:22 +0800
tags: [android,memmory leak]
keywords: [内存泄漏]
---
Android 编程所使用的 Java 是一门使用垃圾收集器（GC, garbage collection）来自动管理内存的语言，它使得我们不再需要手动调用代码来进行内存回收。那么它是如何判断的呢？简单说，如果一个对象，从它的根节点开始不可达的话，那么这个对象就是没有引用的了，是会被垃圾收集器回收的，其中，所谓的 “根节点” 往往是一个线程，比如主线程。因此，**如果一个对象从它的根节点开始是可达的有引用的，但实际上它已经没有再使用了，是无用的，这样的对象就是内存泄漏的对象**，它会在内存中占据我们应用程序原本就不是很多的内存，导致程序变慢，甚至内存溢出（OOM）程序崩溃。

内存泄漏的原因并不难理解，但仅管知道它的存在，往往我们还是会不知觉中写出致使内存泄漏的代码。在 Android 编程中，也是有许多情景容易导致内存泄漏，以下将一一列举一些我所知道的内存泄漏案例，从这些例子中应该能更加直观了解怎么导致了内存泄漏，从而在编程过程中去避免。

**静态变量造成内存泄漏**

首先，比较简单的一种情况是，静态变量致使内存泄漏，说到静态变量，我们至少得了解其生命周期才能彻底明白。静态变量的生命周期，起始于类的加载，终止于类的释放。对于 Android 而言，程序也是从一个 main 方法进入，开始了主线程的工作，如果一个类在主线程或旁枝中被使用到，它就会被加载，反过来说，假如一个类存在于我们的项目中，但它从未被我们使用过，算是个孤岛，这时它是没有被加载的。一旦被加载，只有等到我们的 Android 应用进程结束它才会被卸载。

于是，当我们在 Activity 中声明一个静态变量引用了 Activity 自身，就会造成内存泄漏：

```java
public class LeakActivity extends AppCompatActivity {
    private static Context sContext;
    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_leak);
        sContext = this;
    }
}
```

这样的代码会导致当这个 Activity 结束的时候，sContext 仍然持有它的引用，致使 Activity 无法回收。解决办法就是在这个 Activity 的 onDestroy 时将 sContext 的值置空，或者避免使用静态变量这样的写法。

同样的，如果一个 Activity 的静态 field 变量内部获得了当前 Activity 的引用，比如我们经常会把 this 传给 View 之类的对象，这个对象若是静态的，并且没有在 Activity 生命周期结束之前置空的话，也会导致同样的问题。

**非静态内部类和匿名内部类造成内存泄漏**

也是一个很常见的情景，经常会遇到的 Handler 问题就是这样一种情况，如果我们在 field 声明一个 Handler 变量：

```java
private Handler mHandler = new Handler() {
    @Override public void handleMessage(Message msg) {
        super.handleMessage(msg);
    }
};
```
由于在 Java 中，非静态内部类（包括匿名内部类，比如这个 Handler 匿名内部类）会引用外部类对象 this（比如 Activity），而静态的内部类则不会引用外部类对象。所以这里 Handler 会引用 Activity 对象，当它使用了 postDelayed 的时候，如果 Activity 已经 finish 了，而这个 handler 仍然引用着这个 Activity 就会致使内存泄漏，因为这个 handler 会在一段时间内继续被 main Looper 持有，导致引用仍然存在，在这段时间内，如果内存吃紧至超出，就很危险了。

解决办法就是大家都知道的使用静态内部类加 WeakReference：

```java
private StaticHandler mHandler = new StaticHandler(this);
public static class StaticHandler extends Handler {
    private final WeakReference<Activity> mActivity;
    public StaticHandler(Activity activity) {
        mActivity = new WeakReference<Activity>(activity);
    }
    @Override public void handleMessage(Message msg) {
        super.handleMessage(msg);
    }
}
```
另外，综合上面两种情况，如果一个变量，既是静态变量，而且是非静态的内部类对象，那么也会造成内存泄漏：

```java
public class LeakActivity extends AppCompatActivity {
    private static Hello sHello;
    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_leak);
        sHello = new Hello();
    }
    public class Hello {}
}
```

注意，这里我们定义的 Hello 虽然是空的，但它是一个非静态的内部类，所以它必然会持有外部类即 LeakActivity.this 引用，导致 sHello 这个静态变量一直持有这个 Activity，于是结果就和第一个例子一样，Activity 无法被回收。

到这里大家应该可以看出，内存泄漏经常和静态变量有关。和静态变量有关的，还有一种常见情景:
>使用单例模式没有解绑致使内存泄漏，单例模式的对象经常是和我们的应用相同的生命周期，如果我们使用 EventBus 或 Otto 并生成单例，注册了一个 Activity 而没有在页面结束的时候进行解除注册，那么单例会一直持有我们的 Activity，这个 Activity 虽然没有使用了，但会一直占用着内存。

**属性动画造成内存泄漏**

另外当我们使用属性动画，我们需要调用一些方法将动画停止，特别是无限循环的动画，否则也会造成内存泄漏，好在使用 View 动画并不会出现内存泄漏，估计 View 内部有进行释放和停止。

**RxJava 使用不当造成内存泄漏**
最后说一说 RxJava 使用不当造成的内存泄漏，RxJava 是一个非常易用且优雅的异步操作库。对于异步的操作，如果没有及时取消订阅，就会造成内存泄漏：

```java
Observable.interval(1, TimeUnit.SECONDS)
          .subscribe(new Action1<Long>() {
              @Override public void call(Long aLong) {
                  // pass
              }
          });
```
同样是匿名内部类造成的引用没法被释放，使得如果在 Activity 中使用就会导致它无法被回收，即使我们的 Action1 看起来什么也没有做。解决办法就是接收 subscribe 返回的 Subscription 对象，在 Activity onDestroy 的时候将其取消订阅即可：

```java
public class LeakActivity extends AppCompatActivity {
    private Subscription mSubscription;
    @Override protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_leak);
        mSubscription = Observable.interval(1, TimeUnit.SECONDS)
            .subscribe(new Action1<Long>() {
              @Override public void call(Long aLong) {
                  // pass
              }
            });
    }
    @Override protected void onDestroy() {
        super.onDestroy();
        mSubscription.unsubscribe();
    }
}
```
除了以上这种解决方式之外，还有一种解决方式就是通过 RxJava 的 compose 操作符和 Activity 的生命周期挂钩，我们可以使用一个很方便的第三方库叫做 [RxLifecycle ](https://github.com/trello/RxLifecycle)来快捷做到这点，使用起来就像这样：

```java
public class MyActivity extends RxActivity {
    @Override
    public void onResume() {
        super.onResume();
        myObservable
            .compose(bindToLifecycle())
            .subscribe();
    }
}
```

另外，它还提供了和 View 的便捷绑定，详情可以点击我提供的链接进行了解，这里不多说了。

总结来说，仍然是前面说的内部类或匿名内部类引用了外部类造成了内存泄漏，所以在实际编程过程中，如果涉及此类问题或者线程操作的，应该特别小心，很可能不知不觉中就写出了带内存泄漏的代码了。

**内存泄漏的检测**

前面说了不少内存泄漏的场景和对应的解决办法，但如果我们不知不觉中写出了带有内存泄漏隐患的代码怎么办，面对这个问题，其实到现在，我们是很幸运的，因为有很多相关的检查方式或组件可以选择，比如最简单的：观察 Memory Monitor 内存走势图，可以或多或少知道内存情况，但如果要精确地追踪到内存泄漏点，这里特别推荐伟大的 Square 公司开源的 [LeakCanary](https://github.com/square/leakcanary) 方案，LeakCanary 可以做到非常简单方便、低侵入性地捕获内存泄漏代码，甚至很多时候你可以捕捉到 Android 官方组件的内存泄漏代码，具体使用大家可以自行参看其说明。
![LeakCanary ](https://raw.githubusercontent.com/hxmeie/tuchuang/master/images/20200104141613.png)
