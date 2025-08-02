---
categories: [知识点]
title: Android MVI架构详解
date: 2025-07-29 14:15:00 +0800
pin: false
last_modified_at: 2025-08-02 15:41:00 +0800
tags: [android,mvi,compose]
keywords: [MVI]
image:
  path: https://cdn.jsdelivr.net/gh/hxmeie/tuchuang@master/images/202508021635671.jpg
  lqip: /assets/img/placeholder.webp
  alt: MVI架构详解
---

### 什么是 MVI 架构？

MVI 是 **Model-View-Intent** 的缩写，它是一种现代的、响应式的应用架构模式。其灵感来源于前端框架（如 React 中的 Redux），核心思想是**单向数据流 (Unidirectional Data Flow)** 和**唯一数据源 (Single Source of Truth)**。

与 MVVM 或 MVP 不同，MVI 旨在使应用的状态管理更加可预测、可维护和可测试。

### MVI 的核心组件

MVI 将应用的逻辑分为三个主要部分：

1. **Model (模型)**
   - 这不代表传统意义上的数据层（如 Repository）。在 MVI 中，Model 特指 **UI 的状态 (UI State)**。
   - 它是一个**不可变 (Immutable)** 的数据对象，包含了渲染当前界面所需的所有信息。例如：加载状态、数据列表、错误信息等。
   - 每当状态需要改变时，不是去修改现有对象，而是创建一个包含新状态的**全新对象**。
2. **View (视图)**
   - 负责渲染 Model 所描述的 UI 状态，并捕获用户的交互操作。在现代 Android 开发中，这通常是 Activity、Fragment 或 Jetpack Compose 的 Composable 函数。
   - View 的职责非常“被动”，它只做两件事：**显示状态**和**发送用户的操作意图**。它本身不包含任何业务逻辑。
3. **Intent (意图)**
   - **注意：** 这里的“Intent”与 Android 系统中用于启动组件的 `android.content.Intent` **完全不同**。
   - 它代表了用户的一个**操作意图**或**业务请求**。例如，“点击刷新按钮”、“加载下一页数据”、“在输入框输入了文字”等，都可以被建模为一个 Intent。它是一个描述用户“想要做什么”的对象。

### MVI 的数据流转：一个封闭的循环

MVI 的数据流遵循一个严格且可预测的循环，这也是它的精髓所在：

1. **用户操作 -> Intent**：用户在 **View** 上进行操作（如点击按钮）。
2. **Intent -> ViewModel**：**View** 将这个操作包装成一个 **Intent** 对象，并发送给处理逻辑的地方（通常是 ViewModel）。
3. **ViewModel 处理 Intent**：ViewModel 接收到 **Intent**，根据其类型执行相应的业务逻辑（如发起网络请求、读写数据库等）。
4. **业务逻辑 -> 新的 Model**：业务逻辑执行完毕后，ViewModel 会基于当前状态和业务结果，创建一个**全新的 Model (State)** 对象来反映 UI 的变化。
5. **新 Model -> View**：ViewModel 将这个新的 **Model** 发送出去（通常通过 `StateFlow`）。
6. **View 渲染新 Model**：**View** 一直在监听 **Model** 的变化。一旦接收到新的 Model，它就会用新数据**完全重新渲染**自己的界面。

这个过程形成了一个封闭的、单向的循环，使得任何状态的变化都有迹可循，极大地简化了调试过程。

### MVI 的优势

- **可预测性**：由于数据流是单向的，状态的每一次变更都源于一个明确的 Intent，这使得追踪和复现 Bug 变得非常容易。
- **唯一数据源**：UI 的所有状态都集中在一个不可变的 State 对象中，避免了多个数据源导致的状态不一致问题。
- **高度可测试性**：ViewModel 的逻辑变得非常纯粹：输入一个旧 State 和一个 Intent，输出一个新 State。这种纯函数式的逻辑非常容易进行单元测试。
- **线程安全**：由于 State 对象是不可变的，你可以在任何线程中创建新的 State，而不用担心多线程并发修改导致的问题。
- **与声明式 UI 完美契合**：MVI 的思想与 Jetpack Compose 等声明式 UI 框架天生一对。UI 就是状态的映射函数 (`UI = f(State)`)，这与 MVI 的理念完全一致。

接下来，我将提供一个具体的代码示例来演示这个流程。

