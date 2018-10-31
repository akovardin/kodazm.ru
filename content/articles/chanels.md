+++
date = "2018-11-05T20:53:09+03:00"
draft = false
title = "Погружаемся в каналы"
+++

Перевод статьи "[Diving Deep Into The Golang Channels](https://codeburst.io/diving-deep-into-the-golang-channels-549fd4ed21a8)".

В этой статье поговорим о реализации каналов в Go и связанных с ними операциях.

Конкурентность в Go это больше чем просто синтаксис. Это паттерн. Паттерн это способ решения типичных 
проблем при работе с конкурентностью когда необходима синхронизация. 

В Go используется CSP(Communicating Sequential Processes) модель конкуренции и синхронизация достигается через
использование каналов. Главная философия конкурентности в Go выражена одной фразой:

> Не сообщайтесь через разделение памяти. Вместо этого разделяйте память для сообщения.

Go надеется, что вы будете поступать правильно. Поэтому в статье рассмотрим как можно следовать этой философии
используя каналы.

### Что такое каналы

```go
func goRoutineA(a <-chan int) {
    val := <-a
    fmt.Println("goRoutineA received the data", val)
}
func main() {
    ch := make(chan int)
    go goRoutineA(ch)
    time.Sleep(time.Second * 1)
}
```
![](/img/chanels/1.jpeg)
![](/img/chanels/2.jpeg)

Горутины блокируются на каналах до получения сообщения из канала. Канал должен уметь разблокировать рутины.

