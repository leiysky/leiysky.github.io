---
title: 使用Go编写CLI程序
date: 2018-10-06 19:22:50
tags: Golang
---

## 前言

使用Go语言已有一段时间了，我也渐渐爱上了这门某种意义上相当便利的语言。于是我决定用Go来写一些实用的小程序，一方面是加深自己对于Go的标准库的了解，另一方面则是回顾一些UNIX系统相关的知识。

所以这次我就将用Go实现一个分页打印的CLI程序**selpg**。

该程序相关的一些说明参考自[这里](https://www.ibm.com/developerworks/cn/linux/shell/clutil/index.html)，有兴趣的可以看看。

那么废话不多说，直接进入正题。

## UNIX与GNU风格的flag-style

对于一个命令行程序来说，flag是十分重要的，这直接决定了用户的使用体验。

实际上对于命令行程序的参数设计没有明确的要求，但大致可以分为**UNIX**, **GNU**和**BSD**三种流派。

**UNIX**的命令行规范在**POSIX**标准和**SUS(Single UNIX Specification)**中均有提及，在此就不做深入的研究，仅提一些众所周知约定俗成的部分。

在**UNIX**流派下，每个flag为一个`-`和一个字母组成(或者是多个，可以将多个短选项合并在一个`-`中，比如`ps -aux`)，一般是单词的缩写，可以是大写或者小写，如一般用于获取版本信息的`-v`或者`-V`；抑或是`--`后面跟上一个单词，比如获取版本信息的`--version`。一般我们称其为短选项和长选项，仅仅是写法不同。

在此之上，flag又分为可赋值和不可赋值两种，在实现上一般将不可赋值的flag设计为Boolean类型。可赋值的flag一般用于设置一些参数的具体数值，比如`tail -n 10`，也可以写作`tail -n=10`，这里的10就是`n`这个flag的值。不可赋值的一般用于设置一些配置选项，比如`rm -rf`中的`r`和`f`就分别代表**递归(recursive)**和**强制(force)**。

**GNU**风格的flag与**UNIX**的差别主要在于**GNU**风格的flag大多使用`--`加上单词或者词组(如`npm --no-optional`)，其他方面差别并不是很大。

虽然说了这么多，设计CLI程序的参数实际上只需要遵守一个原则：**易用**。

这个**易**在我看来主要有几点：

1. 参数名易懂，常用的参数如`-h --help`这类的尽可能遵从传统，尽量让用户在看到参数名的时候就能知道参数的作用
2. 简单明了的的参数说明，写清参数的用法，用途
3. 尽可能压缩常用参数的数量

## 写程序前的准备

在开始写程序前，我们还需要做几件事：

* 调研需要用到的utils，比如解析flag的package，找到合适的工具能大大节约我们的精力
* 设计程序的工作流程，这可以帮助我们理清程序的逻辑，写出流畅的代码
* 填饱肚子，这可以让我们精力更加充沛(刚吃过饭的同学可以跳过这一步)

### 调研阶段

要手动解析程序的flags可不是一件轻松的事情，其中涉及到大量的字符串处理和逻辑判断，一不小心写错了可能就要花上很久的时间来排查错误。

好在Go语言的标准库已经为我们提供了一个很棒的flag库。这个库能帮我们做的事大致如下：

* 解析flag并与变量绑定
* 自动生成帮助文档
* 为参数提供默认值

以下是一个使用flag包的示例：

```go
package main

import (
	"flag"
  "fmt"
)

func main() {
  a := flag.Int("a", 1, "parameter a") // 定义一个参数名为a的参数，默认值为1，后面为帮助说明
  b := flag.String("b", "", "parameter b")
  c := flag.Bool("c", false, "parameter c")
  var A int
  var B string
  var C bool
  flag.IntVar(&A, "A", 1, "parameter A") // 将参数A绑定到变量A，默认值为1，后面为帮助说明
  flag.StringVar(&B, "B", "", "parameter B")
  flag.BoolVar(&C, "C", false, "parameter C")
  flag.Parse() // 解析参数，注意该函数必须在参数定义之后调用
  args := flag.Args() // args为flag以外的参数列表
  fmt.Printf("parameter a is: %d\n", a)
  fmt.Printf("parameter b is: %s\n", b)
  fmt.Printf("parameter A is: %d\n", A)
  fmt.Printf("parameter B is: %s\n", B)
}
```

flag包的`Int`可返回对应参数值的指针，`IntVar`则可以将参数值直接与变量绑定，非常的方便。

在传入命令行参数时，形如`program -a 10 -b=hello`，均可将值解析。

另外，考虑到该程序涉及到输入输出的重定向，需要往buffer或是stream中读写数据。fmt的实现都是基于Stdio的(除了fmt.Fprint系列)，自然不适用。

好在Go语言的标准库还有另一个用于bufferio的包**bufio**。

在Go的io包中定义了一组**Reader**和**Writer**的interfaces，用于输入输出的读写。bufio则是提供了一组**Reader**和**Writer**的实现。

以下是一个样例：

```go
package main

import (
	"bufio"
  "os"
)

func main() {
  input := os.Stdin
  output := os.Stdout
  // input, _ := os.Open("some_in_file")
  // output, _ := os.Open("some_out_file)
  reader := bufio.NewReader(input) // 这里的参数类型实际上是io.Reader,input是File*类型，因为File实现了io.Reader，所以可以进行转换
  writer := bufio.NewWriter(output)
  buffer := reader.Read()
  writer.Write(buffer)
  writer.Flush() // 这里需要手动Flush才能显示到stdout
}
```

非常的简单易用，只要输入流实现了`io.Reader`的相关接口(输出流同理)，既可以用来创建Reader。bufio也提供了一套丰富的读写方式，比如`ReadBytes()`,`ReadString()`,`ReadLine()`等等，按照需求使用即可，一些细节可以阅读官方文档或者自己试验一下。

### 设计阶段

该程序的逻辑比较简单，没有循环，没有太多跳转之类的，就是一个线性流程。

根据需求，我们可以将整个流程归纳为：

1. 解析参数
2. 设置输入输出
3. 读取输入内容，分页，打印

接下来便可以开始进行代码的编写了。

## 代码实现

先贴一下实现后的代码：

```go
package main

import (
	"bufio"
	"flag"
	"fmt"
	"io"
	"os"
	"os/exec"
)

type selpgArgs struct {
	startPage int
	endPage   int
	lNumber   int
	pageType  byte
	dest      string
	args      []string
}

func main() {
	var args selpgArgs
	initArgs(&args)
	handleInput(args)
}

func initArgs(args *selpgArgs) {
	flag.IntVar(&args.startPage, "s", 1, "Start page number")
	flag.IntVar(&args.endPage, "e", 1, "End page number")
	flag.StringVar(&args.dest, "d", "", "Set the output to destination pipe")
	fword := flag.Bool("f", false, "Page with form feeds")
	flag.IntVar(&args.lNumber, "l", 72, "Page with lines number")
	flag.Parse()
	args.pageType = 'l'
	if *fword {
		args.pageType = 'f'
	}
	if args.startPage > args.endPage {
		fmt.Fprintln(os.Stderr, "Start page is greater than end page")
	}
	args.args = flag.Args()
}

func handleInput(args selpgArgs) {
	var in *os.File
	var out *os.File
	var cmd *exec.Cmd
	var pageNum, lineNum int
	if len(args.args) == 0 {
		in = os.Stdin
	} else {
		var err error
		in, err = os.Open(args.args[0])
		if err != nil {
			fmt.Fprintf(os.Stderr, "Couldn't open input file: %s\n", string(args.args[0]))
			return
		}
	}
	if args.dest != "" {
		cmd = exec.Command("/usr/bin/lp", fmt.Sprintf("-d%s", args.dest))
		reader, writer, err := os.Pipe()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Couldn't open pipe to %s\n", args.dest)
		}
		cmd.Stdin = reader
		out = writer
	} else {
		out = os.Stdout
	}
	if args.pageType == 'l' {
		var line []byte
		reader := bufio.NewReader(in)
		writer := bufio.NewWriter(out)
		lineNum = 0
		pageNum = 1
		for true {
			var err error
			line, _, err = reader.ReadLine()
			if err != nil {
				if err == io.EOF {
					break
				}
				fmt.Println(err)
				break
			}
			lineNum++
			if lineNum > args.lNumber {
				pageNum++
				lineNum = 1
			}
			if pageNum >= args.startPage && pageNum <= args.endPage {
				writer.Write(line)
				writer.Flush()
			}
		}
	} else {
		pageNum = 1
		reader := bufio.NewReader(in)
		writer := bufio.NewWriter(out)
		for true {
			buffer, err := reader.ReadByte()
			if err == io.EOF {
				break
			}
			if buffer == '\f' {
				pageNum++
			}
			if pageNum >= args.startPage && pageNum <= args.endPage {
				writer.WriteByte(buffer)
				writer.Flush()
			}
		}
	}

	if pageNum < args.startPage {
		fmt.Fprintf(os.Stderr, "Start page (%d) is greater than total pages (%d), no output written\n", args.startPage, pageNum)
	} else if pageNum < args.endPage {
		fmt.Fprintf(os.Stderr, "End page (%d) is greater than total pages (%d), less output than expected\n", args.endPage, pageNum)
	}

	if cmd != nil {
		cmd.Run()
	}
	fmt.Println()
}

```

代码不长，只有一百多行。这还是多亏了flag包为我省了不少的力气。

首先，为了方便记录，我设计了一个类型`type selpgArgs struct`用于存储该程序的相关参数：

```go
type selpgArgs struct {
	startPage int // 开始页码
	endPage   int // 结束页码
	lNumber   int // 每页行数
	pageType  byte // 分页类型，按照每页行数或是分页符\f
	dest      string // 输出到打印程序的管道
	args      []string // arguments，即文件名
}
```

我将主要的工作分为两个函数`initArgs`和`handleInput`，分别用于初始化参数和进行主要的打印工作。

在flag的帮助下，我的`initArgs`仅仅用了几行代码就搞定了，非常方便：

```go
func initArgs(args *selpgArgs) {
	flag.IntVar(&args.startPage, "s", 1, "Start page number")
	flag.IntVar(&args.endPage, "e", 1, "End page number")
	flag.StringVar(&args.dest, "d", "", "Set the output to destination pipe")
	fword := flag.Bool("f", false, "Page with form feeds")
	flag.IntVar(&args.lNumber, "l", 72, "Page with lines number")
	flag.Parse()
	args.pageType = 'l'
	if *fword {
		args.pageType = 'f'
	}
	if args.startPage > args.endPage {
		fmt.Fprintln(os.Stderr, "Start page is greater than end page")
	}
	args.args = flag.Args()
}
```

之后就是根据参数进行读写工作：

```go
func handleInput(args selpgArgs) {
	var in *os.File
	var out *os.File // 因为UNIX环境下万物皆为File，所以这里直接将input和output的类型定为了File*
	var cmd *exec.Cmd
	var pageNum, lineNum int
	if len(args.args) == 0 {
		in = os.Stdin // 没有输入文件名的情况下将标准输入作为输入来源
	} else {
		var err error
		in, err = os.Open(args.args[0]) // 输入了文件名的情况下将目标文件作为标准输入
		if err != nil {
			fmt.Fprintf(os.Stderr, "Couldn't open input file: %s\n", string(args.args[0]))
			return
		}
	}
	if args.dest != "" {
		cmd = exec.Command("/usr/bin/lp", fmt.Sprintf("-d%s", args.dest)) // 指定了打印机的管道后用exec打印，注意GO的exec是不会使用shell作为起点的，所以不会有环境变量，需要手动加入，或者指定完整的filePath
		reader, writer, err := os.Pipe()
		if err != nil {
			fmt.Fprintf(os.Stderr, "Couldn't open pipe to %s\n", args.dest)
		}
		cmd.Stdin = reader
		out = writer
	} else {
		out = os.Stdout
	}
	if args.pageType == 'l' { // 按行数分页
		var line []byte
		reader := bufio.NewReader(in)
		writer := bufio.NewWriter(out)
		lineNum = 0
		pageNum = 1
		for true {
			var err error
			line, _, err = reader.ReadLine()
			if err != nil {
				if err == io.EOF { // 读取EOF后结束
					break
				}
				fmt.Println(err)
				break
			}
			lineNum++
			if lineNum > args.lNumber {
				pageNum++
				lineNum = 1
			}
			if pageNum >= args.startPage && pageNum <= args.endPage {
				writer.Write(line)
				writer.Flush() // 这里需要手动Flush
			}
		}
	} else { // 按分页符分页
		pageNum = 1
		reader := bufio.NewReader(in)
		writer := bufio.NewWriter(out)
		for true {
			buffer, err := reader.ReadByte()
			if err == io.EOF {
				break
			}
			if buffer == '\f' {
				pageNum++
			}
			if pageNum >= args.startPage && pageNum <= args.endPage {
				writer.WriteByte(buffer)
				writer.Flush()
			}
		}
	}

	if pageNum < args.startPage {
		fmt.Fprintf(os.Stderr, "Start page (%d) is greater than total pages (%d), no output written\n", args.startPage, pageNum)
	} else if pageNum < args.endPage {
		fmt.Fprintf(os.Stderr, "End page (%d) is greater than total pages (%d), less output than expected\n", args.endPage, pageNum)
	}

	if cmd != nil {
		cmd.Run()
	}
	fmt.Println()
}

```

就这样一个简单的selpg文件就搞定了。

## 测试一下

做好之后我们简单的测试一下。

![image-20181006191041720](/images/image-20181006191041720.png)

帮助信息可以正常显示。

![image-20181006191356729](/images/image-20181006191356729.png)

使用命令行输入时可以正常分页(可以看到只有前两行被输出)。

这里有一个40行的样例文件：

```
hello world 1
hello world 12
hello world 123
hello world 1234
hello world 12345
hello world 123456
hello world 1234567
hello world 12345678
hello world 123456789
hello world 1234567890
hello world 123456789
hello world 12345678
hello world 1234567
hello world 123456
hello world 12345
hello world 1234
hello world 123
hello world 12
hello world 1
hello world 
hello world 1
hello world 12
hello world 123
hello world 1234
hello world 12345
hello world 123456
hello world 1234567
hello world 12345678
hello world 123456789
hello world 1234567890
hello world 123456789
hello world 12345678
hello world 1234567
hello world 123456
hello world 12345
hello world 1234
hello world 123
hello world 12
hello world 1
hello world
```

![image-20181006191757182](/images/image-20181006191757182.png)

可以看到能够正常输出。

![image-20181006191857866](/images/image-20181006191857866.png)

标准错误也可正常输出。

![image-20181006192013254](/images/image-20181006192013254.png)

管道操作也可正常使用。

![image-20181006192104624](/images/image-20181006192104624.png)

重定向输出也可以正常使用。

