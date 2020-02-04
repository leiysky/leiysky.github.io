---
title: LevelDB源码剖析
date: 2019-03-27 00:32:35
tags: ['Database', 'LevelDB']
categories: ['Database']
---

# 前言

`LevelDB`是谷歌开源的一款高性能嵌入式 kv 数据库，基于`LSM-tree`索引，是`Bigtable`的简化版实现（可以这么理解）。

它的特点是写入速度非常快，达到了`O(1)`级别的时间复杂度。但是付出的代价就是读取的速度非常慢，尤其是对于数据库中不存在的 key 进行`get`操作会扫描所有的记录。

对于 LevelDB 的具体设计本文就不再提及，这里主要从代码的层面分析一下 LevelDB 的结构（膜拜一下 Jeff Dean 亲手写的 C++）。

# LevelDB 的入口 db.h

`db.h`中定义了`LevelDB`对外开放的接口——`DB`类。

`DB`类的代码如下：

```cpp
class LEVELDB_EXPORT DB {
 public:
  static Status Open(const Options& options,
                     const std::string& name,
                     DB** dbptr);

  DB() = default;

  DB(const DB&) = delete;
  DB& operator=(const DB&) = delete;

  virtual ~DB();
  virtual Status Put(const WriteOptions& options,
                     const Slice& key,
                     const Slice& value) = 0;
  virtual Status Delete(const WriteOptions& options, const Slice& key) = 0;
  virtual Status Write(const WriteOptions& options, WriteBatch* updates) = 0;
  virtual Status Get(const ReadOptions& options,
                     const Slice& key, std::string* value) = 0;
  virtual Iterator* NewIterator(const ReadOptions& options) = 0;
  virtual const Snapshot* GetSnapshot() = 0;
  virtual void ReleaseSnapshot(const Snapshot* snapshot) = 0;
  virtual bool GetProperty(const Slice& property, std::string* value) = 0;
  virtual void GetApproximateSizes(const Range* range, int n,
                                   uint64_t* sizes) = 0;
  virtual void CompactRange(const Slice* begin, const Slice* end) = 0;
};
```

在这个类里面定义了`Put`, `Delete`, `Get`, `Write`这几个`CURD`的基本操作，以及`LevelDB`支持的`feature`，获取快照等。

接下来，我将先从这几个基本操作入手，结合 LevelDB 的源码进行分析。

## Put

当你调用`Put`写入一个 value 时，会发生些什么呢？

LevelDB 写入数据的流程非常简单：

1. 追加 Log 到 Log 文件
2. 检查是否需要 compaction

我们首先看看`Put`函数的实现。

`LevelDB`本身的实现在`db/db_impl.h`和`db/db_impl.cc`中。

`Put`的实现如下：

```cpp
Status DBImpl::Put(const WriteOptions& o, const Slice& key, const Slice& val) {
  return DB::Put(o, key, val);
}
```

可以看到这里 DBImpl 覆盖了 DB 的 Put 方法，并且在其中透传参数调用了父类的 Put。

```cpp
Status DB::Put(const WriteOptions& opt, const Slice& key, const Slice& value) {
  WriteBatch batch;
  batch.Put(key, value);
  return Write(opt, &batch);
}
```

`Put`的本质就是一个`Write`操作带上了自己封装的`Batch`。

所以我们继续来看`Write`的过程。

以下是精简过的`Write`代码:

```cpp
Status DBImpl::Write(const WriteOptions& options, WriteBatch* my_batch) {
  Writer w(&mutex_);
  w.batch = my_batch;

  MakeRoomForWrite(my_batch == NULL);

  uint64_t last_sequence = versions_->LastSequence();
  Writer* last_writer = &w;
  WriteBatch* updates = BuildBatchGroup(&last_writer);
  WriteBatchInternal::SetSequence(updates, last_sequence + 1);
  last_sequence += WriteBatchInternal::Count(updates);

  log_->AddRecord(WriteBatchInternal::Contents(updates));
  WriteBatchInternal::InsertInto(updates, mem_);

  versions_->SetLastSequence(last_sequence);
  return Status::OK();
}
```

这里首先面临的一个关键步骤是`MakeRoomForWrite`。

