---
categories: [转载, Android]
title: ViewModel源码研究之聊聊onSaveInstanceState和onRetainNonConfigurationInstance的区别
date: 2021-07-22 10:00:00 +0800
pin: false
tags: [转载, Android]
keywords: [ViewModel, onSaveInstanceState, onRetainNonConfigurationInstance, Activity恢复, 源码]
---

> 本文转载自 [ViewModel源码研究之聊聊onSaveInstanceState和onRetainNonConfigurationInstance的区别](https://juejin.cn/post/6987566061499449357)（作者：字节小站）。版权归原作者所有，此处仅作个人学习备份。

1. 前言
=====

最近在研究**ViewModel**实现原理。**ViewModel**有两个特性。

1. 当配置发生改变时（例如：**旋转屏幕**），重新创建的**Activity**能够通过**ViewModel**将数据还原回来，
2. 当按返回键或者调用**finish**方法时，**ViewModel**能够感知到**onDestroy**事件，同时将**ViewModel**保存的**Closeable**对象关闭掉（例如：**主动关闭协程**）

当屏幕旋转时，会调用**Activity**的**onRetainNonConfigurationInstance**方法。**ViewModel**组件正是通过该方法将**ViewModel**保存起来，给重建的**Activity**使用。

```
//androidx.activity:activity:1.2.2@aar
//ComponentActivity.java

public final Object onRetainNonConfigurationInstance() {
    // Maintain backward compatibility.
    Object custom = onRetainCustomNonConfigurationInstance();

    ViewModelStore viewModelStore = mViewModelStore;
    if (viewModelStore == null) {
        // No one called getViewModelStore(), so see if there was an existing
        // ViewModelStore from our last NonConfigurationInstance
        NonConfigurationInstances nc =
                (NonConfigurationInstances) getLastNonConfigurationInstance();
        if (nc != null) {
            viewModelStore = nc.viewModelStore;
        }
    }

    if (viewModelStore == null && custom == null) {
        return null;
    }

    NonConfigurationInstances nci = new NonConfigurationInstances();
    nci.custom = custom;
    nci.viewModelStore = viewModelStore;
    return nci;
}
```

**Activity**还有个类似的方法**onSaveInstanceState()** ，**onSaveInstanceState()** 和**onRetainNonConfigurationInstance()** 的区别是：

1. **onSaveInstanceState()** 调用的场景是：activity1启动activity2。生命周期调用顺序如下：

> activity1.onPause()->activity2.onCreate()->activity2.onStart()->activity2.onResume()->activity1.onStop()->activity1.onSaveInstanceState()，

2. **onRetainNonConfigurationInstance()** 调用场景是当configuration发生改变时，例如：旋转屏幕。

**那么问题来了，一共有三个**

> 1. 它们存储的状态数据颗粒度一样吗？
> 2. 它们把状态数据存储到哪里去了？
> 3. 如果系统后台将Activity杀掉后，它们都能把状态恢复回来吗？

2. onSaveInstanceState(Bundle outState)方法详解
===========================================

首先在**ComponentActivity**的**onSaveInstanceState(Bundle outState)** 方法中加个断点，重点关注 ActivityThread.callActivityOnSaveInstanceState(Bundle outState)。

2.1 ActivityThread.callActivityOnSaveInstanceState(Bundle outState)
-------------------------------------------------------------------

```
//ActivityThread.java

private void callActivityOnSaveInstanceState(ActivityClientRecord r) {
    r.state = new Bundle();
    r.state.setAllowFds(false);
    if (r.isPersistable()) {
        r.persistentState = new PersistableBundle();
        mInstrumentation.callActivityOnSaveInstanceState(r.activity, r.state,
                r.persistentState);
    } else {
        mInstrumentation.callActivityOnSaveInstanceState(r.activity, r.state);
    }
}
```

我们注意到**r.state = new Bundle()，** 原来outState参数是在这里创建的。Bundle可以用来组件间传递数据，也可以用来进程间传递数据。

2.2 ActivityThread.handleStopActivity()
---------------------------------------

```
public void handleStopActivity(IBinder token, boolean show, int configChanges,
        PendingTransactionActions pendingActions, boolean finalStateRequest, String reason) {
    final ActivityClientRecord r = mActivities.get(token);
    r.activity.mConfigChangeFlags |= configChanges;

    final StopInfo stopInfo = new StopInfo();
    performStopActivityInner(r, stopInfo, show, true /* saveState */, finalStateRequest,
            reason);
    updateVisibility(r, show);

    // Make sure any pending writes are now committed.
    if (!r.isPreHoneycomb()) {
        QueuedWork.waitToFinish();
    }

    stopInfo.setActivity(r);
    stopInfo.setState(r.state);
    stopInfo.setPersistentState(r.persistentState);
    pendingActions.setStopInfo(stopInfo);
    mSomeActivitiesChanged = true;
}
```

2.3 PendingTransactionActions$StopInfo.run()
--------------------------------------------

该方法调用了 `ActivityManager.getService().activityStopped(mActivity.token, mState, mPersistentState, mDescription)` 方法，还将 2.1 中创建的 mState 当参数传进来了。

2.4 ActivityManagerService.activityStopped()
--------------------------------------------

```
//ActivityManagerService.java
@Override
public final void activityStopped(IBinder token, Bundle icicle,
        PersistableBundle persistentState, CharSequence description) {
    // Refuse possible leaked file descriptors
    if (icicle != null && icicle.hasFileDescriptors()) {
        throw new IllegalArgumentException("File descriptors passed in Bundle");
    }
    final long origId = Binder.clearCallingIdentity();
    synchronized (this) {
        final ActivityRecord r = ActivityRecord.isInStackLocked(token);
        if (r != null) {
            r.activityStoppedLocked(icicle, persistentState, description);
        }
    }
    trimApplications();
    Binder.restoreCallingIdentity(origId);
}
```

2.5 ActivityRecord.activityStoppedLocked
----------------------------------------

我们注意到最终**bundle**数据会保存在**ActivityRecord**的**icicle**对象中。

> **总结**：**onSaveInstanceState**方法是当**Activity**调用了**onStop**后，会调用到**ActivityThread**的**callActivityOnSaveInstanceState()**方法，把**Activity**需要保存的数据放入**Bundle**对象中，并且随后通过IPC进程间通信机制，调用**ActivityManagerService的activityStopped**方法，将**Bundle**对象保存到AMS端的**ActivityRecord**中。

2.6 被杀端后恢复数据过程
--------------

最终是通过 ActivityStackSupervisor.realStartActivityLocked → LaunchActivityItem.execute() → ActivityThread.performLaunchActivity 用 `r.state` 恢复数据：

```
private Activity performLaunchActivity(ActivityClientRecord r, Intent customIntent){
   activity.mCalled = false;
    if (r.isPersistable()) {
        mInstrumentation.callActivityOnCreate(activity, r.state, r.persistentState);
    } else {
        mInstrumentation.callActivityOnCreate(activity, r.state);
    }
}
```

3. onRetainNonConfigurationInstance()
=====================================

该方法是在重建**Activity**时调用**performDestoryActivity**时会保存数据。

```
ActivityClientRecord performDestroyActivity(IBinder token, boolean finishing,
          int configChanges, boolean getNonConfigInstance, String reason) {
  ActivityClientRecord r = mActivities.get(token);
  //省略一些代码
      if (getNonConfigInstance) {
          try {
              r.lastNonConfigurationInstances
                      = r.activity.retainNonConfigurationInstances();
          } catch (Exception e) {
              // ...
        }
      }
  }
```

我们可以看到**onRetainNonConfigurationInstance**方法返回的**Object**会赋值给**ActivityClientRecord**的**lastNonConfigurationInstances**。

4. 答案
=====

1. 颗粒度不一样。**onSaveInstanceState()**是保存到**Bundle**中，只能保存**Bundle**能接受的数据类型，比如一些基本类型的数据。而**onRetainNonConfigurationInstance()** 可以保存任何类型的数据，数据类型是**Object**
2. **onSaveInstanceState()**数据最终存储到**ActivityManagerService**的**ActivityRecord**中了，也就是存到**系统进程**中去了。而**onRetainNonConfigurationInstance()** 数据是存储到**ActivityClientRecord**中，也就是存到**应用本身的进程**中了
3. **onSaveInstanceState**存到系统进程中，所以App被杀之后还是能恢复的。而**onRetainNonConfigurationInstance**存到本身进程中，App被杀是没法恢复的。