```kotlin
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlin.random.Random

// 1. 定义 Contract: State 和 Intent
// =================================================================

/**
 * 定义 UI 状态 (Model)
 * @param isLoading 是否正在加载
 * @param quote 当前显示的引言
 * @param error 错误信息，如果没有错误则为 null
 */
data class MainUiState(
    val isLoading: Boolean = false,
    val quote: String = "点击按钮获取一句名言",
    val error: String? = null
)

/**
 * 定义用户意图 (Intent)
 * 使用 sealed interface/class 可以限制意图的类型
 */
sealed interface MainIntent {
    object FetchQuote : MainIntent
}


// 2. 创建 ViewModel
// =================================================================

class MainViewModel : ViewModel() {

    // _state 是可变的，且是私有的，只能在 ViewModel 内部修改
    private val _state = MutableStateFlow(MainUiState())
    // state 是暴露给外部的、不可变的 StateFlow，用于 UI 观察
    val state = _state.asStateFlow()

    /**
     * ViewModel 的核心职责：接收 Intent，并将其转化为 State 的变更
     */
    fun handleIntent(intent: MainIntent) {
        when (intent) {
            is MainIntent.FetchQuote -> {
                fetchQuote()
            }
        }
    }

    private fun fetchQuote() {
        viewModelScope.launch {
            // 步骤 1: 发出“加载中”的状态
            _state.value = _state.value.copy(isLoading = true, error = null)

            try {
                // 步骤 2: 模拟网络请求
                delay(1500) // 模拟 1.5 秒的网络延迟

                // 模拟成功或失败
                if (Random.nextBoolean()) {
                    val newQuote = mockQuotes.random()
                    // 步骤 3 (成功): 发出包含新数据的状态
                    _state.value = _state.value.copy(isLoading = false, quote = newQuote)
                } else {
                    // 步骤 3 (失败): 抛出异常
                    throw RuntimeException("网络连接失败！")
                }

            } catch (e: Exception) {
                // 步骤 4 (捕获异常): 发出包含错误信息的状态
                _state.value = _state.value.copy(isLoading = false, error = e.message)
            }
        }
    }

    // 模拟一些数据
    private val mockQuotes = listOf(
        "生活就像一盒巧克力，你永远不知道下一颗是什么味道。",
        "Stay hungry, stay foolish.",
        "代码就是最好的文档。",
        "你唯一需要回头的时候，是为了看自己走了多远。"
    )
}


// 3. 创建 View (Activity + Jetpack Compose)
// =================================================================

class MainActivity : ComponentActivity() {

    private val viewModel: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MviExampleTheme {
                // 将 ViewModel 的 state 和 intent 处理函数传入 Composable
                MainScreen(
                    state = viewModel.state.collectAsState().value,
                    onIntent = { intent -> viewModel.handleIntent(intent) }
                )
            }
        }
    }
}

@Composable
fun MainScreen(state: MainUiState, onIntent: (MainIntent) -> Unit) {
    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(24.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            // 根据 state.quote 显示文本
            Text(
                text = state.quote,
                style = MaterialTheme.typography.headlineSmall,
                textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(40.dp))

            // 根据 state.isLoading 决定显示加载圈还是按钮
            if (state.isLoading) {
                CircularProgressIndicator()
            } else {
                Button(
                    onClick = { onIntent(MainIntent.FetchQuote) },
                    // 加载中时禁用按钮
                    enabled = !state.isLoading
                ) {
                    Text(text = "获取下一句")
                }
            }

            // 如果 state.error 不为 null，则显示错误信息
            state.error?.let {
                Spacer(modifier = Modifier.height(24.dp))
                Text(
                    text = it,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
    }
}

// 主题和预览
@Composable
fun MviExampleTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = darkColorScheme(), // 使用深色主题
        content = content
    )
}

@Preview(showBackground = true)
@Composable
fun DefaultPreview() {
    MviExampleTheme {
        MainScreen(
            state = MainUiState(quote = "这是一个预览"),
            onIntent = {}
        )
    }
}

@Preview(showBackground = true)
@Composable
fun LoadingPreview() {
    MviExampleTheme {
        MainScreen(
            state = MainUiState(isLoading = true),
            onIntent = {}
        )
    }
}

@Preview(showBackground = true)
@Composable
fun ErrorPreview() {
    MviExampleTheme {
        MainScreen(
            state = MainUiState(error = "加载失败了！"),
            onIntent = {}
        )
    }
}

```



### MVI 与 MVVM 的对比



MVI 经常被拿来与 MVVM (Model-View-ViewModel) 进行比较。它们的主要区别在于：

| 特性         | MVVM                                                         | MVI                                                          |
| ------------ | ------------------------------------------------------------ | ------------------------------------------------------------ |
| **数据流**   | 通常是双向的（通过数据绑定），但也可以实现单向。             | 严格的单向数据流。                                           |
| **状态管理** | ViewModel 可能会暴露多个可变的 `LiveData` 或 `StateFlow` 来代表不同的 UI 状态。 | ViewModel 只暴露一个唯一的、不可变的 `State` 对象（通常通过 `StateFlow`）。 |
| **用户操作** | View 直接调用 ViewModel 的方法。                             | View 发送 `Intent` (意图) 给 ViewModel。                     |