`MakeRoomForWrite`的作用是为`Write`制造条件，包括可用的`memtable`和 Log 的`writer`。

`MakeRoomForWirte`内部是一个无限的 loop，参数为一个`bool force`。顾名思义其作用为强制发起一次`compaction`，触发条件为`mybatch==nullptr`，其分支情况如下：

1. 检查是否需要延迟写入`L0`文件（`force`为`false`，且`L0`文件过多时会`delay`1000ms，一次`MakeRoomForWrite`的过程最多有一次`delay`）
2. 如果当前的`memtable`容量够用则跳出 loop，返回后将直接使用当前`memtable`
3. 检查是否有`immutable table`，如果有则表示上一次`compaction`还未完成，继续等待
4. 检查`L0`文件数量，如果数量过多也说明`compaction`未完成，继续等待
5. 创建新的`memtable`，并且对旧的进行`compaction`（过程为创建 Log 文件，设置`immutable table`为旧的`memtable`，创建新的`memtable`，调用`MaybeScheduleCompaction`）
   这个函数：

```cpp
void DBImpl::MaybeScheduleCompaction() {
  mutex_.AssertHeld();
  if (background_compaction_scheduled_) {
    // Already scheduled
  } else if (shutting_down_.load(std::memory_order_acquire)) {
    // DB is being deleted; no more background compactions
  } else if (!bg_error_.ok()) {
    // Already got an error; no more changes
  } else if (imm_ == nullptr &&
             manual_compaction_ == nullptr &&
             !versions_->NeedsCompaction()) {
    // No work to be done
  } else {
    background_compaction_scheduled_ = true;
    env_->Schedule(&DBImpl::BGWork, this);
  }
}
```

那么我们也可以猜到，`MaybeScheduleCompaction`这个函数实际上就是`compaction`的入口。我们先来大致看一下他的内容（代码比较短，我就直接贴代码了）：

```c++
void DBImpl::MaybeScheduleCompaction() {
  mutex_.AssertHeld();
  if (background_compaction_scheduled_) {
    // Already scheduled
  } else if (shutting_down_.load(std::memory_order_acquire)) {
    // DB is being deleted; no more background compactions
  } else if (!bg_error_.ok()) {
    // Already got an error; no more changes
  } else if (imm_ == nullptr &&
             manual_compaction_ == nullptr &&
             !versions_->NeedsCompaction()) {
    // No work to be done
  } else {
    background_compaction_scheduled_ = true;
    env_->Schedule(&DBImpl::BGWork, this);
  }
}
```

可以看到具体的`Schedule`是与环境相挂钩的，其执行一定会触发`minor compaction`，如果满足条件也会触发`major compaction`。LevelDB 提供了`Windows`和`POSIX`两种实现，我们之后再来看。

在`MakeRoomForWrite`之后，会调用`_log.AddRecord()`来追加一条 Log，并且使用`WriteBatchInternal::Contents(updates)`来写入`memtable`。

关于 Log 的内容会在之后展开讲，这里主要提一下，写`memtable`的过程实际上就是在`memtable`的`skiplist`中插入一条记录。

一次`Put`的过程就是这样，非常的简洁，这也是`LevelDB`写入速度快的原因。

## Get

LevelDB 极高的写性能带来的代价就是他的读性能非常的差。

每次`Get`操作的读取顺序为：

1. `memtable`
2. `immutable table`
3. `L0`文件
4. 高`Level`文件

只有在所有的文件都被读完后才能确定目标`key`是不存在的。

`Get`方法的脉络很清晰，因为其本质就是一个遍历查找的过程，整理后的代码如下：

```cpp
Status DBImpl::Get(const ReadOptions& options, const Slice& key, std::string* value) {
  LookupKey lkey(key, versions_->LastSequence());
  if (mem_->Get(lkey, value, NULL)) {
    // Done
  } else if (imm_ != NULL && imm_->Get(lkey, value, NULL)) {
    // Done
  } else {
    versions_->current()->Get(options, lkey, value, NULL);
  }

  MaybeScheduleCompaction();
  return Status::OK();
}
```

我们先来看看`memtable`的`Get`。

