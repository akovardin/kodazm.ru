+++

date = "2018-10-13T19:45:02+03:00"
draft = false
title = "Strace в 60 строчек код"

+++

![](/img/syscall/title.png)

Перевод статьи Liz Rice "[Strace in 60 lines of Go](https://hackernoon.com/strace-in-60-lines-of-go-b4b76e3ecd64)".

Эта статья написана по мотивам моего доклада "[A Go Programmer’s Guide to Syscalls](https://gophercon.com/speakers/27)". Вы можете посмотреть код [тут](http://github.com/lizrice/strace-from-scratch).

Чтобы объяснить некоторые моменты работы [линуксовского ptrace](http://man7.org/linux/man-pages/man2/ptrace.2.html я решила написать свою базовую реализацию [strace](http://man7.org/linux/man-pages/man1/strace.1.html). И в этой статье я расскажу, как этот самодельный strace работает. Если у вас есть время, то можете посмотреть видео того самого доклада:

<iframe width="935" height="630" src="https://www.youtube.com/embed/01w7viEZzXQ?start=11" frameborder="0" allow="autoplay; encrypted-media" allowfullscreen></iframe>

### Брекпоинт в процессе потомке

Наша программа перехватывает все сисколы которые были вызваны в процессе работы любой команды, которую мы указываем через аргументы. Для вызова заданной команды используется `exec.Command()`. Указываем что хотим использовать ptrace в дочернем процессе: в настройках `SysProcAttr` сетим `Ptrace: true`. Ниже пример кода который будет у нас в `main()` функции:

```go
fmt.Printf("Run %v\n", os.Args[1:])
cmd := exec.Command(os.Args[1], os.Args[2:]...)
cmd.Stderr = os.Stderr
cmd.Stdin = os.Stdin
cmd.Stdout = os.Stdout
cmd.SysProcAttr = &syscall.SysProcAttr{
    Ptrace: true,
}
cmd.Start()
err := cmd.Wait()
if err != nil {
    fmt.Printf("Wait returned: %v\n", err)
}
```

Эти настройки нужны для перевода процесса потомока в брейкпоинт состояние как только он будет создан. Если мы сейчас запустим этот код, то `cmd.Wait()` завершится с ошибкой.

```
root@vm-ubuntu:myStrace# ./myStrace echo hello
Run [echo hello]
Wait returned: stop signal: trace/breakpoint trap
root@vm-ubuntu:myStrace# hello
```

Видно что повился текст hello. Это кажется странным, потому что мы просто перевели дочернй процесс в брейкпоинт состояние. Если добавить небольшую задержку перед `cmd.Wait()`, то станет видно что это происходит только после завершения родительского процесса. Родительский процесс переводит своего потомка в брейкпоинт состояние, но после завершения родителя уже ничего не "удерживает" дочерний процесс и он продолжает работу печатая слово hello.

### Узнаем сискол через реестр дочернего процесса

Теперь нам нужно получить реест для дочернего процесса. Напомню, что пид запущенного процесса можно получить из `cmd.Process.Pid`. А для доступа к реестру нужно использовать ptrace команду PTRACE_GETREGS. Go-шный пакет syscall неплохо упрощает нам жизнь предоставляя функции для большого количества ptrace команд:

```go
pid = cmd.Process.Pid
err = syscall.PtraceGetRegs(pid, &regs)
```

На выходе мы получаем структуру в которой есть информация о всем реестре дочернего процесса. На моем x86 CPU идентификатор сискола указан в поле `Orig_rax`. Можем получить немного больше информации:

```go
name, _ := sec.ScmpSyscall(regs.Orig_rax).GetName()
fmt.Printf("%s\n", name)
```

`sec` это алиас для пакета `seccomp/libseccomp-golang`

### Получаем следующий сискол

Теперь "отпускаем" программу до момента следующего сискола. Для этого используем ptrace команду PTRACE_SYSCALL. И в пакете syscall уже есть готовая функция:

```go
err = syscall.PtraceSyscall(pid, 0)
```

Мы должны дождаться SIGTRAP

```go
_, err = syscall.Wait4(pid, nil, 0, nil)
```

### И повторить

Сейчас нам снова нужно прочитать реестр, узнать название следующего сискола и потом опять "отпустить" программу до следующего сискола и так далее в цикле.

Но нам нужно понять когда пора остановиться. В своей простой реализации я останавливаюсь, когда `PtraceGetRegs` возвращает ошибку. Из текста ошибки видно что она возникает когда не получается прочитать данные из несуществующего процесса, что логично, так как наш дочерний процесс уже завершен.

### Нюанс 

Если запустить текущую версию нашей программы, то сисколы будут выводиться по два раза. Это происходит из-за PTRACE_SYSCALL который останавливает программу дважды: до и после вызова сискола. Вот более подробное описание:

![](/img/syscall/syscall.png)

Поэтому пришлось добавить переменную `exit` чтобы пропусакть повторные сисколы в цикле. Ниже код который выводит уже по одному сисколу:

```go
for {
    if exit {
        err = syscall.PtraceGetRegs(pid, &regs)
        if err != nil {
            break
        }
        name, _ := sec.ScmpSyscall(regs.Orig_rax).GetName()
        fmt.Printf("%s\n", name)
    }
    err = syscall.PtraceSyscall(pid, 0)
    if err != nil {
        panic(err)
    }
    _, err = syscall.Wait4(pid, nil, 0, nil)
    if err != nil {
        panic(err)
    }
    exit = !exit
}
```

###Статистика по сисколам

Для подсчета количества вызовов сисколов было написано немного [вспомогательного кода](https://github.com/lizrice/strace-from-scratch/blob/master/syscallcounter.go).

### Заключение

Наша небольшая утилита работает очень похоже на обычный `strace`. Результаты которая выдает наш код и `strace -c`  для команды `echo hello` практически одинаковые - в обоих случаях список сисколов одинаковый.

<script src="https://asciinema.org/a/TcEvXJvxXS6YyzCtowWpOfq6z.js" id="asciicast-TcEvXJvxXS6YyzCtowWpOfq6z" async></script>

<a href="https://asciinema.org/a/TcEvXJvxXS6YyzCtowWpOfq6z" target="_blank"><img src="https://asciinema.org/a/TcEvXJvxXS6YyzCtowWpOfq6z.png" /></a>

В конечной реализации выводятся параметры для каждого сискола. Если вы тоже хотите это реализовать, то вам нужно получать чуть [больше информации из реестра](http://syscalls.kernelgrok.com/).

В докладе было показано как можно использовать [seccomp security module](http://blog.aquasec.com/new-docker-security-features-and-what-they-mean-seccomp-profiles) для предотвращения вызова определенных сисколов. Вы можеет попробовать тоже самое раскоментив `disallow()`. Но это все просто как идея, я не призываю писать продакшен код, который будет решать, какой сискол нужен, а какой нет. Если вам понравилась идея с  "песочницей" для приложения, то можете [посмотреть доклад](https://www.google.co.uk/url?sa=t&rct=j&q=&esrc=s&source=web&cd=1&cad=rja&uact=8&ved=0ahUKEwitiNyuipDVAhXrAMAKHYl5BqMQtwIIKzAA&url=https%3A%2F%2Fwww.youtube.com%2Fwatch%3Fv%3DBuFTHOgsgAY&usg=AFQjCNEvLzasIbNnh-u61pkQJtH6rssj7Q) от [Jessie Frazelle](https://medium.com/@jessfraz).

Огромное спасибо [@nelhage](https://medium.com/@nelhage) с докладом [implementation of strace in C](https://blog.nelhage.com/2010/08/write-yourself-an-strace-in-70-lines-of-code/) и [Michał Łowicki](https://medium.com/@mlowicki) с докладом [deep dives into making a debugger in Go](https://medium.com/golangspec/making-debugger-for-golang-part-i-53124284b7c8)  за вдохновение и информацию. и не меньшее спасибо каждому гофреу на Gophercon.