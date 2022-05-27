---
title: 使用ANTLR4编写parser
date: 2019-07-29 19:59:06
tags: ['Parser', 'ANTLR']
categories: ['Parser']
---

## 前言

ANTLR 是一款由 Java 编写的开源语法解析工具。

我们知道在编译的过程中，主要有词法分析(Lexical Analysis), 语法分析(Grammar Analysis), 语义分析(Semantic Analysis), 中间代码生成(Intermediate Code Generation)等过程。

但是这是对于高级语言的编译过程，有时候我们需要设计一些 DSL 或者配置文件格式，这时候只需要词法分析和语法分析就可以解决我们的需求。

ANTLR 可以通过 BNF 或者 EBNF 文法的语法定义文件生成默认的 Lexer 和基本的 ast，并且提供了 listener, visitor 两种可选的方式来遍历 ast。对比起 yacc 和 lex 的组合，它的好处在于能生成相对友好的代码方便你进行处理（不用在几千行的 `.y` 文件里面爬摸滚打了）。

ANTLR 的最新版本是 4，在这篇文章里我将使用 Go 作为生成的 target 语言。

## ANTLR4 的安装

[自己看](https://github.com/antlr/antlr4/blob/master/doc/getting-started.md)

## 简单的 EBNF 文法

EBNF, 即扩展巴恩斯范式，是一种上下文无关文法。现代编程语言基本都使用 EBNF 来进行语法定义。

我们首先来简单定义一个四则运算表达式的语法规则:

```g4
grammar Math;

math : expr EOF;

expr :    op=('+'|'-') expr                    # unaryExpr
      |   left=expr op=('*'|'/') right=expr    # infixExpr
      |   left=expr op=('+'|'-') right=expr    # infixExpr
      |   value=NUM                            # numberExpr
      ;

ADD: '+';
SUB: '-';
MUL: '*';
DIV: '/';

NUM :   [0-9]+ ('.' [0-9]+)? ([eE] [+-]? [0-9]+)?;
WS  :   [ \t\r\n] -> channel(HIDDEN);
```

将其保存为 `Math.g4`(注意，文件名必须与 grammar 一致)。

使用如下指令生成代码：

```sh
$ antlr -Dlanguage=Go -visitor -o . Math.g4
```

我们可以看到当前目录下生成了几个文件：

```sh
.
├── Math.g4
├── Math.tokens
├── MathLexer.tokens
├── math_base_listener.go
├── math_base_visitor.go
├── math_lexer.go
├── math_listener.go
├── math_parser.go
└── math_visitor.go
```

其中 `math_parser.go` 包括了生成的基本 ast 的定义，`math_listener.go` 和 `math_visitor.go` 分别包含了 `listener` 和 `visitor` 的接口定义。

`listener` 和 `visitor` 的区别在于，`listener` 的遍历路线 ANTLR 已经帮你选好了，你只需要写对于不同节点的处理方式即可。而 `visitor` 则意味着你需要自己编写遍历的逻辑。

接下来我们自己定义一个可以进行 Evaluate 的 ast：

```go
type NodeType int

const (
  NodeExpr NodeType = iota
  NodeValue
)

type OpType int

const (
  OpAdd OpType = iota
  OpSub
  OpMul
  OpDiv
)

type Node struct {
  Type      NodeType
  Left      *Node
  Right     *Node
  Op        OpType
  Val       float64
}

func (n *Node) Evaluate() float64 {
  if n.Type == NodeExpr {
    switch n.Op {
    case OpAdd:
      return n.Left.Evaluate() + n.Right.Evaluate()
    case OpSub:
      return n.Left.Evaluate() - n.Right.Evaluate()
    case OpMul:
      return n.Left.Evaluate() * n.Right.Evaluate()
    case OpDiv:
      return n.Left.Evaluate() / n.Right.Evaluate()
    }
  }
  return n.Evaluate()
}
```

那么该如何转换出这样的结构呢？

我们可以使用 `visitor` 来重构整个 ast：

```go
type convertVisitor struct {
	BaseMathVisitor
}

func (v *convertVisitor) Visit(tree antlr.ParseTree) interface{} {
	return tree.Accept(v)
}

func (v *convertVisitor) VisitMath(ctx *MathContext) interface{} {
	return ctx.Expr().Accept(v)
}

func (v *convertVisitor) VisitExpr(ctx *ExprContext) interface{} {
	node := &Node{}
	if ctx.value != nil {
		node.Type = NodeValue
		node.Val, _ = strconv.ParseFloat(ctx.value.GetText(), 64)
	} else if len(ctx.AllExpr()) == 1 {
		node.Left = &Node{
			Type: NodeValue,
			Val:  0,
		}
		node.Right = ctx.Expr(0).Accept(v).(*Node)
		switch ctx.op.GetTokenType() {
		case MathLexerADD:
			node.Op = OpAdd
		case MathLexerSUB:
			node.Op = OpSub
		}
	} else if len(ctx.AllExpr()) > 1 {
		node.Left = ctx.Expr(0).Accept(v).(*Node)
		node.Right = ctx.Expr(1).Accept(v).(*Node)
		switch ctx.op.GetTokenType() {
		case MathLexerADD:
			node.Op = OpAdd
		case MathLexerSUB:
			node.Op = OpSub
		case MathLexerMUL:
			node.Op = OpMul
		case MathLexerDIV:
			node.Op = OpDiv
		}
	}
	return node
}

func Parse(expr string) *Node {
	input := antlr.NewInputStream(expr)
	lexer := NewMathLexer(input)
	tokenStream := antlr.NewCommonTokenStream(lexer, antlr.TokenDefaultChannel)
	parser := NewMathParser(tokenStream)
	tree := parser.Math()
	v := &convertVisitor{}
	return v.Visit(tree).(*Node)
}

```

调用 `Parse` 既可以将表达式的字符串转换为我们的 `Node`。