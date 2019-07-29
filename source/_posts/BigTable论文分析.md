---
title: BigTable论文分析
date: 2019-05-08 08:10:51
tags:
---

# 前言
`BigTable`是谷歌在2004年时开发的`NoSQL`数据库，引领了新世纪`NoSQL`的潮流，也为传统数据库的`Scale-out`提供了思路，是十分划时代的产品。

由于`BigTable`本身是闭源的（开源版本数据库产品为`HBase`，存储引擎部分为`LevelDB`）,因此这篇文章主要分析的是`Google`在2006年发表的`BigTable`论文（主要作者为`Jeff Dean`等大牛）。

虽然现在已经是9102年了，很多技术已经有了翻天覆地的变化，但是这篇论文中的很多思想仍然十分有借鉴意义（虽然大部分内容算是广告）。

# 目录
`BigTable`是十分精简的一篇论文，只有14页。

其主要分为10个部分，分别是：
* `1 Introduction`: 简介
* `2 Data Model`: 主要介绍`BigTable`的数据存储模型
* `3 API`: 接口设计
* `4 Building Blocks`: 相关的infra组件
* `5 Implementation`: 具体实现
* `6 Refinements`: 系统优化
* `7 Performance Evaluation`: 性能评估
* `8 Real Applications`: 实际场景下的应用
* `9 Lessons`: 一些心得
* `10 Related Workd`: 相关工作

接下来本文将对各个部分进行尽可能细致的分析。

# Introduction
> Over the last two and a half years we have designed, implemented, and deployed a distributed storage system for managing structured data at Google called Bigtable. Bigtable is designed to reliably scale to petabytes of data and thousands of machines. Bigtable has achieved several goals: wide applicability, scalability, high performance, and high availability. 
> Bigtable is used by more than sixty Google products and projects, including Google Analytics, Google Finance, Orkut, Personalized Search, Writely, and Google Earth. These products use Bigtable for a variety of demanding workloads, which range from throughput-oriented batch-processing jobs to latency-sensitive serving of data to end users. The Bigtable clusters used by these products span a wide range of configurations, from a handful to thousands of servers, and store up to several hundred terabytes of data.

`Introduction`的开头首先介绍了一下`BigTable`诞生的背景，以及它的一些特点。

我们可以看到一些关键词：
* `distributed storage system`: `BigTable`与传统数据库很大的一个不同是——它是一个真正意义上的分布式存储。可以做到完全Sharding，读写都在不同的节点上完成。不像传统的主从复制模式，只能在主节点进行写操作。
* `wide applicability, scalability, high performance, and high availability`: 我们知道大家在推销自己的产品时总会有一些夸大的成分，G家也不例外。这里提到`BigTable`实现了高通用性，扩展性，高性能，高可用。后两点存疑，高通用性主要得益于`key-value`的模型，但也只是通用，并不一定好用。因此我们重点关注的它的扩展性。

这一部分我们可以看到`BigTable`尝试去解决的一些问题。

首先我们知道，传统的`RDBMS`关系型数据库非常依赖单机的性能。

在计算机领域`Scale-out`可以分成两个流派：
* 以IBM为首的大型机流派，通过堆砌单机的性能来支撑更高负载的系统，也就是垂直扩展
* 以Google等互联网公司为首的分布式集群流派，通过堆砌机器数量来提高性能，也就是水平扩展

老牌的数据库，如`Oracle`, `MySQL`, 都是设计成的单机模式，当单机的性能达到瓶颈时就无法扩展了。

然而在互联网的场景下，会有很多海量数据处理的需求。

谷歌作为互联网企业的领头羊，很早就摸到了传统数据库的天花板，因此他们尝试着设计了一套分布式存储的解决方案，也就是`BigTable`。

在解决`Scale-out`问题的同时，谷歌也在思考另一个问题，就是能否将数据的存储模型做的更加的通用化。

为此，他们结合`key-value`的映射模型，设计了`row-column-data`的映射模型。

