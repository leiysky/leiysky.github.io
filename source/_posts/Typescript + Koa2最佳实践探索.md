---
title: TypeScript + Koa2最佳实践探索
date: 2018-10-18 15:27:35
tags: TypeScript
---

## 前言

TypeScript是微软研发的一种静态类型语言，是JavaScript的超集。使用TypeScript编写的代码可以通过`tsc`编译器编译成JavaScript的代码，从而在浏览器，node等JavaScript运行时上使用。

相比JavaScript，TypeScript提供了静态类型检查等功能，大大弥补了JavaScript的不足之处。

实际上我对TypeScript的种种好处早有耳闻，也阅读过官方文档，但是因为平时的工作都是写js为主，一直没机会用TypeScript构建项目。多亏了刚刚崩掉的Gitlab给了我一段假期，我终于有机会来尝试着用ts构建项目。

## 安装和配置TypeScript

### 安装

安装TypeScript实际上就是安装TypeScript的编译器`tsc`，方法十分简单，通过npm即可安装：

```shell
$ npm install -g typescript
```

安装成功后，我们便可以来尝试一下，使用TypeScript写一个简单的程序，并且保存为`greeter.ts`:

```typescript
function greeter(person) {
    return "Hello, " + person;
}

let user = "Jane User";

document.body.innerHTML = greeter(user);
```

在终端中运行：

```shell
$ tsc greeter.ts
```

我们便可以看到目录中出现了一个编译出来的`greeter.js`文件。

### 配置

可以通过创建`tsconfig.json`文件来配置`tsc`。

`tsc`在运行时会查找运行目录下的`tsconfig.json`文件，并使用其中的配置，如果没有，则会使用默认配置。

以下是一份`tsconfig.json`的样例：

```json
{
  "compilerOptions": {
    "target": "es2015",
    "module": "commonjs",
    "outDir": "./dist",
    "declaration": true,
    "declarationDir": "./@types",
    "sourceMap": true,
    "removeComments": true,
    "noImplicitAny": false,
    "preserveConstEnums": true,
    "experimentalDecorators": true,
    "emitDecoratorMetadata": true,
    "typeRoots": [
      "node_modules/@types",
      "node_modules/koa-custom-response/typings/response.d.ts",
      "typings"
    ]
  },
  "compileOnSave": false,
  "includes": [
    "src/**/*"
  ],
  "exclude": [
    "node_modules",
    "dist"
  ]
}
```

