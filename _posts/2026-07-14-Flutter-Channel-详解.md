---
categories: [Flutter, 混合开发]
title: Flutter Channel 详解
date: 2026-07-14 10:36:54 +0800
tags: [flutter, channel, 平台通道, 混合开发]
keywords: [Flutter, Channel, MethodChannel, EventChannel, BasicMessageChannel, 平台通道, Pigeon, ffi, 混合开发, 线程模型]
---

Flutter 的 Channel（平台通道）是 Dart 层与原生平台（Android/iOS 等）之间通信的桥梁。因为 Flutter 的 UI 和业务逻辑都运行在独立的 Flutter 引擎里，想访问平台特有能力（电池、传感器、蓝牙、原生 SDK 等）就必须“跨界”通信，而 Channel 就是这套异步消息传递机制。

## 整体架构

![Flutter 平台通道架构](https://cdn.jsdelivr.net/gh/hxmeie/tuchuang/images/20260714101428136.png)

消息的流动是这样的：Dart 侧发起调用 → 参数经 Codec 序列化成二进制（`ByteData`）→ 通过 `BinaryMessenger` 传给原生侧 → 原生侧解码、执行、编码结果 → 异步回传给 Dart。整个过程完全异步，所有 Channel 底层都走同一条 `BinaryMessenger` 通道，只是封装的语义不同。

三个关键角色：

- **BinaryMessenger**：最底层的二进制信使，只认「通道名 + 一段字节 + 一个回调」，负责真正的收发。三种 Channel 都是它之上的语义封装。
- **Codec（编解码器）**：负责在两端把 Dart 对象 ↔ 二进制、原生对象 ↔ 二进制互转，保证跨语言的数据一致。
- **Handler（处理器）**：原生侧注册的回调（`MethodCallHandler` / `StreamHandler` / `MessageHandler`），收到消息后执行并回传结果。

> 一句话：**三种 Channel = 同一条 BinaryMessenger + 不同的 Codec + 不同的语义封装**。

## 三种 Channel 类型

Flutter 提供三种 Channel，对应三种通信语义。

| 类型 | 语义 | 方向 | Dart 侧返回 | 典型场景 |
|---|---|---|---|---|
| **MethodChannel** | 方法调用—返回结果（类 RPC） | 一次性、可双向发起 | `Future<T>` | 取电量、调原生 SDK、跳原生页 |
| **EventChannel** | 持续的数据流订阅 | 原生 → Dart（单向推送） | `Stream<T>` | 传感器、定位、电量变化、下载进度 |
| **BasicMessageChannel** | 自由的双向消息 | 双向、两端都能主动发 | `Future<T>`（回复） | 高频通信、自定义编解码、平台视图握手 |

- **MethodChannel** 是最常用的，用于一次性的“方法调用—返回结果”（类似 RPC）。Dart 调用一个原生方法，拿到一个 `Future`。
- **EventChannel** 用于原生侧持续向 Dart 推送数据流（如传感器、定位、电量变化），Dart 侧订阅一个 `Stream`。
- **BasicMessageChannel** 用于双向、无方法名概念的自由消息传递，可自定义编解码器，两端都能主动发消息。

### MethodChannel

Dart 侧发起调用：

```dart
import 'package:flutter/services.dart';

class BatteryService {
  // 通道名建议用「域名反写/功能」保证全局唯一
  static const _channel = MethodChannel('com.example.app/battery');

  Future<int> getBatteryLevel() async {
    try {
      final int level = await _channel.invokeMethod('getBatteryLevel');
      return level;
    } on PlatformException catch (e) {
      throw '获取电量失败: ${e.message}';
    } on MissingPluginException {
      throw '原生端未实现该方法';
    }
  }
}
```

**传参数**：`invokeMethod` 的第二个参数就是要传给原生的数据，支持标准编解码器能识别的任意类型（一般用 `Map` 传多个参数）：

```dart
final token = await _channel.invokeMethod<String>('login', {
  'username': 'tom',
  'age': 18,
  'vip': true,
});
```

Dart 3.x 还提供了带类型的便捷方法，省去手动强转：

```dart
final list = await _channel.invokeListMethod<String>('getContacts'); // List<String>?
final map  = await _channel.invokeMapMethod<String, int>('getScores'); // Map<String,int>?
```

Android 侧（Kotlin），在 `configureFlutterEngine` 中注册：

```kotlin
class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.app/battery"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBatteryLevel" -> {
                        val level = getBatteryLevel()
                        if (level != -1) result.success(level)
                        else result.error("UNAVAILABLE", "无法获取电量", null)
                    }
                    "login" -> {
                        // 取参数：call.argument<T>("key")
                        val username = call.argument<String>("username")
                        val age = call.argument<Int>("age")
                        result.success("token_for_$username")
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
```

iOS 侧（Swift），在 `AppDelegate` 中注册：

```swift
let controller = window?.rootViewController as! FlutterViewController
let channel = FlutterMethodChannel(
    name: "com.example.app/battery",
    binaryMessenger: controller.binaryMessenger)

channel.setMethodCallHandler { (call, result) in
    guard call.method == "getBatteryLevel" else {
        result(FlutterMethodNotImplemented)
        return
    }
    // ... 取电量后 result(level) 或 result(FlutterError(...))
}
```

要点：`result.success / result.error / result.notImplemented` 三选一且**只能调用一次**。Dart 侧对应地会收到正常值、`PlatformException`、或 `MissingPluginException`。

**反向调用（原生 → Dart）**：MethodChannel 是双向的，原生侧也能主动调 Dart 方法。Dart 侧用 `setMethodCallHandler` 注册处理器：

```dart
_channel.setMethodCallHandler((call) async {
  switch (call.method) {
    case 'onNativeEvent':
      final data = call.arguments as String;
      return 'ack'; // 返回值会作为结果回传给原生
    default:
      throw MissingPluginException();
  }
});
```

原生侧（Kotlin）用**同名通道**发起调用（**必须在平台主线程**）：

```kotlin
channel.invokeMethod("onNativeEvent", "payload", object : MethodChannel.Result {
    override fun success(result: Any?) { /* 拿到 Dart 的返回值 */ }
    override fun error(code: String, msg: String?, details: Any?) {}
    override fun notImplemented() {}
})
```

### EventChannel

适合“订阅式”的持续数据流。Dart 侧：

```dart
class SensorService {
  static const _channel = EventChannel('com.example.app/sensor');

  Stream<double> get sensorStream =>
      _channel.receiveBroadcastStream().map((e) => e as double);
}

// 使用
final sub = SensorService().sensorStream.listen(
  (value) => print('传感器值: $value'),
  onError: (e) => print('出错: $e'),   // 对应原生 sink.error(...)
  onDone: () => print('流结束'),        // 对应原生 sink.endOfStream()
);
// 记得在 dispose 时 sub.cancel(); → 会触发原生的 onCancel
```

Android 侧实现 `StreamHandler`，`onListen` 时开始推送，`onCancel` 时释放资源。**注意传感器/定位回调常在别的线程，向 `EventSink` 发数据必须切回平台主线程**：

```kotlin
class SensorStreamHandler(private val sensorManager: SensorManager)
    : EventChannel.StreamHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var listener: SensorEventListener? = null

    override fun onListen(args: Any?, sink: EventChannel.EventSink) {
        listener = object : SensorEventListener {
            override fun onSensorChanged(e: SensorEvent) {
                // 切回主线程再发送
                mainHandler.post { sink.success(e.values[0].toDouble()) }
            }
            override fun onAccuracyChanged(s: Sensor?, a: Int) {}
        }
        sensorManager.registerListener(listener, /* sensor */, SensorManager.SENSOR_DELAY_UI)
    }

    override fun onCancel(args: Any?) {
        sensorManager.unregisterListener(listener) // 释放，避免泄漏
        listener = null
    }
}
```

`EventSink` 有三个方法：`success(data)` 推送数据、`error(code, msg, details)` 推送错误、`endOfStream()` 结束流。

iOS 侧实现 `FlutterStreamHandler`：

```swift
class SensorStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?

  func onListen(withArguments arguments: Any?,
                eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    self.eventSink = events
    // 开始监听，拿到数据后回主线程 events(value)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.eventSink = nil  // 注销监听、释放资源
    return nil
  }
}

// 注册
let channel = FlutterEventChannel(name: "com.example.app/sensor",
                                  binaryMessenger: controller.binaryMessenger)
channel.setStreamHandler(SensorStreamHandler())
```

`onListen(args:...)` 的 `args` 是 Dart 侧 `receiveBroadcastStream(arguments)` 传来的参数，可用来区分「订阅哪一路数据」。

### BasicMessageChannel

两端都能主动发送消息，并可指定编解码器，适合**高频、无「方法名」概念**的自由通信：

```dart
const channel = BasicMessageChannel<String>(
  'com.example.app/echo',
  StringCodec(),
);

// 主动发送并等待回复
final reply = await channel.send('hello native');

// 接收原生主动发来的消息
channel.setMessageHandler((message) async {
  return '收到: $message';
});
```

Android 侧对称实现：

```kotlin
val channel = BasicMessageChannel(messenger, "com.example.app/echo", StringCodec.INSTANCE)

// 接收 Dart 发来的消息并回复
channel.setMessageHandler { message, reply -> reply.reply("收到: $message") }

// 主动向 Dart 发消息
channel.send("hello dart") { reply -> /* 拿到 Dart 的回复 */ }
```

## 编解码器（Codec）

Channel 传输的是二进制，靠 Codec 在两端做序列化。常见的有：

- `StandardMessageCodec` / `StandardMethodCodec`：默认编解码器，支持 null、bool、数值、String、`Uint8List`、`List`、`Map` 等基础类型，两端自动映射。`StandardMethodCodec` 其实是在 `StandardMessageCodec` 之上，额外封装了「方法名 + 参数」和「成功/异常信封（envelope）」的结构。
- `StringCodec`：只传字符串（UTF-8）。
- `JSONMessageCodec` / `JSONMethodCodec`：传 JSON 可编码对象。
- `BinaryCodec`：不做任何转换，直接传原始字节（`ByteData`），零拷贝、开销最低。

### 标准编解码器的跨端类型对照

| Dart | Android（Kotlin） | iOS（Swift） |
|---|---|---|
| `null` | `null` | `nil` |
| `bool` | `Boolean` | `NSNumber(value: Bool)` |
| `int`（≤ 32 位） | `Int` | `NSNumber(value: Int32)` |
| `int`（> 32 位） | `Long` | `NSNumber(value: Int64)` |
| `double` | `Double` | `NSNumber(value: Double)` |
| `String` | `String` | `String` |
| `Uint8List` | `ByteArray` | `FlutterStandardTypedData(bytes:)` |
| `Int32List` | `IntArray` | `FlutterStandardTypedData(int32:)` |
| `Int64List` | `LongArray` | `FlutterStandardTypedData(int64:)` |
| `Float32List` | `FloatArray` | `FlutterStandardTypedData(float32:)` |
| `Float64List` | `DoubleArray` | `FlutterStandardTypedData(float64:)` |
| `List` | `List` | `Array` |
| `Map` | `HashMap` | `Dictionary` |

> **易踩的坑**：Dart 的 `int` 会按大小编码成 32 位或 64 位，因此在 Android 端接收时**可能是 `Int` 也可能是 `Long`**。稳妥做法是用 `call.argument<Number>("x")` 再 `.toLong()`，或干脆约定用字符串传大整数。

### 自定义 Codec 传输复杂对象

标准编解码器不支持自定义类，复杂对象要么先转成 `Map`，要么继承 `StandardMessageCodec` 扩展类型（自定义类型标识需 ≥ 128，避开内置）：

```dart
class MyCodec extends StandardMessageCodec {
  const MyCodec();

  @override
  void writeValue(WriteBuffer buffer, dynamic value) {
    if (value is Point) {
      buffer.putUint8(128);            // 自定义类型标识
      super.writeValue(buffer, value.x);
      super.writeValue(buffer, value.y);
    } else {
      super.writeValue(buffer, value); // 其余交给父类
    }
  }

  @override
  dynamic readValueOfType(int type, ReadBuffer buffer) {
    switch (type) {
      case 128:
        return Point(readValue(buffer), readValue(buffer));
      default:
        return super.readValueOfType(type, buffer);
    }
  }
}
```

原生侧需实现**对称**的读写逻辑，类型标识两端必须一致。实践中这块最容易两端对不上，也是 Pigeon 更受青睐的原因之一。

## 线程模型

这是最容易踩坑的地方，可以拆成「原生侧在哪个线程」和「Dart 侧在哪个 isolate」两个问题。

### 原生侧：默认在平台主线程

默认情况下，原生侧的 `MethodCallHandler`（以及 `EventSink`、`MessageHandler`）运行在**平台主线程（UI 线程）**上。因此：

1. **耗时操作（网络、IO、大计算）必须自己切到后台线程**，否则会卡住整个平台 UI；
2. 处理完再**切回平台主线程**调 `result.success(...)` —— 官方明确要求：从平台侧调用（回传）到 Flutter 必须在**平台主线程**发起。

```kotlin
"heavyWork" -> {
    Thread {
        val data = doHeavyWork()               // 后台线程执行
        Handler(Looper.getMainLooper()).post { // 切回主线程回传
            result.success(data)
        }
    }.start()
}
```

iOS 同理：后台用 `DispatchQueue.global()`，回传用 `DispatchQueue.main.async { result(data) }`。

### TaskQueue：让 handler 直接跑在后台线程

Flutter 引入了 `BinaryMessenger.TaskQueue`，注册通道时指定它，就能让该通道的 handler **直接在后台线程执行**，省去手动切线程，避免阻塞平台 UI 线程。

Android（Kotlin）：

```kotlin
override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
  val taskQueue = binding.binaryMessenger.makeBackgroundTaskQueue()
  channel = MethodChannel(
      binding.binaryMessenger,
      "com.example.foo",
      StandardMethodCodec.INSTANCE,
      taskQueue)               // ← 指定后台队列
  channel.setMethodCallHandler(this)
}
```

iOS（Swift）：

```swift
public static func register(with registrar: FlutterPluginRegistrar) {
  let taskQueue = registrar.messenger().makeBackgroundTaskQueue?()
  let channel = FlutterMethodChannel(name: "com.example.foo",
                                     binaryMessenger: registrar.messenger(),
                                     codec: FlutterStandardMethodCodec.sharedInstance(),
                                     taskQueue: taskQueue)   // ← 指定后台队列
  let instance = MyPlugin()
  registrar.addMethodCallDelegate(instance, channel: channel)
}
```

### Dart 侧：root isolate 与后台 isolate

从 Flutter 侧调用平台通道，应当在 **root isolate**，或**已注册的后台 isolate** 上发起。默认在别的 isolate 里直接用 Channel 会失败，需要先用主 isolate 的 `RootIsolateToken` 初始化 `BackgroundIsolateBinaryMessenger`：

```dart
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // 在 root isolate 拿到 token
  final rootIsolateToken = RootIsolateToken.instance!;
  Isolate.spawn(_isolateMain, rootIsolateToken);
}

Future<void> _isolateMain(RootIsolateToken token) async {
  // 后台 isolate 注册后才能用依赖平台通道的插件
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);

  final prefs = await SharedPreferences.getInstance(); // 可以用了
  print(prefs.getBool('isDebug'));
}
```

**限制**：后台 isolate 可以「主动向原生请求并等回复」，但**无法接收原生主动推送的消息**（unsolicited messages）。也就是说，像「长期监听 Firestore 变更」这种由原生主动 push 的场景，不能放在后台 isolate；而「查询一次拿结果」是可以的。

## 插件化封装

上面示例把通道注册写在 `MainActivity` / `AppDelegate` 里，只适合 app 自用。如果要做成**可复用的 plugin**，应实现 `FlutterPlugin`，在 `onAttachedToEngine` 里注册、`onDetachedFromEngine` 里释放：

```kotlin
class BatteryPlugin : FlutterPlugin, MethodChannel.MethodCallHandler {
  private lateinit var channel: MethodChannel

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel = MethodChannel(binding.binaryMessenger, "com.example.app/battery")
    channel.setMethodCallHandler(this)
  }
  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null) // 释放
  }
  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) { /* ... */ }
}
```

对于需要同时支持多平台、且各平台实现独立发布的场景，官方推荐 **federated plugin（联合插件）** 架构：把「接口层 / 平台实现层 / 平台接口约定层」拆开，各端独立演进。

## 更现代的替代方案

手写 Channel 有个明显痛点：方法名是字符串、参数是无类型 `Map`，两端容易对不上，重构时也没有编译期检查。因此实际项目里越来越常用两种方案。

### Pigeon（推荐）

Flutter 官方的**代码生成**工具。用一个 Dart 接口文件描述通信协议，它自动生成两端类型安全的样板代码，底层仍然是 Channel，但省去手写、保证类型一致，支持嵌套类、API 分组、异步包装。

定义协议（`pigeons/messages.dart`）：

```dart
import 'package:pigeon/pigeon.dart';

class SearchRequest {
  final String query;
  SearchRequest({required this.query});
}

class SearchReply {
  final String result;
  SearchReply({required this.result});
}

@HostApi()          // Flutter 调原生
abstract class Api {
  @async
  SearchReply search(SearchRequest request);
}

@FlutterApi()       // 原生反向调 Flutter
abstract class FlutterSearchApi {
  void onResult(SearchReply reply);
}
```

生成两端代码：

```bash
dart run pigeon \
  --input pigeons/messages.dart \
  --dart_out lib/generated_pigeon.dart \
  --kotlin_out android/app/src/main/kotlin/.../Messages.kt \
  --swift_out ios/Runner/Messages.swift
```

Flutter 侧像调本地方法一样使用，全程有类型检查：

```dart
import 'generated_pigeon.dart';

Future<void> onClick() async {
  final reply = await Api().search(SearchRequest(query: 'test'));
  print('reply: ${reply.result}');
}
```

中大型项目、跨端协议较多时，强烈建议用 Pigeon 取代手写 MethodChannel。

### dart:ffi

完全绕开 Channel，通过 FFI（Foreign Function Interface）**直接调用 C/C++ 动态库**，是**同步调用、开销更低**，适合对性能敏感或已有 C 库的场景（如音视频、加解密、图像处理）。缺点是**不能直接调 Java/Kotlin/Swift 层的 API**，只能到 C/C++。

### 三种方式对比

| 维度 | 手写 Channel | Pigeon | dart:ffi |
|---|---|---|---|
| 类型安全 | ❌ 字符串 + 无类型 Map | ✅ 编译期检查 | ✅ |
| 调用方式 | 异步 | 异步 | **同步** |
| 能调原生（Java/Kotlin/Swift） | ✅ | ✅ | ❌（仅 C/C++） |
| 序列化开销 | 有 | 有 | 几乎无 |
| 适用 | 简单、少量交互 | 协议多、要类型安全 | 性能热点、已有 C 库 |

## 原理浅析

以 `MethodChannel.invokeMethod` 为例，底层流程大致是：

1. `StandardMethodCodec` 把「方法名 + 参数」编码成 `ByteData`；
2. 调 `BinaryMessenger.send(channelName, byteData)`，返回一个 `Future<ByteData?>`；
3. 二进制经 Flutter 引擎发到原生侧，找到该通道名注册的 handler 执行；
4. 原生 handler 调 `result.success/error`，结果被编码成「信封（envelope）」二进制回传；
5. Dart 侧 `decodeEnvelope` 解码：成功则 complete 返回值，失败则抛 `PlatformException`；通道名没有对应 handler 则抛 `MissingPluginException`。

`EventChannel` 本质是：`receiveBroadcastStream` 时先给原生发一条「listen」消息触发 `onListen`，之后原生通过 `EventSink` 持续回发数据；`cancel` 时发「cancel」触发 `onCancel`。`BasicMessageChannel` 则是最贴近 `BinaryMessenger` 的一层薄封装。**三者殊途同归，都建立在同一条 `BinaryMessenger` 之上**。

## 常见问题与踩坑

- **`MissingPluginException` 从哪来**？常见于：原生侧没注册该通道 / 两端通道名或方法名不一致 / 注册时机太早（引擎还没初始化）/ 热重启后原生状态没重建。排查先核对通道名字符串。
- **`result` 只能回调一次**，且漏调会让 Dart 侧的 `Future` **永远挂起**（既不完成也不报错）。异常分支也要记得回 `error`。
- **EventChannel 一定要在 `onCancel` 里释放监听**（注销 listener、停止定时器），否则内存泄漏。
- **线程别搞错**：耗时放后台，回传（`result` / `sink`）切回平台主线程；或用 TaskQueue 让 handler 直接跑后台。
- **类型对照要留意**，尤其 `int` 在 Android 上可能是 `Int` 或 `Long`；复杂对象先转 `Map` 或用 Pigeon。
- **注册时机**要在引擎初始化之后（Android 用 `configureFlutterEngine` / plugin 的 `onAttachedToEngine`）。
- **通道名务必全局唯一**（用包名前缀），否则不同插件之间会冲突。
- **性能**：Channel 每次调用都有序列化 + 跨线程开销，避免「chatty」的高频小调用（如每帧一次）；传大块数据用 `Uint8List` + `BinaryCodec` 减少拷贝；真正的性能热点考虑 `dart:ffi`。

## 小结

- Channel 是 Flutter 与原生通信的**异步二进制消息**机制，三种类型（Method / Event / BasicMessage）都建立在同一条 `BinaryMessenger` 之上，区别只是语义与 Codec。
- 记牢**线程模型**：原生 handler 默认在平台主线程，耗时要切后台、回传要切回主线程，或用 TaskQueue；Dart 侧跨 isolate 要先 `BackgroundIsolateBinaryMessenger.ensureInitialized`。
- 手写通道适合简单场景；**协议一多就上 Pigeon**（类型安全、代码生成）；**性能热点或已有 C 库用 dart:ffi**（同步、低开销）。
