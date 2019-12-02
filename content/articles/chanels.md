+++
date = "2018-11-01T20:53:09+03:00"
draft = false
title = "Погружаемся в каналы"
+++

![](/img/channels/main.png)

Перевод статьи "[Diving Deep Into The Golang Channels](https://codeburst.io/diving-deep-into-the-golang-channels-549fd4ed21a8)".

В этой статье поговорим о реализации каналов в Go и связанных с ними операциях.

Конкурентность в Go это больше чем просто синтаксис. Это паттерн. Паттерн это способ решения типичных 
проблем при работе с конкурентностью когда необходима синхронизация. 

<!--more-->

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
![](/img/channels/1.jpeg)
![](/img/channels/2.jpeg)

Горутины блокируются на каналах до получения сообщения из канала. Канал должен уметь разблокировать рутины.

Небольшое отступлении. Если вы не очень хорошо понимаете как работает планировщик в Go, то вам стоит прочитать эту замечательную статью: [https://morsmachine.dk/go-scheduler](https://morsmachine.dk/go-scheduler).

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
        gcdata: *1,
        str: 1015,
        ptrToThis: 45376,
    },
    sendx: 0,
    recvx: 0,
    recvq: waitq<int> {
        first: *sudog<int> nil,
        lsat: *sudog<int> nil,
    },
    sendq: waitq<int> {
        first: *sudog<int> nil,
        last: *sudog<int> nil,
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

Пока еще непонятно, что за тип `sudog`.

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
        gcdata: *1,
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
        last: *sudog<int> nil,
    },
    lock: runtime.mutex {key:0},
}
```

Обратите внимание на поля `recvq.first` и `recvq.last`. `recvq` сейчас содержит заблокированные горутины. В нашем примере `goroutineA` и `goroutineB` сначала пытаются читать данные из `ch`. Но там ничего нет пока мы не пошлем в канал первые данные(`ch <- 3`), поэтому горутины блокируются на операции чтения и в поля `recvq.first` и `recvq.last` сетятся объекты типа `sudog` представляющие эти рутины.

По сути `recvq` и `sendq` это связанные списки, которые работают как показано на картинке:

![](/img/channels/3.jpeg)

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

```go
if c.qcount < c.dataqsiz {
    // Space is available in the channel buffer. Enqueue the element to send.
    qp := chanbuf(c, c.sendx)
    if raceenabled {
        raceacquire(qp)
        racerelease(qp)
    }
    typedmemmove(c.elemtype, qp, ep)
    c.sendx++
    if c.sendx == c.dataqsiz {
        c.sendx = 0
    }
    c.qcount++
    unlock(&c.lock)
    return true
}
```

`chanbuf(c, i)` - доступ к нужному куску памяти. Чтобы определить есть ли свободное место сравниваем `qcount` и `dataqsiz`. Елемент ставится в очередь через копирование памяти на которую указывает `ep` в буффер и нкремент счетчика `sendx`

#### Отправка в канал с заполненным буффером

```go
// Block on the channel. Some receiver will complete our operation for us.
gp := getg()
mysg := acquireSudog()
mysg.releasetime = 0
if t0 != 0 {
    mysg.releasetime = -1
}
// No stack splits between assigning elem and enqueuing mysg
// on gp.waiting where copystack can find it.
mysg.elem = ep
mysg.waitlink = nil
mysg.g = gp
mysg.isSelect = false
mysg.c = c
gp.waiting = mysg
gp.param = nil
c.sendq.enqueue(mysg)
goparkunlock(&c.lock, waitReasonChanSend, traceEvGoBlockSend, 3)
```
Получаем объек горутины в текущем стеке. С помощью `acquireSudog` паркуем горутину и добавлем ее `sendq` канала.

#### Отправка в канал. Вводы

* Внутри канала активно используется структура `lock`
* Запись может происходить напрямую через выбор ожидающей горутины из `recvq` и передачу сообщения непосредственно ей.
* Если очередт с горутинами пустая, то пытаемся записать сообщение в буффер если он доступен и там есть место. Запись происходит через копирование данных из горутины в буфер.
* Если буфер заполнен, то данные сохраняются в структуре текущей горутины и горутина блокируется и ставится в очередь `sendq`

Обратите внимание на последний пункт. Это актуально для небуферезированных каналов, даже если к них есть полу `buf`. При отправке сообщения в такой канал оно сохранится в поле `elem` структуры `sudog`.

Давайте рассмотрим еще один пример:

```go
package main

