+++
date = "2019-12-07T11:00:00+03:00"
draft = true
title = "Безопасное использование unsafe.Pointer"
tags = ["golang", "unsafe"]
+++

Перевод "[Safe use of unsafe.Pointer](https://blog.gopheracademy.com/advent-2019/safe-use-of-unsafe-pointer/)"

С помощью пакета `unsafe` можно творить множество интересных хаков без оглядки на систему типов Go. Он дает доступ к низкоуровневому АПИ почти как в C. Но использование `unsafe` - это легкий способ выстрелить себе в ногу, поэтому нужно соблюдать определенные правила. При написании такого кода очень легко совершить ошибку.

В этой статье рассмотрим инструменты, с помощью которых можно проверять валидность использования `unsafe.Pointer` в ваших Go программах. Если у вас нет опыта использования пакета `unsafe`, то я рекомендую почитать [мою прошлую статью](https://blog.gopheracademy.com/advent-2017/unsafe-pointer-and-system-calls/).

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