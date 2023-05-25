---
categories: [Blog]
title: Kotlin 单例模式推荐写法
date: 2020-02-03 15:40:20 +0800
last_modified_at:
tags: [kotlin]
keywords: [kotlin,singleton]
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