LevelDB 的`memtable`本质上是一个常规的`skiplist`，存储了有序的`entries`。所以`memtable`的`Get`操作就是使用用户提供的`comparator`去进行一个查找。

这里有个小细节就是每个`entry`都存储了一个`ValueType`，用于标记该`key`的类型，是**插入**还是**删除**。

我们知道 LevelDB 的删除本质上也是追加一条记录，在`compaction`的时候才会真正的删除掉`key`。

LevelDB 的写入方式保证了`Get`能从最新的数据开始读，因此如果读到了一个指定`key`的删除记录，则可以确定该`key`已经不存在了。

`immutable table`的结构与`memtable`是相同的，不同点在于它是不可变的，相当于是一个`memtable`与`SSTable`文件之间的缓冲。

接下来我们看看`version`的`Get`操作。

在`version`的`Get`操作中有一个比较重要的概念——`FileMetaData`。

`FileMetaData`的定义如下：

```cpp
struct FileMetaData {
  int refs;
  int allowed_seeks;          // Seeks allowed until compaction
  uint64_t number;
  uint64_t file_size;         // File size in bytes
  InternalKey smallest;       // Smallest internal key served by table
  InternalKey largest;        // Largest internal key served by table

  FileMetaData() : refs(0), allowed_seeks(1 << 30), file_size(0) { }
};
```

我们可以看到其中定义了一个`smallest`和`largest`，它们描述了文件中存储的`key`的区间。我们在读取的时候可以根据这个区间确定`key`是否在该文件中，这样加快了`key`的定位速度。

`version`的`Get`过程也十分简单粗暴，逐层检索`key`，找到为止。

## Delete & Write

`Delete`其实就是`Put`，而`Put`的本质是`Write`，这两个操作就不再展开讲。

# 追加写的核心——Log

LSM 树的思想是将内存中维护的树定期 flush 到磁盘上持久化，以提高写入的性能。但是我们知道内存中的数据是 Volatile 的，这就需要 log 来保证数据的持久性。

Log 相关的代码主要有`log_format.h`, `log_reader.h`, `log_writer.h`。

## log_format.h

这个文件中定义了`log`的格式：

```cpp
enum RecordType {
  // Zero is reserved for preallocated files
  kZeroType = 0,

  kFullType = 1,

  // For fragments
  kFirstType = 2,
  kMiddleType = 3,
  kLastType = 4
};
static const int kMaxRecordType = kLastType;

static const int kBlockSize = 32768;

// Header is checksum (4 bytes), length (2 bytes), type (1 byte).
static const int kHeaderSize = 4 + 2 + 1;
```

我们知道 LevelDB 的 log 是连续存储在文件中的（为了最大化顺序读写的性能，每次将一条`Record`写入文件），每条 Log 都有一个 header 存储相关的元信息。这里的元信息为三个：`CRC`校验码，Log 内容长度，Log 位置信息。

LevelDB 的日志每个块的大小是固定的（为了对齐 32K），因此 Log 的数据有可能会被切分到不同的块。这里我们可以知道有四种位置关系，分别是：

- 整个 Log 在该块中
- Log 的开头在该块中
- Log 的中间部分在该块中（占据整个块）
- Log 的尾部在该块中

那么这个`kZeroType`是做什么的呢？

考虑这种情况，一个块在写入后只剩下不到 7 个字节的空间，不足以塞下一个 header。

这时 LevelDB 会选择使用`\x00`来填充剩余的空间。

当剩余 7 个字节时，则塞入一个`kZeroType`的 header。

## log_writer.h

`log_writer.h`中定义了一个`Writer`类，它的主要方法只有一个，就是`AddRecord`，也就是我们之前在`Put`中看到的追加 Log 的操作。

`AddRecord`的实现如下：