### 一个简单的 MVI 示例代码 2 (Kotlin + Jetpack Compose)

下面，我们通过一个简单的例子来演示 MVI 架构。这个例子将实现一个功能：点击按钮从网络加载一条随机的“一言” (Hitokoto) 并显示在屏幕上，同时处理加载和错误状态。

我们将使用 Kotlin Coroutines 和 Flow 来实现异步操作和响应式的数据流。

#### 1. 定义 State 和 Intent

首先，我们需要定义 UI 的状态 (`MainState`) 和用户的意图 (`MainIntent`)。

```kotlin
// MainContract.kt

// 定义 UI 状态
data class MainState(
    val isLoading: Boolean = false,
    val hitokoto: String = "点击按钮获取一言",
    val error: String? = null
)

// 定义用户意图
sealed class MainIntent {
    object FetchHitokoto : MainIntent()
}
```



#### 2. 创建 ViewModel

ViewModel 负责接收 `Intent`，处理业务逻辑，并生成新的 `State`。

```kotlin
// MainViewModel.kt

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.consumeAsFlow
import kotlinx.coroutines.launch

class MainViewModel : ViewModel() {

    // 使用 Channel 来接收一次性的 Intent
    val intentChannel = Channel<MainIntent>(Channel.UNLIMITED)

    private val _state = MutableStateFlow(MainState())
    val state = _state.asStateFlow()

    init {
        handleIntent()
    }

    private fun handleIntent() {
        viewModelScope.launch {
            intentChannel.consumeAsFlow().collect { intent ->
                when (intent) {
                    is MainIntent.FetchHitokoto -> fetchHitokoto()
                }
            }
        }
    }

    private fun fetchHitokoto() {
        viewModelScope.launch {
            // 1. 设置加载状态
            _state.value = _state.value.copy(isLoading = true, error = null)

            // 2. 模拟网络请求
            try {
                // 在实际项目中，这里会调用 Repository 来获取数据
                kotlinx.coroutines.delay(1500) // 模拟网络延迟
                val newHitokoto = "人生得意须尽欢，莫使金樽空对月。" // 模拟获取到的数据

                // 3. 更新成功状态
                _state.value = _state.value.copy(isLoading = false, hitokoto = newHitokoto)
            } catch (e: Exception) {
                // 4. 更新失败状态
                _state.value = _state.value.copy(isLoading = false, error = "加载失败，请重试")
            }
        }
    }
}
```



#### 3. 构建 View (Jetpack Compose)

View 负责观察 `State` 的变化并渲染 UI，同时在用户交互时发送 `Intent`。

```kotlin
// MainActivity.kt

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.viewModels
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    private val viewModel: MainViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            MviExampleTheme {
                MainScreen(
                    state = viewModel.state.collectAsState().value,
                    onIntent = { intent ->
                        lifecycleScope.launch {
                            viewModel.intentChannel.send(intent)
                        }
                    }
                )
            }
        }
    }
}

@Composable
fun MainScreen(state: MainState, onIntent: (MainIntent) -> Unit) {
    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center
        ) {
            Text(
                text = state.hitokoto,
                style = MaterialTheme.typography.headlineSmall,
                textAlign = TextAlign.Center
            )

            Spacer(modifier = Modifier.height(32.dp))

            if (state.isLoading) {
                CircularProgressIndicator()
            } else {
                Button(
                    onClick = { onIntent(MainIntent.FetchHitokoto) },
                    enabled = !state.isLoading
                ) {
                    Text(text = "获取一言")
                }
            }

            state.error?.let {
                Spacer(modifier = Modifier.height(16.dp))
                Text(
                    text = it,
                    color = MaterialTheme.colorScheme.error,
                    style = MaterialTheme.typography.bodyMedium
                )
            }
        }
    }
}
```

### 总结

MVI 架构通过其严格的单向数据流和集中的状态管理，为构建复杂且高质量的 Android 应用提供了一个强大的范式。虽然在初次接触时，可能会觉得相比 MVVM 需要编写更多的模板代码（如定义 State 和 Intent），但这种投入在项目的长期维护性和可测试性上会带来巨大的回报。尤其是在使用 Jetpack Compose 这种声明式 UI 框架时，MVI 的思想能够与之完美契合，让 UI 的更新逻辑变得更加清晰和自然。希望通过本文的讲解和示例，您能对 MVI 架构有一个更深入的理解，并能在您的下一个项目中尝试使用它。
