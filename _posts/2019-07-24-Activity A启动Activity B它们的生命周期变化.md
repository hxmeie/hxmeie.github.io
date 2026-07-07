---
categories: [转载, Android]
title: Activity A启动Activity B它们的生命周期变化
date: 2019-07-24 10:00:00 +0800
pin: false
tags: [转载, android]
keywords: [Activity, 生命周期, onStop, 透明主题, onResume]
---

> 本文转载自 [Activity A启动Activity B它们的生命周期变化](https://blog.csdn.net/weixin_43589682/article/details/97030740)。版权归原作者所有，此处仅作个人学习备份。

当活动启动另一个活动的时候，应该考虑被启动的活动的可见性。

**1. 当 Activity B 覆盖 A 导致 A 完全不可见时：**

两个活动的生命周期变化为：

```bash
//【1】部署程序
D/MainActivity: onCreate------A
D/MainActivity: onStart-------A
D/MainActivity: onResume------A

//【2】点击A中的按钮开始跳转到B
D/MainActivity: onPause-------A
D/SecondActivity: onCreate----B
D/SecondActivity: onStart-----B
D/SecondActivity: onResume----B
D/MainActivity: onStop--------A

//【3】然后点击返回键从B返回A
D/SecondActivity: onPause-----B
D/MainActivity: onRestart-----A
                onStart-------A
D/MainActivity: onResume------A
D/SecondActivity: onStop------B
D/SecondActivity: onDestroy---B
```

**2. 当 Activity B 背景被设置为透明（相当于发生跳转后，A 部分可见）：**

它们的生命周期的变化为：

```bash
//【1】部署程序
D/MainActivity: onCreate------A
D/MainActivity: onStart-------A
D/MainActivity: onResume------A

//【2】点击A中的按钮开始跳转到B
D/MainActivity: onPause-------A
D/SecondActivity: onCreate----B
D/SecondActivity: onStart-----B
D/SecondActivity: onResume----B

//【3】然后点击返回键从B返回A
D/SecondActivity: onPause-----B
D/MainActivity: onResume------A
D/SecondActivity: onStop------B
D/SecondActivity: onDestroy---B
```

**总结**：当 A 启动 B 时，并且启动之后 A 还处于部分可见状态，当启动完 B 之后并不回调 A 的 onStop() 方法。

Activity 的生命周期图：

![Activity生命周期](https://cdn.jsdelivr.net/gh/hxmeie/tuchuang/images/20260706173520135.jpeg)

小笔记：(设置 Activity 的透明度为半透明)

```java
//【1】AndroidManifest.xml里的Activity标签里配置透明主题：
android:theme="@android:style/Theme.Translucent.NoTitleBar"

//【2】一般创建Activity的时候都是默认继承AppCompatActivity的（这种情况下设置透明主题程序会崩溃），需要继承自Activity
public class MainActivity extends Activity {...}
```

第二步中设置透明主题的时候因为 Theme.AppCompat 中没有 Translucent，因此会导致程序崩溃。