```cpp
Status Writer::AddRecord(const Slice& slice) {
  const char* ptr = slice.data();
  size_t left = slice.size();

  // Fragment the record if necessary and emit it.  Note that if slice
  // is empty, we still want to iterate once to emit a single
  // zero-length record
  Status s;
  bool begin = true;
  do {
    const int leftover = kBlockSize - block_offset_;
    assert(leftover >= 0);
    if (leftover < kHeaderSize) {
      // Switch to a new block
      if (leftover > 0) {
        // Fill the trailer (literal below relies on kHeaderSize being 7)
        assert(kHeaderSize == 7);
        dest_->Append(Slice("\x00\x00\x00\x00\x00\x00", leftover));
      }
      block_offset_ = 0;
    }

    // Invariant: we never leave < kHeaderSize bytes in a block.
    assert(kBlockSize - block_offset_ - kHeaderSize >= 0);

    const size_t avail = kBlockSize - block_offset_ - kHeaderSize;
    const size_t fragment_length = (left < avail) ? left : avail;

    RecordType type;
    const bool end = (left == fragment_length);
    if (begin && end) {
      type = kFullType;
    } else if (begin) {
      type = kFirstType;
    } else if (end) {
      type = kLastType;
    } else {
      type = kMiddleType;
    }

    s = EmitPhysicalRecord(type, ptr, fragment_length);
    ptr += fragment_length;
    left -= fragment_length;
    begin = false;
  } while (s.ok() && left > 0);
  return s;
}
```

这里唯一要注意的就是剩余空间不足时的处理方式，前面已经提过了。

在`EmitPhysicalRecord`中则会将发生的更改`flush`到磁盘上。

## log_reader.h

`log_reader.h`中主要定义了`Reader`，用于读取 Log。

和`Writer`相对应，`Reader`的主要方法就是一个`ReadRecord`。

`ReadRecord`的逻辑也很简单：

- 使用`ReadPhysicalRecord`读取`record`，这个过程会做`CRC`校验
- 根据`Type`选择处理方式

# LevelDB 的 Compaction

LSM 中，数据合并的过程叫做`Compaction`，其中有三种：

- `Minor Compaction`: 内存中的树与磁盘文件合并
- `Major Compaction`: SSTable 与上层 SSTable 文件合并
- `Full Compaction`: 全部合并

LevelDB 实现了`Minor Compaction`和`Major Compaction`。

我们在前面有提到`MaybeScheduleCompaction`这个函数：

```cpp
void DBImpl::MaybeScheduleCompaction() {
  mutex_.AssertHeld();
  if (background_compaction_scheduled_) {
    // Already scheduled
  } else if (shutting_down_.load(std::memory_order_acquire)) {
    // DB is being deleted; no more background compactions
  } else if (!bg_error_.ok()) {
    // Already got an error; no more changes
  } else if (imm_ == nullptr &&
             manual_compaction_ == nullptr &&
             !versions_->NeedsCompaction()) {
    // No work to be done
  } else {
    background_compaction_scheduled_ = true;
    env_->Schedule(&DBImpl::BGWork, this);
  }
}
```

`env_->Schedule`传入的参数`DBImpl::BGWork`就是实际运行`Compaction`过程的函数指针，我们来看看其实现：

```cpp
void DBImpl::BGWork(void* db) {
  reinterpret_cast<DBImpl*>(db)->BackgroundCall();
}

void DBImpl::BackgroundCall() {
  MutexLock l(&mutex_);
  assert(background_compaction_scheduled_);
  if (shutting_down_.load(std::memory_order_acquire)) {
    // No more background work when shutting down.
  } else if (!bg_error_.ok()) {
    // No more background work after a background error.
  } else {
    BackgroundCompaction();
  }

  background_compaction_scheduled_ = false;

  // Previous compaction may have produced too many files in a level,
  // so reschedule another compaction if needed.
  MaybeScheduleCompaction();
  background_work_finished_signal_.SignalAll();
}
```

`DBImpl::BGWork`中直接调用了入口函数`DBImpl::BackgroundCall`。在后者中，调用了`BackgroundCompaction`。

`DBImpl::BackgroundCompaction`是一个比较长的函数，简化后的代码如下：

```cpp
void DBImpl::BackgroundCompaction() {
  // 去掉了manual模式的相关内容
  CompactMemtable();
  Compaction* c;
  c = versions_->PickCompaction();
  CompactionState* compact = new CompactionState(c);
  DoCompactionWork(compact);
  CleanupCompaction(compact);
  c->ReleaseInputs();
  DeleteObsoleteFiles();
  delete c;
}
```

