---
categories: [知识点]
title: MVI 架构模式中的 UiState 设计：单一、嵌套与 `sealed class` 的应用
date: 2025-07-29 18:27:00 +0800
pin: false
last_modified_at: 2025-08-02 15:43:00 +0800
tags: [android,compose]
keywords: [MVI]
---


在 MVI (Model-View-Intent) 架构模式中，**`UiState` 是核心概念之一**，它代表了用户界面在任何给定时刻的完整且不可变的状态。理解如何有效设计 `UiState` 对于构建清晰、可预测且易于维护的应用至关重要。

------



## 1. MVI 中 ViewModel 的 UiState：单一性与最佳实践

在 MVI 架构中，推荐**每个屏幕（或功能模块）只对应一个 `ViewModel`，并且该 `ViewModel` 暴露一个单一的 `UiState`。**

### 为什么推荐单一 `UiState`？

MVI 的核心理念是**单向数据流（Unidirectional Data Flow）和状态的不可变性（Immutability）**。单一 `UiState` 具有以下显著优势：

- **清晰且可预测：** 整个 UI 的状态被封装在一个对象中，使得状态变化更容易理解和预测 UI 行为。
- **简化调试：** 当问题出现时，可以更轻松地追踪状态变化历史，快速定位问题。
- **确保一致性：** 避免了 UI 不同部分状态不一致的情况，因为所有组件都响应同一个状态。
- **易于测试：** 单一、不可变的 `UiState` 简化了单元测试和 UI 测试。
- **时间旅行调试：** 有助于实现时间旅行调试，回溯到任意 `UiState` 来查看 UI 在那一刻的样子。

尽管技术上可以在 `ViewModel` 中管理多个独立的 `UiState` 对象（例如，使用不同的 `StateFlow` 或 `LiveData`），但这通常**不符合 MVI 的最佳实践**，并可能导致状态分散、同步问题以及调试复杂性。

------



## 2. 嵌套的 UiState：管理复杂 UI 状态的有效方式

当 UI 状态变得复杂时，一个巨大的 `UiState` 可能难以管理。此时，推荐使用**嵌套的 `UiState`**，即将大的 `UiState` 拆分成更小、更具体的**不可变的数据类**，并作为属性嵌套在主 `UiState` 中。



### 示例代码：用户资料页面的嵌套 `UiState`

以下是一个用户资料页面的示例，展示了如何使用嵌套 `UiState` 来组织页面状态：

```kotlin
// 1. 定义子状态数据类
data class LoadingState(
    val isLoading: Boolean = false,
    val errorMessage: String? = null
)

data class UserDataState(
    val userId: String? = null,
    val userName: String? = null,
    val userEmail: String? = null,
    val profileImageUrl: String? = null
)

// 2. 定义主 UiState，包含嵌套的子状态
data class UserProfileUiState(
    val loading: LoadingState = LoadingState(),     // 嵌套 LoadingState
    val userData: UserDataState = UserDataState(),   // 嵌套 UserDataState
    val isEditing: Boolean = false                  // 页面特有的其他状态
)

// 3. ViewModel 示例
class UserProfileViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(UserProfileUiState())
    val uiState: StateFlow<UserProfileUiState> = _uiState.asStateFlow()

    init {
        fetchUserProfile()
    }

    private fun fetchUserProfile() {
        viewModelScope.launch {
            // 设置加载状态
            _uiState.update { currentState ->
                currentState.copy(loading = currentState.loading.copy(isLoading = true, errorMessage = null))
            }

            try {
                // 模拟网络请求和数据获取
                delay(2000)
                val fetchedUser = User(id = "123", name = "张三", email = "zhangsan@example.com", imageUrl = "https://example.com/avatar.jpg")

                // 更新用户数据和加载状态
                _uiState.update { currentState ->
                    currentState.copy(
                        loading = currentState.loading.copy(isLoading = false),
                        userData = UserDataState(
                            userId = fetchedUser.id,
                            userName = fetchedUser.name,
                            userEmail = fetchedUser.email,
                            profileImageUrl = fetchedUser.imageUrl
                        )
                    )
                }
            } catch (e: Exception) {
                // 处理错误
                _uiState.update { currentState ->
                    currentState.copy(loading = currentState.loading.copy(isLoading = false, errorMessage = "加载失败: ${e.message}"))
                }
            }
        }
    }

    // 示例：更新用户姓名
    fun updateUserName(newName: String) {
        _uiState.update { currentState ->
            currentState.copy(
                userData = currentState.userData.copy(userName = newName)
            )
        }
    }

    // 示例：切换编辑模式
    fun toggleEditMode() {
        _uiState.update { currentState ->
            currentState.copy(isEditing = !currentState.isEditing)
        }
    }
}

// 模拟数据模型
data class User(
    val id: String,
    val name: String,
    val email: String,
    val imageUrl: String
)
```

