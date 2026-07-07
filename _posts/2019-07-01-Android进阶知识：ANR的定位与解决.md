---
categories: [转载, Android]
title: "Android进阶知识：ANR的定位与解决"
date: 2019-07-01 10:00:00 +0800
pin: false
tags: [转载, android]
keywords: [ANR, Android, 主线程, 卡顿, 性能优化]
---

> 本文转载自 [Android进阶知识：ANR的定位与解决](https://juejin.cn/post/6844904069731975176)。版权归原作者所有，此处仅作个人学习备份。

## 1、前言

`ANR`对于`Android`开发者来说一定不会陌生，从刚开始学习`Android`时的一不注意就`ANR`，到后来知道主线程不能进行耗时操作注意到这点后，程序出现`ANR`的情况就大大减少了，甚至于消失了。那么真的是只要在主线程做耗时操作就会产生`ANR`吗？为什么在有时候明明觉得自己没在主线程做耗时操作也出现了`ANR`呢？一旦出现莫名其妙的`ANR`，怎么定位导致`ANR`的产生的位置和解决问题呢？那么接下来就来一个个的解决这些问题。

## 2、ANR是什么？

`ANR`全称`Application Not Responding`即应用程序无响应。在`Android`中如果应用程序有一段时间无法响应用户操作，系统会弹出弹窗，让用户选择是继续等待还是强制关闭程序。一款良好应用`APP`是不应该出现这个弹窗的。

## 3、ANR的产生原因

`ANR`产生原因和类型有以下几种：

#### 1、`Activity`在5秒钟之内无法响应屏幕触摸事件挥着键盘输入事件就会产生`ANR`。

KeyDispatchTimeout
Reason：Input event dispatching timed out

#### 2、`BroadcastReceiver`在10秒钟之内还未执行完成就会产生`ANR`。

BroadcastTimeout
Reason：Timeout of broadcast BroadcastRecord

#### 3、`Service`各个生命周期在20秒钟之内没有执行完成就会产生`ANR`。

ServiceTimeout
Reason：Timeout executing service

#### 4、`ContentProvider`在10秒钟之内没有执行完成就会产生`ANR`。

ContentProviderTimeout
Reason：timeout publishing content providers

在以上这几种原因中出现最多的一般是第一种，而且往往都是因为在写代码时不注意，在主线程做了耗时的操作。

## 4、ANR的定位与解决

关于`ANR`的定位这里举一个例子来看。这是我之前遇到的一次出现`ANR`的时候所解决问题的情况和解决步骤。

![](https://p1-jj.byteimg.com/tos-cn-i-t2oaga2asx/gold-user-assets/2019/7/1/16bab3b7588c00aa~tplv-t2oaga2asx-jj-mark:3024:0:0:0:q75.png)

首先当然是复现`ANR`现象，找准`ANR`出现的地方，查看对应代码，如果能直接看出来问题所在，找到代码中做的错误操作那么直接修改相应代码就解决问题了。但是如果没法轻易看出问题原因，接下来就只好去`Logcat`中查看对应的错误日志。

```
07-22 21:39:17.019 819-851/? E/ActivityManager: ANR in com.xxxx.performance (com.xxxx.performance/.view.home.activity.MainActivity)
    PID: 7398
    Reason: Input dispatching timed out (com.xxxx.performance/com.xxxx.performance.view.home.activity.MainActivity, Waiting to send non-key event because the touched window has not finished processing certain input events that were delivered to it over 500.0ms ago.  Wait queue length: 29.  Wait queue head age: 8579.3ms.)
    Load: 18.22 / 18.1 / 18.18
    CPU usage from 0ms to 8653ms later:
      124% 7398/com.xxxx.performance: 118% user + 6.5% kernel / faults: 4962 minor 7 major
      82% 819/system_server: 28% user + 53% kernel / faults: 10555 minor 11 major
      23% 4402/adbd: 1% user + 22% kernel
      10% 996/com.android.systemui: 4.6% user + 6.2% kernel / faults: 4677 minor 1 major
      4.6% 2215/com.android.phone: 1.5% user + 3.1% kernel / faults: 5411 minor
      6.3% 6268/perfd: 3.4% user + 2.8% kernel / faults: 134 minor
      0.5% 1149/com.miui.whetstone: 0.1% user + 0.3% kernel / faults: 3016 minor 1 major
      0.2% 2097/com.xiaomi.finddevice: 0.1% user + 0.1% kernel / faults: 2256 minor
      0.6% 2143/com.miui.daemon: 0.2% user + 0.3% kernel / faults: 2798 minor
      1.2% 1076/com.xiaomi.xmsf: 0.6% user + 0.6% kernel / faults: 2802 minor
      0% 2122/com.android.server.telecom: 0% user + 0% kernel / faults: 2929 minor
      0% 2244/com.miui.contentcatcher: 0% user + 0% kernel / faults: 1800 minor
      0% 2267/com.mediatek.nlpservice: 0% user + 0% kernel / faults: 2052 minor
      0% 2166/com.xiaomi.mitunes: 0% user + 0% kernel / faults: 1797 minor 3 major
      0% 2190/com.fingerprints.service: 0% user + 0% kernel / faults: 1857 minor
      0.1% 154/mmcqd/0: 0% user + 0.1% kernel
      0.4% 8069/logcat: 0.3% user + 0.1% kernel
      ......
```

从日志第一行开始看，可以看到发生错误的应用包名和类名，这里是`ANR in com.xxxx.performance (com.xxxx.performance/.view.home.activity.MainActivity)`。接着看到进程号`PID`为`7398`。发生`ANR`的`Reason`是`Input dispatching timed out`就是上面提到的第一种。再往下就是活跃进程的`CPU`占用率日志。

```
   124% 7398/com.xxxx.performance
   82% 819/system_server
   10% 996/com.android.systemui
   4.6% 2215/com.android.phone
   ......
```

光看`Logcat`中的日志只能看到这些信息，大概知道是在`MainActivity`出现了问题，但还是不能清楚的定位到发生`ANR`的代码行，想要获得进一步的错误信息只能通过查看`ANR`过程中生成的堆栈信息文件`traces.txt`了。

`traces.txt`文件位置在`/data/anr/`目录下，可以通过以下`adb`命令将其拷贝到sd卡目录下获取查看。

```
adb shell
cat  /data/anr/traces.txt  >/mnt/sdcard/traces.txt  
exit
```

`traces.txt`里的信息：

```
DALVIK THREADS (42):
"main" prio=5 tid=1 Native
  | group="main" sCount=1 dsCount=0 obj=0x75ceafb8 self=0x55933ae7e0
  | sysTid=7398 nice=0 cgrp=default sched=0/0 handle=0x7f7ddae0f0
  | state=S schedstat=( 101485399944 3411372871 31344 ) utm=9936 stm=212 core=1 HZ=100
  | stack=0x7fc8d40000-0x7fc8d42000 stackSize=8MB
  | held mutexes=
  kernel: __switch_to+0x74/0x8c
  kernel: futex_wait_queue_me+0xcc/0x158
  kernel: futex_wait+0x120/0x20c
  kernel: do_futex+0x184/0xa48
  kernel: SyS_futex+0x88/0x19c
  kernel: cpu_switch_to+0x48/0x4c
  native: #00 pc 00017750  /system/lib64/libc.so (syscall+28)
  native: #01 pc 000d1584  /system/lib64/libart.so (_ZN3art17ConditionVariable4WaitEPNS_6ThreadE+140)
  native: #02 pc 00388098  /system/lib64/libart.so (_ZN3artL12GoToRunnableEPNS_6ThreadE+1068)
  native: #03 pc 000a5db8  /system/lib64/libart.so (_ZN3art12JniMethodEndEjPNS_6ThreadE+24)
  native: #04 pc 000280e4  /data/dalvik-cache/arm64/system@framework@boot.oat (Java_android_graphics_Paint_native_1init__+156)
  at android.graphics.Paint.native_init(Native method)
  at android.graphics.Paint.<init>(Paint.java:435)
  at android.graphics.Paint.<init>(Paint.java:425)
  at android.text.TextPaint.<init>(TextPaint.java:49)
  at android.text.Layout.<init>(Layout.java:160)
  at android.text.StaticLayout.<init>(StaticLayout.java:111)
  at android.text.StaticLayout.<init>(StaticLayout.java:87)
  at android.text.StaticLayout.<init>(StaticLayout.java:66)
  at android.widget.TextView.makeSingleLayout(TextView.java:6543)
  at android.widget.TextView.makeNewLayout(TextView.java:6383)
  at android.widget.TextView.checkForRelayout(TextView.java:7096)
  at android.widget.TextView.setText(TextView.java:4082)
  at android.widget.TextView.setText(TextView.java:3940)
  at android.widget.TextView.setText(TextView.java:3915)
  at com.xxxx.performance.view.home.fragment.AttendanceCheckInFragment.onNowTimeSuccess(AttendanceCheckInFragment.java:887)
  at com.xxxx.performance.presenter.attendance.AttendanceFragmentPresenter$6.onNext(AttendanceFragmentPresenter.java:214)
  at com.xxxx.performance.presenter.attendance.AttendanceFragmentPresenter$6.onNext(AttendanceFragmentPresenter.java:205)
  at io.reactivex.internal.operators.observable.ObservableObserveOn$ObserveOnObserver.drainNormal(ObservableObserveOn.java:198)
  at io.reactivex.internal.operators.observable.ObservableObserveOn$ObserveOnObserver.run(ObservableObserveOn.java:250)
  at io.reactivex.android.schedulers.HandlerScheduler$ScheduledRunnable.run(HandlerScheduler.java:109)
  ......
  ......
```

还是从头开始看，来看每个字段对应的含义：
线程名：`main`
线程优先级：`prio=5`
线程锁ID： `tid=1`
线程状态：`Native`
线程组名称：`group="main"`
线程被挂起的次数：`sCount=1`
线程被调试器挂起的次数：`dsCount=0`
线程的java的对象地址：`obj=0x75ceafb8`
线程本身的Native对象地址：`self=0x55933ae7e0`
线程调度信息：
Linux系统中内核线程ID: `sysTid=7398`与主线程的进程号相同
线程调度优先级：`nice=0`
线程调度组：`cgrp=default`
线程调度策略和优先级：`sched=0/0`
线程处理函数地址：`handle=0x7f7ddae0f0`
线程的上下文信息：
线程调度状态：`state=S`
线程在CPU中的执行时间、线程等待时间、线程执行的时间片长度：`schedstat=(101485399944 3411372871 31344 )`
线程在用户态中的调度时间值：`utm=9936`
线程在内核态中的调度时间值：`stm=212`
最后执行这个线程的CPU核序号：`core=1`
线程的堆栈信息：
堆栈地址和大小：`stack=0x7fc8d40000-0x7fc8d42000 stackSize=8MB`
最后看到堆栈信息里的这一行：

```
at com.xxxx.performance.view.home.fragment.AttendanceCheckInFragment.onNowTimeSuccess(AttendanceCheckInFragment.java:887)
```

这里就看清楚了是在`AttendanceCheckInFragment`中的887行出现的问题，再到对应代码行中就很容易发现`ANR`的原因了。

## 5、ANR的相关问题

* **在Activity的onCreate方法里调用sleep方法会发生ANR吗？**

以前一直认为在主线程做了耗时操作就会发生`ANR`，那么真的是这样吗？在`Activity`的`onCreate`方法里调用`Thread.sleep(60 * 1000)`让主线程`sleep`60秒，会导致应用程序`ANR`吗？写个`Demo`测试一下。

```
public class MainActivity extends AppCompatActivity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        try {
            Log.d("ANR","开始sleep");
            Thread.sleep(60*1000);
            Log.d("ANR","sleep完成");
            
        } catch (InterruptedException e) {
            e.printStackTrace();
        }
    }
}
```

如上代码，运行程序，结果应用没有发生ANR,在`sleep`了60秒后正常打印日志。

![](https://p1-jj.byteimg.com/tos-cn-i-t2oaga2asx/gold-user-assets/2019/6/29/16ba38019c708d14~tplv-t2oaga2asx-jj-mark:3024:0:0:0:q75.png)

再次运行程序，这回在程序运行后按下返回键查看现象：![](https://p1-jj.byteimg.com/tos-cn-i-t2oaga2asx/gold-user-assets/2019/7/1/16bab4717bb6e7c4~tplv-t2oaga2asx-jj-mark:3024:0:0:0:q75.png)

这次果然就`ANR`了。通过这个例子，显而易见的得到了这个问题的正确答案。在`Activity`的`onCreate`方法里调用`sleep`方法或者说做耗时操作，不一定会产生`ANR`。其实从`ANR`本身意为应用程序没有响应，同时根据上面总结的`ANR`原因就可以看出，耗时操作本身是不会产生`ANR`的，导致`ANR`的根本还是应用程序无法在一定时间内响应用户的操作。所以因为主线程被耗时操作占用了，主线成程无法对下一个操作进行响应才会`ANR`，没有需要响应的操作自然就不会产生`ANR`，或者应该这样说:主线程做耗时操作，非常容易引发`ANR`。

## 6、总结

* **光在主线程做耗时操作不会产生ANR，超时响应用户操作才会产生ANR。**
* **ANR的定位方法主要是根据Logcat中日志和ANR过程中生成的堆栈信息文件traces.txt。**
* **解决问题不如预防问题，写代码的时候要注意预防产生ANR。**
* **预防ANR的产生不光是在Activity中注意要把耗时操作放到子线程中去，还要注意在使用其他三个组件时，在其生命周期中同样不能做太耗时的操作。另外在使用多线程时候要注意同步和死锁的情况，一旦产生死锁主线程同样会引发ANR。**