## Minor Compaction
首先来看看`CompactMemtable`这个函数(同样是简化版)：

```cpp
void DBImpl::CompactMemTable() {
  VersionEdit edit;
  Version* base = versions_->current();
  base->Ref();
  Status s = WriteLevel0Table(imm_, &edit, base);
  base->Unref();
  edit.SetPrevLogNumber(0);
  edit.SetLogNumber(logfile_number_);
  s = versions_->LogAndApply(&edit, &mutex_);
  imm_->Unref();
  imm_ = nullptr;
  has_imm_.store(false, std::memory_order_release);
  DeleteObsoleteFiles();
}
```

我们知道`memtable`的`compaction`过程为：

1. 将当前的`memtable`切换为`immutable memtable`
2. 将`immutable memtable`转换为 SSTable 文件

这里为了保证写操作不被阻塞，首先会生成一个相同的`memtable`，将其作为`imm`，并尝试使用`WriteLevel0Table`进行`compaction`。

`WriteLevel0Table`的实现如下：

```cpp
Status DBImpl::WriteLevel0Table(MemTable* mem, VersionEdit* edit,
                                Version* base) {
  FileMetaData meta;
  meta.number = versions_->NewFileNumber();
  pending_outputs_.insert(meta.number);
  Iterator* iter = mem->NewIterator();
  Status s;
  s = BuildTable(dbname_, env_, options_, table_cache_, iter, &meta);
  delete iter;
  pending_outputs_.erase(meta.number);
  int level = 0;
  const Slice min_user_key = meta.smallest.user_key();
  const Slice max_user_key = meta.largest.user_key();
  level = base->PickLevelForMemTableOutput(min_user_key, max_user_key);
  edit->AddFile(level, meta.number, meta.file_size,
                  meta.smallest, meta.largest);
  return s;
}
```

这里的关键步骤是`BuildTable`，这个函数将会把 memtable 的具体内容写入指定的文件。

这一块的嵌套会有点深，`BuildTable`是在`builder.cc`里面实现的函数，本质上是构造了一个`TableBuilder`来创建 SSTable，所以我们直接看`TableBuilder`相关的内容。

`TableBuilder`相关的文件为`table_builder.h`和`table_builder.cc`。

`TableBuilder`的声明如下：

```cpp
class TableBuilder {
 public:
  TableBuilder(const Options& options, WritableFile* file);

  TableBuilder(const TableBuilder&) = delete;
  void operator=(const TableBuilder&) = delete;

  ~TableBuilder();

  Status ChangeOptions(const Options& options);

  void Add(const Slice& key, const Slice& value);

  void Flush();

  Status status() const;

  Status Finish();

  void Abandon();

  uint64_t NumEntries() const;

  uint64_t FileSize() const;

 private:
  bool ok() const { return status().ok(); }
  void WriteBlock(BlockBuilder* block, BlockHandle* handle);
  void WriteRawBlock(const Slice& data, CompressionType, BlockHandle* handle);

  struct Rep;
  Rep* rep_;
};
```

这个类的使用方法也很简单明了，构造出实例后调用`Add`向 Table 中写入记录，之后调用`Finish`或者`Abandon`来完成 Table 的构建，再销毁实例。

我们主要关注`Add`这个函数的实现(精简版本)：

```cpp
void TableBuilder::Add(const Slice& key, const Slice& value) {
  Rep* r = rep_;
  if (r->pending_index_entry) {
    // data block为空时才会进入该分支
    r->options.comparator->FindShortestSeparator(&r->last_key, key);
    std::string handle_encoding;
    r->pending_handle.EncodeTo(&handle_encoding);
    r->index_block.Add(r->last_key, Slice(handle_encoding));
    r->pending_index_entry = false;
  }
  r->filter_block->AddKey(key);
  r->last_key.assign(key.data(), key.size());
  r->num_entries++;
  r->data_block.Add(key, value);
  const size_t estimated_block_size = r->data_block.CurrentSizeEstimate();
  Flush();
}
```