func goroutineA(c2 chan int) {
    c2 <- 2
}

func main() {
    c2 := make(chan int)
    go goroutineA(c2)

    for {
    }
}
```

Как выглядит структура `c2` в рантайме?

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
        alg: *(*runtime.typeAlg)(0x4bff90),
        gcdata: *1,
        str: 775,
        ptrToThis: 28320,
    },
    sendx: 0,
    recvx: 0,
    recvq: waitq<int> {
        first: *sudog<int> nil,
        last: *sudog<int> nil,
    },
    sendq: waitq<int> {
        first: *(*sudog<int>)(0xc000074000),
        last: *(*sudog<int>)(0xc000074000),
    },
    lock: runtime.mutex {key:0},
}
```

Видно что когда мы отправляем в канал новое значение `2`, оно не попадает в буфер. Это значение
сохраняется в структуре `sudog`. Когда горутина `goroutineA` пытается отправить сообщение в канал - еще нет нт одного получателя. Горутина попадает в список `sendq` и блокируется. Можно посмотреть как выглядит структура `sendq` в рантайме:

```
p c2.sendq
waitq<int> {
    first: *sudog<int> {
        g: *(*runtime.g)(0xc000001080),
        isSelect: false,
        next: *runtime.sudog nil,
        prev: *runtime.sudog nil,
        elem: 2,
        acquiretime: 0,
	    releasetime 0,
        ticket: 0,
        parent: *runtime.sudog nil,
        waitlink: *runtime.sudog nil,
        waittail: *runtime.sudog nil,
        c: *(*runtime.hchan)(0xc00001e120),
    }
}
```
Все значения в канал передаются по значению. Это важно запомнить. Давайте расмотрим такой пример.

```go
type user struct {
    name string
    age int8
}

var u = user{name:"Anku", age:25}
var g := &g

func modifyUser(pu *user) {
    fmt.Println("modifyUser Receive Value", pu)
    ou.name = "Anand"
}

func printUser(u <-chan *user) {
    time.Sleep(2 * time.Second)
    fmt.Println("printUser goroutine called", <-u)   
}

func main() {
    c := make(chan *user, 5)
    c <- g
    fmt.Println(g)
    // modify g
    g := &user{name: "Ankur Anand", age:100}
    go printUser(c)
    go modifyUser(g)
    time.Sleep(time.Second * 5)
    fmt.Println(g)
}
```

Что выведет эта программа? Значения передаются через копирование. В нашем случае в канал будет скопировано значение `g`. 

> Не сообщайтесь через разделение памяти. Вместо этого разделяйте память для сообщения

Вот что выведет программа:

```
&{Ankur 25}
modifyUser Received Value &{Ankur Anand 100}
printUser goRoutine called &{Ankur 25}
&{Anand 100}
```

![](/img/channels/4.jpeg)

### Операции чтения из канала

Операция чтения очень похожа на запись.

```go
func chanrecv(c *hchan, ep unsafe.Pointer, block bool) (selected, received bool) {
	// raceenabled: don't need to check ep, as it is always on the stack
	// or is new memory allocated by reflect.

	if debugChan {
		print("chanrecv: chan=", c, "\n")
	}

	if c == nil {
		if !block {
			return
		}
		gopark(nil, nil, waitReasonChanReceiveNilChan, traceEvGoStop, 2)
		throw("unreachable")
    }
    // ...
    lock(&c.lock)

	if c.closed != 0 && c.qcount == 0 {
		if raceenabled {
			raceacquire(c.raceaddr())
		}
		unlock(&c.lock)
		if ep != nil {
			typedmemclr(c.elemtype, ep)
		}
		return true, false
	}

	if sg := c.sendq.dequeue(); sg != nil {
		// Found a waiting sender. If buffer is size 0, receive value
		// directly from sender. Otherwise, receive from head of queue
		// and add sender's value to the tail of the queue (both map to
		// the same buffer slot because the queue is full).
		recv(c, sg, ep, func() { unlock(&c.lock) }, 3)
		return true, true
	}

	if c.qcount > 0 {
        qp := chanbuf(c, c.recvx)
        //...
        if ep != nil {
			typedmemmove(c.elemtype, ep, qp)
		}
		typedmemclr(c.elemtype, qp)
		c.recvx++
		if c.recvx == c.dataqsiz {
			c.recvx = 0
		}
		c.qcount--
		unlock(&c.lock)
		return true, true
    }
    // ...
    // no sender available: block on this channel.
	gp := getg()
	mysg := acquireSudog()
	mysg.releasetime = 0
	if t0 != 0 {
		mysg.releasetime = -1
	}
	// No stack splits between assigning elem and enqueuing mysg
	// on gp.waiting where copystack can find it.
	mysg.elem = ep
	mysg.waitlink = nil
	gp.waiting = mysg
	mysg.g = gp
	mysg.isSelect = false
	mysg.c = c
	gp.param = nil
	c.recvq.enqueue(mysg)
    goparkunlock(&c.lock, waitReasonChanReceive, traceEvGoBlockRecv, 3)
    // ...
}
```

