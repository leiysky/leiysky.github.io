---
title: Golang constructor
date: 2018-10-28 20:04:35
tags: Golang
---
## Go中构造函数的N种写法
在支持面向对象的语言中，都有类似C++中通过创建类的实例的方式来创建对象的渠道。

而在这类编程范式中，大多使用 **构造函数(constructor)** 来初始化对象(或者用于做对象创建时的hook)

我们都知道面向对象带来的便利——逻辑上的抽象，统一的接口，无一不为面向服务的项目(业务逻辑代码)的编写带来极大的便利。

Golang设计的初衷虽然是用于代替底层的C等语言，但是由于其简洁高效的特点，还是有很多人选择用它来写业务逻辑。

虽然Golang中没有提供原生的面向对象支持(比如class等概念)，但我们也可以用其实现简单的面向对象。

今天我们就来讲一讲Golang中构造函数的N中写法。

## Rob Pike Style
首先来讲讲**Rob Pike Style**的`constructor`，这个名字是我起的(其实主要是因为这种写法最早出现在Rob Pike的一篇[博客](https://commandcenter.blogspot.com/2014/01/self-referential-functions-and-design.html))

不说别的，先来看一段代码：
```go
package main

import (
    "fmt"
)

type options struct {
    a int64
    b string
    c map[int]string
}

func NewOption(opt ...ServerOption) *options {
    r := new(options)
    for _, o := range opt {
        o(r)
    }
    return r
}

type ServerOption func(*options)

func WriteA(s int64) ServerOption {
    return func(o *options) {
        o.a = s
    }
}

func WriteB(s string) ServerOption {
    return func(o *options) {
        o.b = s
    }
}

func WriteC(s map[int]string) ServerOption {
    return func(o *options) {
        o.c = s
    }
}

func main() {
    opt1 := WriteA(int64(1))
    opt2 := WriteB("test")
    opt3 := WriteC(make(map[int]string,0))

    op := NewOption(opt1, opt2, opt3)

    fmt.Println(op.a, op.b, op.c)
}
```

这段代码乍看起来有点骚，利用闭包来进行构造，不过实际上还是很好理解的。

其中的`WriteA`, `WriteB`, `WriteC`就像一个又一个的插头，插上了，某盏灯就亮了起来。

这样写的好处主要有几点：
* `NewOption`函数实现后就不需要更改，降低了耦合度
* 在实例创建时，很直观地可以看出初始化的方式
* 创建实例时可按需要定制初始化的方式，十分自由，而无需关心其具体实现，降低了耦合度

## 链式调用
这种方式和上面的方式思路差不多，主要是写法上的不同，更加适合**Java**等语言的思维。

```go
package main

import (
    "fmt"
)

type options struct {
    a int64
    b string
    c map[int]string
}

type ServerOption func(*options)

func (o *options) WriteA(s int64) ServerOption {
  o.a = s
  return o
}

func (o *options) WriteB(s string) ServerOption {
  o.b = s
  return o
}

func (o *options) WriteC(s map[int]string) ServerOption {
  o.c = s
  return o
}

func main() {
    op := new(options).WriteA(int64(1))
                      .WriteB("test")
                      .WriteC(make(map[int]string,0))

    fmt.Println(op.a, op.b, op.c)
}
```

这种写法其实还蛮有意思的……