这里的代码需要对照 SSTable 的结构来看，这里有一张图：
![](https://leveldb-handbook.readthedocs.io/zh/latest/_images/sstable_logic.jpeg)

SSTable 文件中分为数据块和 meta 块，每个数据块就是具体的 Key-VAlue，meta 块又分成：

- `Filter Block`: 布隆过滤器块，用于加快 Key 的查找
- `Meta Index Block`: 记录`Filter Block`的相关元信息，比如索引数据块偏移和过滤数据块偏移
- `Index Block`: 记录数据块索引
- `Footer`: 其他的 meta 信息

根据以上的代码逻辑，我们可以知道，每次`Add`的过程为：

1. 编码数据
2. 插入索引数据
3. 插入过滤数据
4. 插入数据块

我们将把重点放在 2, 3, 4 步骤上。

插入索引数据和插入 KV 数据都是使用的`BlockBuilder`。

`BlockBuilder`与`TableBuilder`的接口基本一致，因此我们也是主要关注它的`Add`接口。

`Add`的实现如下：

```cpp
void BlockBuilder::Add(const Slice& key, const Slice& value) {
  Slice last_key_piece(last_key_);
  size_t shared = 0;
  const size_t min_length = std::min(last_key_piece.size(), key.size());
  while ((shared < min_length) && (last_key_piece[shared] == key[shared])) {
    shared++;
  }
  const size_t non_shared = key.size() - shared;
  PutVarint32(&buffer_, shared);
  PutVarint32(&buffer_, non_shared);
  PutVarint32(&buffer_, value.size());
  buffer_.append(key.data() + shared, non_shared);
  buffer_.append(value.data(), value.size());
  last_key_.resize(shared);
  last_key_.append(key.data() + shared, non_shared);
  assert(Slice(last_key_) == key);
  counter_++;
}
```

`Index Block`的结构如下图：
![](https://leveldb-handbook.readthedocs.io/zh/latest/_images/indexblock_format.jpeg)

可以看到每一条索引记录存储的实际上是一个`Max Key`，加上偏移与长度。

这里必须要提到的是，LevelDB在存储Key-Value时并不一定会存储完整的`Key`，而是会存储下**与前一条记录的Key不共享的部分**。

`Data Block`的存储方式如下图：
![](https://leveldb-handbook.readthedocs.io/zh/latest/_images/entry_format.jpeg)

举个例子：
* `abc`, `acc`这两个连续的`Key`在存储时，`Unshared key`分别为`abc`和`cc`。

除此之外，LevelDB还有一个`Restart Point`的设计，会每隔几条记录存储一个完整的`Key`。这个记录数的默认值为`16`。

对于索引块的插入，调用方式为`r->index_block.Add(r->last_key, Slice(handle_encoding))`。

这里`r->last_key`的值来源于`r->options.comparator->FindShortestSeparator(&r->last_key, key)`。

`FindShortestSeparator`实际上是一个非常有意思的函数，它的字面意思是找出最短的分隔符。

那么这里的分隔符是什么呢？答案就是`Index Block`中的`Max Key`。

`TableBuilder`并不会在一开始构造时就找出`Max Key`，而是等到下一个`Data Block`的第一个`Key`出现时做这件事。

它会取出前一个`Data Block`的最后一个`Key`，也就是前一个`Data Block`中最大的，与后一个`Data Block`的第一个`Key`的最长公有前缀，并将其后一位的字符+1，作为`Max Key`。

比如说，前一个`Data Block`的最后一个`Key`为`abcd`，后一个`Data Block`的第一个`Key`为`abcf`，那么他们的最长前缀为`abc`，取出的`Max Key`为`abce`(`e`为`d+1`)。

这样以来可以保证前一个`Data Block`中的所有数据都会小于`Max Key`，也不会对后面的`Data Block`产生影响，还节约了存储空间，十分的巧妙。

关于布隆过滤器这里就不再展开讲。

## Major Compaction

看完了`memtable`的`minor compaction`，我们来看看`SSTable`的`major compaction`。

与`minor compaction`不同，`major compaction`的过程比较复杂，它涉及到两个`level`之间有重叠`key`的`SSTable`的合并。

这部分会单独开一篇博客来分析。