虽然后来的很多场景证明这种方式存在一些缺陷（事务封装，查询优化等），谷歌也在2010年后研发了新的`Spanner`数据库，但这仍不失为一次伟大的尝试。

# Data Model
这一部分主要是介绍了`BigTable`的一个数据存储模型。

`BigTable`使用的是

`(row:string, column:string, time:int64) → string`

这样的一种映射。

通过`row`, `column`和时间戳对应一个具体的value。

这里有一张图：
![data model](images/bigtable-datamodel.png)

我们可以尝试用`RDBMS`的`Table`中的一些概念来描述这个模型。

在数据库中的每个`Table`会有一个`Schema`，也就是表头。这个表头描述了每条记录的`fields`。

每条记录都会有一个`Primary Key`，用于帮助数据库定位到唯一的一条记录。

在`BigTable`中每一个`row`对应的表里的一条记录，这个`row`扮演的就是一个`Primary Key`的角色。

`column`则是对应的记录的`fields`。

两者的`Table`概念是比较相似的，但是不同的是，`BigTable`直接将`TimeStamp`作为`key`的一部分（虽然`RDBMS`也可以使用`created_time`之类的做联合主键，但这是`optional`的），而且`BigTable`的`column`有`column families`的概念，这个之后会提到。

这就表示`BigTable`会更加强调一个时间戳的区别，我们可以将其定义为`版本`，即相同`(row, column)`的不同版本。

论文中提供了一个使用场景的例子：Google的网页爬虫存储。对于一个`Page`，可以把`URL`作为`row`，将`Page`的具体内容存储在`content`这个`column`下。同时，我们可以将爬取的时间作为`timestamp`，这样可以记录一个网页在不同时间下的内容。

现在`BigTable`的`Data Model`的形态已经描绘出来了，接下来我们来看看一些细节。

## Rows

论文中`row`相关的point如下：
* `BigTable`的`row key`可以是任意的字符串
* 对于单个`row key`的每个读写请求都是原子的
* `BigTable`会按照字典序维护`row key`
* `row key`有动态的分区，每个`row range`被称作`tablet`，是分布式存储的基本单元（`entry`和`tablet`是`1toN`关系）

使用任意的字符串作为`row key`的好处是用户可以自定义`row key`的内容，这样表达能力会更强。

由于`BigTable`是按照`row key`的字典序来编排记录的，用户可以利用这点来做一些局部查找的优化。比如说，需要对某个域名下的所有网站进行分析，可以使用`URL`作为`row key`。这样像`www.baidu.com/a.html`，`www.baidu.com/b.html`很有可能在同一个`tablet`上，因为有共同的`prefix`。如此一来查询的速度就可以得到一定程度上的优化。

但是这样缺点也很明显，那就是随着`key`长度的增加，比较的复杂度也会线性增长，所以需要用户自己来平衡。

`BigTable`本身没有提供事务的功能，但是能保证原子性，因此在业务层实现事务也不会特别困难。

## Coloumn Families
`Column Families`一般被翻译成`列族`，这个概念使用过`HBase`的同学会比较熟悉。

简单来讲，每个`Column Families`下会有许多的`Column`。用户需要通过`family:qualifier`的方式获取到具体到具体的`Column`。

## Timestamps

`BigTable`主要的应用场景还是Google的爬虫业务。

我们知道爬虫本质上是提供了一个网页快照，那么为了方便管理，一般会保留多个版本的快照。

`BigTable`使用了64位整数来表示一个微秒级的时间戳。因为时间戳具有单调递增的特性，可以用来表示一个版本关系。

`BigTable`在此之上还提供了一些版本GC的功能，比如可以配置为只保留最后N个版本的记录。

# API

`BigTable`作为一个`NoSQL`数据库，其API也十分简洁。

