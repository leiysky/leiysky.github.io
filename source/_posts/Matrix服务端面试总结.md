---
title: Matrix服务端面试总结
date: 2018-05-13 14:45:05
tags: 面试
---

## 前言

今天下午完成了matrix服务端的面试，特于此将面试的题目总结一下，以备今后使用。

## HTTP相关

这方面主要考点在于对于HTTP请求头的一些认识。首先先讨论一下HTTP请求的组成。

HTTP请求由**请求行(request line)**，**请求头(request head)**，**空行(empty line)**和**请求体(request body)**。

```json
GET /HTTP/1.1
Host: www.google.com
```

以上是一个标准的HTTP请求行，他做的事情主要是表明一下使用的HTTP协议版本（这里第二行是HTTP1.1要求的一个作用Host指定主机）。

### 请求头

```json
GET / HTTP/1.1
Host: seer.61.com
Connection: keep-alive
Cache-Control: max-age=0
Upgrade-Insecure-Requests: 1
User-Agent: Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/65.0.3325.181 Safari/537.36
Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,* / *;q=0.8
Accept-Encoding: gzip, deflate
Accept-Language: zh-CN,zh;q=0.9,en;q=0.8
Cookie: tm-uuid=6ffe3e26-96d5-0baf-6db2-70c3042acf75; Hm_lvt_a18e04bf933ff220533099052f47a6ff=1526125381; Hm_lpvt_a18e04bf933ff220533099052f47a6ff=1526125381
```

这就是一个请求行和请求头搭配的例子（因为现在还在使用HTTP协议的网站实在太难找了，所以就先拿了赛尔号的主页）。可以看到这其中有很多条key-value，有一些比较常见的比如说：

> 1. User-Agent 首部包含了一个特征字符串，用来让网络协议的对端来识别发起请求的用户代理软件的应用类型、操作系统、软件开发商以及版本号。
> 2. Accept-Charset 请求头用来告知（服务器）客户端可以处理的字符集类型。 借助内容协商机制，服务器可以从诸多备选项中选择一项进行应用， 并使用Content-Type 应答头通知客户端它的选择。 
> 3. Content-Type 实体头部用于指示资源的MIME类型 media type 。 
> 4. Cookie 是一个请求首部，其中含有先前由服务器通过 Set-Cookie  首部投放并存储到客户端的 HTTP cookies。
> 5. Host 请求头指明了服务器的域名（对于虚拟主机来说），以及（可选的）服务器监听的TCP端口号。 
> 6. Referer 首部包含了当前请求页面的来源页面的地址，即表示当前页面是通过此来源页面里的链接进入的。服务端一般使用Referer首部识别访问来源，可能会以此进行统计分析、日志记录以及缓存优化等。 
> 7. 请求首部字段 Origin 指示了请求来自于哪个站点。该字段仅指示服务器名称，并不包含任何路径信息。该首部用于 CORS 请求或者 POST 请求。除了不包含路径信息，该字段与 Referer首部字段相似。 
> 8. Connection 头（header） 决定当前的事务完成后，是否会关闭网络连接。如果该值是“keep-alive”，网络连接就是持久的，不会关闭，使得对同一个服务器的请求可以继续在该连接上完成。

