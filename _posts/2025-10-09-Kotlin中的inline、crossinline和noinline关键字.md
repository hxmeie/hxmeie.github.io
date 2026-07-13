---
categories: [知识点]
title: Kotlin中的inline、crossinline和noinline关键字
date: 2025-10-09 19:31:00 +0800
pin: false
tags: [kotlin]
keywords: [inline,crossinline,noinline]
---

**Kotlin** 中的 **`inline`**、**`crossinline`** 和 **`noinline`** 是在处理 **高阶函数** 时非常重要的关键字，它们主要用于优化性能和控制 lambda 表达式中的**非局部返回（non-local return）**行为。



## 1. `inline` (内联)

### 概念解释

- **`inline`** 关键字用于修饰函数。当一个函数被标记为 `inline` 时，编译器在编译时不会生成该函数的调用代码，而是会将**函数体**（包括作为参数传入的 lambda 表达式的代码）直接**复制并替换**到所有调用该函数的地方。
- **性能优化**：高阶函数（接收 lambda 作为参数的函数）在运行时会创建额外的对象（函数对象），这会带来运行时的开销（内存分配、垃圾回收）。`inline` 消除了这种开销，因为它将 lambda 代码直接嵌入了调用点，避免了创建匿名类和函数调用的性能损耗。
- **非局部返回**：`inline` 函数允许在作为参数传入的 lambda 表达式中使用 **非局部返回** (`return`)。这意味着你可以从 lambda 内部直接返回到调用该内联函数**外部的函数**。

### 适用场景

- 用于**高阶函数**，特别是那些接受 **lambda** 作为参数且代码量不大的函数（例如 Kotlin 标准库中的 `forEach`, `run`, `let`, `apply`, `with` 等）。
- 当你需要允许 lambda 表达式使用 **非局部返回** 时。

### 示例

```kotlin
fun main() {
    println("Start")
    testInline {
        println("Inside lambda before return")
        // 非局部返回：直接从 main 函数返回
        return
        // 这行代码不会被执行
        println("Inside lambda after return")
    }
    // 如果没有 'return'，这行代码会被执行
    println("End") 
}

// 这是一个内联函数
inline fun testInline(block: () -> Unit) {
    println("Before block execution")
    block() 
    println("After block execution")
}

// 输出: Start -> Before block execution -> Inside lambda before return
// (main函数直接返回了，所以后面的代码都不会执行)
```



## 2. `noinline` (非内联)



### 概念解释

- **`noinline`** 关键字用于修饰 **内联函数** 的其中一些 **函数类型参数**。
- 当一个内联函数中有多个函数类型参数时，如果你不希望其中某个（或某些）参数被内联，就可以使用 `noinline` 标记它。
- **作用**：被 `noinline` 标记的参数将作为**普通函数参数**处理，编译器会为它创建一个**函数对象**，运行时会有正常的函数调用开销。它**不能**进行 **非局部返回**。

### 适用场景

- 在**内联函数**中，如果某个 lambda 参数：
  1. 你需要在**运行时保留**它的函数对象（例如，将它存储在一个字段中，或者作为参数传递给另一个非内联函数）。
  2. 你**不希望**它支持非局部返回。

### 示例

```kotlin
inline fun testNoInline(
    inlineBlock: () -> Unit, // 这个参数会被内联
    noinline noInlineBlock: () -> Unit // 这个参数不会被内联
) {
    println("Executing inlineBlock...")
    inlineBlock() // 支持非局部返回
    
    println("Executing noInlineBlock...")
    // 无法在此处使用非局部返回：return 
    // 因为 noInlineBlock 仍然是一个正常的函数对象，只能使用局部返回
    noInlineBlock() 
    
    // 可以将 noInlineBlock 传递给非内联函数或保存起来
    saveFunction(noInlineBlock)
}

fun saveFunction(func: () -> Unit) {
    // 存储或传递函数对象
}
```



## 3. `crossinline` (交叉内联)



### 概念解释

- **`crossinline`** 关键字也用于修饰 **内联函数** 的其中一些 **函数类型参数**。
- **核心作用**：它**强制禁止**在被标记的 lambda 表达式中使用 **非局部返回**。
- 尽管被标记的 lambda 表达式仍然会被**内联**到调用点，但如果在其中使用 `return`，编译器会报错。

### 适用场景

- 用于**内联函数**中的 lambda 参数，当这个 lambda **最终会在另一个执行上下文**中被调用（例如，在另一个对象中、在另一个线程中，或者在另一个非内联函数内部）时。
- **目的**：确保内联 lambda 的执行流程是可预测和安全的，防止非局部返回破坏外部函数的控制流。

### 示例

```kotlin
// 这是一个内联函数
inline fun testCrossInline(
    // 虽然会被内联，但禁止非局部返回
    crossinline crossInlineBlock: () -> Unit 
) {
    // 假设这里是一个非内联函数，它会稍后执行 crossInlineBlock
    runFunctionLater {
        // 在这里使用 return 会导致编译错误
        // return // 编译错误: 'return' is not allowed here
        crossInlineBlock() // 调用 lambda
    }
}

// 这是一个普通的非内联函数
fun runFunctionLater(block: () -> Unit) {
    // 模拟在另一个上下文中执行
    block() 
}
```



## 总结和对比

| 关键字            | 修饰对象       | 是否内<br>联代码 | 是否允许非<br>局部返回 | 主要用途                                             |
| ----------------- | -------------- | ------------ | ----------------------------- | ---------------------------------------------------- |
| **`inline`**      | 函数           | **是**       | **是**                        | 优化高阶函数性能，<br>允许非局部返回                     |
| **`noinline`**    | 内联函数的参数 | **否**       | **否**                        | 禁止特定 lambda <br>内联，保留其函数对<br>象，禁止非局部返回 |
| **`crossinline`** | 内联函数的参数 | **是**       | **否**                        | 允许内联优化，但**强<br>制禁止**非局部返回               |
