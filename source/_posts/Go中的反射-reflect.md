---
title: Go中的反射(reflect)
date: 2019-02-02 23:41:37
tags: Golang
---
许多语言都有反射的机制，并且每家都不尽相同。今天要谈的主要是`go`中的反射。

`go`标准库中有一个`reflect`库，其中实现的就是反射相关的内容。

有些同学可能觉得反射对我们写业务逻辑的来说遥不可及，其实不然。`go`中许多的机制和标准库的实现都依赖于反射，比如说`encoding`中的`json`, `xml`等编码解码库，`format string`中的`%T`和`%v`……

接下来就让我们从头开始认识一下`go`的`reflect`。

## Go反射的基本概念
`go`的反射中主要涉及了两个关键的类型：`reflect.Type`, `reflect.Value`。

在`go`中，每个变量由`Type`和`Value`两部分组成。

`interface`类型变量的结构本质是一个`(value, type)`对，而`interface{}`则是一个能接受所有`interface`的类型（因为其没有`method`，可以满足任何`interface`）

`reflect.Type`顾名思义就是`go`中变量的类型。他最常见的出现方式就是通过`reflect.TypeOf`函数得到（`format string`中的`%T`就是调用这个函数得到的）。

### reflect.Type
`reflect.Type`是一个`interface`，我们可以简单看一下它的一些主要的`method`：

```go
type Type interface {
    Align() int
    FieldAlign() int
    Method(int) Method
    MethodByName(string) (Method, bool)
    NumMethod() int
    Name() string
    PkgPath() string
    Size() uintptr
    String() string
    Kind() Kind
    Implements(u Type) bool
    AssignableTo(u Type) bool
    ConvertibleTo(u Type) bool
    Comparable() bool
    Bits() int
    ChanDir() ChanDir
    IsVariadic() bool
    Elem() Type
    FieldByName(name string) (StructField, bool)
    FieldByNameFunc(match MatchFunc) (StructField, bool)
    In(i int) Type
    Key() Type
    Len() int
    NumField() int
    NumIn() int
    NumOut() int
    Out(i int) Type
}
```
> 需要注意的是：`Type`中的接口并非能在所有类型上调用。对于未实现的方法，比如在非`struct`的类型上调用`NumField`会直接导致`panic`。

`Align`可以返回一个类型的内存分布情况，这一块主要是`unsafe`的内容，在这篇文章里就不展开来讲了。

`Method`和`MethodByName`可以访问类型对象下的`method`，其中`Method`一般是和`MethodByName`搭配使用：
```go
var v SomeType
t := reflect.TypeOf(v)
for i := 0; i < t.NumField(); i++ {
    m := t.Method(i)
    // do something
}
```
以上是一个遍历对象`method`的例子。

这里顺带提一下`Method`类型。

`Method`是一个非常简单的`struct`，定义如下：
```go
type Method struct {
    // Name is the method name.
    // PkgPath is the package path that qualifies a lower case (unexported)
    // method name. It is empty for upper case (exported) method names.
    // The combination of PkgPath and Name uniquely identifies a method
    // in a method set.
    // See https://golang.org/ref/spec#Uniqueness_of_identifiers
    Name    string
    PkgPath string

    Type  Type  // method type
    Func  Value // func with receiver as first argument
    Index int   // index for Type.Method
}
```

这里我们做个小实验：
```go
package main

import (
	"fmt"
	"reflect"
)

type U struct {
	B string
}

func (u *U) Hello(arg string) {}

func Hello(arg string) {}

func main() {
	var u = &U{"hi"}
	fmt.Println(reflect.TypeOf(Hello))
	fmt.Println(reflect.TypeOf(u).Method(0).Type)
}
```

这里会输出什么呢？

答案是：
```
func(string)
func(*main.U, string)
```

我们可以看到虽然两个`Hello`的函数签名是相同的，但是作为`Method`的`Hello`会得到一个`receiver`的指针作为参数（这里将`receiver`的类型改为`U`得到的也会是一个指针，有兴趣的读者可以多做做实验）。

这就意味着`go`中的`method`本质上是个语法糖（比较像`python`的`method`传`self`），我们可以显式地知道每个`method`在内存中只会有一个实体（比起`C++`要好得多，虽然`C++`编译器的一般实现也是这样，但是`C++`的`method`都是通过`this`来获取的，对于用户来说完全是黑盒）。

`Name`, `Size`, `PkgPath`, `String`都是用来查看`Type`的基本信息。`Implements`用于判断`Type`是否实现了某个`interface`。

这里有必要提一下`Kind`这个`method`，因为它真的十分好用。

`reflect.Kind`是一组枚举：
```go
const (
    Invalid Kind = iota
    Bool
    Int
    Int8
    Int16
    Int32
    Int64
    Uint
    Uint8
    Uint16
    Uint32
    Uint64
    Uintptr
    Float32
    Float64
    Complex64
    Complex128
    Array
    Chan
    Func
    Interface
    Map
    Ptr
    Slice
    String
    Struct
    UnsafePointer
)
```
这里面枚举出了所有的`go`基本类型，你可以使用`Kind`方法确切的知道某个变量到底是属于什么类型的。


