* Maximum key size is 512MB
* Memcached only has string type
* GETSET returns old value and set new value
* MSET ...values set multi values
* DEL TYPE EXISTS returns 1 for true and 0 for false
* EXPIRE set the duration time, PERSIST make the key eternal, SET key ex 10 set the expires
* Redis LISTS 由链表实现，因为链表的push速度快，并且可以在确定时间内取出确定长度。需要快速访问时使用sorted set
* Redis data structure自动增减的原则：
  1. 当对某个structure添加元素时，如果key不存在，则会被创建
  2. 对某个structure删除元素时，如果structure为空，则自动删除structure
  3. 对一个空的key使用只读的命令，如LLEN，或者使用删除等操作时，结果与对一个空的structure进行的操作一样
* 