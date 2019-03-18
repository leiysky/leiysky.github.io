---
title: Go中的同步机制sync
date: 2019-02-03 16:09:12
tags:
---
我们都知道在并行程序设计中，同步(sync)是一个永恒的问题。

在传统的多线程程序中，线程同步的手段非常多。

以`Linux`下的`pthread`为例，我们可以通过`信号量(semaphore)`，`锁(Lock)`，`条件变量`等方式进行线程同步。

而这些机制又有各自的作用领域，单是`Lock`就分为`Mutex`互斥锁，`Spin`自旋锁，`RW`读写锁。

本文主要介绍的是`go`中的锁。

`go`中并行编程的形式是`goroutine`，一种轻量级的协程。`go`标准库中提供了`sync`库，用于做`goroutine`之间的同步。`go`在设计时吸收了许多其他语言的优点，因此你在第一次接触`sync`时也会有一种亲切感。

## sync.Mutex

`Mutex`就是互斥锁，它是`Mutual Exclusion`的简写。

我们都知道，在编程时总会有一些对于执行顺序要求很高的代码段。如果执行的顺序不确定，那么程序执行的结果也会是一团糟。

在并行执行的环境下，总会出现这样的竞争条件。

比如说，我们有这样一段代码：
```go
package main

import (
	"fmt"
	"time"
)

var a = 0

func Incr() int {
	a++
	time.Sleep(time.Duration(1)) // 去掉这一行的话输出相同的数字的几率会大大减小，不过依然存在
	return a
}

func main() {
	go func() {
		fmt.Println(Incr())
	}()
	go func() {
		fmt.Println(Incr())
	}()
	time.Sleep(time.Duration(1) * time.Second)
}

```

这段代码我们自然是希望它能输出两个不一样的数字，但事实是它有可能会输出相同的数字。因为并行的两个`goroutine`的语句执行顺序是完全未知的，他们只能在自己的上下文中保证结果正确，实际上可能会穿插执行，甚至乱序。

这个时候我们可以用简单的互斥锁来解决。

我们可以发现这个例子中的整个`Incr`函数都是临界区，所以我们可以这么写：
```go
package main

import (
	"fmt"
	"sync"
	"time"
)

var a = 0

var lock = &sync.Mutex{}

func Incr() int {
	lock.Lock()
	defer lock.Unlock()
	a++
	time.Sleep(time.Duration(1)) // 去掉这一行的话输出相同的数字的几率会大大减小，不过依然存在
	return a
}

func main() {
	go func() {
		fmt.Println(Incr())
	}()
	go func() {
		fmt.Println(Incr())
	}()
	time.Sleep(time.Duration(1) * time.Second)
}

```
这样我们就成功给`Incr`加了锁，所有的`goroutine`共享一个锁。每次执行到`lock.Lock()`时，只有`lock`的状态为`unlock`的情况下才会继续执行，这就保证了一次只有一个`goroutine`在临界区内。

### go的Mutex实现

go的`Mutex`代码不多，只有200多行，阅读起来也比较轻松，因此我们可以对源码进行一下剖析。