### Select

Объединение нескольких каналов.

```go
ch := make(chan int, 5)
chs := make(chan string, 5)
select {
    case msg := <- ch:
        fmt.Println("receive message", msg)
    case msgs := <- chs:
        fmt.Println("receive message", msgs)
    default:
        fmt.Println("no message received")
}
```

Операции взаимно исключающие. Значит, нам нужно использовать блокировку всех используемых в селекте каналов. Блокировки приобретаются в зависимости от текущего кейса, а это значит что каналы блокируются не одновременно.

```
sellock(scases, lockorder)
```

Каждый `scase` в массиве `scases` это структура, которая содержит данные по операции в текущем кейсе и канал, для которого эта операция будет выполнятся.

```go
type scase struct {
    c           *hchan
    elem        unsafe.Pointer
    kind        uint16
    pc          uintptr
    releasetime int64
}
```

`kind` это тип операции в кейсе и он может быть `CaseRecv`, `CaseSend` и `CaseDefault`.

Порядок опроса расчитывается так чтобы задействовать каналы в псевдо случайном порядке. После этого каналы опрашиваются в расчитаном порядке. То как в каком порядке вы напишете кейсы в программе не имеет значения.

Генерация порядка опроса:

```go
for i := 1; i < ncases; i++ {
    j := fastrandn(uint32(i+1))
    pollorder[i] = pollorder[j]
    pollorder[j] = uint16(i)
}
```

Непосредственно проход по очереди опроса:

```go
for i := 0; i < ncases; i++ {
    casi = int(pollorder[i])
    cas = &scases[casi]
    c = cas.c

    switch cas.kind {
    case caseNil:
        continue

    case caseRecv:
        sg = c.sendq.dequeue()
        if sg != nil {
            goto recv
        }
        if c.qcount > 0 {
            goto bufrecv
        }
        if c.closed != 0 {
            goto rclose
        }

    case caseSend:
        if raceenabled {
            racereadpc(c.raceaddr(), cas.pc, chansendpc)
        }
        if c.closed != 0 {
            goto sclose
        }
        sg = c.recvq.dequeue()
        if sg != nil {
            goto send
        }
        if c.qcount < c.dataqsiz {
            goto bufsend
        }

    case caseDefault:
        dfli = casi
        dfl = cas
    }
}
```

`select` может сработать без блокировки если в канале еть данные. Даже без прохода по всем каналам.

Если нет ни одного готового канала и кейса `default` то горутина `g` блокируется попадает в очередь доступности одного из каналов.

```go
gp = getg()
// ...
for _, casei := range lockorder {
    casi = int(casei)
    cas = &scases[casi]
    if cas.kind == caseNil {
        continue
    }
    c = cas.c
    sg := acquireSudog()
    sg.g = gp
    sg.isSelect = true
    // ...
    switch cas.kind {
    case caseRecv:
        c.recvq.enqueue(sg)

    case caseSend:
        c.sendq.enqueue(sg)
    }
}
```

Поле `ag.isSelect` указывает что горутина участвует в селекте

Операции получения, отправки и закрытия в селекте аналогичны обычным операциям получения, отправки и закрытия.

### Заключение

Каналы это очень мощный и интересный механизм в Go. Но чтобы правильно их использовать нужно знать как они устроены. Надеюсь что в этой статье удалось опиать базовые принципы работы каналов.