这里直接以论文中的C++代码为例：
```cpp
// Open the table
Table *T = OpenOrDie("/bigtable/web/webtable");
// Write a new anchor and delete an old anchor 
RowMutation r1(T, "com.cnn.www"); 
r1.Set("anchor:www.c-span.org", "CNN"); 
r1.Delete("anchor:www.abc.com");
Operation op;
Apply(&op, &r1);

Scanner scanner(T);
ScanStream *stream;
stream = scanner.FetchColumnFamily("anchor"); stream->SetReturnAllVersions(); scanner.Lookup("com.cnn.www");
for (; !stream->Done(); stream->Next()) {
  printf("%s %s %lld %s\n", scanner.RowName(),
       stream->ColumnName(),
       stream->MicroTimestamp(),
       stream->Value());
}
```

# Building blocks

这一部分主要描述了`BigTable`的外部依赖。

`BigTable`是一个运行在云上的分布式数据库，其使用大名鼎鼎的`GFS`作为文件系统，用于存储`data`和`log`文件。

这里先提一下，`BigTable`使用的是`LSM-tree`的数据结构，其数据文件主要分为`SSTable`和`LOG`文件。`SSTable`即为存储具体data的数据文件。

`BigTable`同时还依赖了`Chubby`，一个使用`Paxos`算法的分布式锁中间件，用于保证集群的一致性。

# Implementation
终于到了论文的核心部分，这一部分描述了`BigTable`的具体实现。

`BigTable`主要有三个组件：
* Client用于连接`BigTable`的库，类似SDK
* 一个Master节点
* 许多个Tablet节点

这里需要注意的是Client无需通过Master节点来知道自己该访问哪个Tablet节点。

`BigTable`的Master节点主要负责的是为Tablet节点分配Tablet，检测Tablet节点的状态（节点增减，负载等），回收GFS上的资源，维护Tablet的meta信息（列族创建等）。

我们可以发现这其中的Master承担的更像是一个Monitor的角色，但也正是因为Client不会直接依赖Master，系统的可用性会有些许提升。

接下来将从四部分来描述`BigTable`的具体实现：
* `Tablet Location`: Tablet节点的定位
* `Tablet Assignment`: Tablet的分配
* `Tablet Serving`: Tablet处理请求的过程
* `Comapctions`: LSM-tree的Compaction

## Tablet Location

`BigTable`采用了一个3级的B+树来存储`Tablet`的位置信息，如下图：
![Tablet location hierarchy](images/tablet-meta.png)

第一级是一个存储在`Chubby`的文件，其中包含了`root tablet`的位置信息。

而`root tablet`中有一个特殊的`METADATA`表（实际上就是**第一个**表），其中存储了所有`tablet`的位置信息。

`root tablet`节点不会发生分裂，因此`B+`树的级数不会超过3级。

`METADATA`中每一个`row`会存储`tablet`的位置信息。

其中`row key`是一个由`tablet`的表和末尾行编码出的字符串，可以定位到唯一的`tablet`。

`BigTable`的实现中可以通过`root tablet`定位到$2^{34}$个`tablet`。

前面提到过，`Client`访问`Tablet Server`时并不会经过`Master`。`Client`会将`tablet location`缓存下来，查找时直接通过缓存来进行查找。

当`Client`找不到目标`tablet`的位置信息时，或者缓存的数据不正确时，它会递归地通过`Chubby file`这个入口去进行查找，最后再将结果缓存。

比如某个`Client`的缓存信息为空，那当它尝试去查找某个`tablet`的信息的过程如下：
* 查找本地缓存，发现为空
* 从Chubby查找`root tablet`的位置信息
* 从`root tablet`查找`METADATA`
* 将目标`tablet`的位置信息缓存

有缓存的情况下，`Client`无需访问GFS来获取`tablet`的位置信息，所以查询的开销会小很多。

## Tablet Assignment

之前有提到过，`Tablet Server`与`Tablet`是一对多的关系，因此会存在着`Tablet`的分配问题。

在`BigTable`中，`Master`节点会维护存活的`Tablet Server`的集合，并且维护`Tablet`的分配情况（包括未被分配的`Tablet`）。

