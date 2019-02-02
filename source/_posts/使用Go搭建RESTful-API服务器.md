---
title: 使用Go搭建RESTful API服务器
date: 2018-12-07 13:21:16
tags: Golang
---
## 什么是RESTful？

**RESTful**全名是**可表述性状态转移(Representational State Transfer)**，是一套HTTP API的设计风格。

看名字很抽象，所以这里我就结合理论大致的讲一下自己的理解。

**REST**的核心是**资源**的访问，以及客户端/服务端的**C/S**模式。

在**REST**中，API通过URI的形式来访问。与此同时，**REST**也为**HTTP动词**赋予了更加完善的语义。

最常用的动词有`GET`, `POST`, `PUT`, `DELETE`:
* `GET`用于访问已有的资源
* `POST`用于创建资源，并且该资源的标识由服务端维护
* `PUT`用于更新资源，标识由客户端维护
* `DELETE`用于删除一个资源

通过**HTTP动词**，可以实现**REST**的可表述性部分，而状态转移则是通过API的分层来完成的。

**REST**中状态是由客户端维护的，服务端本身无状态。客户端如果要获取资源的情况，需要逐层访问API来实现。

比如说对于某个网站的某个用户的某个信息，可以设计这样的一个**REST API**：
* `/users/:user_id/profiles/:profile_id`（`:xx_id`表示占位符）

这样一来**REST**的概念就清晰了许多。

**REST**的优点是对于资源的访问可视化，更加清晰。但是他也有缺点，就是不太适合一些命令式的**API**，对于这类**API**我们可能要引入**CQRS(命令查询职责分离，Command Query Responsibility Segregation)**的架构，使用一些RPC协议来完成命令式API的调用。

## 开工前的调研

在开始编写服务端之前，需要先进行调研确定技术栈，方便之后的架构设计。

Golang的优势在于有一套较为完善的标准库，非常适合微框架的发展。在参考了几套常用Golang HTTP Server的框架之后，我决定自己写一个中间件的包装组件。

数据库方面，根据要求需要使用BoltDB，在语言库的方面没有更多选择。

确定了这些之后就可以开始编写。

## 架构设计

设计初期，我没有多想便选择了Web领域最成熟，也十分经典的架构`MVC`。

对于中间件的设计，则是使用`AOP`的理念。

在`MVC`架构中，有三个重要的成分：
* `Model`，模型层，主要负责处理数据的序列化和反序列化，这层一般不会涉及业务逻辑。由于设计的是**REST**服务器，因此可以抽象出一套类似`DAO`的`Model API`，`GetByID`, `GetAll`, `Update`, `Create`, `Delete`。
* `View`，视觉层。对于**REST**服务器来说，所谓`View`其实就是呈现的`JSON`数据。
* `Controller`，控制器层。主要处理路由的逻辑，比如参数的解析，数据的组装等。

一般开发时不会完全按照这个范式，我选择在`Model`和`Controller`中间加入一个`Service`层。这一层主要做的事情是访问`Model`取出数据，对其进行一定的包装，包含一些业务逻辑。这样的好处在于可以简化`Controller`，也可以更方便的复用一些逻辑。

这样一来整个项目的文件结构就清晰了：
```
src/
  controllers/   用于放controller文件
    user.go
    ...
  models/        用于放model文件
    user.go
    ...
  services/      用于放service
    user.go
    ...
  utils/         用于放一些常用工具
    utils.go
    ...
  main.go        项目入口
  README         项目说明
  ...
```

## 项目编写

有了一个好的架构之后项目的编写就容易多了，只需要照着框架填鸭即可。

主要讲一下我自己实现的`MiddlewareComposer`。该工具可以将一系列的中间件包装成一个`http.HandleFunc`，调用时是一个洋葱的结构（参考`Koa`中间件的模式）

![onion](images/onion.png)

这样的好处在于可以形成一个整齐的调用栈，处理log，异常等常见服务时非常方便。写起来逻辑也很清晰。

实现起来也很简单，利用函数式编程的闭包特性，我们可以构造出一个自执行的函数。具体请看[这里](https://github.com/go-cloud-service/go-cloud-service/blob/master/utils/middleware.go)

原本还想实现一个路由的中间件，这样嵌套挂载写起来会很方便，但是因为时间关系，最后还是搭配了`Gorilla`的`mux`。

对于`BoltDB`，我为其包装了一组`k-v DB`常用的API，包括`GET`，`SET`，`SCAN`等操作。

## 总结

Golang在工程开发上真的非常省心省力。