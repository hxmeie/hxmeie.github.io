---
layout: post
category: Blog
title: Kotlin 单例模式推荐写法
date: 2020-02-03 15:40:20
tags: Kotlin
keywords: Kotlin,kotlin,singleton
excerpt: Kotlin单例模式的推荐写法,张涛在极客时间的视频中讲过
---

```kotlin
class Singleton private constructor(){
  companion object {

    fun get() : Singleton{
      return Holder.instance
    }

    private object Holder{
      val instance = Singleton()
    }
  }
}
```