`sync.Mutex`涉及的文件为[src/sync/mutex.go](https://golang.org/src/sync/mutex.go)。

该文件中定义了一个`Mutex`的`struct`以及`Locker`的`interface`：
```go
// A Mutex is a mutual exclusion lock.
// The zero value for a Mutex is an unlocked mutex.
//
// A Mutex must not be copied after first use.
type Mutex struct {
	state int32
	sema  uint32
}

// A Locker represents an object that can be locked and unlocked.
type Locker interface {
	Lock()
	Unlock()
}
```
以及一组`Mutex.state`的常量：
```go
const (
	mutexLocked = 1 << iota // 1
	mutexWoken // 2
	mutexStarving // 4
	mutexWaiterShift = iota // 3
	starvationThresholdNs = 1e6
)
```
这里利用了`iota`的特性生成了一组`bitmap`。

`Locker`上的两个方法`Lock`和`Unlock`十分简洁明了。

接下来我们看看`Lock`方法的实现：
```go
func (m *Mutex) Lock() {
  // Fast path: grab unlocked mutex.
  // 通过原子的CompareAndSwap尝试获取锁的使用权
  // state为非0，即Locked, Woken, Starving或者WaiterShift时交换失败，进入等待
	if atomic.CompareAndSwapInt32(&m.state, 0, mutexLocked) {
    // 检测竞争
		if race.Enabled {
			race.Acquire(unsafe.Pointer(m))
		}
		return
	}

  // 记录等待时间的timer，以进入饥饿状态
	var waitStartTime int64
	starving := false
	awoke := false
	iter := 0
  old := m.state
  // 自旋等待
	for {
		// Don't spin in starvation mode, ownership is handed off to waiters
    // so we won't be able to acquire the mutex anyway.
    // 一个goroutine被唤醒之后会自旋地轮询状态，但是到一定次数之后就会被剥夺自旋权利
    // 在runtime中定义了active_spin = 4，超出这个次数runtiem_canSpin会返回false
		if old&(mutexLocked|mutexStarving) == mutexLocked && runtime_canSpin(iter) {
			// Active spinning makes sense.
			// Try to set mutexWoken flag to inform Unlock
			// to not wake other blocked goroutines.
			if !awoke && old&mutexWoken == 0 && old>>mutexWaiterShift != 0 &&
				atomic.CompareAndSwapInt32(&m.state, old, old|mutexWoken) {
				awoke = true
			}
			runtime_doSpin()
			iter++
			old = m.state
			continue
    }
    // 进入该分支说明锁处于Starving或者Unlocked
		new := old
    // Don't try to acquire starving mutex, new arriving goroutines must queue.
    // 不为Starving状态时排队
		if old&mutexStarving == 0 {
			new |= mutexLocked
    }
		if old&(mutexLocked|mutexStarving) != 0 {
			new += 1 << mutexWaiterShift
		}
		// The current goroutine switches mutex to starvation mode.
		// But if the mutex is currently unlocked, don't do the switch.
		// Unlock expects that starving mutex has waiters, which will not
		// be true in this case.
		if starving && old&mutexLocked != 0 {
			new |= mutexStarving
		}
		if awoke {
			// The goroutine has been woken from sleep,
			// so we need to reset the flag in either case.
			if new&mutexWoken == 0 {
				throw("sync: inconsistent mutex state")
			}
			new &^= mutexWoken
		}
		if atomic.CompareAndSwapInt32(&m.state, old, new) {
			if old&(mutexLocked|mutexStarving) == 0 {
				break // locked the mutex with CAS
			}
			// If we were already waiting before, queue at the front of the queue.
			queueLifo := waitStartTime != 0
			if waitStartTime == 0 {
				waitStartTime = runtime_nanotime()
			}
			runtime_SemacquireMutex(&m.sema, queueLifo)
			starving = starving || runtime_nanotime()-waitStartTime > starvationThresholdNs
			old = m.state
			if old&mutexStarving != 0 {
				// If this goroutine was woken and mutex is in starvation mode,
				// ownership was handed off to us but mutex is in somewhat
				// inconsistent state: mutexLocked is not set and we are still
				// accounted as waiter. Fix that.
				if old&(mutexLocked|mutexWoken) != 0 || old>>mutexWaiterShift == 0 {
					throw("sync: inconsistent mutex state")
				}
				delta := int32(mutexLocked - 1<<mutexWaiterShift)
				if !starving || old>>mutexWaiterShift == 1 {
					// Exit starvation mode.
					// Critical to do it here and consider wait time.
					// Starvation mode is so inefficient, that two goroutines
					// can go lock-step infinitely once they switch mutex
					// to starvation mode.
					delta -= mutexStarving
				}
				atomic.AddInt32(&m.state, delta)
				break
			}
			awoke = true
			iter = 0
		} else {
			old = m.state
		}
	}

	if race.Enabled {
		race.Acquire(unsafe.Pointer(m))
	}
}
```

整个代码处理逻辑大约是这样的：
1. 进入循环

2. 判断是否能够唤醒，如果能唤醒则进入唤醒状态并且自旋

3. 如果不为饥饿状态，则保证其处于Locked状态，并且进入排队状态（这里的排队数量记录比较trick，直接使用`m.state`的高位记录）

4. 判断是否排队或者是否饥饿，如果只有一个排队则解除饥饿状态

5. 使用原子操作`AddInt32`更新排队数量

我们可以看到，在这个锁结构中，各`goroutine`需要竞争的是`m.state`，所以对于`m.state`的操作一律使用原子操作进行。

`Unlock`的代码：
```go
func (m *Mutex) Unlock() {
	if race.Enabled {
		_ = m.state
		race.Release(unsafe.Pointer(m))
	}

	// Fast path: drop lock bit.
	new := atomic.AddInt32(&m.state, -mutexLocked)
	if (new+mutexLocked)&mutexLocked == 0 {
		throw("sync: unlock of unlocked mutex")
	}
	if new&mutexStarving == 0 {
		old := new
		for {
			// If there are no waiters or a goroutine has already
			// been woken or grabbed the lock, no need to wake anyone.
			// In starvation mode ownership is directly handed off from unlocking
			// goroutine to the next waiter. We are not part of this chain,
			// since we did not observe mutexStarving when we unlocked the mutex above.
			// So get off the way.
			if old>>mutexWaiterShift == 0 || old&(mutexLocked|mutexWoken|mutexStarving) != 0 {
				return
			}
			// Grab the right to wake someone.
			new = (old - 1<<mutexWaiterShift) | mutexWoken
			if atomic.CompareAndSwapInt32(&m.state, old, new) {
				runtime_Semrelease(&m.sema, false)
				return
			}
			old = m.state
		}
	} else {
		// Starving mode: handoff mutex ownership to the next waiter.
		// Note: mutexLocked is not set, the waiter will set it after wakeup.
		// But mutex is still considered locked if mutexStarving is set,
		// so new coming goroutines won't acquire it.
		runtime_Semrelease(&m.sema, true)
	}
}

```
解锁的代码就相对简单了很多，他要做的就是释放锁的`Unlocked`状态，并且尝试唤醒其他的`goroutine`中的`Lock`。

### sync.Mutex的应用

因为`sync.Mutex`实际上是一组实现了的接口，我们可以直接将其与其他的类型组合嵌套使用。

回到上面的例子，我们需要实现一个`Incr`函数，那么我们可以改成这样写：
```go
package main

import (
	"fmt"
	"sync"
	"time"
)

type Increaser interface {
	Incr() int
}

type MyIncreaser struct {
	a int
	sync.Mutex
}

func (m *MyIncreaser) Incr() int { // 这里必须用指针receiver
	m.Lock()
	defer m.Unlock()
	m.a++
	time.Sleep(time.Duration(1)) // 去掉这一行的话输出相同的数字的几率会大大减小，不过依然存在
	return m.a
}

func main() {
	var incr Increaser
	incr = &MyIncreaser{}
	go func() {
		fmt.Println(incr.Incr())
	}()
	go func() {
		fmt.Println(incr.Incr())
	}()
	time.Sleep(time.Duration(1) * time.Second)
}

```

## sync.RWMutex

`go`中的`RWMutex`实际上是`Mutex`的一个简单封装。



## sync.Map

`go`中的`map`本身不是`goroutine`安全的，在并发读写的过程中可能会出现`fatal error: concurrent map read and map write`的`panic`。

`sync.Map`是`go1.9`中推出的新功能，它的特点是能够安全地进行并发读写。

`sync.Map`的定义如下：
```go

```