---
categories: [转载, Java]
title: Carson带你学Java：深入源码解析HashMap 1.7
date: 2018-02-24 10:00:00 +0800
pin: false
tags: [转载, java]
keywords: [HashMap, JDK1.7, 拉链法, 扩容, hash冲突]
---

> 本文转载自 [HashMap源码完全解析（JDK 1.7）](https://blog.csdn.net/carson_ho/article/details/79373026)（作者：Carson_Ho）。版权归原作者所有，此处仅作个人学习备份。
>
> 本文基于 JDK 1.7（Java 7）；关于 JDK 1.8 请看 [关于 HashMap 1.8 的重大更新](https://blog.csdn.net/carson_ho/article/details/79373134)。

前言
--

* `HashMap` 在 `Java` 和 `Android` 开发中非常常见。
* 今天带来 `HashMap` 的全部源码分析。本文基于 JDK 1.7。

1. 简介
-----

类定义：

```
public class HashMap<K,V>
         extends AbstractMap<K,V> 
         implements Map<K,V>, Cloneable, Serializable
```

`HashMap` 的实现在 JDK 1.7 和 JDK 1.8 差别较大，本文主要讲解 JDK 1.7 中 HashMap 的源码解析。

2. 数据结构
-------

`HashMap` 采用的数据结构 = **数组（主） + 单链表（副）**，该数据结构方式也称：**拉链法**。

* 即 `HashMap` 的本质 = 1个存储 `Entry` 类对象的数组 + 多个单链表。
* `Entry` 对象本质 = 1个映射（键 - 值对），属性包括：键（key）、值（value）及下1节点（next）= 单链表的指针 = 也是一个 `Entry` 对象，用于解决 hash 冲突。

`Entry` 类源码：

```
/** 
 * Entry类实现了Map.Entry接口
 * 即 实现了getKey()、getValue()、equals(Object o)和hashCode()等方法
**/  
static class Entry<K,V> implements Map.Entry<K,V> {
    final K key;  // 键
    V value;  // 值
    Entry<K,V> next; // 指向下一个节点 ，也是一个Entry对象，从而形成解决hash冲突的单链表
    int hash;  // hash值
  
    Entry(int h, K k, V v, Entry<K,V> n) {  
        value = v;  
        next = n;  
        key = k;  
        hash = h;  
    }  
    public final K getKey() { return key; }  
    public final V getValue() { return value; }  
    public final V setValue(V newValue) {  
        V oldValue = value;  
        value = newValue;  
        return oldValue;  
    }  
    // 判断2个Entry是否相等，必须key和value都相等，才返回true
    public final boolean equals(Object o) {  
        if (!(o instanceof Map.Entry)) return false;  
        Map.Entry e = (Map.Entry)o;  
        Object k1 = getKey();  
        Object k2 = e.getKey();  
        if (k1 == k2 || (k1 != null && k1.equals(k2))) {  
            Object v1 = getValue();  
            Object v2 = e.getValue();  
            if (v1 == v2 || (v1 != null && v1.equals(v2))) return true;  
        }  
        return false;  
    }  
    public final int hashCode() { 
        return Objects.hashCode(getKey()) ^ Objects.hashCode(getValue());  
    }  
    public final String toString() { return getKey() + "=" + getValue(); }  
    void recordAccess(HashMap<K,V> m) { }  
    void recordRemoval(HashMap<K,V> m) { } 
}
```

3. 基础知识：HashMap中的重要参数
--------------------

`HashMap` 中的主要参数 = 容量、加载因子、扩容阈值。

```
// 1. 容量（capacity）：HashMap中数组的长度，必须是2的幂 & <最大容量（2的30次方）
  static final int DEFAULT_INITIAL_CAPACITY = 1 << 4;  // 默认容量 = 16
  static final int MAXIMUM_CAPACITY = 1 << 30;         // 最大容量 = 2的30次方

// 2. 加载因子(Load factor)：HashMap在其容量自动增加前可达到多满的一种尺度
  final float loadFactor;                              // 实际加载因子
  static final float DEFAULT_LOAD_FACTOR = 0.75f;      // 默认加载因子 = 0.75

// 3. 扩容阈值（threshold）：当哈希表的大小 ≥ 扩容阈值时，就会扩容。扩容阈值 = 容量 x 加载因子
  int threshold;

// 4. 存储数据的Entry类型数组，长度 = 2的幂
  transient Entry<K,V>[] table = (Entry<K,V>[]) EMPTY_TABLE;  
  transient int size;  // HashMap中存储的键值对的数量
```

* 加载因子越大、填满的元素越多 = 空间利用率高、但冲突的机会加大、查找效率变低（链表变长）；
* 加载因子越小、填满的元素越少 = 空间利用率小、冲突的机会减小、查找效率高（链表不长）。

4. 源码分析
-------

### 步骤1：声明1个 HashMap 对象（构造函数）

```
    // 构造函数1：默认构造函数（无参），加载因子 & 容量 = 默认 = 0.75、16
    public HashMap() {
        this(DEFAULT_INITIAL_CAPACITY, DEFAULT_LOAD_FACTOR); 
    }
    // 构造函数2：指定“容量大小”，加载因子 = 默认
    public HashMap(int initialCapacity) {
        this(initialCapacity, DEFAULT_LOAD_FACTOR);
    }
    // 构造函数3：指定“容量大小”和“加载因子”
    public HashMap(int initialCapacity, float loadFactor) {
        if (initialCapacity > MAXIMUM_CAPACITY)
            initialCapacity = MAXIMUM_CAPACITY;
        this.loadFactor = loadFactor;
        threshold = initialCapacity;   // 注：此处不是真正的阈值，后面会重新计算
        init(); // 一个空方法用于未来的子对象扩展
    }
```

注意：**真正初始化哈希表（初始化存储数组 table）是在第1次添加键值对时，即第1次调用 put() 时。**

### 步骤2：向 HashMap 添加数据（put）

```
    public V put(K key, V value) {
        // 1. 若 哈希表未初始化，则使用构造函数时设置的阈值(即初始容量) 初始化数组table
        if (table == EMPTY_TABLE) { 
            inflateTable(threshold); 
        }  
        // 2.1 若key == null，则将该键值对存放到table[0]（key=null时hash值=0）
        if (key == null)
            return putForNullKey(value);
        // 2.2 若 key ≠ null，则计算存放数组table中的位置
        int hash = hash(key);
        int i = indexFor(hash, table.length);
        // 3. 判断该key对应的值是否已存在（遍历以该数组元素为头结点的链表）
        for (Entry<K,V> e = table[i]; e != null; e = e.next) {
            Object k;
            // 3.1 若该key已存在，则用新value替换旧value
            if (e.hash == hash && ((k = e.key) == key || key.equals(k))) {
                V oldValue = e.value;
                e.value = value;
                e.recordAccess(this);
                return oldValue;
            }
        }
        modCount++;
        // 3.2 若该key不存在，则将“key-value”添加到table中
        addEntry(hash, key, value, i);
        return null;
    }
```

#### 分析1：初始化哈希表 inflateTable()

```
     private void inflateTable(int toSize) {  
        // 1. 将传入的容量大小转化为：>传入容量大小的最小的2的幂
        int capacity = roundUpToPowerOf2(toSize);
        // 2. 重新计算阈值 threshold = 容量 * 加载因子  
        threshold = (int) Math.min(capacity * loadFactor, MAXIMUM_CAPACITY + 1);  
        // 3. 使用计算后的初始容量初始化数组table
        table = new Entry[capacity];
        initHashSeedAsNeeded(capacity);  
    }  
```

#### 分析3：计算存放数组 table 中的位置

```
        // a. 根据键值key计算hash值
        int hash = hash(key);
        // b. 根据hash值 最终获得 key对应存放的数组Table中位置
        int i = indexFor(hash, table.length);
```

```
     // JDK 1.7实现：hashCode() + 4次位运算 + 5次异或运算（9次扰动）
     static final int hash(int h) {
        h ^= k.hashCode(); 
        h ^= (h >>> 20) ^ (h >>> 12);
        return h ^ (h >>> 7) ^ (h >>> 4);
     }
     // JDK 1.8实现：hashCode() + 1次位运算 + 1次异或运算（2次扰动）
      static final int hash(Object key) {
           int h;
           return (key == null) ? 0 : (h = key.hashCode()) ^ (h >>> 16);
     }
     // 将扰动处理后的结果 与运算(&) （数组长度-1），得到存储在数组table的位置
      static int indexFor(int h, int length) {  
          return h & (length-1); 
      }
```

关于计算数组下标，有3个核心问题，其根本目的都是**提高存储 key-value 的数组下标位置的随机性 & 分布均匀性，尽量避免 hash 值冲突**：

1. **为什么不直接采用 hashCode() 作为下标？** 容易出现哈希码与数组大小范围不匹配的情况。
2. **为什么采用 哈希码 & (数组长度-1)？** 根据容量大小，按需取哈希码一定数量的低位作为下标，解决“哈希码与数组大小范围不匹配”问题（这也是为什么容量必须是2的幂）。
3. **为什么要对哈希码进行扰动处理？** 加大哈希码低位的随机性，使分布更均匀，减少 Hash 冲突。

#### 分析5：addEntry —— 添加键值对 & 扩容

```
      void addEntry(int hash, K key, V value, int bucketIndex) {  
          // 1. 插入前判断容量是否足够，若不足则扩容2倍、重新计算hash值和下标
          if ((size >= threshold) && (null != table[bucketIndex])) {  
            resize(2 * table.length);
            hash = (null != key) ? hash(key) : 0;
            bucketIndex = indexFor(hash, table.length);
        }  
        // 2. 创建1个新的数组元素（Entry） 并放入到数组中
        createEntry(hash, key, value, bucketIndex);  
    }  

   void resize(int newCapacity) {  
        Entry[] oldTable = table;  
        int oldCapacity = oldTable.length; 
        if (oldCapacity == MAXIMUM_CAPACITY) {  
            threshold = Integer.MAX_VALUE;  
            return;  
        }  
        Entry[] newTable = new Entry[newCapacity];  
        transfer(newTable);   // 将旧数组数据转移到新table中
        table = newTable;  
        threshold = (int)(newCapacity * loadFactor); 
    } 

    // 过程：按旧链表的正序遍历链表、在新链表的头部依次插入（头插法）
    void transfer(Entry[] newTable) {
        Entry[] src = table; 
        int newCapacity = newTable.length;
        for (int j = 0; j < src.length; j++) { 
            Entry<K,V> e = src[j];           
            if (e != null) {
                src[j] = null; 
                do { 
                    Entry<K,V> next = e.next; 
                    int i = indexFor(e.hash, newCapacity); 
                    e.next = newTable[i]; 
                    newTable[i] = e;  
                    e = next;             
                } while (e != null);
            }
        }
    }

    void createEntry(int hash, K key, V value, int bucketIndex) { 
        Entry<K,V> e = table[bucketIndex];
        // 头插法：table中每个位置永远只保存最新插入的Entry，旧Entry放入链表中
        table[bucketIndex] = new Entry<>(hash, key, value, e);  
        size++;  
    }   
```

**键值对的添加方式：单链表的头插法。** 即将该位置（数组上）原来的数据放到链表下1个节点，新数据放到数组位置上。

**扩容机制：** 在扩容 resize() 转移数据时 = 按旧链表的正序遍历链表、在新链表的头部依次插入，即扩容后容易出现**链表逆序**（扩容前 1->2->3，扩容后 3->2->1）。此时若多线程并发执行 put()，一旦触发扩容，**容易出现环形链表**，从而在获取数据、遍历链表时形成死循环（Infinite Loop），即线程不安全。

### 步骤3：从 HashMap 获取数据（get）

get() 与 put() 过程原理几乎相同：

```
   public V get(Object key) {  
        if (key == null)  
            return getForNullKey();
        Entry<K,V> entry = getEntry(key);
        return null == entry ? null : entry.getValue();  
    }  

    final Entry<K,V> getEntry(Object key) {  
        if (size == 0) return null;  
        // 1. 计算hash值；2. 计算数组下标；3. 遍历该下标处链表寻找key对应值
        int hash = (key == null) ? 0 : hash(key);  
        for (Entry<K,V> e = table[indexFor(hash, table.length)]; e != null; e = e.next) {  
            Object k;  
            if (e.hash == hash && ((k = e.key) == key || (key != null && key.equals(k))))  
                return e;  
        }  
        return null;  
    }  
```

5. 与 JDK 1.8 的区别
----------------

JDK 1.8 的优化目的主要是：减少 Hash 冲突 & 提高哈希表的存、取效率。主要区别：

* **数据结构**：1.7 是 数组 + 单链表；1.8 是 数组 + 单链表 + 红黑树（链表长度 ≥ 8 且数组长度 ≥ 64 时转红黑树）。
* **扩容转移数据**：1.7 采用头插法（可能逆序，多线程易成环形链表死循环）；1.8 采用尾插法（不会逆序，不易成环）。
* **hash 扰动**：1.7 做了9次扰动（4次位运算 + 5次异或）；1.8 简化为2次扰动（1次位运算 + 1次异或）。

> 注：JDK 1.8 虽然改用尾插法避免了环形链表，但因为没有加同步锁保护，**HashMap 依然是线程不安全的**。

6. 补充问题
-------

* **哈希表如何解决 Hash 冲突**：拉链法（数组 + 链表）。
* **为什么 String、Integer 适合作 key**：这些类是 final 的、不可变，保证了 key 的不可更改性（hashCode 不会变），且内部已重写 equals() 和 hashCode()。
* **key 为 Object 类型时需实现哪些方法**：需正确重写 equals() 和 hashCode()，保证相等的对象有相等的 hashCode。