Небольшое отступлении. Если вы не очень хорошо понимаете как работает планировщик в Go, то вам стоит прочитать эту замечательную статью: ![https://morsmachine.dk/go-scheduler](https://morsmachine.dk/go-scheduler).

### Структура канала

В Go структура канала(channel) это основной способ передачи сообщений между каналами. Как же эта структура
выглядит после инициализации?

```go
ch := make(chan int, 3)
```

```
chan int {
    qcount: 0,
    dataqsiz: 3,
    buf: *[3]int [0,0,0],
    elemsize: 8,
    closed: 0,
    elemtype: *runtime._type {
        size: 8,
        ptrdata: 0,
        hash: 4149441018,
        tflag: tflagUncommon|tflagExtraStar|tflagNamed,
        align: 8,
        fieldalign: 8,
        kind: 130,
        alg: *(*runtime.typeAlg)(0x568eb0),
        gcdata: 1,
        str: 1015,
        ptrToThis: 45376,
    },
    sendx: 0,
    recvx: 0,
    recvq: waitq<int> {
        first: *sudog<int> nil,
        first: *sudog<int> nil,
    },
    sendq: waitq<int> {
        first: *sudog<int> nil,
        first: *sudog<int> nil,
    },
    lock: runtime.mutex {key:0},
}
```

Выглядит неплохо, неплохо. Но что это все значит? И откуда берется эта структура? Давайте рассмотрим несколько
важных типов до того как двигаться дальше.

### hchan

Когда мы пишем `make(chan int, 2)` то создается экземпляр структуры `hchan` с такими полями:

```go
type hchan struct {
	qcount   uint           // total data in the queue
	dataqsiz uint           // size of the circular queue
	buf      unsafe.Pointer // points to an array of dataqsiz elements
	elemsize uint16
	closed   uint32
	elemtype *_type // element type
	sendx    uint   // send index
	recvx    uint   // receive index
	recvq    waitq  // list of recv waiters
	sendq    waitq  // list of send waiters

	// lock protects all fields in hchan, as well as several
	// fields in sudogs blocked on this channel.
	//
	// Do not change another G's status while holding this lock
	// (in particular, do not ready a G), as this can deadlock
	// with stack shrinking.
	lock mutex
}

type waitq struct {
	first *sudog
	last  *sudog
}
```

рассмотрим какие поля что обозначают в этой структуре:

**dataqsize** это размер буфера который мы указали при создании канала.
**elemsize** размер одного элемента в канале
**buf** циклическая очередь(циклический буфер) где сохраняются данные. Используется только в буферизированных каналах.
**closed** индикатор закрытого канала. При создании канала это поле 0. После вызова `close` в это поле устанавливается 1.
**sendx** и **recvx** это поля для сохранения состояния буфера. Они указывают на позиции в массиве откуда должна происходить отправка или куда должны попадать новые данные.
**recvq** и **sendq** очереди заблокированных горутин, которые ожидают отправки в канал или чтение из него.
**lock** все отправки и получения должны быть защищены блокировкой

Пока еще непонятно, что за тип `sudog`^

### sudog

sudog это представление горутины которая стоит в очереди

```go
type sudog struct {
	// The following fields are protected by the hchan.lock of the
	// channel this sudog is blocking on. shrinkstack depends on
	// this for sudogs involved in channel ops.

	g *g

	// isSelect indicates g is participating in a select, so
	// g.selectDone must be CAS'd to win the wake-up race.
	isSelect bool
	next     *sudog
	prev     *sudog
	elem     unsafe.Pointer // data element (may point to stack)

	// The following fields are never accessed concurrently.
	// For channels, waitlink is only accessed by g.
	// For semaphores, all fields (including the ones above)
	// are only accessed when holding a semaRoot lock.

	acquiretime int64
	releasetime int64
	ticket      uint32
	parent      *sudog // semaRoot binary tree
	waitlink    *sudog // g.waiting list or semaRoot
	waittail    *sudog // semaRoot
	c           *hchan // channel
}
```

Давайте немного расширим наш пример с каналом и шаг за шагом посмотрим как он работает. Разберемся что делает его таким мощным инструментом.

```go
func goRoutineA(a <-chan int) {
    val := <-a
    fmt.Println("goRoutineA received the data", val)
}

func goRoutineB(a <-chan int) {
    val := <-a
    fmt.Println("goRoutineB received the data", val)
}

func main() {
    ch := make(chan int)
    go goRoutineA(ch)
    go goRoutineB(ch)
    ch <- 3
    time.Sleep(time.Second * 1)
}
```
Какой теперь станет структура канала? Что поменяется?

```
chan int {
    qcount: 0,
    dataqsiz: 0,
    buf: *[0]int [],
    elemsize: 8,
    closed: 0,
    elemtype: *runtime._type {
        size: 8,
        ptrdata: 0,
        hash: 4149441018,
        tflag: tflagUncommon|tflagExtraStar|tflagNamed,
        align: 8,
        fieldalign: 8,
        kind: 130,
        alg: *(*runtime.typeAlg)(0x568eb0),
        gcdata: 1,
        str: 1015,
        ptrToThis: 45376,
    },
    sendx: 0,
    recvx: 0,
    recvq: waitq<int> {
        first: *(*sudog<int>)(0xc000088000),
        last: *(*sudog<int>)(0xc000088060),
    },
    sendq: waitq<int> {
        first: *sudog<int> nil,
        first: *sudog<int> nil,
    },
    lock: runtime.mutex {key:0},
}
```

Обратите внимание на поля `recvq.first` и `recvq.last`. `recvq` сейчас содержит заблокированные горутины. В нашем примере `goroutineA` и `goroutineB` сначала пытаются читать данные из `ch`. Но там ничего нет пока мы не пошлем в канал первые данные(`ch <- 3`), поэтому горутины блокируются на операции чтения и в поля `recvq.first` и `recvq.last` сетятся объекты типа `sudog` представляющие эти рутины.

По сути `recvq` и `sendq` это связанные списки, которые работают как показано на картинке:

![](/img/chanels/2.jpeg)

Эти структуры играют важную роль в работе каналов. Давайте разберемся, что происходит при отправке данных в канал.

### Отправка в канал

Во время отправки могут возникнуть разные ситуации: отправка в закрытый канал, неинициализированный и так далее. Давайте разберемся со всеми случаями.

#### Отправка в nil канал

```go
if c == nil {
    // ...
    gopark(nil, nil, waitReasonChanSendNilChan, traceEvGoStop, 2)
    throw("unreachable")
}
```

Если мы попытаемся отправить данные в nil канал то горутина приостановит свою работу.

#### Отправка в закрытый канал

```go
if c.closed != 0 {
    unlock(&c.lock)
    panic(plainError("send on closed channel"))
}
```

При отправке в закрытый канал мы получим панику.

#### Горутина блокируется. Данные передаются самой горутине

```go
if sg := c.recvq.dequeue(); sg != nil {
    send(c, sg, ep, func() {unlock(&c.lock)}, 3)
    return true
}
```

В этом месте `recvq`играет очень важную роль. Если в `recvq` нет других рутин, то его можно считать ожидающим получателем и ближайшая операция записи сразу передает значение этому получателю. Это реализовано в функции `send()`.

```go
func send(c *hchan, sg *sudog, ep unsafe.Pointer, unlockf func(), skip int) {
    // ...
    if sg.elem != nil {
        sendDirect(c.elementype, sg, ep)
        sg.elem = nil
    }
    gp := sg.g
    gp.param = unsafe.Pointer(sg)
    if sg.releasetime != 0 {
        ag.releasetime = cputicks()
    }
    goready(gp, skip+1)
}
```

Обратите внимание на `goready(gp, skip+1)`. Горутина которая заблокировалась до получения данных 
продолжит свою работу после вызова `goready` - планировщик снова ее запустит.

#### Отправка в буфферизированный канал когда в буффере еще есть место