**代码解析：**

1. **`LoadingState` 和 `UserDataState`：** 这些是独立的**不可变 `data class`**，分别封装了加载过程和用户数据相关的状态。
2. **`UserProfileUiState`：** 这是 `ViewModel` 暴露的**主 `UiState`**。它通过**组合**的方式，将 `LoadingState` 和 `UserDataState` 的实例作为其属性。此外，它还可以包含页面特有的其他状态，如 `isEditing`。
3. **`UserProfileViewModel`：** 在更新状态时，使用 `copy()` 方法创建一个**新的 `UserProfileUiState` 实例**，并只更新需要改变的部分。例如，`currentState.copy(loading = currentState.loading.copy(isLoading = true))` 仅更新了 `loading` 子状态中的 `isLoading` 字段。

这种方法保持了单一 `UiState` 的概念，但通过内部结构使其更易于管理和扩展。

------



## 3. `UiState` 与 `sealed class` 的应用场景差异

在 MVI 架构中，**`UiState` 通常使用 `data class` 而不是直接使用 `sealed class`**，这主要是因为它们的设计目的和表示方式不同。

### `data class` 用于表示**组合**的状态

- **组合性：** `data class` 能够轻松地将多个独立的数据点（如用户名、加载状态、错误信息、列表数据等）**组合**成一个单一的、内聚的对象，表达 UI 在任何给定时刻的**完整状态**。
- **可变性（通过 `copy` 方法）：** MVI 强调状态的不可变性，即每次状态更新都会生成一个**新的 `UiState` 实例**。`data class` 提供的 `copy()` 方法是实现这一点的最佳方式，它允许高效地创建新对象，只改变需要更新的属性，而保持其他属性不变。
- **表达连续性：** `UiState` 代表了 UI 的连续演变，在一个统一的状态模型中进行微调。

### `sealed class` 用于表示**互斥的、离散**的状态

`sealed class` (或 `sealed interface`) 通常用于表示**有限的、互斥的离散状态**，这些状态之间不能同时存在。它们最常见的应用场景包括：

1. **事件（Events）/意图（Intents）/动作（Actions）：** 在 MVI 中，**`Intent` (或 `Action`) 通常会用 `sealed class` 来定义**，因为用户的每个意图都是一个独立的、互斥的动作。

   ```kotlin
   sealed class UserIntent {
       object LoadUser : UserIntent()
       data class UpdateName(val newName: String) : UserIntent()
       object ToggleEditMode : UserIntent()
   }
   ```

2. **一次性操作（One-Time Events）：** 对于那些只发生一次、不需要在 UI 中持久表示的操作（例如显示 Toast 消息、导航），也常使用 `sealed class` 包裹在 `Effect` 或 `Event` 层中。

3. **表示数据加载的不同阶段（作为 `UiState` 的子属性）：** `sealed class` 可以用于表示**某个特定数据流的加载状态**，并作为 **`UiState` 的一个属性**存在。

   ```kotlin
   sealed class DataStatus {
       object Idle : DataStatus()
       object Loading : DataStatus()
       data class Success<T>(val data: T) : DataStatus()
       data class Error(val message: String) : DataStatus()
   }
   
   data class MyScreenUiState(
       val productListStatus: DataStatus = DataStatus.Idle, // 这里的DataStatus就是sealed class
       val selectedProduct: Product? = null
   )
   ```

   在这种情况下，`DataStatus` 本身是互斥的（要么是 Idle，要么是 Loading，要么是 Success，要么是 Error），但它只是整个 `UiState` 中的一个**组件**。

### 总结

- **`data class` 适合作为主 `UiState`**，用于**组合**所有 UI 所需的属性，表达 UI 的**完整且连续**的状态。
- **`sealed class` 适合表示互斥的、离散的类型**，如用户的意图、一次性操作，或者作为 `UiState` 内部某个属性的**互斥阶段**。

因此，`UserProfileUiState` 使用 `data class` 是因为它要表示用户资料页面的整体、可组合的状态，而不是几个互斥的阶段。而如果我们需要表示加载过程中的互斥阶段，我们会将其作为 `UiState` 内的一个 `data class` 属性，或在更复杂的场景下，在该属性内部使用 `sealed class` 来表示更细粒度的互斥状态。