---
categories: [转载, Java]
title: 这一次，彻底搞懂Java中的ReentrantLock实现原理
date: 2021-06-19 10:00:00 +0800
pin: false
tags: [转载, Java]
keywords: [ReentrantLock, AQS, CLH队列, 公平锁, 可重入锁]
---

> 本文转载自 [这一次，彻底搞懂Java中的ReentrantLock实现原理](https://juejin.cn/post/6975435256111300621)（作者：赌一包辣条）。版权归原作者所有，此处仅作个人学习备份。

本文是Java并发系列的第三篇文章，将详细的讲解ReentrantLock与AQS的底层实现原理。

一、初识ReentrantLock
-----------------

> 注：下文中会多次出现**同步队列**这个关键词，这里的**同步队列**指的是没有获取到锁而处于阻塞状态的线程形成的队列。等同于上篇文章《这一次，彻底搞懂Java中的synchronized关键字》中提到的阻塞队列 \_EntryList。

上篇文章我们深入分析了synchronized关键字的实现原理。那么本篇文章我们来认识一下Java中另外一个同步机制--ReentrantLock。ReentrantLock是在JDK1.5的java.util.concurrent包中引入的。相比synchronized，ReentrantLock拥有更强大的并发功能。在深入分析ReentrantLock之前，我们先来了解一下ReentrantLock的使用。

### 1.ReentrantLock使用

上篇文章介绍的synchronized关键字是一种隐式锁，即它的加锁与释放是自动的，无需我们关心。而ReentrantLock是一种显式锁，需要我们手动编写加锁和释放锁的代码。下面我们来看下ReentrantLock的使用方法。

```
public class ReentrantLockDemo {
    // 实例化一个非公平锁，构造方法的参数为true表示公平锁，false为非公平锁。
    private final ReentrantLock lock = new ReentrantLock(false);
    private int i;

    public void testLock() {
        // 拿锁，如果拿不到会一直等待
        lock.lock();
        try {
            // 再次尝试拿锁(可重入)，拿锁最多等待100毫秒
            if (lock.tryLock(100, TimeUnit.MILLISECONDS))
                i++;
        } catch (InterruptedException e) {
            e.printStackTrace();
        } finally {
            // 释放锁
            lock.unlock(); 
            lock.unlock();
        }
    }
}
```

上述代码中lock.lock()会进行拿锁操作，如果拿不到锁则会一直等待。如果拿到锁之后则会执行try代码块中的代码。接下来在try代码块中又通过tryLock(100, TimeUnit.MILLISECONDS)方法尝试再次拿锁，此时，拿锁最多会等待100毫秒，如果在100毫秒内能获得锁，则tryLock方法返回true，拿锁成功，执行i++操作。

另外，要注意被ReentrantLock加锁区域必须用try代码块包裹，且释放锁需要在finally中来避免死锁。执行几次加锁，就需要几次释放锁。

### 2.公平锁与非公平锁

> **公平锁**是指多个线程按照申请锁的顺序来获取锁，线程直接进入同步队列中排队，队列中最先到的线程先获得锁。**非公平锁**是多个线程加锁时每个线程都会先去尝试获取锁，如果刚好获取到锁，那么线程无需等待，直接执行，如果获取不到锁才会被加入同步队列的队尾等待执行。

公平锁的优点在于各个线程公平平等，每个线程等待一段时间后，都有执行的机会，而它的缺点相较于于非公平锁整体执行速度更慢，吞吐量更低。而非公平锁的优点是可以减少唤起线程的开销，整体的吞吐效率高；它的缺点是队列中等待的线程可能一直或者长时间获取不到锁。

### 3.可重入锁与非可重入锁

> **可重入锁**又名递归锁，是指同一个线程在获取外层同步方法锁的时候，再进入该线程的内层同步方法会自动获取锁（前提锁对象得是同一个对象或者class），不会因为之前已经获取过还没释放而阻塞。上篇文章讲到的synchronized与本篇讲的ReentrantLock都属于可重入锁。可重入锁可以有效避免死锁的产生。

### 4.排他锁与共享锁

> **排他锁**也叫独占锁，是指该锁一次只能被一个线程所持有。**共享锁**是指该锁可被多个线程所持有。

二、ReentrantLock源码简析
-------------------

接下来我们来看一下ReentrantLock类的代码结构：

```
public class ReentrantLock implements Lock, java.io.Serializable {

    private final Sync sync;
    
    public ReentrantLock() {
        sync = new NonfairSync();
    }

    public ReentrantLock(boolean fair) {
        sync = fair ? new FairSync() : new NonfairSync();
    }
    
    // ...省略其它代码
}
```

可以看到，ReentrantLock的代码结构非常简单。它实现了Lock和Serializable两个接口，在无参构造方法中初始化了一个非公平锁。ReentrantLock所有拿锁和释放锁的操作都是通过Sync这个成员变量来实现的。Sync是ReentrantLock中的一个抽象内部类，它有两个实现，分别为NonfairSync与FairSync。

Sync中已经实现了非公平锁的逻辑（nonfairTryAcquire）以及释放锁的操作（tryRelease），其对锁状态的判断都是通过state来实现的，state为0表示未加锁状态，state大于0表示加锁状态。

NonfairSync非公平锁仅仅在tryAcquire中直接调用了nonfairTryAcquire。FairSync公平锁的tryAcquire与非公平锁的实现其实只有一句之差，即公平锁先去判断了同步队列中是否有在等待的线程（hasQueuedPredecessors），如果没有才会去进行拿锁操作。而非公平锁不会管是否有同步队列，先去拿了再说。

三、AbstractQueuedSynchronizer（AQS）
----------------------------------

AbstractQueuedSynchronizer可以翻译为队列同步器，通常简称为AQS。AbstractQueuedSynchronizer类继承了AbstractOwnableSynchronizer，其中维护了四个成员：

* **exclusiveOwnerThread** 表示独占当前锁的线程；
* **head与tail** 分别表示了等待线程队列的头结点和尾结点；
* **state** 表示同步的状态，为0时表示未加锁状态，而大于0时表示加锁状态。

看到这里，不禁想起上篇文章讲到的synchronized锁中的monitor对象。是不是惊奇的发现AQS与synchronized的monitor竟然有异曲同工之妙。但是AQS的功能却远不止如此。

四、从AQS看ReentrantLock
--------------------

### 1.ReentrantLock的lock方法

lock方法调用了Sync的acquire，而acquire在AQS中实现：

```
    // AbstractQueuedSynchronizer
    public final void acquire(int arg) {
        if (!tryAcquire(arg) &&
            acquireQueued(addWaiter(Node.EXCLUSIVE), arg))
            selfInterrupt();
    }
```

在AQS的acquire方法中首先调用了tryAcquire，这个方法会通过CAS去尝试拿锁，返回值表示是否成功获取锁。最理想的情况是通过tryAcquire方法直接拿到了锁。如果没有拿到锁，则调用addWaiter方法将其加入到了同步队列。

### 2.AQS与双向CLH队列

CLH队列是Craig、Landin and Hagersten队列的简称，它是单向链表。而AQS中的队列是CLH变体的虚拟双向队列。在AQS中将所有请求锁失败的线程或者调用了await方法的线程封装成一个Node节点来实现锁的分配。Node中封装了等待的线程和线程当前的状态，其中线程的状态有四种，分别为：

* **CANCELLED** 表示线程被取消的状态。
* **SIGNAL** 表示节点处于被唤醒状态，当其前驱结点释放了同步锁或者被取消后就会通知处于SIGNAL状态的后继节点的线程执行。
* **CONDITION** 调用了await方法后处于等待状态的线程节点会被标记为此种状态。
* **PROPAGATE** 与共享模式有关，表示节点处于可运行状态。

addWaiter方法将线程封装成Node并插入到同步队列的队尾（通过CAS）。同步队列的头结点是一个不存储任何数据的空节点。

在将节点加入到同步队列后，节点就会开启自旋操作（acquireQueued），并观察前驱节点的状态，等待满足执行的条件。如果node前驱节点是头结点，则尝试去获取同步状态，成功之后则可执行同步代码；如果node的前驱节点不是头结点，那么则调用shouldParkAfterFailedAcquire方法判断是否要将线程挂起，如果是则调用parkAndCheckInterrupt将线程挂起（LockSupport.park）。

### 3.可中断锁lockInterruptibly

在ReentrantLock中还支持可中断锁的获取，是通过lockInterruptibly()和tryLock()方法来实现的。它与lock方法逻辑几乎一样，差别在于检测到线程中断后直接抛出异常。

### 4.锁的释放

ReentrantLock释放锁是通过它自身的unlock方法，unlock方法中同样调用了AQS的release方法。tryRelease操控state，对state减去releases，如果state为0那么就释放锁，并且将排他线程设置为null，最后更新state。释放锁成功之后则会调用unparkSuccessor来唤起后继节点（LockSupport.unpark）。

五、总结
----

ReentrantLock内部通过FairSync和NonfairSync来实现公平锁和非公平锁。它们都是继承自AQS实现，在AQS内部通过state来标记同步状态，如果state为0，线程可以直接获取锁，如果state大于0，则线程会被封装成Node节点进入CLH队列并阻塞线程。AQS的CLH队列是一个双向的链表结构，头结点是一个空的Node节点。新来的node节点会被插入队尾并开启自旋去判断它的前驱节点是不是头结点。如果是头结点则尝试获取锁，如果不是头结点，则根据条件进行挂起操作。

参考&推荐阅读

- 深入剖析基于并发AQS的（独占锁）重入锁(ReetrantLock)及其Condition实现原理
- 从ReentrantLock的实现看AQS的原理及应用（美团技术团队）
