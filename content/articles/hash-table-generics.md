+++
date = "2020-07-22T11:00:00+03:00"
draft = true
title = "Пишем хештейбл с дженериками"
tags = ["golang"]
+++

Перевод статьи "[Go generics draft design: building a hashtable](https://mdlayher.com/blog/go-generics-draft-design-building-a-hashtable/)".

В 2018 я реализовал игрушечную хеш таблицу в качестве демонстрации как работает хаш таблица по капотом. В этой реализации ключами были строки и значения тоже были строковыми.

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

