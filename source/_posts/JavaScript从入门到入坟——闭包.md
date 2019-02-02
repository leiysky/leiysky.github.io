---
title: JavaScript从入门到入坟——闭包
date: 2018-05-31 14:55:12
tags: JavaScript
---

## 导语

闭包是函数式编程中非常重要的一个概念，以下引用维基百科的介绍：

> 在[计算机科学](https://zh.wikipedia.org/wiki/%E8%AE%A1%E7%AE%97%E6%9C%BA%E7%A7%91%E5%AD%A6)中，**闭包**（英语：Closure），又稱**词法闭包**（Lexical Closure）或**函數閉包**（function closures），是引用了自由变量的函数。这个被引用的自由变量将和这个函数一同存在，即使已经离开了创造它的环境也不例外。所以，有另一种说法认为闭包是由函数和与其相关的引用环境组合而成的实体。闭包在运行时可以有多个实例，不同的引用环境和相同的函数组合可以产生不同的实例。

简单来说，闭包就是一个引用了外部变量的函数与该变量创建环境连结成的一个结构(**struct, record**)。该环境和函数不会在函数被调用完后就被销毁，可以长时间存在，因此常被用于创造一个私有的环境。

目前最广为人知的拥有闭包特性的高级语言就是Javascript和Python。而熟悉这两种语言的大佬们都知道，闭包的应用在平时的开发工作中是非常重要的，特别是在写Javascript的时候。如果离开了闭包，Javascript的很多功能将无法实现。

因此，了解闭包的机制是JavaScript学习之路上必不可少的一道坎。现在就让我们开始探索闭包的奥秘（x）

## 一道面试题

首先我们先来看一道面试题：

```js
function fun(n,o) {
  console.log(o);
  return {
    fun:function(m){
      return fun(m,n);
    }
  };
}
var a = fun(0);  a.fun(1);  a.fun(2);  a.fun(3);//undefined,?,?,?
var b = fun(0).fun(1).fun(2).fun(3);//undefined,?,?,?
var c = fun(0).fun(1);  c.fun(2);  c.fun(3);//undefined,?,?,?
//问:三行a,b,c的输出分别是什么？
```

第一眼看到题目的时候一定觉得十分头疼，因为这一个fun函数中竟然有这么多种fun的调用。

先留下几个问题：

1. fun函数中return的object中的fun中return的`fun(m, n)` (即第五行的`fun(m, n)`)调用的是哪个函数？
2. 1中的调用的`fun(m, n)`的n是什么值？

不用着急想答案，我们先来分析一下这份代码。

在开始分析之前，先整理一下JavaScript函数相关的知识。

### 函数的种类

在JavaScript中函数分为以下几种：

**匿名函数 (anonymous function)**

```js
function () {};
// 或者使用ES6的箭头函数
() => {};
```

**普通函数 (named function)**

```js
function foo() {};
var foo = () => {};
// 或者使用ES6箭头函数
const foo = () => {};
```

**内部函数 (inner function)**

内部函数就是定义在函数内部的函数，也是闭包中十分重要的概念。

```js
function addSquares(a,b) {
   function square(x) {
      return x * x;
   }
   return square(a) + square(b);
};
// 使用ES6箭头函数
const addSquares = (a,b) => {
   const square = x => x*x;
   return square(a) + square(b);
};
```

**自调用匿名函数 (Immediately Invoked Function Expressions)**

这种不太常见，不过有时候也会有些用处。

```js
(function foo() {
    console.log("Hello Foo");
}());

(function food() {
    console.log("Hello Food");
})();
```

那么很显然，这里的`fun`返回的是一个由内部函数组成的Object。

### 作用域

JavaScript中的作用域比较奇特，它不像C-family的语言，只要是个花括号就有单独的作用域。Javascript中只有全局作用域和函数作用域。

比如说:

```js
var a = 1;
if(true) {
    var a = 2;
}
console.log(a); // 2

var a = 1;
(function () {var a = 2})();
console.log(a); // 1
```

这里是个很典型的例子。在`if`的语句块中执行的`var a = 2;`实际上是重新定义了一个a，覆盖了全局作用域中a的值。而在函数中定义的a不会覆盖全局作用域的a，因为它有一个独立的作用域。

这种作用域机制引发了一系列的问题，举个例子：

```js
for (var i = 0; i < 5 ;i++) {
    setTimeout(function() {
        console.log(i); // 5 5 5 5 5
    }, 2000); // 延时2秒
} 
```

按照以往写其他语言的逻辑，这段代码输出的应该是**0 1 2 3 4**，但是由于没有独立的块级作用域，每个`console.log(i)`中的`i`实际上是同一个变量的引用，因为延时2秒后i的值固定为5，所以此时执行的输出全都会输出当前`i`的值。

解决这个问题的方法就是人为创造块级作用域，使每次循环传入的参数不同。实现这个有两种思路，一种是使用闭包，另一种是ES6提供的块级作用域声明`let`和`const`（本质上也是使用了闭包的机制）。

使用闭包的解决方案如下:

```js
for (var i = 0; i < 5; i++) {
    (function(i) {
        setTimeout(function() {
        	console.log(i); // 0 1 2 3 4
    	}, 2000);
    })(i); 
}
```

这里将`i`作为参数传入作用域中。因为JavaScript的参数传递采取的是值传递的方式，每次循环传入的`i`会单独创建一个作用域，因此最后输出的值会不同。

JavaScript中有一个很形象的名称来形容这种作用域——作用域链。

整个JavaScript程序的作用域链可以组成一棵作用域树，其根节点是全局作用域。当一个子节点中要使用一个变量时，它会先在当前作用域寻找，如果找不到该变量的定义，则从它的父节点中寻找，如此递归，直到寻找到该变量的定义或者到达根节点并且没有找到该变量的定义。

举个例子：

```js
var a = "hahaha";
function A() {
    return function() {
        console.log(a);
    }
}

function B() {
    var a = "ruaruarua";
    return function() {
        console.log(a);
    }
}

function C() {
    return function() {
        console.log(b);
    }
}

A()(); // hahaha
B()(); // ruaruarua
C()(); // undefined
```

在这个例子中，作用域树可以画成：

```js
global
|
|-- a = "hahaha"
|
|-- A
|   |
|   |-- function
|
|-- B
|   |
|   |-- function
|   |-- a = "ruaruarua"
|
|-- C
    |
    |-- function
```

不难看出全局作用域上有变量a(值为"hahaha")，A、B、C三个函数作用域，A、B、C中又各有一个子函数。当调用某个子函数时，子函数会先在自己的作用域中寻找a的定义，之后向上逐层寻找。A中输出的是全局作用域中的a，B中子函数输出的是B作用域中的a，C中因为在整条作用域链上都没有找到b的定义，因此会输出undefined。

### 垃圾回收机制

JavaScript在定义变量的时候就会自动为变量分配内存空间，并且不需要手动进行释放（也没有提供手动释放内存的关键字），所以一般没有人会关心这些内存是否在使用，如何被使用。

不过JavaScript的内存回收机制实际上为闭包机制的实现提供了便利。

JavaScript的内存回收是通过对变量引用的追踪完成的，当指向内存中某片区域的变量数量为0时，这片区域就会被释放。这种机制一般被称作**引用计数(Reference Counting)**。

实际上对于**引用(Reference)**的定义还要再复杂一些：

> 在内存管理的环境中，一个对象如果有访问另一个对象的权限（隐式或者显式），叫做一个对象引用另一个对象。例如，一个Javascript对象具有对它[原型](https://developer.mozilla.org/en/JavaScript/Guide/Inheritance_and_the_prototype_chain)的引用（隐式引用）和对它属性的引用（显式引用）。

而在javascript中，这里的**对象**指的不仅仅是各个类型的变量，还有函数的作用域，或者说是一个变量环境。

这里来看一个简单的闭包的例子：

```js
function A() {
    var a = "hahaha";
    return function() {
        return a;
    }
}
var b = A();
console.log(b()); // hahaha
```

这里的`A()`调用之后会返回一个函数对象，而这个函数对象又会返回它的外部的变量——定义在`A`中的`a`。按照写C-family的经验，一个函数执行完之后其中定义的栈变量会随着函数一起被回收掉。但是在这里，`A()`执行完之后`a`的值依旧可以被访问到（函数返回的a是a的引用）。

这是因为内部函数是会和它的执行环境绑定在一起的。当`var b = A();`语句执行时，b引用了`A`内部的变量，即被返回的函数对象。根据垃圾回收的机制，该函数的引用没有变为0，因此不会被释放。而该对象的访问是建立在其执行环境也被保存的情况下。

当一个函数中的某个变量被外部引用时，该函数作用域上的父节点执行的上下文会全部被存下，而不是被释放。

因此在使用js的函数时应当尽量避免返回内部变量的引用，以免引起内存过高的占用。

另外，引用计数还有一种很严重的缺陷，参照以下代码：

```js
function f(){
  var o = {};
  var o2 = {};
  o.a = o2; // o 引用 o2
  o2.a = o; // o2 引用 o

  return "azerty";
}

f();
```

这里的o和o2之间产生了循环引用，引用的计数永远不会归零，因此该作用域下的变量不会被自动回收，从而造成内存泄漏。

### 继续分析题目

回顾完上面的知识，我们继续来看这道题。

先公布下答案，方便之后分析：

```js
function fun(n,o) {
  console.log(o);
  return {
    fun:function(m){
      return fun(m,n);
    }
  };
}
var a = fun(0);  a.fun(1);  a.fun(2);  a.fun(3);//undefined,?,?,?
var b = fun(0).fun(1).fun(2).fun(3);//undefined,?,?,?
var c = fun(0).fun(1);  c.fun(2);  c.fun(3);//undefined,?,?,?
//问:三行a,b,c的输出分别是什么？

//答案：
//a: undefined,0,0,0
//b: undefined,0,1,2
//c: undefined,0,1,1
```

首先是第一部分的代码。

```js
var a = fun(0);
a.fun(1); 
a.fun(2);  
a.fun(3);
```

在执行`var a = fun(0);`这行代码时，第一次调用了`fun`函数。首先做个小实验：

```js
function fun(n,o) {
  console.log(o);
  return {
    fun:function(m){
      return fun(m,n);
    }
  };
}
```

![image-20180531140714064](/var/folders/kt/wcrwryxs5mn8n609rnljhn3m0000gn/T/abnerworks.Typora/image-20180531140714064.png)

这里可以看出fun对应的function中调用的`fun(m, n)`并不是它本身，而是顺着作用域链向上找到的在全局作用域定义的`fun(n, o)`。那么问题1就解决了。

接下来就可以开始考虑问题2，这里调用的n自然而然就是`fun(n, o)`中传入的参数n。

了解清楚这些，我们就可以开始整理整个流程。

首先看`var a = fun(0);`，将参数代入是这样子的：

```js
function fun(0, undefined) {
  console.log(undefined);
  return {
    fun:function(m){
      return fun(m, 0);
    }
  };
}
```

再执行下一句`a.fun(1)`：

```js
function fun(1, 0) {
  console.log(0);
  return {
    fun:function(m){
      return fun(m, 1);
    }
  };
}
```

那么这里理所应当输出0。

再看下一句，`a.fun(2)`。这里和上一句一样，都是建立在a的上下文中的，因此n的值还是0，所以也是输出0。以此类推，`a.fun(3)`也是一样，会输出0。

接下来分析下一段：

```js
var b = fun(0).fun(1).fun(2).fun(3);//undefined,?,?,?
```

这里可以看出是一个递归调用的过程，每一次fun的调用都是以上一次调用的返回结果为基础，写成代码是这样的：

```js
function fun(0, undefined) {
  console.log(undefined);
  return {
    fun:function(m){
      return fun(m, 0);
    }
  };
} // fun(0)

function fun(1, 0) {
  console.log(0);
  return {
    fun:function(m){
      return fun(m, 1);
    }
  };
} // fun(0).fun(1)

function fun(2, 1) {
  console.log(1);
  return {
    fun:function(m){
      return fun(m, 2);
    }
  };
} // fun(0).fun(1).fun(2)

function fun(3, 2) {
  console.log(2);
  return {
    fun:function(m){
      return fun(m, 3);
    }
  };
} // fun(0).fun(1).fun(2).fun(3)
```

很显然，输出是0 1 2。

分析了前两个，第三个的结果也很容易可以推导出来，在此我就不再多做分析。

## 闭包的应用

经过以上的学习，大家对于闭包机制已经十分了解了，接下来我们来讲一讲闭包在实际开发中的应用。

### 私有变量

我们都知道，JavaScript中没有像C++那样类的定义，实现面向对象的方式依靠的是原型链(以后会详细讲到)。

这样的方式有一个很大的缺点就是没有访问控制，对象所有的属性都是public级别的。为了营造一个private的class filed，我们可以使用闭包来实现。因为闭包可以实现对一个作用域的访问控制。

接下来是一个面向对象的例子：

```js
function A() {
    this.a = "hahaha";
    this.b = "ruaruarua";
}

var a = new A();
console.log(a.a); // hahaha
console.log(a.b); // ruaruarua
```

这是一个典型的JavaScript式面向对象，所有属性都是对外公开的，可以随意访问，那么我们现在用闭包实现一个私有变量域。在此之前考虑一个问题，怎么做才能使用户无法从**A的实例上**直接访问私有变量呢？

下面是代码：

```js
function A() {
    this.getPrivate = function() {
        return {
            _a : "hahaha",
            _b : "ruaruarua"
        }
    }
    this.a = function() {
        return this.getPrivate()._a;
    }
    this.b = function() {
        return this.getPrivate()._b;
    }
}
```

这样就实现了私有变量。A的实例只能通过`getPrivate()`或者`a()`和`b()`的方式获得，并且不可直接更改。因为A的实例无法访问子函数的作用域，自然也就无法访问其中的变量。

### 实用闭包

在 Web 中，你想要这样做的情况特别常见。大部分我们所写的 JavaScript 代码都是基于事件的 — 定义某种行为，然后将其添加到用户触发的事件之上（比如点击或者按键）。我们的代码通常作为回调：为响应事件而执行的函数。

假如，我们想在页面上添加一些可以调整字号的按钮。一种方法是以像素为单位指定 `body` 元素的 `font-size`，然后通过相对的 `em` 单位设置页面中其它元素（例如`header`）的字号：

```Css
body {
  font-family: Helvetica, Arial, sans-serif;
  font-size: 12px;
}

h1 {
  font-size: 1.5em;
}

h2 {
  font-size: 1.2em;
}
```

我们的文本尺寸调整按钮可以修改 `body` 元素的 `font-size` 属性，由于我们使用相对单位，页面中的其它元素也会相应地调整。

以下是 JavaScript：

```js
function makeSizer(size) {
  return function() {
    document.body.style.fontSize = size + 'px';
  };
}

var size12 = makeSizer(12);
var size14 = makeSizer(14);
var size16 = makeSizer(16);
```

`size12`，`size14` 和 `size16` 三个函数将分别把 `body` 文本调整为 12，14，16 像素。我们可以将它们分别添加到按钮的点击事件上。如下所示：

 ```js
document.getElementById('size-12').onclick = size12;
document.getElementById('size-14').onclick = size14;
document.getElementById('size-16').onclick = size16;
 ```

```Html
<a href="#" id="size-12">12</a>
<a href="#" id="size-14">14</a>
<a href="#" id="size-16">16</a>
```

这样就实现了这个按钮。

### 在循环中使用闭包

这部分请参照作用域部分的讲解。