当存在一个未被分配的`Tablet`，并且存在一个`Tablet Server`有足够的空间来容纳该`Tablet`时，`Master`节点会向目标`Tablet Server`发送一个请求让其接收`Tablet`，这是最简单的一个分配过程。

`Tablet`的分配需要保持强一致，因此`BigTable`使用`Chubby`来维护与`Tablet Server`的联系。

当一个`Tablet Server`启动时，它会获得一个全局的互斥锁（这个锁本质上是一个`Chubby`的全局唯一文件，会保存在一个特定的目录下）。

`Master`通过监视这个目录来发现`Tablet Server`。

当一个`Tablet Server`失去它的锁时，就会停止服务它的`Tablets`。`Chubby`提供了一种高效的机制，可以让一个`Tablet Server`判断自己是否还持有锁。

`Tablet Server`会持续的更新自己的锁的状态，只要其对应的文件还在。如果文件已经被删除了，那么这个`Tablet Server`就无法再提供服务，它会进行自裁。这里通过文件存在与否来决定`Tablet Server`的死活主要是为了将控制权交给`Master`，具体的管理过程后面会提到。

当一个`Tablet Server`被集群删除时，它就会尝试释放自己的锁以便`Master`重新分配。

`Master`节点负责检测一个`Tablet Server`是否停止服务它的`Tablets`，如果是则为那些`Tablets`重新分配`Tablet Server`。

`Master`的检测有如下要点：
* `Master`会周期性轮询`Tablet Server`的锁的状态——这里是直接向`Tablet Server`询问状态信息，因为这样的话，在因为网络等原因无法访问到`Tablet Server`的情况下，`Master`可以认为`Tablet Server`已经失效。
* 当`Master`无法访问到`Tablet Server`或者`Tablet Server`汇报自己的锁已失效时，`Master`就会尝试去获取`Tablet Server`的锁。如果能获取到锁说明`Chubby`服务是存活的，对应的`Tablet Server`则存在问题。因此`Master`可以通过删除掉该文件来防止`Tablet Server`重新提供服务。
* 一个`Tablet Server`的文件被删除后，`Master`可以将其被分配的`Tablets`重新分配。
* `Master`在与`Chubby`的`session`断开后会进行自裁，以此保障系统的健壮性。`Master`的失效并不会影响系统的运作。

`Master`在被集群管理系统启动的时候需要重建`Tablets`分配的情况，因此`Master`的启动将遵循以下步骤：
1. 从`Chubby`获取一个全局唯一的`master`锁，防止并发启动`Master`
2. 扫描`Tablet Server`的目录，获取存活的`Tablet Server`的信息
3. 与所有的`Tablet Server`通信以确定`Tablets`的分配情况
4. 扫描`METADATA`文件，获取所有`Tablets`的情况

这样一来就可以重建已被分配和未被分配的`Tablets`的集合。

但是这种设计会造成一个问题，就是第4步必须在`METADATA`被分配了之后才能进行。所以在进行重建步骤3时，如果没有发现`root Tablet Server`的分配情况，`Master`会将`root Tablet Server`加入未分配集合。这样可以确保`root`被分配。

`Tablet Server` 的集合只有在几种情况下才会生改变：

* 创建了新的 `Table` 或者某个 `Table` 被删除
* 两个 `Table` 合并
* 一个 `Table` 分裂成两个

`Master` 可以始终保持对 `Tablet` 的跟踪，因为前两种变更都是由 `Master` 主动发起的。

对于分裂的情况，`Master` 的处理方式比较特殊。它是由 `Tablet Server` 先在 `METADATA` 表里面记录上新的 `Tablet` 的信息，在提交之后再通知 `Master`。这种情况下如果因为某些原因分裂失败了，`Master` 在分配新的 `Tablet` 给 `Tablet Server` 时也会检测到其分裂的情况，从而作出修复。

## Tablet Serving