（参考自MDN[https://developer.mozilla.org/zh-CN/docs/Web/HTTP/Headers]())

请求头中还有一个很重要的概念，就是**请求方法(Request method)**。

**HTTP/1.1**中定义了八种请求方法，分别是:

> GET 
>
> 向指定的资源发出“显示”请求。使用GET方法应该只用在读取数据，而不应当被用于产生“副作用”的操作中，例如在Web Application中。其中一个原因是GET可能会被网络蜘蛛等随意访问。 
>
> HEAD 
>
> 与GET方法一样，都是向服务器发出指定资源的请求。只不过服务器将不传回资源的本文部分。它的好处在于，使用这个方法可以在不必传输全部内容的情况下，就可以获取其中“关于该资源的信息”（元信息或称元数据）。 
>
> POST 
>
> 向指定资源提交数据，请求服务器进行处理（例如提交表单或者上传文件）。数据被包含在请求本文中。这个请求可能会创建新的资源或修改现有资源，或二者皆有。 
>
> PUT
>
> 向指定资源位置上传其最新内容。 DELETE 请求服务器删除Request-URI所标识的资源。 TRACE 回显服务器收到的请求，主要用于测试或诊断。 OPTIONS 这个方法可使服务器传回该资源所支持的所有HTTP请求方法。用'*'来代替资源名称，向Web服务器发送OPTIONS请求，可以测试服务器功能是否正常运作。 
>
> CONNECT 
>
> HTTP/1.1协议中预留给能够将连接改为管道方式的代理服务器。通常用于SSL加密服务器的链接（经由非加密的HTTP代理服务器）。

比较常用的有四种，分别是**GET,POST,DELETE,PUT**。这也是我们实现**RESTful API**的一个很重要的概念。

### 请求体

请求体主要是为PUT和POST方法提供的，用于传输一些信息。

### 响应

响应(**response**)也包括状态行(**status line**)响应头(**response head**)和响应体(**response body**)。

响应头和请求头的字段种类相同，它一般被用于向客户端传递一些配置，比如Set-Cookie等。而响应体中的内容就是用户请求的结果。

状态行表示响应的状态，如下：

```json
HTTP/1.1 200 OK
```

以上是一个HTTP请求的状态行。状态行包含一个状态码(**status code**)。常见的状态码如下：

> HTTP **100 Continue** 信息型状态响应码表示目前为止一切正常, 客户端应该继续请求, 如果已完成请求则忽略
>
> HTTP  **101 Switching Protocol**（协议切换）状态码表示服务器应客户端升级协议的请求（[`Upgrade`](https://developer.mozilla.org/zh-CN/docs/Web/HTTP/Headers/Upgrade)请求头）正在进行协议切换。
>
> HTTP **200 OK** 表明请求已经成功. 默认情况下状态码为200的响应可以被缓存。
>
> 不同请求方式对于请求成功的意义如下:
>
> - [`GET`](https://developer.mozilla.org/zh-CN/docs/Web/HTTP/Methods/GET): 已经取得资源，并将资源添加到响应的消息体中。
> - [`HEAD`](https://developer.mozilla.org/zh-CN/docs/Web/HTTP/Methods/HEAD): 响应的消息体为头部信息。
> - [`POST`](https://developer.mozilla.org/zh-CN/docs/Web/HTTP/Methods/POST): 响应的消息体中包含此次请求的结果。
> - [`TRACE`](https://developer.mozilla.org/zh-CN/docs/Web/HTTP/Methods/TRACE): 响应的消息体中包含服务器接收到的请求信息。
>
> HTTP **300 Multiple Choices** 是一个用来表示重定向的响应状态码，表示该请求拥有多种可能的响应。用户代理或者用户自身应该从中选择一个。由于没有如何进行选择的标准方法，这个状态码极少使用。
>
> HTTP **304 Not Modified**说明无需再次传输请求的内容，也就是说可以使用缓存的内容。这通常是在一些安全的方法（[safe](https://developer.mozilla.org/en-US/docs/Glossary/safe)），例如[`GET`](https://developer.mozilla.org/zh-CN/docs/Web/HTTP/Methods/GET) 或[`HEAD`](https://developer.mozilla.org/zh-CN/docs/Web/HTTP/Methods/HEAD) 或在请求中附带了头部信息： [`If-None-Match`](https://developer.mozilla.org/zh-CN/docs/Web/HTTP/Headers/If-None-Match)或[`If-Modified-Since`](https://developer.mozilla.org/zh-CN/docs/Web/HTTP/Headers/If-Modified-Since)。
>
> HTTP **400 Bad Request** 响应状态码表示由于语法无效，服务器无法理解该请求。 客户端不应该在未经修改的情况下重复此请求。
>
> HTTP **403 Forbidden** 代表客户端错误，指的是服务器端有能力处理该请求，但是拒绝授权访问。
>
> HTTP **404** **Not Found** 代表客户端错误，指的是服务器端无法找到所请求的资源。返回该响应的链接通常称为坏链（broken link）或死链（dead link），它们会导向链接出错处理([link rot](https://en.wikipedia.org/wiki/Link_rot))页面。
>
> HTTP **500 Internal Server Error** 是表示服务器端错误的响应状态码，意味着所请求的服务器遇到意外的情况并阻止其执行请求。
>
> HTTP **502** **Bad Gateway** 是一种HTTP协议的服务器端错误状态代码，它表示扮演网关或代理角色的服务器，从上游服务器中接收到的响应是无效的。

### Cookie和Session

Cookie在web开发中是一个很重要的概念，其能为无状态的HTTP协议保存用户的会话状态，以及一些用户定制的配置。

服务器在第一次接收到一个用户的HTTP请求时，服务器可以在响应头中添加一个**Set-Cookie**字段，浏览器接收到之后就会存下Cookie（在浏览器中设置禁用Cookie后不会保存）。其中字段如下：

> Secure: 指定Cookie只能由HTTPS协议传输。
>
> HttpOnly: 指定Cookie不能被`document.cookie`访问。
>
> Domain: 指定Cookie的作用域，如`Domain=www.google.com`，指定了能接受Cookie的主机。
>
> Path: 指定主机下哪些路径可以接收Cookie。
>
> Expires: 指定一个过期时间`Expires=Date()`。

## Javascript相关

### 闭包

js的闭包是一个很神奇但是又极其蛋疼的机制，它从某种意义上解决了js没有块级作用域的问题，但是同时又造成了内存泄漏。

具体的做法是利用js的函数作用域，从一个函数中返回一个子函数，将该函数的作用域暴露给外部，如：

```js
var a = function(){
    var b = function(){
        var c="hahaha";
        return c;
    };
    return b;
}
console.log(a()()); // 控制台中会打印出c的值
```

而比较实用的作用是一个重用函数使用不同参数时产生的不同后果，比如：

```js
function makeSizer(size) {
  return function() {
    document.body.style.fontSize = size + 'px';
  };
}

var size12 = makeSizer(12);
var size14 = makeSizer(14);
var size16 = makeSizer(16);

document.getElementById('size-12').onclick = size12;
document.getElementById('size-14').onclick = size14;
document.getElementById('size-16').onclick = size16;
```

HTML和CSS代码如下：

```html
<a href="#" id="size-12">12</a>
<a href="#" id="size-14">14</a>
<a href="#" id="size-16">16</a>
```

```css
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

运行以上的js代码之后点击不同的会产生不同的结果。

再比如循环输出一个局部变量：

```js
var a = function(){
    for(var i = 0;i < 5;++i){
        setTimeout(()=>{
            console.log(i);
        }, 2000);
    }    
}
a(); // 此处会输出五个5
var b = function(){
    for(var i = 0;i < 5;++i){
        (function(i){setTimeout(()=>{
            console.log(i);
        }, 2000);})(i);
    }    
}
b(); // 此处会输出0 1 2 3 4
```

这里使用闭包传入的五个i是独立的五个Number，五个不同的引用。

但是使用闭包也有一个很需要注意的问题，就是内存的使用。因为闭包的实现是基于js的垃圾回收机制的。

js有自己的自动回收机制，利用的是**引用计数(Reference counting)**的方式。所谓**引用计数**，指的是当创建一个对象的实例并在堆上申请内存时，对象的引用计数就为1，在其他对象中需要持有这个对象时，就需要把该对象的引用计数加1，需要释放一个对象时，就将该对象的引用计数减1，直至对象的引用计数为0，对象的内存会被立刻释放。

以上面的函数b为例，i作为参数传入闭包中。我们都知道js的函数参数是值传递的，从原理上讲就是在堆上创建一个新的变量，复制了参数原引用的值，这样一来函数内部就拥有了一个新的变量环境。而在`setTimeout()`的回调函数中，`console.log(i)`保留了对参数i的引用，因此在函数执行结束后不会被回收（一般的**自调用匿名函数**在运行完后就会被回收），而是在`setTimeout()`的回调函数运行之后才会回收。

闭包的常见应用主要为**创建私有空间**。比如我们需要在一个对象中创建私有变量，可以这么写：

```js
var A = function() {
    var private = {
        name: "leiysky",
        age: 20,
    };
    this.getPrivate = () => {
        return private;
    }
}
var b = new A();
console.log(b.getPrivate().name); // 控制台输出leiysky
```

这样以来private中的值不能直接被外部访问，但是可以通过一个成员函数获取。

### 原型链

js本身没有提供传统面向对象的机制，但是它提供了一种很神奇的机制，可以让我们实现继承，那就是**原型(prototype)**。

js中每个函数都会有一个`prototype`属性，这个属性中的内容是按照一定的规则自动获取的，默认会有一个`constructor`的属性，其他属性则是继承自**Obeject.constructor.prototype**上的。而这个`constructor`是一个指向`prototype`属性所在函数的引用，通过`constructor`可以为原型对象添加别的属性。

> 没有官方的方法用于直接访问一个对象的原型对象——原型链中的“连接”被定义在一个内部属性中，在 JavaScript 语言标准中用 `[[prototype]]` 表示（参见 [ECMAScript](https://developer.mozilla.org/en-US/docs/Glossary/ECMAScript)）。然而，大多数现代浏览器还是提供了一个名为 `__proto__` （前后各有2个下划线）的属性，其包含了对象的原型。ES5中新增了`Object.getPrototypeOf()`方法，可以返回`[[prototype]]`的值。

通过对象实例可以访问原型中的属性（但是不能修改），原型又可以访问原型的原型的属性，这样一来就形成了一条原型链。

使用原型创建对象很简单，比如:

```js
function a(){
    a.prototype.name = "hello";
}
var b = new a();
console.log(b.name); // 控制台输出hello
```

使用原型链来实现继承有一种很简单的模式：

```js
function father(){
    this.name = "father";
}
father.prototype.getName = function(){
    return this.name;
}
function son(){
    this.name = "son";
}
son.prototype = new father();
var jack = new son();
jack.name = "jack";
console.log(jack.getName()); // 控制台输出jack
```

还有一种继承的思路就是在子类的构造函数中调用父类的构造函数，可以通过在子类的`constructor`中写`father.call(this)`来实现。

不过prototype继承有一个很大的缺点就是链上的对象会共享引用类型属性的值，这点必须注意。

## ES6相关

ES6中定义了许多种新的语法和机制，为开发带来的极大的便利。但是其中有一点蛋疼的就是许多的语法本质上只是个语法糖，利用原本的机制包装一下就变成了一个新东西。

### class

ES6中提供了一般面向对象语言中很常见的一个概念，写法如下：

```js
class A {
    constructor(){
        this.name = "A";
    }
    
    getName(){
        return this.name;
    }
    
    static addOne(a){
        return a + 1;
    }
}

class B entends A{
    constructor() {
        super();
        this.name = "B";
    }
}
var a = new A();
var b = new B();
a.getName(); // 返回A
b.getName(); // 返回B
a.addOne(1); // undefined
A.addOne(1); // 返回2
```

其中可以分为几部分来讲：

1. `constructor`是class的构造函数，也就是A本身
2. `getName`等成员方法直接定义
3. `static`可以定义A本身的静态方法，实例不可调用，只能通过A调用
4. `extends`可以进行继承

实际上class就是对于直接在prototype上写属性的一个语法糖，但是ES6定义了一系列规范来限制这些行为，总体来说还是比以前好用多了。

不过在面试过程中遇到了一个很有意思的事情，一位同学在写class相关的代码时用了以下写法：

```js
class A{
    getName = ()=>{
        return this.name;
    }
}
class B extends A{}
```

这里的getName实际上会被定义成一个静态的属性，如果使用的是`function()`来定义匿名函数将会出现问题，因为this的环境会改变（我原本以为会报错，不过实际上并没有）。但是这里他使用了一个箭头函数，绑定的是上一层的this，巧妙的避免了这点，让我感到十分惊讶。

### Promise + Generator +Cowrap = Async + Await

ES6中的Promise为异步的写法提供了一种相对较舒服的方案，不用像从前一样写成callback hell。再搭配上generator和cowrap可以很方便的写成一个链式调用。

首先讲讲Promise：

> ```js
> new Promise( function(resolve, reject) {...} /* executor */  );
> ```
>
> Promise对象有一个参数，就是excutor。
>
> executor是带有 `resolve` 和 `reject` 两个参数的函数 。Promise构造函数执行时立即调用`executor` 函数， `resolve` 和 `reject` 两个函数作为参数传递给`executor`（executor 函数在Promise构造函数返回新建对象前被调用）。`resolve` 和 `reject` 函数被调用时，分别将promise的状态改为*fulfilled（*完成）或rejected（失败）。executor 内部通常会执行一些异步操作，一旦完成，可以调用resolve函数来将promise状态改成*fulfilled*，或者在发生错误时将它的状态改为rejected。
>
> 如果在executor函数中抛出一个错误，那么该promise 状态为rejected。executor函数的返回值被忽略。
>
> `Promise` 对象是一个代理对象（代理一个值），被代理的值在Promise对象创建时可能是未知的。它允许你为异步操作的成功和失败分别绑定相应的处理方法（handlers）。 这让异步方法可以像同步方法那样返回值，但并不是立即返回最终执行结果，而是一个能代表未来出现的结果的promise对象
>
> 一个 `Promise`有以下几种状态:
>
> - *pending*: 初始状态，既不是成功，也不是失败状态。
> - *fulfilled*: 意味着操作成功完成。
> - *rejected*: 意味着操作失败。
>
> pending 状态的 Promise 对象可能触发fulfilled 状态并传递一个值给相应的状态处理方法，也可能触发失败状态（rejected）并传递失败信息。当其中任一种情况出现时，Promise 对象的 `then` 方法绑定的处理方法（handlers ）就会被调用（then方法包含两个参数：onfulfilled 和 onrejected，它们都是 Function 类型。当Promise状态为*fulfilled*时，调用 then 的 onfulfilled 方法，当Promise状态为*rejected*时，调用 then 的 onrejected 方法， 所以在异步操作的完成和绑定处理方法之间不存在竞争）。
>
> 因为 `Promise.prototype.then` 和  `Promise.prototype.catch` 方法返回promise 对象， 所以它们可以被链式调用。
>
> ![image-20180513140606397](./image-20180513140606397.png)

要用Promise实现一个简单的异步调用写法如下：

```js
var a = ()=>{
    return new Promise((resolve, reject)=>{
    	setTimeout(()=>{
        	console.log("haha");
        	resolve();
    	}, 2000);
	}).then(()=>{
    console.log("hello");
	});
};
a(); // 两秒后输出haha，之后输出hello
```

可是这样的链式写法还是太长了，所以我们又使用了generator来进行简化。

再介绍下genertor：

>Generator是一个可迭代的对象，由一个generator function返回。
>
>```js
>function* gen() { 
>  yield 1;
>  yield 2;
>  yield 3;
>}
>
>let g = gen(); 
>// "Generator { }"
>```
>
>Generator的方法：
>
>- [`Generator.prototype.next()`](https://developer.mozilla.org/zh-CN/docs/Web/JavaScript/Reference/Global_Objects/Generator/next)
>
>  返回一个由 [`yield`](https://developer.mozilla.org/zh-CN/docs/Web/JavaScript/Reference/Operators/yield)表达式生成的值。
>
>- [`Generator.prototype.return()`](https://developer.mozilla.org/zh-CN/docs/Web/JavaScript/Reference/Global_Objects/Generator/return)
>
>  返回给定的值并结束生成器。
>
>- [`Generator.prototype.throw()`](https://developer.mozilla.org/zh-CN/docs/Web/JavaScript/Reference/Global_Objects/Generator/throw)
>
>  向生成器抛出一个错误。

可以想像在generator中执行异步，由promise的then()方法来调用next就可以实现以同步的方式自动执行代码。

此处可以使用一些cowrap的模块来实现对generator的包装。

在ES7中新出现的**async/await**是一个很好的解决方案，它能用同步的写法进行异步操作（虽然也是generator的语法糖）。尽管现在在浏览器中的表现不佳，但是nodejs的新版本已经完美支持，非常好用。

具体的写法很简单：

```js
async function foo(){
    await setTimeout(()=>{
        console.log("hahaha");
    }, 2000);
}
foo(); // 两秒后输出hahaha
```

这里的foo()会返回一个Promise对象，从而进行异步调用。