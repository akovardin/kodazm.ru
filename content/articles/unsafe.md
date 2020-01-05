+++
date = "2019-12-07T11:00:00+03:00"
draft = false
title = "Безопасное использование unsafe"
tags = ["golang", "unsafe"]
+++

![](/img/unsafe/main.png)

Перевод "[Safe use of unsafe.Pointer](https://blog.gopheracademy.com/advent-2019/safe-use-of-unsafe-pointer/)"

С помощью пакета `unsafe` можно делать множество интересных хаков без оглядки на систему типов Go. Он дает доступ к низкоуровневому АПИ почти как в C. Но использование `unsafe` - это легкий способ выстрелить себе в ногу, поэтому нужно соблюдать определенные правила. При написании такого кода очень легко совершить ошибку.

В этой статье рассмотрим инструменты, с помощью которых можно проверять валидность использования `unsafe.Pointer` в ваших Go программах. Если у вас нет опыта использования пакета `unsafe`, то я рекомендую почитать [мою прошлую статью](https://blog.gopheracademy.com/advent-2017/unsafe-pointer-and-system-calls/).

<!--more-->

При использовании `unsafe` нужно быть вдвойне внимательным и осторожным. К счастью, есть инструменты, которые помогут обнаружить проблемы до появления критических багов или уязвимостей.

### Проверка на этапе компиляции с помощью go vet

Уже давно существует команда `go vet` с помощью которой можно проверять недопустимые преобразования между типами `unsafe.Pointer` и `uintptr`.

Давайте сразу посмотрим пример. Предположим, мы хотим использовать арифметику указателей, чтобы пробежаться по массиву и вывести все элементы:

```go
package main

import (
    "fmt"
    "unsafe"
)

func main() {
    // An array of contiguous uint32 values stored in memory.
    arr := []uint32{1, 2, 3}

    // The number of bytes each uint32 occupies: 4.
    const size = unsafe.Sizeof(uint32(0))

    // Take the initial memory address of the array and begin iteration.
    p := uintptr(unsafe.Pointer(&arr[0]))
    for i := 0; i < len(arr); i++ {
        // Print the integer that resides at the current address and then
        // increment the pointer to the next value in the array.
        fmt.Printf("%d ", (*(*uint32)(unsafe.Pointer(p))))
        p += size
    }
}
```

На первый взгляд, все выглядит правильным и даже работает как надо. Если запустить программу, то она отработает как надо и выведет на экран содержимое массива.

```
$ go run main.go 
1 2 3
```

Но в этой программе есть скрытый нюанс. Давайте посмотрим, что скажет `go vet`.

```
$ go vet .
# github.com/mdlayher/example
./main.go:20:33: possible misuse of unsafe.Pointer
```

Чтобы разобраться с этой ошибкой, придется [обратиться к документации](https://golang.org/pkg/unsafe/#Pointer) по типу `unsafe.Pointer`

> Преобразование `Pointer` в `uintptr` позволяет получить адрес в памяти для указанного значения в виде простого целого числа. Как правило, это используется для вывода этого адреса.

> Преобразование `uintptr` обратно в `Pointer` в общем случае недопустимо.

> `uintptr` это простое число, не ссылка. Конвертирование `Pointer` в `uintptr` создает простое число без какой либо семантики указателей. Даже если в `uintptr` сохранен адрес на какой либо объект, сборщик мусора не будет обновлять значение внутри `uintptr`, если объект будет перемещен или память будет повторно использована.

Проблема нашей программы в этом месте:

```
p := uintptr(unsafe.Pointer(&arr[0]))

// What happens if there's a garbage collection here?
fmt.Printf("%d ", (*(*uint32)(unsafe.Pointer(p))))
```

Мы сохраняем `uintptr` значение в `p` и не используем его сразу. А это значит, что в момент срабатывания сборщика мусора, адрес сохраненный в `p` станет невалидным, указывающим непонятно куда.

Давайте представим что такой сценарий уже произошел и теперь `p` больше не указывает на `uint32`. Вполне вероятно, что когда мы преобразуем адрес из переменной `p` в указатель, он будет указывать на участок памяти в котором хранятся пользовательские данные или приватный ключ TLS. Это потенциальная уязвимость, злоумышленник сможет получить доступ к конфедициальным данным через stdput или тело HTTP ответа.

Получается, как только мы сконвертировали `unsafe.Pointer` в `uintptr`, то уже нельзя конвертировать обратно в  `unsafe.Pointer`, за исключением одного особого случая:

> Если `p` указывает на выделенный объект, его можно изменить с помощью преобразования в `uintptr`, добавления смещения и обратного преобразования в `Pointer`.

Казалось бы, мы так и делали. Но тут вся хитрость в том, что все преобразования и арифметику указателей нужно делать за один раз:

```go
package main

import (
    "fmt"
    "unsafe"
)

func main() {
    // An array of contiguous uint32 values stored in memory.
    arr := []uint32{1, 2, 3}

    // The number of bytes each uint32 occupies: 4.
    const size = unsafe.Sizeof(uint32(0))

    for i := 0; i < len(arr); i++ {
        // Print an integer to the screen by:
        //   - taking the address of the first element of the array
        //   - applying an offset of (i * 4) bytes to advance into the array
        //   - converting the uintptr back to *uint32 and dereferencing it to
        //     print the value
        fmt.Printf("%d ", *(*uint32)(unsafe.Pointer(
            uintptr(unsafe.Pointer(&arr[0])) + (uintptr(i) * size),
        )))
    }
}
```

Эта программа делает тоже самое, что и в первом примере. Но теперь `go vet` не ругается:

```
$ go run main.go 
1 2 3 
$ go vet .
```

Я не рекомендую использовать арифметику указателей для итераций по массив. Тем не менее, это замечательно, что в Go есть возможность работать на более низком уровне.

### Проверка в рантайме с помощью флага компиятора checkptr

В компилятор Go недавно добавили поддержку [нового флага для дебага](https://go-review.googlesource.com/c/go/+/162237), который инструментирует `unsafe.Pointer` для поиска невалидных вариантов использования во время исполнения. В Go 1.13 эта фича еще не зарелижена, но она уже есть в мастере(gotip в случае с репозиторием Go)

```
$ go get golang.org/dl/gotip
go: finding golang.org/dl latest
...
$ gotip download
Updating the go development tree...
...
Success. You may now run 'gotip'!
$ gotip version
go version devel +8054b13 Thu Nov 28 15:16:27 2019 +0000 linux/amd64
```

Давайте рассмотрим еще один пример. Предположим, мы передаем структуру из Go в ядро Linux чз API, которое работает с C `union` типом. Один из вариантов - использовать Go структуру, в которой содержится необработанный массив байтов(имитирующий сишный `union`). А потом создавать типизированные варианты аргументов.

```go
package main

import (
    "fmt"
    "unsafe"
)

// one is a typed Go structure containing structured data to pass to the kernel.
type one struct{ v uint64 }

// two mimics a C union type which passes a blob of data to the kernel.
type two struct{ b [32]byte }

func main() {
    // Suppose we want to send the contents of a to the kernel as raw bytes.
    in := one{v: 0xff}
    out := (*two)(unsafe.Pointer(&in))

    // Assume the kernel will only access the first 8 bytes. But what is stored
    // in the remaining 24 bytes?
    fmt.Printf("%#v\n", out.b[0:8])
}
```

Когда мы запускаем эту программу на стабильной версии Go (в нашем случае Go 1.13.4), то видим, что в первых 8 байтах в массиве находятся наши `uint64` данные(с обратным порядком байтов на моей машине).

```
$ go run main.go
[]byte{0xff, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0}
```

Но в этой программе тоже есть ошибка. Если запустить ее на версии Go из мастера с указанием флага `checkptr`, то увидим следующее:

```
$ gotip run -gcflags=all=-d=checkptr main.go 
panic: runtime error: unsafe pointer conversion

goroutine 1 [running]:
main.main()
        /home/matt/src/github.com/mdlayher/example/main.go:17 +0x60
exit status 2
```

Это совсем новая проверка и она не дает полной картины что пошло не так. Тем не менее, указание на строку 17 и сообщение "unsafe pointer conversion" дает подсказку где начинать искать.

Преобразовывая маленькую структуру в большую, мы считываем произвольный кусок памяти за пределами маленькой структуры. Это еще один потенциальный способ создать уязвимость в программе.

Чтобы безопасно выполнить эту операцию, перед копированием данных нужно инициализировать структуру `union`. Так мы гарантируем, что произвольная память не будет доступна:

```go
package main

import (
    "fmt"
    "unsafe"
)

// one is a typed Go structure containing structured data to pass to the kernel.
type one struct{ v uint64 }

// two mimics a C union type which passes a blob of data to the kernel.
type two struct{ b [32]byte }

// newTwo safely produces a two structure from an input one.
func newTwo(in one) *two {
    // Initialize out and its array.
    var out two

    // Explicitly copy the contents of in into out by casting both into byte
    // arrays and then slicing the arrays. This will produce the correct packed
    // union structure, without relying on unsafe casting to a smaller type of a
    // larger type.
    copy(
        (*(*[unsafe.Sizeof(two{})]byte)(unsafe.Pointer(&out)))[:],
        (*(*[unsafe.Sizeof(one{})]byte)(unsafe.Pointer(&in)))[:],
    )

    return &out
}

func main() {
    // All is well! The two structure is appropriately initialized.
    out := newTwo(one{v: 0xff})

    fmt.Printf("%#v\n", out.b[:8])
}
```

Если сейчас запустим программу с такими же флагами, то никакой ошибки не будет:

```
$ gotip run -gcflags=all=-d=checkptr main.go 
[]byte{0xff, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0}
```

Можем убрать обрезание слайса в `fmt.Printf` и убедимся, что весь массив заполнен 0.

```go
[32]uint8{
	0xff, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
	0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
	0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
	0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
}
```

Эту ошибку очень легко допустить. Я сам недавно исправлял свою же ошибку [в тестах в пакете](https://github.com/golang/sys/commit/b69606af412f43a225c1cf2044c90e317f41ae09) `x/sys/unix`. Я написал довольно много кода с использованием `unsafe`, но даже опытные программисты могут легко допустить ошибку. Поэтому все эти инструменты для валидации так важны.

### Заключение

Пакет `unsafe` это очень мощный инструмент с острым как бритва краем, которым очень легко отрезать себе пальцы. При взаимодействии с ядром Linux очень часто приходится пользоваться `unsafe`. Очень важно использовать дополнительные инструменты, такие как `go vet` и флаг `checkptr` для проверки вашего кода на безопасность.

Если вам приходится часто использовать `unsafe`, то рекомендую зайти в канал [#darkarts в Gophers Slack](https://invite.slack.golangbridge.org/). В этом канале много ветеранов, которые помогли мне научится эффективно использовать `unsafe` в моих приложениях.

Если у вас остались вопросы, то можете спокойно найти меня в [Gophers Slack](https://gophers.slack.com/), [GitHub](https://github.com/mdlayher) и [Twitter](https://twitter.com/mdlayher).

Особые благодарности:
* [Cuong Manh Le (@cuonglm) ](https://github.com/cuonglm) за подсказку с [модификатором =all для флага checkptr](https://github.com/gopheracademy/gopheracademy-web/pull/332#discussion_r351896035)
* [Miki Tebeka (@tebeka)](https://github.com/tebeka) за ревью этого поста.

### Ссылки

* [Пакет unsafe](https://golang.org/pkg/unsafe/)
* Статья ["Gopher Academy: unsafe.Pointer and system calls"](https://blog.gopheracademy.com/advent-2017/unsafe-pointer-and-system-calls/)
* [cmd/compile: add -d=checkptr to validate unsafe.Pointer rules](https://go-review.googlesource.com/c/go/+/162237)