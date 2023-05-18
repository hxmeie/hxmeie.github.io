---
categories: [Blog]
title: 延伸一个View的触摸（点击）区域
date: 2016-01-09 21:37:02 +0800
tags: [view,android]
keywords: [扩展触摸区域,延伸点击区域]
---


在我们的开发过程中可能会有这样的情况，我在xml布局文件中设置一个控件，如Button、ImageView等，他们的宽高给了固定值，但是这个值有点小，设置点击事件的时候，我们很难准确的在屏幕上触摸到它，改大了又对整体布局有影响或者其他原因不能改变宽高。那么这种情况下我们该怎么办呢？

Android源码中有一个类 **TouchDelegate**，这个类的作用就是帮助我们处理当你需要一个View的触摸区域大于它实际区域大小（宽高）时的情况。这个触摸区域被改变的View就叫做 **delegate view**,这个类应该被delegate view 的parent view所使用。

下面先讲一下使用的步骤，然后结合代码再来一遍加深印象。

1.获取parent view即你要改变的View所在的根布局，然后在主线程里post一个Runnable。这个是为了确保我们在调用`getHitRect()`方法之前parent已经将child view绘制出来了。`getHitRect(Rect outRect)`方法的作用是将你设置的触摸矩形区域返回给view。

2.获取child view，然后调用`getHitRect()`方法获取child view 触摸矩形区域。

3.实例化一个TouchDelegate,将child view和扩展的矩形触摸区域当做参数传进去。

4.将TouchDelegate设置给parent view,这样的话，矩形区域内的触摸事件都相当于是child view的。

废话不多说直接上代码：

**布局文件activity_main.xml**

``` xml
<?xml version="1.0" encoding="utf-8"?>
<RelativeLayout xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:tools="http://schemas.android.com/tools"
    android:id="@+id/root_view"
    android:layout_width="match_parent"
    android:layout_height="match_parent"
    tools:context="com.hxm.touchdelegate.MainActivity">

    <TextView
        android:id="@+id/text_view"
        android:layout_width="wrap_content"
        android:layout_height="wrap_content"
        android:text="h" />
</RelativeLayout>
```

**主要代码片段**

``` java
//获取 parent view
 View rootView = findViewById(R.id.root_view);
 rootView.post(new Runnable() {
    // post一个Runnable,这个是为了确保我们在调用`getHitRect()`方法之前parent已经将child view绘制出来了。
     @Override
     public void run() {
         //delegate view的边界(我这个例子里就是TextView要扩展的区域)
         Rect delegateArea = new Rect();
         TextView textView = (TextView) findViewById(R.id.text_view);
         textView.setOnClickListener(new View.OnClickListener() {
             @Override
             public void onClick(View view) {
                 Toast.makeText(MainActivity.this, "onclick", Toast.LENGTH_SHORT).show();
             }
         });
         //将扩展区域赋给 TextView
         textView.getHitRect(delegateArea);
         //我这里要将textView的右边和下边区域各扩展100，textview是顶着屏幕左上角的，扩展上下没意义
         delegateArea.right += 100;
         delegateArea.bottom += 100;
         //实例化一个TouchDelegate，并传参
         TouchDelegate touchDelegate = new TouchDelegate(delegateArea, textView);
         //将TouchDelegate设置给parent view
         if (View.class.isInstance(textView.getParent())) {
             ((View) textView.getParent()).setTouchDelegate(touchDelegate);
         }
     }
 });
```
将上面的代码运行后，你会发现“h”这个字母的点击区域确实扩大了。
