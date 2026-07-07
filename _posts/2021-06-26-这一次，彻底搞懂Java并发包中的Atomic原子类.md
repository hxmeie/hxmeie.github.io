---
categories: [转载, Java]
title: 这一次，彻底搞懂Java并发包中的Atomic原子类
date: 2021-06-26 10:00:00 +0800
pin: false
tags: [转载, java]
keywords: [Atomic, CAS, Unsafe, ABA问题, 原子类]
---

> 本文转载自 [这一次，彻底搞懂Java并发包中的Atomic原子类](https://juejin.cn/post/6977993272538955806)（作者：赌一包辣条）。版权归原作者所有，此处仅作个人学习备份。

前两篇文章我们深入的讲解了synchronized关键字以及ReentranLock，它们都是在并发过程中通过同步状态来确保只有一个线程操作共享变量的。而本篇文章我们将来认识一个无锁状态也能保证线程安全的方法，它就是JDK1.5中引入的并发包Atomic原子操作类。

一、初始Atomic并发包
-------------

从JDK1.5开始，Java在java.util.concurrent.atomic包下引入了一些Atomic相关的原子操作类，这些类避免使用加锁来实现同步，从而更加方便、高效的实现原子操作。

Atomic包下所有的原子类都只适用于单个元素，即只能保证一个基本数据类型、对象、或者数组的原子性。根据使用范围，可以将这些类分为四种类型，分别为原子**更新基本类型**、**原子更新数组**、**原子更新引用**、**原子更新属性**。

### 1.原子更新基本类型

atomic包下原子更新基本数据类型包括AtomicInteger、AtomicLong、AtomicBoolean三个类。这里，我们以AtomicInteger为例来学习如何使用。

AtomicInteger中提供了很多方法供我们调用，如：

```
// 获取当前值，然后自加，相当于i++
getAndIncrement()
// 获取当前值，然后自减，相当于i--
getAndDecrement()
// 自加1后并返回，相当于++i
incrementAndGet()
// 自减1后并返回，相当于--i
decrementAndGet()
// 获取当前值，并加上预期值
getAndAdd(int delta)
// 获取当前值，并设置新值
int getAndSet(int newValue)
```

需要注意的是这些方法都是原子操作，在多线程下也能够保证原子性。

### 2.原子更新引用类型

基本类型的原子类只能更新一个变量，如果需要原子更新多个变量，则需要使用引用类型原子类。引用类型的原子类包括AtomicReference、AtomicStampedReference、AtomicMarkableReference三个。

* **AtomicReference** 引用原子类
* **AtomicStampedReference** 原子更新带有版本号的引用类型。该类将整数值与引用关联起来，可用于解决原子的更新数据和数据的版本号，可以解决使用 CAS 进行原子更新时可能出现的 ABA 问题。
* **AtomicMarkableReference** 原子更新带有标记的引用类型。该类将 boolean 标记与引用关联起来。

### 3.原子更新数组

这里原子更新数组并不是对数组本身的原子操作，而是对数组中的元素。主要包括3个类：AtomicIntegerArray、AtomicLongArray及AtomicReferenceArray，分别表示原子更新整数数组的元素、原子更新长整数数组的元素以及原子更新引用类型数组的元素。

### 4.原子更新对象属性

如果需要更新某个对象中的某个字段，可以使用更新对象字段的原子类。包括三个类，AtomicIntegerFieldUpdater、AtomicLongFieldUpdater以及AtomicReferenceFieldUpdater。需要注意的是这些类的使用需要满足以下条件：

* 被操作的字段不能是static类型；
* 被操纵的字段不能是final类型；
* 被操作的字段必须是volatile修饰的；
* 属性必须对于当前的Updater所在区域是可见的。

二、CAS
-----

前文中已经提到Atomic包下的类是无锁操作，无锁的实现就得益于CAS。

CAS是Compare And Swap的简称，即比较并交换的意思。CAS是一种无锁算法，其算法思想如下：

> CAS的函数公式：compareAndSwap(V,E,N)； 其中V表示要更新的变量，E表示预期值，N表示期望更新的值。调用compareAndSwap函数来更新变量V，如果V的值等于期望值E，那么将其更新为N，如果V的值不等于期望值E，则说明有其它线程跟新了这个变量，此时不会执行更新操作，而是重新读取该变量的值再次尝试调用compareAndSwap来更新。

可见CAS其实存在一个循环的过程，这个循环过程一般也称作**自旋**。

### 2.CAS存在的缺点

虽然通过CAS可以实现无锁同步，但是CAS也有其局限性和问题所在。

* （1）只能保证一个共享变量的原子性。对于多个共享变量操作是CAS是无法保证的，这时候必须使用枷锁来是实现。
* （2）存在性能开销问题。由于CAS是一个自旋操作，如果长时间的CAS不成功会给CPU带来很大的开销。
* （3）ABA问题。因为CAS是通过检查值有没有发生改变来保证原子性的，假若一个变量V的值为A，线程1和线程2同时都读取到了这个变量的值A，此时线程1将V的值改为了B，然后又改回了A，期间线程2一直没有抢到CPU时间片。等到线程1将V的值改回A后线程2才得到执行。那么此时，线程2并不知道V的值曾经改变过。这个问题就被成为**ABA问题**。

ABA问题的解决其实也容易处理，即添加一个版本号，每次更新值同时也更新版本号即可。上文中提到的AtomicStampedReference就是用来解决ABA问题的。

### 3.CPU对CAS的支持

在操作系统中CAS是一种系统原语，原语由多条指令组成，且原语的执行是连续不可中断的。因此CAS实际上是一条CPU的原子指令，虽然看上去CAS是一个先比较再交换的操作，但实际上这个过程是由CPU保证了原子操作。

### 4.CAS与Atomic原子类

在AtomicInteger类中，所有的操作都是通过一个类型为Unsafe的成员变量来实现的。Unsafe类是位于sun.misc包下的一个类，这个类中提供了用于执行低级别、不安全的操作方法，其中就包括了CAS的能力。

三、CAS的实现类--Unsafe
-----------------

Unsafe是一个神奇且鲜为人知的Java类，因为在平时开发中很少用到它。但是这个类中为我们提供了相当多的功能，它即可以让Java语言像C语言指针一样操作内存，同时还提供了CAS、内存屏障、线程调度、对象操作、数组操作等能力。

### 1.获取Unsafe实例

Unsafe类是一个单例，并且提供了一个getUnsafe的方法来获取Unsafe的实例。但是，这个方法只有在引导类加载器加载Unsafe类是调用才合法，否则会抛出一个SecurityException异常。因此，想要获取Unsafe类的实例一般使用反射：

```
        try {
            Field field = Unsafe.class.getDeclaredField("theUnsafe");
            field.setAccessible(true);
            Unsafe unsafe = (Unsafe) field.get(null);
        } catch (Exception e) {
            e.printStackTrace();
        }
```

### 2.Unsafe类中的CAS

Unsafe类中与CAS相关的主要有以下几个方法：

```
    // 第一个参数o为给定对象，offset为对象内存的偏移量，通过这个偏移量迅速定位字段并设置或获取该字段的值，expected表示期望值，x表示要设置的值，下面3个方法都通过CAS原子指令执行操作。
    public final native boolean compareAndSetInt(Object o,long offset,int expected,int x);
    public final native boolean compareAndSetObject(Object o, long offset,Object expected,Object x);    
    public final native boolean compareAndSetLong(Object o, long offset,long expected,long x);
```

可以看到，这些方法都是native方法，调用的底层代码实现。而AtomicInteger中也正是使用了这里的方法才实现的CAS操作。

### 3.线程调度相关

在Unsafe中提供了线程挂起、恢复及锁机制相关的方法，如unpark、park等。上篇文章讲解RetranLock与AQS时涉及到线程挂起的操作其实也是调用的Unsafe的park方法。

### 4.对象操作

Unsafe还提供了对象实例化及操作对象属性相关的方法，如objectFieldOffset、getObject、putObject、allocateInstance等。其中allocateInstance方法可以绕过对象的构造方法直接创建对象，Gson解析json反序列化对象时就有用到这个方法。

### 5.Unsafe的其它功能

除了CAS、线程调度、对象相关的功能外，Unsafe还提供了内存操作，可以实现堆外内存的分配等。由于不是本篇文章的重点，这里就不一一介绍了。

参考&推荐阅读

- Java魔法类：Unsafe应用解析（美团技术团队）
- Java并发编程-无锁CAS与Unsafe类及其并发包Atomic