这样讲起来也许会太过抽象，所以我们试想一个场景。

我们的手里有一个`struct`类型，它的结构十分复杂，且深度不确定。它可能是这样的：
```go
type SomeStruct struct {
    FieldA string
    FieldB int16
    FieldC map[string]interface{}
    FieldD *SomeStruct
}
```

虽然一般日常工作中可能不会有人这样写代码，但它就是出现了，你也没有办法，只能硬着头皮上。

现在你的工作是遍历整个`struct`的每个`field`，并将其`print`出来，你要怎么做？

一般人看到这个需求肯定一拍脑袋就递归搜索走起了，但是需要注意的是这里有个`interface{}`。

这意味着这里的类型是动态的，你无法在编译时就决定其搜索策略。

你可能想到使用`TypeOf`来识别`Type`，但是实际上`TypeOf`只能得到变量定义时的类型。比如说`type MyInt int`, `type YourInt int`，虽然大家都是`int`，但是在`Type`看来是不一样的。

这个时候就要用上`Kind`了。得亏`go`作为一个强类型语言，类型十分严谨。你可以根据其**底层类型**决定搜索策略，比如说对于`int`, `int8`, `int16`, `int32`, `int64`, `uint`, `uint8`, `uint16`, `uint32`, `uint64`, `float32`, `float64`等类型直接`print`，而对于`struct`则继续迭代遍历其`field`。

这时还有一种比较有意思的情况，就是`interface{}`的实际类型为**指针**。对于指针，反射无法直接提取其实际的值，只能通过解引用。

面对这种情况，我们可以使用`Kind`判断变量的类型是否为指针，如果是指针则通过`Elem`方法取出其中的值。

> 这时又可以引申出一种特殊情况，就是`go`中的多级指针。实际上`go`不允许显式定义多级指针，但是我们可以通过`var p = &new(SomeStruct)`这种方式创造多级指针。对于多级指针，反射无法正常地进行类型的萃取，需要十分注意。正常人不应该这样写代码，尽管它可以这么写。这也是`go`和`C`十分相似的一个地方。

### reflect.Value
`reflect.Value`是`go`的`interface`的核心。

在`go`中，变量的类型可以按这种方式区分：`concrete type`和`interface type`。

`concrete type`就是我们在编译时便可确认的值，而`interface type`则是动态的。

`reflect.Value`可以接受任意类型的值，并对其进行一些处理，比如说`get`或者`set`。

`reflect.Vlaue`上的`method`非常多，并且可以直接通过`Type`方法获取`Value`的`Type`。这其中涵盖了`go`中各个类型的各种基本操作，在此就不多做赘述。

## 使用reflect实现遍历

以我在前面提到的需求为例，我们尝试用`reflect`来实现。

比如说我们要打印每一个数据项，那么我们可以这样写(DFS实现)：
```go
package itr

import (
	"fmt"
	"reflect"
)

func Traverse(i interface{}) {
	v := reflect.ValueOf(i)
	name := v.Type().Name()
	if v.Kind() == reflect.Ptr {
		name = v.Elem().Type().Name()
	}
	fmt.Println("Ready to traverse:", name)
	traverse(name, v)
}

func traverse(path string, v reflect.Value) {
	switch v.Kind() {
	case reflect.Invalid:
		return
	case reflect.Slice, reflect.Array:
		for idx := 0; idx < v.Len(); idx++ {
			traverse(fmt.Sprintf("%s[%d]", path, idx), v.Index(idx))
		}
	case reflect.Map:
		for _, k := range v.MapKeys() {
			traverse(fmt.Sprintf("%s[%v]", path, k), v.MapIndex(k))
		}
	case reflect.Struct:
		for i := 0; i < v.NumField(); i++ {
			traverse(fmt.Sprintf("%s.%s", path, v.Type().Field(i).Name), v.Field(i))
		}
	case reflect.Ptr:
		if v.IsNil() {
			fmt.Printf("%s = nil", path)
		} else {
			traverse(fmt.Sprintf("(*%s)", path), v.Elem())
		}
	default:
		fmt.Println(path, "=", v)
	}
}

```
这段代码里没有覆盖到`interface`的情况，如有需要可以自己加上。

让我们来测试一下：
```go
package itr

import "testing"

type testStruct struct {
	a string
	b int
	c map[string]string
	d []int
}

func TestTraverse(t *testing.T) {
	var a = &testStruct{"hello", 123, map[string]string{"hi": "how are you"}, []int{3, 4, 5, 6, 9}}
	Traverse(a)
}
```

结果如下：
```
Ready to traverse: testStruct
(*testStruct).a = hello
(*testStruct).b = 123
(*testStruct).c[hi] = how are you
(*testStruct).d[0] = 3
(*testStruct).d[1] = 4
(*testStruct).d[2] = 5
(*testStruct).d[3] = 6
(*testStruct).d[4] = 9
PASS
ok      github.com/leiysky/itr  0.005s
```
