+++
date = "2020-07-22T11:00:00+03:00"
draft = false
title = "Пишем хештейбл с дженериками"
tags = ["golang"]
+++

![](/img/hashtable/main.png)

Перевод статьи "[Go generics draft design: building a hashtable](https://mdlayher.com/blog/go-generics-draft-design-building-a-hashtable/)".

В 2018 я реализовал игрушечную хеш таблицу в качестве демонстрации как работает хаш таблица по капотом. В этой реализации ключами были строки и значения тоже были строковыми.

<!--more-->

Через два года после этого, в июне этого года на официальном сайте появилась статья "[The Next Step for Generics](https://blog.golang.org/generics-next-step)" в которой рассказали про черновик дизайна дженериков, основанных на расширении существующих интерфейсах и новой концепции - контрактов. Если вы еще не сделали этого, то я очень рекомендую изучить [черновик нового дизайна](https://go.googlesource.com/proposal/+/refs/heads/master/design/go2draft-type-parameters.md). Я не эксперт в этой теме и могу говорить только исходя из собственного опыта.

В этой статье я опишу урок, который я вынес при портировании свой хещ таблицы с использованием нового дизайна хештаблицы. Можете пропустить введение и сразу перейти к коду хеш таблицы.

## Хеш таблица без дженериков

Мой код мог работать только со ключами строками и значениями строками.

Тип `Table` - основа всего пакета. Пара ключ/значение сохраняется в слайсе. Таблица разделена на бакеты. Количество бакетов определяется значением `m`:

- Если задать `m` слишком маленьким, то бакетов будет не много. Но тогда будет очень много коллизий и поиск значений замедлится.
- При большом `m` будет много бакетов, поиск по каждому ключу будет быстрым.

Тип `kv` - небольшой хелпер для хранения строковых пар ключ/значение.

```go
// Package hashtable implements a basic hashtable for string key/value pairs.
package hashtable

// A Table is a basic hashtable.
type Table struct {
	m     int
	table [][]kv
}

// A kv stores key/value data in a Table.
type kv struct {
	Key, Value string
}

// New creates a Table with m internal buckets.
func New(m int) *Table {
	return &Table{
		m:     m,
		table: make([][]kv, m),
	}
}
```

Хеш таблица поддерживает две операции:

- `Get` - возвращает значение, если ключ есть в таблице и булевое значение(`true` - если ключ существует)
- `Insert` - вставляет пару ключ/значение в хеш таблицу, перезаписывает значение, если оно там уже есть.

Оба этих метода используют функцию хеширования, которая принимает строку и возвращает целое число, которое определяет в какой бакет попадет значение.

```go
// hash picks a hashtable index to use to store a string with key s.
func (t *Table) hash(s string) int {
	h := fnv.New32()
	h.Write([]byte(s))
	return int(h.Sum32()) % t.m
}
```

Я выбрал `hash/fnv32` как простую не криптографическую хеш функцию, которая возвращает целое число. После вычисления хеша, получаем индекс бакета с помощью деления по модулю `hash % t.m`

Начнем с кода `Go`:

```go
// Get determines if key is present in the hashtable, returning its value and
// whether or not the key was found.
func (t *Table) Get(key string) (string, bool) {
    // Hash key to determine which bucket this key's value belongs in.
	i := t.hash(key)

	for j, kv := range t.table[i] {
		if key == kv.Key {
            // Found a match, return it!
			return t.table[i][j].Value, true
		}
	}

    // No match.
	return "", false
}
```

Первым делом вычисляем хеш ключа, переданного в параметре. Определяем бакет, который будет использоваться для сохранения ключа. Как только определяемся с бакетом - итерируемся по всем значениями в бакете и проверяем соответствие с нашим ключем.

Если ключ совпадает с одним из ключей в бакете, то возвращается значение и `true`

Если совпадение не найдено, то возвращается пустая строка и `false`

Теперь разберемся с `Insert`:

```go
// Insert inserts a new key/value pair into the Table.
func (t *Table) Insert(key, value string) {
	i := t.hash(key)

	for j, kv := range t.table[i] {
		if key == kv.Key {
			// Overwrite previous value for the same key.
			t.table[i][j].Value = value
			return
		}
	}

	// Add a new value to the table.
	t.table[i] = append(t.table[i], kv{
		Key:   key,
		Value: value,
	})
}
```

Метод `Insert` также использует ключ, чтобы определить какой бакет использовать и куда вставлять новую пару ключ/значение. 

Перебирая пары ключ/значения в бакете, может оказаться, что ключ уже есть. В этом случае перезаписывается значение.

Если ключа нет, то новая пара добавляется в слайс.

На этом все. Это очень базовая хеш таблица которая работает со строками.

```go
// 8 buckets ought to be plenty.
t := hashtable.New(8)
t.Insert("foo", "bar")
t.Insert("baz", "qux")

v, ok := t.Get("foo")
fmt.Printf("t.Get(%q) = (%q, %t)", "foo", v, ok)
// t.Get("foo") = ("bar", true)
```

Теперь попробуем использовать дженерики для хеш таблицы

## Хеш таблица на дженериках

Наша цель - переделать существующий код для работы с произвольными парами ключ значение. У нас одно ограничение: ключи в таблице должны [соответствовать предопределенному ограничению `comparable`](https://go.googlesource.com/proposal/+/refs/heads/master/design/go2draft-type-parameters.md#comparable-types-in-constraints), чтобы у нас была возможность проверить равенство.

```go
// Package hashtable implements a basic hashtable for generic key/value pairs.
package hashtable

// A Table is a basic generic hashtable.
type Table(type K comparable, V interface{}) struct {
    // hash is a function which can hash a key of type K with t.m.
    hash func(key K, m int) int

	m     int
	table [][]kv
}

// A kv stores generic key/value data in a Table.
type kv(type K comparable, V interface{}) struct {
	Key   K
	Value V
}

// New creates a table with m internal buckets which uses the specified hash
// function for an input type K.
func New(type K comparable, V interface{}) (m int, hash func(K, int) int) *Table(K, V) {
	return &Table(K, V){
		hash:  hash,
        m:     m,
        // Note the parentheses around "kv(K, V)"; these are required!
		table: make([][](kv(K, V)), m),
	}
}
```

Для универсальных типов нужно использовать списки параметров типа. Каждый из этих типов и функций верхнего уровня должен иметь список параметров типа для `K` и `V`. Типы, которые будут использоваться для `K`, должны соответствовать `comparable`. Для `V` может использоваться любой тип.

Я узнал несколько нюансов, пока писал этот код:

- Функция хеширования `func(K, int) int` теперь отдельный параметр конструктора `New`. Необходимо знать как хешировать разные типы. Я мог бы завести простой интерфейс `Hash() int`, но нужно чтобы код работал со стандартными типами `string` и `int`. 
- Я завис на создании пустого параметризированного слайса с помощью `make()` для поля `Table.table`. Изначально я пытался сделать это так `make([][]kv(K, V))`. Оказалось, все не так просто.

Время для реализации `Get`:

```go
// Get determines if key is present in the hashtable, returning its value and
// whether or not the key was found.
func (t *Table(K, V)) Get(key K) (V, bool) {
    // Hash key to determine which bucket this key's value belongs in.
    // Pass t.m so t.hash can perform the necessary operation "hash % t.m".
    i := t.hash(key, t.m)

    for j, kv := range t.table[i] {
        if key == kv.Key {
            // Found a match, return it!
            return t.table[i][j].Value, true
        }
    }

    // No match. The easiest way to return the zero-value for a generic type
    // is to declare a temporary variable as follows.
    var zero V
    return zero, false
}
```

Для метод обобщенного типа нужно указывать параметр типа в ресейвере. В нашем примере, метод `Get` может принимать любой тип `K` возвращает тип `V` и `bool` для индикации есть ли значение. 

За исключением изменений в приемнике и нескольких обобщенных `K` и `V`, метод выглядит как обычный Go код, что радует.

Еще одна хитрость - обработка [нулевых значений для обобщенных типов](https://go.googlesource.com/proposal/+/refs/heads/master/design/go2draft-type-parameters.md#the-zero-value). По ссылке рекомендуется делать как в примере `var zero V`. Возможно, в будущем этот момент станет проще. Я бы хотел что-то такое `return _, false`, что будет работать и для обычного кода и для обобщенного.

Перейдем к методу `Insert`

```go
// Insert inserts a new key/value pair into the Table.
func (t *Table(K, V)) Insert(key K, value V) {
	i := t.hash(key, t.m)

	for j, kv := range t.table[i] {
		if key == kv.Key {
            // Overwrite previous value for the same key.
			t.table[i][j].Value = value
			return
		}
	}

	// Add a new value to the table.
	t.table[i] = append(t.table[i], kv(K, V){
		Key:   key,
		Value: value,
	})
}
```
Тут понадобилось совсем немного кода для обобщения этого метода.

- Ресейвер метода теперь `*Table(K, V)` вместо `*Table`
- Метод принимает `(key K, value V)` вместо `(key, value string)`
- Структура `kv{}` теперь определяется как `kv(K, V){}`

И на этом с переделкой все! Теперь у нас есть обобщенный тип хештаблицы, который может принимать любые ключи, которые соответствуют `comparable` ограничениям.

## Использование хештаблицы на дженериках 

Для тестирования этого кода, я собираюсь две параллельные хештаблицы, которые взаимодействуют как индекс и обратный индекс между строковыми и числовыми типами.

```go
t1 := hashtable.New(string, int)(8, func(key string, m int) int {
	h := fnv.New32()
	h.Write([]byte(key))
	return int(h.Sum32()) % m
})

t2 := hashtable.New(int, string)(8, func(key int, m int) int {
	// Good enough!
	return key % m
})
```

В момент вызова конструктора `New` определяем параметры типа для `K` и `V`.  Для примера, `t1` это `Table(string, int)`, где `K = string` and `V = int`. `t2` это реверс `Table(int, string)`. Оба типа `int` и `string` соответствуют ограничению `comparable`.

Чтобы хешировать наши обобщенные данные, необходимо реализовать функцию хеширования, которая работает с `K` и `t.m` и генерирует значения типа `int`. Для `t1` мы переиспользуем `hash/fnv` из оригинального примера. Для `t2` достаточно операции получения по модулю.

Я понимаю, что в большинстве случаев компилятор Go должен иметь возможность определять правильные типы для универсальных типов(`K` и `V`) при вызовах вида `hashtable.New`, но я продолжу писать их явно, чтобы привыкнуть к такому дизайну.

Теперь у нас есть две таблицы - индекс и обратный индекс. Давайте их заполним:

```go
strs := []string{"foo", "bar", "baz"}
for i, s := range strs {
	t1.Insert(s, i)
	t2.Insert(i, s)
}
```

Каждая пара ключ/значение в таблице `t1` имеет свое отражение значение/ключ в таблице `t2`. Можем проитерироваться по строкам и их индексам для демонстрации нашего кода в действии.

```go
for i, s := range append(strs, "nope!") {
	v1, ok1 := t1.Get(s)
	log.Printf("t1.Get(%v) = (%v, %v)", s, v1, ok1)

	v2, ok2 := t2.Get(i)
	log.Printf("t2.Get(%v) = (%v, %v)\n\n", i, v2, ok2)
}
```

Вывод [демо программы](https://go2goplay.golang.org/p/XsN2CdNieyM):

```
t1.Get(foo) = (0, true)
t2.Get(0) = (foo, true)

t1.Get(bar) = (1, true)
t2.Get(1) = (bar, true)

t1.Get(baz) = (2, true)
t2.Get(2) = (baz, true)

t1.Get(nope!) = (0, false)
t2.Get(3) = (, false)
```

Готово, мы реализовали обобщенную хештаблицу.

Я хочу провести побольше экспериментов, чтобы лучше разбираться в новом функционале дженериков. Если вы хотите побольше узнать побольше - загляните в [блог Go](https://blog.golang.org/generics-next-step) и новый [черновик по дженерикам](https://go.googlesource.com/proposal/+/refs/heads/master/design/go2draft-type-parameters.md).

Если у вас есть вопросы или комментарии, можете найти [меня в Twitter](https://twitter.com/mdlayher) или [Slack(@mdlayher)](https://invite.slack.golangbridge.org/). Иногда я делаю стримы по Go на Twitch.

## Бонус: "дженерик" хеш функция

После реализации этой хештаблицы, у меня была интересная инструкция в канале #performance в Gophers Slack как во время выполнения получить доступ к "универсальной" функции хеширования, которая используется встроенными таблицами в Go.

@zeebo в Gophers Slack предложил это забавное, ужасающее, и блестящее решение:

```go
unc hash(type A comparable)(a A) uintptr {
	var m interface{} = make(map[A]struct{})
	hf := (*mh)(*(*unsafe.Pointer)(unsafe.Pointer(&m))).hf
	return hf(unsafe.Pointer(&a), 0)
}

func main() {
	fmt.Println(hash(0))
	fmt.Println(hash(false))
	fmt.Println(hash("why hello there"))
}

///////////////////////////
/// stolen from runtime ///
///////////////////////////

// mh is an inlined combination of runtime._type and runtime.maptype.
type mh struct {
	_  uintptr
	_  uintptr
	_  uint32
	_  uint8
	_  uint8
	_  uint8
	_  uint8
	_  func(unsafe.Pointer, unsafe.Pointer) bool
	_  *byte
	_  int32
	_  int32
	_  unsafe.Pointer
	_  unsafe.Pointer
	_  unsafe.Pointer
	hf func(unsafe.Pointer, uintptr) uintptr
}
```

Этот код использует факт, что интерфейс в Go, на самом деле, является кортежем из типа данных времени выполнения и указателем на тип. Получив доступ к этому указателю и используя `unsafe` и приведения его к представлению мапы во время выполнения (которая имеет поле c функцией хеширования), мы можем создать универсальную функцию хеширования для использования в нашем собственном коде!
