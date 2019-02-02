---
title: 浅谈gRPC
date: 2018-12-29 12:58:53
tags: golang
---

## 什么是gRPC？
[gRPC](https://grpc.io) 是谷歌推出的一款开源RPC框架，主要应用于微服务领域。

它的特点是基于HTTP/2，支持跨语言（目前有C, Java和golang版本，其中C版本更是有C, C++, Node.js, Python, Ruby, Obj-C, PHP以及C#的上层实现），支持流式通信（节约性能）。

在gRPC中，运行着服务的分布式节点需要开启一个gRPC服务器。客户端可以通过gRPC客户端来像调用本地的函数一样直接调用远程服务（如下图所示）。

![gRPC应用结构示意图](/images/gRPC.png)

gRPC默认使用的通信数据结构是谷歌的`Protocol Buffers`，简称`protobuf`。`protobuf`的严格定义是一套 **结构数据化机制** 这套通信协议最大的特点就是跨语言，可自定义schema，以及体积小，在频繁RPC的场景下与`Thrift`一样十分受到青睐。（具体内容可以参考[protobuf官网](https://developers.google.com/protocol-buffers/)）

## 简单使用
在这里将举一些在golang中使用gRPC的例子。

### 安装

首先我们要安装`protobuf`。

安装golang版本之前需要先安装c++版本的，源码包可以到[这里](https://github.com/protocolbuffers/protobuf/releases)下载。

运行以下指令进行安装：
```shell
$ cd path/to/protobuf
$ ./configure
$ sudo make
$ make install
```
等漫长的等待之后安装就完成了，可以运行`protoc`指令测试一下。

之后我们安装golang版本的：
```shell
$ go get -u github.com/golang/protobuf/protoc-gen-go
```
运行以上指令即可安装。

### 试用
这里我们使用官方提供的例子，首先获取官方的相关源码：
```shell
$ export PATH=$PATH:$GOPATH/bin # 确保GOBIN在PATH中
$ go get -u google.golang.org/grpc/examples/helloworld/greeter_client
$ go get -u google.golang.org/grpc/examples/helloworld/greeter_server
```

接下来就可以试试了：
```shell
$ greeter_server &
$ greeter_client
```
我们可以看到终端中打印出了一些信息。

### 简单分析example代码
样例目录的结构为：
```
├── greeter_client
│   └── main.go
├── greeter_server
│   └── main.go
├── helloworld
│   ├── helloworld.pb.go
│   └── helloworld.proto
└── mock_helloworld
    ├── hw_mock.go
    └── hw_mock_test.go
```

首先看看`greeter_server/main.go`
```golang
/*
 *
 * Copyright 2015 gRPC authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

//go:generate protoc -I ../helloworld --go_out=plugins=grpc:../helloworld ../helloworld/helloworld.proto

package main

import (
	"context"
	"log"
	"net"

	"google.golang.org/grpc"
	pb "google.golang.org/grpc/examples/helloworld/helloworld"
	"google.golang.org/grpc/reflection"
)

const (
	port = ":50051"
)

// server is used to implement helloworld.GreeterServer.
type server struct{}

// SayHello implements helloworld.GreeterServer
func (s *server) SayHello(ctx context.Context, in *pb.HelloRequest) (*pb.HelloReply, error) {
	log.Printf("Received: %v", in.Name)
	return &pb.HelloReply{Message: "Hello " + in.Name}, nil
}

func main() {
	lis, err := net.Listen("tcp", port)
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}
	s := grpc.NewServer()
	pb.RegisterGreeterServer(s, &server{})
	// Register reflection service on gRPC server.
	reflection.Register(s)
	if err := s.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}
```

在这个文件里主要做了几件事：

* 声明并实现了`gRPC`的服务`SayHello`
* 监听端口的`TCP socket`
* 使用`grpc.NewServer()`开启一个`gRPC` server
* 使用`pb.RegisterGreeterServer()`注册一个`protobuf`服务
* 使用`gRPC`的`reflection.Register`注册一个`gRPC`服务

我们再来看看客户端：
```go
/*
 *
 * Copyright 2015 gRPC authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 */

package main

import (
	"context"
	"log"
	"os"
	"time"

	"google.golang.org/grpc"
	pb "google.golang.org/grpc/examples/helloworld/helloworld"
)

const (
	address     = "localhost:50051"
	defaultName = "world"
)

func main() {
	// Set up a connection to the server.
	conn, err := grpc.Dial(address, grpc.WithInsecure())
	if err != nil {
		log.Fatalf("did not connect: %v", err)
	}
	defer conn.Close()
	c := pb.NewGreeterClient(conn)

	// Contact the server and print out its response.
	name := defaultName
	if len(os.Args) > 1 {
		name = os.Args[1]
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	r, err := c.SayHello(ctx, &pb.HelloRequest{Name: name})
	if err != nil {
		log.Fatalf("could not greet: %v", err)
	}
	log.Printf("Greeting: %s", r.Message)
}
```

`Greeter_client`主要做了几件事：
* 使用`grpc.Dial()`连接一个`gRPC`服务（这里使用的是`Insecure`非安全模式）
* 使用`pb.NewGreeterClient()`创建一个`protobuf`客户端
* 调用`protobuf`客户端的`SayHello`服务

一个简单的gRPC应用就是这样的结构。

## gRPC的一些特性

在RPC领域有许多成熟的框架，比如大名鼎鼎的`Thrift`，各大互联网公司均有使用。

而近两年新出来的gRPC却能在这片领域中开拓出一片自己的天地，可见其必然有制胜法宝，接下来就让我们谈谈gRPC的几大特性。

### 跨语言能力

大部分的RPC框架都是基于同一语言的，因为这样可以保证通信时数据结构不会混乱，不会出现不同语言之间数据结构不兼容的情况。

但是现在早已不是那个`Java C++ Python`一把梭的时代了。某些公司因为业务需求和历史遗留问题仍在沿用单一技术栈（没错，我说的就是某鹅厂），但是新兴的公司基本都是多技术栈混合。在这个百花齐放的年代，各语言都有各自的优点，都有业务上的需求。

拿字节跳动为例，该公司是目前国内的`Golang`大厂。从2015年开始，公司的许多业务都使用`Golang`来编写，因为`Golang`有着运行速度快，编写速度快，维护成本低，跨平台能力强，标准库发达的优点，非常适合在大型工程项目中使用。但同时，公司也有许多`C++`，`Python`的项目，再加上高度微服务化的架构，对于RPC的需求可见一斑。

`gRPC`就有非常强大的跨语言能力。得益于`protobuf`的跨语言序列化，`gRPC`能够在不同的语言间尽可能多的提供数据结构，而不是单一的字符串类型。这大大的提升了开发效率，以及服务的可用性。

### 流通信

`gRPC`是通过`HTTP/2`实现的，他借助于底层的`HTTP/2`特性，实现了流通信。可以支持单向流，以及服务端、客户端双向流通信。

流通信的好处有很多，最直观的就是能节约性能。

`gRPC`使用`http frame`的方式，对`http`请求进行切分，从而达到和`TCP`类似的效果。

`gRPC`的请求和响应结构为：
* Request → Request-Headers *Length-Prefixed-Message EOS
* Response → (Response-Headers *Length-Prefixed-Message Trailers) / Trailers-Only

以下是`gRPC`HTTP frame的样例：

Request:
```
HEADERS (flags = END_HEADERS)
:method = POST
:scheme = http
:path = /google.pubsub.v2.PublisherService/CreateTopic
:authority = pubsub.googleapis.com
grpc-timeout = 1S
content-type = application/grpc+proto
grpc-encoding = gzip
authorization = Bearer y235.wef315yfh138vh31hv93hv8h3v

DATA (flags = END_STREAM)
<Length-Prefixed Message>
```

Response:
```
HEADERS (flags = END_HEADERS)
:status = 200
grpc-encoding = gzip
content-type = application/grpc+proto

DATA
<Length-Prefixed Message>

HEADERS (flags = END_STREAM, END_HEADERS)
grpc-status = 0 # OK
trace-proto-bin = jher831yy13JHy3hc
```

### 安全通信

因为`gRPC`是基于`HTTP/2`实现的，因此可以支持多种授权机制，比如`SSL/TLS`, `OAuth 2.0`, 或者谷歌校验等方式。

使用`SSL/TLS`时，客户端和服务端之间交换的所有数据均会被加密，并且为客户端提供了可选的凭证服务，比如证书之类的。

## gRPC未来发展

`gRPC`提供了服务提供和服务调用的方式，但是没有提供服务发现机制，对于分布式部署的服务并不那么友好。因此在使用`gRPC`时，我们还需定制一些服务发现的服务，比如`Consul`。

目前服务发现主要分为两种，一种是**客户端发现**，一种是**服务端发现**。

![client_discover](/images/client_discover.png)

**客户端发现**就是由调用方来从某个服务注册中心中寻找一个可用的服务，并进行接入。这样的好处在于直观，但是缺点是对于客户端来说耦合度较高，可能需要依赖大量SDK。

![server_discover](/images/server_discover.png)

**服务端发现**是现在比较推崇的一种方式。他在服务注册中心之前加了一层负载均衡器（反向代理）。客户端无需知道服务注册的查找细节，只需直接请求，由负载均衡器为其路由到最优的节点上。

## 总结

`gRPC`的前景非常好，希望能看到其大展身手。