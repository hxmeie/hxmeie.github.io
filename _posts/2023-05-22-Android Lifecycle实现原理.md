---
categories: [面试复习,知识点]
title: Android Lifecycle实现原理
date: 2023-05-22 13:49:00 +0800
last_modified_at: 
tags: [转载,复习]
keywords: [面试,Android,lifecycle]
image:
  path: https://cdn.jsdelivr.net/gh/hxmeie/tuchuang@master/images/202305221346402.jpg
  lqip: /assets/img/placeholder.webp
  alt: Lifecyce原理解析
---

>转载自：<https://juejin.cn/post/6970624724493664287>
{: .prompt-info}

## 1.Lifecycle了解

- 到官方文档下看 **[Google Lifecycle](https://link.juejin.cn?target=https%3A%2F%2Fdeveloper.android.google.cn%2Fjetpack%2Fandroidx%2Freleases%2Flifecycle)**，Lifecycle的作用是：生命周期感知型组件可执行操作来响应另一个组件（如 Activity 和 Fragment）的生命周期状态的变化。这些组件有助于您写出更有条理且往往更精简的代码，这样的代码更易于维护。
- 我们之前开发，因为Activity 或者是 Fragment 的生命周期问题而间接引起的内存问题挺多的，比如每次都要写资源，或者控件工具的回收释放，如果忘记写了，那么可能会引起内存泄漏，而现在搭配 Lifecycle，给我们生命周期的回调，就不必再像以前在某个生命周期加上逻辑代码，而是直接提前写对应的代码，更好解决生命周期问题。

## 2.生命周期获取对比

### 2.1 之前的生命周期获取

- 我们需要Activity重写每一个生命周期的方法，在里面加入逻辑，如果某个回收忘记写了，就可能触发内存泄漏问题。

```java
override fun onPause() {
    super.onPause()
    Log.d(TAG, "onPause")
}

override fun onStop() {
    super.onStop()
    Log.d(TAG, "onStop")
}

override fun onStart() {
    super.onStart()
    Log.d(TAG, "onStart")
}

override fun onResume() {
    super.onResume()
    Log.d(TAG, "onResume")
}

override fun onRestart() {
    super.onRestart()
    Log.d(TAG, "onRestart")
}

override fun onDestroy() {
    super.onDestroy()   
    Log.d(TAG, "onDestroy")
}
```

![之前的生命周期](https://cdn.jsdelivr.net/gh/hxmeie/tuchuang@master/images/202305221354445.awebp)

### 2.2 Lifecycle回调生命周期

- 使用Lifecycle，只要拿到Activity的Lifecycle，注册观察，就能回调生命周期了，非常方便，如果写的自定义View或者工具，需要生命周期感知，就可以利用Lifecycle，将逻辑写在内部，代码也更间接，使用者也不要去注意创建回收问题。

```java
lifecycle.addObserver(object : LifecycleEventObserver {
    override fun onStateChanged(source: LifecycleOwner, event: Lifecycle.Event) {
      Log.d(TAG,event.toString())
    }
})
```

![Lifecycle](https://cdn.jsdelivr.net/gh/hxmeie/tuchuang@master/images/202305221354369.awebp)

## 3.源码分析

### 3.1 类关系图

![Lifecycle](https://cdn.jsdelivr.net/gh/hxmeie/tuchuang@master/images/202305221356941.awebp)

- 在Activity 获取 Lifecycle，实际上是通过Activity的父类 **ComponentActvitiy** 获取，父类实现了 **LifecycleOwner** 接口，就能获取 Lifecycle ,最后注册 **LifecycleObserver** 就能拿到生命周期回调了。

### 3.2 ComponentActvitiy.onCreate

- 在ComponentActvitiy的 **onCreate** 方法里面可以看到 **ReportFragment** 的创建。

```java
    /* ComponentActvitiy */
    @Override
    protected void onCreate(@Nullable Bundle savedInstanceState) {
        ...
        ReportFragment.injectIfNeededIn(this);
        ...
    }
```

### 3.3 getLifecycle方法

```java
    /* ComponentActvitiy */
  	private final LifecycleRegistry mLifecycleRegistry = new LifecycleRegistry(this);
  	
    @NonNull
    @Override
    public Lifecycle getLifecycle() {
        return mLifecycleRegistry;
    }
```

### 3.4 Lifecycle.Event

- Lifecycle.Event 是个枚举类，这里的生命周期 Event 并不是Fragment的，在后面的生命周期处理时会用上的。

```java
public enum Event {
        ON_CREATE,
        ON_START,
        ON_RESUME,
        ON_PAUSE,
        ON_STOP,
        ON_DESTROY,
        ON_ANY;
       ...
    }
```

### 3.5 ReportFragment的创建

- ReportFragment 是一个 **没有界面的Fragment**，如果有了解过Glide原理的同学，应该也知道这个方法，就是通过看不见的Fragment，来感知生命周期，让使用者无需考虑生命周期的问题。
- 在SDK29以上的版本 使用的是 **LifecycleCallbacks.registerIn(activity)**。

```java
    /* ReportFragment */
    public static void injectIfNeededIn(Activity activity) {
        if (Build.VERSION.SDK_INT >= 29) {
            // On API 29+, we can register for the correct Lifecycle callbacks directly
            LifecycleCallbacks.registerIn(activity);
        }
        // Prior to API 29 and to maintain compatibility with older versions of
        // ProcessLifecycleOwner (which may not be updated when lifecycle-runtime is updated and
        // need to support activities that don't extend from FragmentActivity from support lib),
        // use a framework fragment to get the correct timing of Lifecycle events
        android.app.FragmentManager manager = activity.getFragmentManager();
        if (manager.findFragmentByTag(REPORT_FRAGMENT_TAG) == null) {
            manager.beginTransaction().add(new ReportFragment(), REPORT_FRAGMENT_TAG).commit();
            // Hopefully, we are the first to make a transaction.
            manager.executePendingTransactions();
        }
    }
```

### 3.6 LifecycleCallbacks.registerIn(activity)

- LifecycleCallbacks 实现了  Application.ActivityLifecycleCallbacks接口，在SDK29以上的生命周期分发是由Application 分发的，activity注册就能回调。
- 大名鼎鼎的LeakCanary在监听Activity生命周期，也是使用 Application.ActivityLifecycleCallbacks。

```java
    @RequiresApi(29)
    static class LifecycleCallbacks implements Application.ActivityLifecycleCallbacks {
    
        static void registerIn(Activity activity) {
            activity.registerActivityLifecycleCallbacks(new LifecycleCallbacks());
        }
		...
        @Override
        public void onActivityPostCreated(@NonNull Activity activity,
                @Nullable Bundle savedInstanceState) {
            dispatch(activity, Lifecycle.Event.ON_CREATE);
        }
      ...
    }
```

### 3.7 ReportFragment.dispatch 版本兼容

- 如果SDK版本小于29，ReportFragment的各个生命周期方法里，会调用 dispatch 方法。
- 比如 onActivityCreated。
- 反正无论是使用 LifecycleCallbacks.registerIn(activity)，还是 Fragment 的生命周期回调，最后都会dispatch。

```java
    @Override
    public void onActivityCreated(Bundle savedInstanceState) {
        super.onActivityCreated(savedInstanceState);
        dispatchCreate(mProcessListener);
        dispatch(Lifecycle.Event.ON_CREATE);
    }

    private void dispatch(@NonNull Lifecycle.Event event) {
        if (Build.VERSION.SDK_INT < 29) {
            // Only dispatch events from ReportFragment on API levels prior
            // to API 29. On API 29+, this is handled by the ActivityLifecycleCallbacks
            // added in ReportFragment.injectIfNeededIn
            dispatch(getActivity(), event);
        }
    }
    
    static void dispatch(@NonNull Activity activity, @NonNull Lifecycle.Event event) {
        if (activity instanceof LifecycleRegistryOwner) {
            ((LifecycleRegistryOwner) activity).getLifecycle().handleLifecycleEvent(event);
            return;
        }

        if (activity instanceof LifecycleOwner) {
            Lifecycle lifecycle = ((LifecycleOwner) activity).getLifecycle();
            if (lifecycle instanceof LifecycleRegistry) {
                ((LifecycleRegistry) lifecycle).handleLifecycleEvent(event);
            }
        }
    }
```

### 3.8 Lifecycle.State

- 这个类跟Lifecycle.Event的关系看图就能理解。
- State只有5个但是生命周期可是不止5个，所以Google他们设计时，就创建流程正着走，销毁流程就反正走。

![Lifecycle.State](https://cdn.jsdelivr.net/gh/hxmeie/tuchuang@master/images/202305221356364.awebp)

```java
    /* Lifecycle.State */
    public enum State {
        DESTROYED,
      
        INITIALIZED,
      
        CREATED,
     
        STARTED,

        RESUMED;
        
        public boolean isAtLeast(@NonNull State state) {
            return compareTo(state) >= 0;
        }
    }
```

### 3.9 handleLifecycleEvent

- LifecycleRegistryOwner 也是继承 LifecycleOwner，所以他们最后都会执行 LifecycleRegistry 的 handleLifecycleEvent 方法。
- 就是把 Lifecycle.Event处理一下，转化成 Lifecycle.State。

```java
    /* Lifecycle.Event */
        @NonNull
        public State getTargetState() {
            switch (this) {
                case ON_CREATE:
                case ON_STOP:
                    return State.CREATED;
                case ON_START:
                case ON_PAUSE:
                    return State.STARTED;
                case ON_RESUME:
                    return State.RESUMED;
                case ON_DESTROY:
                    return State.DESTROYED;
                case ON_ANY:
                    break;
            }
            throw new IllegalArgumentException(this + " has no target state");
        }
```

- 将 Lifecycle.State 继续往下传，先用 mState 保存，再 sync 方法处理。

```java
    /* LifecycleRegistry  */
    public void handleLifecycleEvent(@NonNull Lifecycle.Event event) {
        enforceMainThreadIfNeeded("handleLifecycleEvent");
        moveToState(event.getTargetState());
    }

    private void moveToState(State next) {
        if (mState == next) {
            return;
        }
        //保存state状态
        mState = next;
        if (mHandlingEvent || mAddingObserverCounter != 0) {
            mNewEventOccurred = true;
            // we will figure out what to do on upper level.
            return;
        }
        mHandlingEvent = true;
        sync();
        mHandlingEvent = false;
    }
```

### 3.10 sync

- 这里利用上一个方法保存的mState，用于比较，判断是正向执行还是反向执行生命周期。

```java
    /* LifecycleRegistry  */
    private void sync() {
    	//这是弱引用包装过的LifecycleOwner 
        LifecycleOwner lifecycleOwner = mLifecycleOwner.get();
        if (lifecycleOwner == null) {
            throw new IllegalStateException("LifecycleOwner of this LifecycleRegistry is already"
                    + "garbage collected. It is too late to change lifecycle state.");
        }
        while (!isSynced()) {
            mNewEventOccurred = false;
            // no need to check eldest for nullability, because isSynced does it for us.
            //上一个方法保存的mState，跟组件之前的的mState对比
            if (mState.compareTo(mObserverMap.eldest().getValue().mState) < 0) {
            	//返向执行流程
                backwardPass(lifecycleOwner);
            }
           
            Map.Entry<LifecycleObserver, ObserverWithState> newest = mObserverMap.newest();
            if (!mNewEventOccurred && newest != null
                    && mState.compareTo(newest.getValue().mState) > 0) {
                //正向执行流程
                forwardPass(lifecycleOwner);
            }
        }
        mNewEventOccurred = false;
    }
```

### 3.11 forwardPass

- 反向的逻辑差不多，只是执行 backwardPass ，先转换Stata，最后执行  observer.dispatchEvent。
- 这里又把 Lifecycle.State 转回 Lifecycle.Event，然后给观察者分发出去。

```java
    /* Lifecycle.Event */
        @Nullable
        public static Event upFrom(@NonNull State state) {
            switch (state) {
                case INITIALIZED:
                    return ON_CREATE;
                case CREATED:
                    return ON_START;
                case STARTED:
                    return ON_RESUME;
                default:
                    return null;
            }
        }
```

- 转换 Event.upFrom ，发送 observer.dispatchEvent。

```java
    /* LifecycleRegistry  */
    private void forwardPass(LifecycleOwner lifecycleOwner) {
        Iterator<Map.Entry<LifecycleObserver, ObserverWithState>> ascendingIterator =
                mObserverMap.iteratorWithAdditions();
        while (ascendingIterator.hasNext() && !mNewEventOccurred) {
            Map.Entry<LifecycleObserver, ObserverWithState> entry = ascendingIterator.next();
            ObserverWithState observer = entry.getValue();
            while ((observer.mState.compareTo(mState) < 0 && !mNewEventOccurred
                    && mObserverMap.contains(entry.getKey()))) {
                pushParentState(observer.mState);

				//转化
                final Event event = Event.upFrom(observer.mState);
                if (event == null) {
                    throw new IllegalStateException("no event up from " + observer.mState);
                }
				//发送
                observer.dispatchEvent(lifecycleOwner, event);
                popParentState();
            }
        }
    }
```

### 3.12 发送生命周期状态

- ObserverWithState 发送出 Lifecycle.Event ，至此就结束了，有注册订阅关系的地方就能收到。

```java
    static class ObserverWithState {
        State mState;
        LifecycleEventObserver mLifecycleObserver;

        ObserverWithState(LifecycleObserver observer, State initialState) {
            mLifecycleObserver = Lifecycling.lifecycleEventObserver(observer);
            mState = initialState;
        }

		/* 分发生命周期状态 */
        void dispatchEvent(LifecycleOwner owner, Event event) {
            State newState = event.getTargetState();
            mState = min(mState, newState);
            mLifecycleObserver.onStateChanged(owner, event);
            mState = newState;
        }
    }
```

### 3.13 简易流程图

![简易流程图](https://cdn.jsdelivr.net/gh/hxmeie/tuchuang@master/images/202305221356151.awebp)