详细的配置选项文档可以到[官网](https://www.tslang.cn/docs/handbook/compiler-options.html)查看，在此我会列举几个比较重要的选项：

* `target`：该选项指明了编译出的js文件的标准，目前有：`"ES3"`（默认）， `"ES5"`， `"ES6"`/`"ES2015"`， `"ES2016"`，`"ES2017"`或 `"ESNext"` (`ESNEXT`的生成列表为[ES proposed features](https://github.com/tc39/proposals))
* `module`：该选项指明了生成哪个模块系统代码，选项有：`"None"`，`"CommonJS"`， `"AMD"`，`"System"`， `"UMD"`， `"ES6"`或`"ES2015"`。 在使用node的时候我们选择`CommonJS`。
* `moduleResolution`：该选项指明了处理模块的方式，有`Node`和`Classic`两种，在浏览器环境下使用时选择`Classic`，在`Node`环境下使用时使用`Node`。
* `outDir`：编译出来的文件重定向的位置。不指定的情况下，编译的生成文件将与原文件放在同一目录下，所以一般会指定一个`./build`之类的目录作为编译结果存放的目录。
* `sourceMap`：该选项指定是否开启sourceMap。因为TypeScript无法直接执行，需要编译成Javascript代码，所以我们如果要对TypeScript调试的话，需要一种代码映射的手段。sourceMap提供的就是这样的一种功能，它通过生成一个`.map`文件来描述映射的信息。需要debug的时候建议开启该功能。
* `sourceRoot`：指定source文件，即ts源文件的目录。**注意：这个选项可能并不像它看起来那样有用！**`.map`文件本质上是一个js文件，内容是一个`object`。其中有一个属性`"sources"`，这个属性指定了源文件的url。在没有指定`sourceRoot`的情况下，`tsc`会自动查找源文件的路径，并在`"sources"`中写入一个**正确**的url。但是如果指定了`sourceRoot`，`tsc` 就会失去它的智能，并在`"sources"`中写入`sourceRoot`和源文件名拼接而成的url。举个例子：源文件的url为`workRoot/src/app.ts`，编译出来的js文件url为`workRoot/build/app.js`，`sourceRoot`的值为`src`，那么`workRoot/build/app.js.map`文件中的`sources`属性的值为`["src/app.ts"]`。这时显然是无法映射到`app.ts`文件的。但是如果没有指定`sourceRoot`的话，`sources`的值则会是`["../src/app.ts"]`，即为正确的路径。
  这个选项的正确用途我还没想到，不过一般情况下不需要指定。
* `mapRoot`：为debugger指定`.map`文件的目录，并非编译时生效。当`.map`文件与原js文件不在一个目录下时，可以告诉debugger到何处去寻找`.map`文件。一般情况下也不需要指定。

## 创建Koa2项目

一个简单的Koa2项目的目录结构如下：

```
├── src
│   ├── controllers         ---  控制器
│   ├── models              ---  数据库 model
│   ├── utils               ---  常用的工具
│   └── services            ---  controller 与 model 的粘合层 ，包含业务逻辑
├── config
│   └── environments        ---  环境变量
└── test
    └── apis                ---  测试用例
```

有了`TypeScript`的泛型支持后，可以再抽象出一个`DAO`层，进一步解耦。

要定制`Koa`的`Context`的话，可以在`utils`下进行一个模块的扩展，比如说我写在`src/utils/index.ts`里面：

```typescript
// index.ts
declare module 'koa' {
  export interface Context {
    setResponse(data: object, status: string, msg?: string, code?: number): void;
  }
}

/**
 * 正常发送响应时使用此函数
 */
export function setResponse(data: object,
                            status: string = 'OK',
                            msg: string = 'OK',
                            code: number = 200) {
  this.status = code;
  const time = new Date();
  this.body = { status, msg, time, data: data || {} };
}

```

这里是一个简单的响应函数，我们将其声明与`Koa`的`Context`的声明合并，这样别处的代码可以获取`ctx.setResponse`的声明，方便补全，也能让ts自己识别。

具体的模块编写上与JS的区别并不是很大，有了类型支持后会变的方便一些。如果有什么别的想法之后会再补充。

## 使用VSCODE进行调试

**VSCODE(Visual Studio Code)**是微软提供的一款轻量级的代码编辑器。但是其具有相当庞大的扩展库，并且具有优秀的生态。如果用心配置的话，其功能足以媲美IDE。

因为VSCODE本身是使用TypeScript开发的，所以对JavaScript和TypeScript的支持都很完美，特别是调试。

在这里我主要介绍一套使用`node inspector`进行调试的方法。

我的项目结构是这样的：

![image-20181018103606690](/images/image-20181018103606690.png)

在app.ts中启动了`Koa`并挂载了`koa-router`。hello.ts中是一个简单的controller，负责处理`/`的`GET`请求。

`tsconfig.json`的配置如下：

```json
{
  "compilerOptions": {
    "module": "commonjs",
    "allowJs": true,
    "checkJs": true,
    "outDir": "./build",
    "noEmit": false,
    "strictNullChecks": true,
    "strictFunctionTypes": true,
    "noImplicitThis": false,
    "noImplicitReturns": true,
    "moduleResolution": "node",
    "noUnusedLocals": false,
    "noUnusedParameters": false,
    "esModuleInterop": true,
    "experimentalDecorators": true,
    "emitDecoratorMetadata": true,
    "sourceMap": true,
    "target": "esnext"
  },
  "include": [
    "src/**/*"
  ],
  "exclude": [
    "node_modules",
    "build"
  ]
}
```

其中比较重要的是`target`尽量设置成`es2017`之后的版本(最好是`esnext`)。主要是因为es2017之后有官方的`async`和`await`的实现，调试的时候可以将断点map到`async`函数中。而在此之前的版本经由`tsc`编译出的js代码如同用`babel`等pollyfill编译出的，实现方式千奇百怪，难以调试。

之后我们进行VSCODE的debug配置文件`launch.json`的配置：

```json
{
  "version": "0.2.0",
  "configurations": [
    {
      "type": "node",
      "request": "launch",
      "name": "Launch Program",
      "program": "${workspaceFolder}/build/app.js",
      "sourceMaps": true,
      "outFiles": [ // 该选项指定了map文件的寻找路径
        "build"
      ]
    },
    {
      "type": "node",
      "request": "attach",
      "name": "附加",
      "port": 5858,
      "timeout": 10000,
      "restart": true,
      "address": "localhost",
      "sourceMaps": true,
      "outFiles": [
        "build"
      ]
    }
  ]
}
```

这里我提供了两种调试方式：

* 一种是通过node的launch，也就是直接启动项目的入口。这种方式最为直接，但是实际上并不是很方便，因为每一次调试都需要重新启动项目。

* 另一种是通过attach的方式，使用`node-inspector`进行调试。

关于第一种方式我就不再介绍，接下来讲讲如何使用`node-inspector`进行调试。

首先我们在开发环境中安装`nodemon`：

```shell
$ npm install -g nodemon
```

`nodemon`是一个能监测node的代码变化自动重启的软件，调试时非常好用。

运行指令：

```shell
$ tsc && nodemon build/app.js --inspect 5858 --signal SIGHUP
```

这条指令编译了TypeScript代码，并且使用`nodemon`运行编译出的js代码。`node-inspector`的端口被设置为5858，与`launch.json`中配置的一致。并且在接受到`SIGHUP`信号时项目会自动重启。

之后，我们在VSCODE中按下`F5`开启调试，Debugger就会附加到正在运行的node进程上。因为开启了`sourceMap`，我们可以直接在TypeScript代码上进行断点调试，十分方便。

![image-20181018152308635](/images/image-20181018152308635.png)

正如上图所示，代码成功在断点处停止，调用栈也正确显示，这样一来一个TypeScript的开发环境就搭建完成了。