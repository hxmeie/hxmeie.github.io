---
categories: [转载, Android]
title: ViewModel源码研究之聊聊onSaveInstanceState和onRetainNonConfigurationInstance的区别
date: 2021-07-22 10:00:00 +0800
pin: false
tags: [转载, android]
keywords: [ViewModel, onSaveInstanceState, onRetainNonConfigurationInstance, Activity恢复, 源码]
---

> 本文转载自 [ViewModel源码研究之聊聊onSaveInstanceState和onRetainNonConfigurationInstance的区别](https://juejin.cn/post/6987566061499449357)（作者：字节小站）。版权归原作者所有，此处仅作个人学习备份。

# 1. 前言

最近在研究**ViewModel**实现原理。**ViewModel**有两个特性。

1. 当配置发生改变时（例如：**旋转屏幕**），重新创建的**Activity**能够通过**ViewModel**将数据还原回来，
2. 当按返回键或者调用**finish**方法时，**ViewModel**能够感知到**onDestroy**事件，同时将**ViewModel**保存的**Closeable**对象关闭掉（例如：**主动关闭协程**）

当屏幕旋转时，会调用**Activity**的**onRetainNonConfigurationInstance**方法。**ViewModel**组件正是通过该方法将**ViewModel**保存起来，给重建的**Activity**使用。

```java
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

1. **onRetainNonConfigurationInstance()** 调用场景是当configuration发生改变时，例如：旋转屏幕。

**那么问题来了，一共有三个**

> 1. 它们存储的状态数据颗粒度一样吗？
> 2. 它们把状态数据存储到哪里去了？
> 3. 如果系统后台将Activity杀掉后，它们都能把状态恢复回来吗？

为了搞清楚这些问题，首先我在 **"小站交流群"** 提出了这些问题，幸运得是得到了一些积极的反馈。得到了一些结论和线索之后，便开始从源码中寻找答案，期间也遇到了一些问题，比如：**ActivityManagerService**的**activityStopped**方法的远程代理调用找不到，在群友们的帮助下，最终顺利找到，交流的过程中还是有不少收获。

# 2. onSaveInstanceState(Bundle outState)方法详解

首先在**ComponentActivity**的**onSaveInstanceState(Bundle outState)** 方法中加个断点。调用栈如下： ![img](https://cdn.jsdelivr.net/gh/hxmeie/tuchuang/images/20260713175944049.awebp) **重点关注ActivityThread.callActivityOnSaveInstanceState(Bundle outState)**

## 2.1 ActivityThread.callActivityOnSaveInstanceState(Bundle outState)

```java
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

**重点关注ActivityThread.handleStopActivity()**

## 2.2 ActivityThread.handleStopActivity()

```java
public void handleStopActivity(IBinder token, boolean show, int configChanges,
        PendingTransactionActions pendingActions, boolean finalStateRequest, String reason) {
    final ActivityClientRecord r = mActivities.get(token);
    r.activity.mConfigChangeFlags |= configChanges;

    final StopInfo stopInfo = new StopInfo();
    performStopActivityInner(r, stopInfo, show, true /* saveState */, finalStateRequest,
            reason);

    if (localLOGV) Slog.v(
        TAG, "Finishing stop of " + r + ": show=" + show
        + " win=" + r.window);

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

**注意到pendingActions.setStopInfo(stopInfo)**

## 2.3 PendingTransactionActions$StopInfo.run()

```java
@Override
public void run() {
    // Tell activity manager we have been stopped.
    try {
        if (DEBUG_MEMORY_TRIM) Slog.v(TAG, "Reporting activity stopped: " + mActivity);
        // TODO(lifecycler): Use interface callback instead of AMS.
        ActivityManager.getService().activityStopped(
                mActivity.token, mState, mPersistentState, mDescription);
    } catch (RemoteException ex) {
        // Dump statistics about bundle to help developers debug
        final LogWriter writer = new LogWriter(Log.WARN, TAG);
        final IndentingPrintWriter pw = new IndentingPrintWriter(writer, "  ");
        pw.println("Bundle stats:");
        Bundle.dumpStats(pw, mState);
        pw.println("PersistableBundle stats:");
        Bundle.dumpStats(pw, mPersistentState);

        if (ex instanceof TransactionTooLargeException
                && mActivity.packageInfo.getTargetSdkVersion() < Build.VERSION_CODES.N) {
            Log.e(TAG, "App sent too much data in instance state, so it was ignored", ex);
            return;
        }
        throw ex.rethrowFromSystemServer();
    }
}
```

该方法调用了ActivityManager.getService().activityStopped(mActivity.token, mState, mPersistentState, mDescription)方法。还将2.1中创建的mState当参数传进来了。

## 2.4 ActivityManagerService.activityStopped()

```java
//ActivityManagerService.java
@Override
public final void activityStopped(IBinder token, Bundle icicle,
        PersistableBundle persistentState, CharSequence description) {
    if (DEBUG_ALL) Slog.v(TAG, "Activity stopped: token=" + token);

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

重点关注r.activityStoppedLocked(icicle, persistentState, description)

## 2.5 ActivityRecord.activityStoppedLocked

```java
final void activityStoppedLocked(Bundle newIcicle, PersistableBundle newPersistentState,
        CharSequence description) {
    final ActivityStack stack = getStack();
    if (mState != STOPPING) {
        Slog.i(TAG, "Activity reported stop, but no longer stopping: " + this);
        stack.mHandler.removeMessages(STOP_TIMEOUT_MSG, this);
        return;
    }
    if (newPersistentState != null) {
        persistentState = newPersistentState;
        service.notifyTaskPersisterLocked(task, false);
    }
    if (DEBUG_SAVED_STATE) Slog.i(TAG_SAVED_STATE, "Saving icicle of " + this + ": " + icicle);

    if (newIcicle != null) {
        icicle = newIcicle;
        haveState = true;
        launchCount = 0;
        updateTaskDescription(description);
    }
    if (!stopped) {
        if (DEBUG_STATES) Slog.v(TAG_STATES, "Moving to STOPPED: " + this + " (stop complete)");
        stack.mHandler.removeMessages(STOP_TIMEOUT_MSG, this);
        stopped = true;
        setState(STOPPED, "activityStoppedLocked");

        mWindowContainerController.notifyAppStopped();

        if (finishing) {
            clearOptionsLocked();
        } else {
            if (deferRelaunchUntilPaused) {
                stack.destroyActivityLocked(this, true /* removeFromApp */, "stop-config");
                mStackSupervisor.resumeFocusedStackTopActivityLocked();
            } else {
                mStackSupervisor.updatePreviousProcessLocked(this);
            }
        }
    }
}
```

我们注意到最终**bundle**数据会保存在**ActivityRecord**的**icicle**对象中。

------

**总结**：**onSaveInstanceState**方法是当**Activity**调用了**onStop**后，会调用到**ActivityThread**的**callActivityOnSaveInstanceState()\**方法，把\**Activity**需要保存的数据放入**Bundle**对象中，并且随后通过IPC进程间通信机制，调用**ActivityManagerService的activityStopped**方法，将**Bundle**对象保存到AMS端的**ActivityRecord**中。

## 2.6 被杀端后恢复数据过程

![img](https://cdn.jsdelivr.net/gh/hxmeie/tuchuang/images/20260713190931081.awebp)

## 2.7 ActivityStackSupervisor.realStartActivityLocked

```java
//ActivityStackSupervisor.java
final boolean realStartActivityLocked(ActivityRecord r, ProcessRecord app,
          boolean andResume, boolean checkConfig) throws RemoteException {
     // 忽略其它代码
     // Create activity launch transaction.
      final ClientTransaction clientTransaction = ClientTransaction.obtain(app.thread,
              r.appToken);
      clientTransaction.addCallback(LaunchActivityItem.obtain(new Intent(r.intent),
              System.identityHashCode(r), r.info,
              // TODO: Have this take the merged configuration instead of separate global
              // and override configs.
              mergedConfiguration.getGlobalConfiguration(),
              mergedConfiguration.getOverrideConfiguration(), r.compat,
              r.launchedFromPackage, task.voiceInteractor, app.repProcState, r.icicle,
              r.persistentState, results, newIntents, mService.isNextTransitionForward(),
              profilerInfo));
    // 忽略其它代码
}
```

**我们看到最终是通过ActivityRecord.icicle恢复数据。**

## 2.8 LaunchActivityItem.execute()

```java
//LaunchActivityItem.java
@Override
public void execute(ClientTransactionHandler client, IBinder token,
        PendingTransactionActions pendingActions) {
    Trace.traceBegin(TRACE_TAG_ACTIVITY_MANAGER, "activityStart");
    ActivityClientRecord r = new ActivityClientRecord(token, mIntent, mIdent, mInfo,
            mOverrideConfig, mCompatInfo, mReferrer, mVoiceInteractor, mState, mPersistentState,
            mPendingResults, mPendingNewIntents, mIsForward,
            mProfilerInfo, client);
    client.handleLaunchActivity(r, pendingActions, null /* customIntent */);
    Trace.traceEnd(TRACE_TAG_ACTIVITY_MANAGER);
}
```

## 2.9 ActivityThread.performLaunchActivity(ActivityClientRecord r, Intent customIntent)

```java
private Activity performLaunchActivity(ActivityClientRecord r, Intent customIntent){
   activity.mCalled = false;
    if (r.isPersistable()) {
        mInstrumentation.callActivityOnCreate(activity, r.state, r.persistentState);
    } else {
        mInstrumentation.callActivityOnCreate(activity, r.state);
    }
}
```

# 3. onRetainNonConfigurationInstance()

![img](https://cdn.jsdelivr.net/gh/hxmeie/tuchuang/images/20260713191159207.awebp)

该方法是在重建**Activity**时调用**performDestoryActivity**时会保存数据。

```java
ActivityClientRecord performDestroyActivity(IBinder token, boolean finishing,
          int configChanges, boolean getNonConfigInstance, String reason) {
  ActivityClientRecord r = mActivities.get(token);
  //省略一些代码
      if (getNonConfigInstance) {
          try {
              r.lastNonConfigurationInstances
                      = r.activity.retainNonConfigurationInstances();
          } catch (Exception e) {
              if (!mInstrumentation.onException(r.activity, e)) {
                  throw new RuntimeException(
                          "Unable to retain activity "
                          + r.intent.getComponent().toShortString()
                          + ": " + e.toString(), e);
        }
      }
  }
```

我们可以看到**onRetainNonConfigurationInstance**方法返回的**Object**会赋值给**ActivityClientRecord**的**lastNonConfigurationInstances**。

# 4. 答案

1. 颗粒度不一样。**onSaveInstanceState()\**是保存到\**Bundle**中，只能保存**Bundle**能接受的数据类型，比如一些基本类型的数据。而**onRetainNonConfigurationInstance()** 可以保存任何类型的数据，数据类型是**Object**
2. **onSaveInstanceState()\**数据最终存储到\**ActivityManagerService**的**ActivityRecord**中了，也就是存到**系统进程**中去了。而**onRetainNonConfigurationInstance()** 数据是存储到**ActivityClientRecord**中，也就是存到**应用本身的进程**中了
3. **onSaveInstanceState**存到系统进程中，所以App被杀之后还是能恢复的。而**onRetainNonConfigurationInstance**存到本身进程中，App被杀是没法恢复的。
