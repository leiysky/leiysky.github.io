---
title: Golang gzip源码剖析
date: 2018-11-14 18:09:09
tags: golang
---

gzip是[RFC1952](https://tools.ietf.org/html/rfc1952)中定义的一种压缩格式，Golang官方的gzip包对其进行了实现。

## 类型定义

gzip包中实现了对gzip文件的Writer：

```go
// A Writer is an io.WriteCloser.
// Writes to a Writer are compressed and written to w.
type Writer struct {
	Header      // written at first call to Write, Flush, or Close
	w           io.Writer
	level       int
	wroteHeader bool
	compressor  *flate.Writer
	digest      uint32 // CRC-32, IEEE polynomial (section 8)
	size        uint32 // Uncompressed size (section 2.3.1)
	closed      bool
	buf         [10]byte
	err         error
}
```

其中的`w`是对于目标文件的Writer，对其进行`Write`写入的数据都是经过压缩的。

并且定义了一组配置常量：

```go
// These constants are copied from the flate package, so that code that imports
// "compress/gzip" does not also have to import "compress/flate".
const (
	NoCompression      = flate.NoCompression
	BestSpeed          = flate.BestSpeed
	BestCompression    = flate.BestCompression
	DefaultCompression = flate.DefaultCompression
	HuffmanOnly        = flate.HuffmanOnly
)
```

## 函数实现

创建Writer的函数：

```go
// NewWriter returns a new Writer.
// Writes to the returned writer are compressed and written to w.
//
// It is the caller's responsibility to call Close on the Writer when done.
// Writes may be buffered and not flushed until Close.
//
// Callers that wish to set the fields in Writer.Header must do so before
// the first call to Write, Flush, or Close.
func NewWriter(w io.Writer) *Writer {
	z, _ := NewWriterLevel(w, DefaultCompression)
	return z
}

// NewWriterLevel is like NewWriter but specifies the compression level instead
// of assuming DefaultCompression.
//
// The compression level can be DefaultCompression, NoCompression, HuffmanOnly
// or any integer value between BestSpeed and BestCompression inclusive.
// The error returned will be nil if the level is valid.
func NewWriterLevel(w io.Writer, level int) (*Writer, error) {
	if level < HuffmanOnly || level > BestCompression {
		return nil, fmt.Errorf("gzip: invalid compression level: %d", level)
	}
	z := new(Writer)
	z.init(w, level)
	return z, nil
}

func (z *Writer) init(w io.Writer, level int) {
	compressor := z.compressor
	if compressor != nil {
		compressor.Reset(w)
	}
	*z = Writer{
		Header: Header{
			OS: 255, // unknown
		},
		w:          w,
		level:      level,
		compressor: compressor,
	}
}
```

`NewWriter`本质上也是通过调用`NewWriterLevel`创建的Writer，使用的是默认的压缩等级。

`init`实现了`Writer`类型中的`init`方法，主要做的是Writer的初始化。

```go
// Reset discards the Writer z's state and makes it equivalent to the
// result of its original state from NewWriter or NewWriterLevel, but
// writing to w instead. This permits reusing a Writer rather than
// allocating a new one.
func (z *Writer) Reset(w io.Writer) {
	z.init(w, z.level)
}
```

`Reset`函数的实现为了节约内存，选择重用一个Writer而不是新建一个。

```go
// writeBytes writes a length-prefixed byte slice to z.w.
func (z *Writer) writeBytes(b []byte) error {
	if len(b) > 0xffff {
		return errors.New("gzip.Write: Extra data is too large")
	}
	le.PutUint16(z.buf[:2], uint16(len(b)))
	_, err := z.w.Write(z.buf[:2])
	if err != nil {
		return err
	}
	_, err = z.w.Write(b)
	return err
}

// writeString writes a UTF-8 string s in GZIP's format to z.w.
// GZIP (RFC 1952) specifies that strings are NUL-terminated ISO 8859-1 (Latin-1).
func (z *Writer) writeString(s string) (err error) {
	// GZIP stores Latin-1 strings; error if non-Latin-1; convert if non-ASCII.
	needconv := false
	for _, v := range s {
		if v == 0 || v > 0xff {
			return errors.New("gzip.Write: non-Latin-1 header string")
		}
		if v > 0x7f {
			needconv = true
		}
	}
	if needconv {
		b := make([]byte, 0, len(s))
		for _, v := range s {
			b = append(b, byte(v))
		}
		_, err = z.w.Write(b)
	} else {
		_, err = io.WriteString(z.w, s)
	}
	if err != nil {
		return err
	}
	// GZIP strings are NUL-terminated.
	z.buf[0] = 0
	_, err = z.w.Write(z.buf[:1])
	return err
}
```

`writeBytes`和`writeString`是两个私有函数。`writeBytes`主要用于向writer写入一个带有前缀的byte切片。`writeString`则是向Writer写入一个UTF-8的字符串。在`writeString`中对于字符的范围进行了判断，对于ASCII可表示的字符直接进行存储，而如果字符超出了这个范围，则会进行转换。

```go
// Write writes a compressed form of p to the underlying io.Writer. The
// compressed bytes are not necessarily flushed until the Writer is closed.
func (z *Writer) Write(p []byte) (int, error) {
	if z.err != nil {
		return 0, z.err
	}
	var n int
	// Write the GZIP header lazily.
	if !z.wroteHeader {
		z.wroteHeader = true
		z.buf = [10]byte{0: gzipID1, 1: gzipID2, 2: gzipDeflate}
		if z.Extra != nil {
			z.buf[3] |= 0x04
		}
		if z.Name != "" {
			z.buf[3] |= 0x08
		}
		if z.Comment != "" {
			z.buf[3] |= 0x10
		}
		if z.ModTime.After(time.Unix(0, 0)) {
			// Section 2.3.1, the zero value for MTIME means that the
			// modified time is not set.
			le.PutUint32(z.buf[4:8], uint32(z.ModTime.Unix()))
		}
		if z.level == BestCompression {
			z.buf[8] = 2
		} else if z.level == BestSpeed {
			z.buf[8] = 4
		}
		z.buf[9] = z.OS
		_, z.err = z.w.Write(z.buf[:10])
		if z.err != nil {
			return 0, z.err
		}
		if z.Extra != nil {
			z.err = z.writeBytes(z.Extra)
			if z.err != nil {
				return 0, z.err
			}
		}
		if z.Name != "" {
			z.err = z.writeString(z.Name)
			if z.err != nil {
				return 0, z.err
			}
		}
		if z.Comment != "" {
			z.err = z.writeString(z.Comment)
			if z.err != nil {
				return 0, z.err
			}
		}
		if z.compressor == nil {
			z.compressor, _ = flate.NewWriter(z.w, z.level)
		}
	}
	z.size += uint32(len(p))
	z.digest = crc32.Update(z.digest, crc32.IEEETable, p)
	n, z.err = z.compressor.Write(p)
	return n, z.err
}

```

`Write`函数中主要的写入工作还是通过`writeString`和`writeBytes`来实现的，它对于gzip的文件格式做了规范，使得输出的内容符合gzip的定义。

```go
// Flush flushes any pending compressed data to the underlying writer.
//
// It is useful mainly in compressed network protocols, to ensure that
// a remote reader has enough data to reconstruct a packet. Flush does
// not return until the data has been written. If the underlying
// writer returns an error, Flush returns that error.
//
// In the terminology of the zlib library, Flush is equivalent to Z_SYNC_FLUSH.
func (z *Writer) Flush() error {
	if z.err != nil {
		return z.err
	}
	if z.closed {
		return nil
	}
	if !z.wroteHeader {
		z.Write(nil)
		if z.err != nil {
			return z.err
		}
	}
	z.err = z.compressor.Flush()
	return z.err
}
```

`Flush`的作用是在进行http等网络通信时，判断服务端socket的reader是否能接收整个压缩过的包。如果遇到无法写入的情况，`Flush`会挂起，直到数据被成功写入才返回。在此期间如果有异常出现，`Flush`会返回对应的`error`。

```go
// Close closes the Writer by flushing any unwritten data to the underlying
// io.Writer and writing the GZIP footer.
// It does not close the underlying io.Writer.
func (z *Writer) Close() error {
	if z.err != nil {
		return z.err
	}
	if z.closed {
		return nil
	}
	z.closed = true
	if !z.wroteHeader {
		z.Write(nil)
		if z.err != nil {
			return z.err
		}
	}
	z.err = z.compressor.Close()
	if z.err != nil {
		return z.err
	}
	le.PutUint32(z.buf[:4], z.digest)
	le.PutUint32(z.buf[4:8], z.size)
	_, z.err = z.w.Write(z.buf[:8])
	return z.err
}
```

