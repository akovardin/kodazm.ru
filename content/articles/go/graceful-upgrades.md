+++
date = "2018-10-29T20:53:09+03:00"
draft = false
title = "Бесшовное обновление"
+++

![](/img/upgrade/main.png)

Перевод статьи "[Graceful upgrades in Go](https://blog.cloudflare.com/graceful-upgrades-in-go/)"

Идея бесшовного обновления заключается в смене конфигурации и кода процесса пока он запущен, так что никто ничего не заметил. Если вам кажется что этот способ небезопасный, нежелательный и подверженный ошибкам - то я в целом я с вами согласен. Но иногда вам нужна такая функциональность. Такое часто случается если у вас нет балансера перед вашим приложением. Такой подход используется в Cloudflare и нам пришлось реализовать целый набор различных решений вокруг этой проблемы.

<!--more-->

Оказалось что для решение этой задачи нужно немного низкоуровневого программирования и это реально затягивает. В этой статье вы узнаете на какие компромиссы нам пришлось пойти и почему вам стоит использовать нашу опенсорсную либу. Для нетерпеливых ссылка на [гитхаб](https://github.com/cloudflare/tableflip) и на [документацию](https://godoc.org/github.com/cloudflare/tableflip).

### Основы

Что это вообще такое бесшовное обновление для процесса? К примеру, есть некоторый сферический ыеб-сервер. Мы хотим отправлять к нему запросы и никогда не получать ошибки потому что он умеет бесшовно обновляться. 

Мы знаем, что HTTP использует TCP под капотом, а с TCP мы взаимодействуем через BSD сокеты. Мы говорим OS что хотим принимать соединения на 80 порт и OS предоставляет нам сокет на прослушивание, затем мы вызываем `Accept()` и ожидаем новых клиентов.

Мы не сможем обслужить клиентов если OS не будет знать о прослушивании 80 порта или не будет вызван `Accept()`. Весь фокус в бесшовном обновление - не допускать этих двух моментов, те всегда прослушивать 80 порт и вызывать `Accept()`. Давайте рассмотрим как можно добиться такого поведения. Начнем с простых решений и будем двигаться к сложным.

### Простой `Exec()`

Окей, посмотрим насколько все это сложно. Для начала будем использовать `Exec()` с новым бинарником(для начала без форка). Это делает именно то что нужно - заменяет текущий код новым, загруженным с диска.

```go
// The following is pseudo-Go.

func main() {
	var ln net.Listener
	if isUpgrade {
		ln = net.FileListener(os.NewFile(uintptr(fdNumber), "listener"))
	} else {
		ln = net.Listen(network, address)
	}
	
	go handleRequests(ln)

	<-waitForUpgradeRequest

	syscall.Exec(os.Argv[0], os.Argv[1:], os.Environ())
}
```

К сожалению, такой подход имеет ряд фатальных недостатков. Мы не можем отменить `Exec()`. Например, если у вас есть ошибка в конфиге, то новый процесс попытается прочитать его и просто упадет.

Кроме того, такое решение предполагает, что новый процесс инициализируется мгновенно. На самом деле между загрузкой нового бинарника и первым вызовом `Accept()` может пройти много времени и ядро отменит часть соединений, так как [очередь прослушивания будет переполненной](https://veithen.github.io/2014/01/01/how-tcp-backlog-works-in-linux.html).

![](/img/upgrade/Example1-1.png)

Использование чистого `Exec()` не наш путь.

### Listen() все на свете

Теперь мы можем попробовать более продвинутое решение. Давайте форкнем и запустим новый процесс, который проинициализируется как обычно. В какой-то момент будут созданы сокеты, прослушивающие одинаковые адреса. К сожалению, так это не заработает - мы получим ошибку 48 известную как "Address Already In Use". Ядро запрещает нам прослушивание на тому же адресу и порту, которые использовались для старого процесса.

Но у нас есть флаг `SO_REUSEPORT`. С его помощью можно сказать ядру, чтоб оно игнорировало факт прослушивания сокета по адресу с портом и просто алоцировало новый.

```go
func main() {
	ln := net.ListenWithReusePort(network, address)

	go handleRequests(ln)

	<-waitForUpgradeRequest

	cmd := exec.Command(os.Argv[0], os.Argv[1:])
	cmd.Start()

	<-waitForNewProcess
}
```

Теперь оба процесса прослушивают сокеты и обновление должно заработать. Так?

`SO_REUSEPORT` очень своеобразный. Как системные программисты мы привыкли представлять себе сокеты как файловые дескрипторы, которые возвращаются в результате вызова. Но в ядре есть различия между структурой данных сокета и одним или несколькими файловыми дискрипторами указывающими на нее. Если вы используете `SO_REUSEPORT` то будет создан именно новый сокет, не просто новый файловый дескриптор. Новый и старый процессы будут ссылаться на разные сокеты, которые используют одинаковые адреса. И потенциально у нас может возникнуть состояние гонки: новые но еще не принятые соединения на сокете старого процесса будут убиты ядром. Ребята из GitHub [написали отличную статью о этой проблеме](https://githubengineering.com/glb-part-2-haproxy-zero-downtime-zero-delay-reloads-with-multibinder/#haproxy-almost-safe-reloads).

В GitHub проблему с `SO_REUSEPORT` решили через использование скрытой фичи сикола `sendmsg` которая называется "[вспомогательные данные(ancilliary data)](http://man7.org/linux/man-pages/man0/sys_socket.h.0p.html)". Это позволяет привязать вспомогательные данные к сокету. Использование такого подхода в GitHub позволяет элегантно интегрироваться с HAProxy. К счастью, у нас есть возможность изменять нашу программу и мы можем выбрать более простые альтернативы.

### NGINX: шаринг сокетов через fork и exec

NGINX это проверенная рабочая лошадка всея интенета. И он поддерживает бесшовное обновление. Мы используем его в Cloudflare и уверены в его реализации.

Сервер написан по принципу процесс на одно ядро. Это значит, что вместо запуска множества тредов, NGINX запускает по одному процессу на каждое логическое ядро. Дополнительно есть мастер процесс, который управляет бесшовными обновлениями.

Мастер процесс отвечает за создание сокетов используемых NGINX и разделение их между воркерами. Все делается довольно прямолинейно: очищается бит `FD_CLOEXEC` для всех прослушиваемых сокетов. Поэтому сокеты не закрываются после вызова сискола `exec()`. Дальше мастер исполняет обычную пляску с `fork()` / `exec()`, передавая номера файловых дискрипторов через переменные окружения.

Механизм бесшовного обновления работает очень похоже. Сначала создается новый мастер процесс(PID 1176) - [это описано в документации](http://nginx.org/en/docs/control.html#upgrade). Он наследует все прослушиваемые сокеты от старого мастер процесса(PID 1017) как это делают воркеры. И потом запускает новых воркеров:

```
 CGroup: /system.slice/nginx.service
       	├─1017 nginx: master process /usr/sbin/nginx -g daemon on; master_process on;
       	├─1019 nginx: worker process
       	├─1021 nginx: worker process
       	├─1024 nginx: worker process
       	├─1026 nginx: worker process
       	├─1027 nginx: worker process
       	├─1028 nginx: worker process
       	├─1029 nginx: worker process
       	├─1030 nginx: worker process
       	├─1176 nginx: master process /usr/sbin/nginx -g daemon on; master_process on;
       	├─1187 nginx: worker process
       	├─1188 nginx: worker process
       	├─1190 nginx: worker process
       	├─1191 nginx: worker process
       	├─1192 nginx: worker process
       	├─1193 nginx: worker process
       	├─1194 nginx: worker process
       	└─1195 nginx: worker process
```
Теперь у нас запущены два независимых процесса NGINX. PID 1176 может быть новая версия NGINX или может использовать новый конфигурационный файл. Когда на порт 80 приходит новое соединение - его обрабатывает один из 16 запущенных воркеров по выбору ядра.

В конце концов мы получим полностью замененный NGINX:

```
CGroup: /system.slice/nginx.service
       	├─1176 nginx: master process /usr/sbin/nginx -g daemon on; master_process on;
       	├─1187 nginx: worker process
       	├─1188 nginx: worker process
       	├─1190 nginx: worker process
       	├─1191 nginx: worker process
       	├─1192 nginx: worker process
       	├─1193 nginx: worker process
       	├─1194 nginx: worker process
       	└─1195 nginx: worker process
```

С этого момента все новые соединения обрабатываются одним из этих оставшихся 8 воркеров.

В NGINX есть различные способы защиты от дурака. Если вы попытаетесь запустить новый процесс обновления до окончания предыдущего, то получите ошибку:

```
[crit] 1176#1176: the changing binary signal is ignored: you should shutdown or terminate before either old or new binary's process
```

И такой подход вполне оправдан. В нашем решении для Go это тоже должно быть реализовано.

### Хотелки

Путь которым пошли разработчики NGINX самый правильный. Это очень четкий механизм с конкретными шагами:

![](/img/upgrade/upgrade-lifecycle.svg)

Тут решены все проблемы с которыми мы столкнулись выше. В идеале, хотелось бы видеть NGINX'совскую реализацию бесшовного обновления в виде Go пакета.

* Никакого запущенного старого кода после обновления
* Новый процесс может спокойно упасть при обновлении и это не вызовет проблем.
* Только одно обновление может быть запущенно в один момент

Конечно, уже есть достаточно библиотек, которые решают похожие задачи:

* [github.com/alext/tablecloth](github.com/alext/tablecloth)
* [github.com/astaxie/beego/grace](github.com/astaxie/beego/grace)
* [github.com/facebookgo/grace](github.com/facebookgo/grace)
* [github.com/crawshaw/littleboss](github.com/crawshaw/littleboss)

К сожалению, ни одна из библиотек не реализует все наши хотелки. Основная проблема: они разработаны для бесшовного обновления `http.Server`. Это делает их более красивыми, но теряется гибкость и их сложно использовать для других протоколов основанных на сокетах. Поэтому нам пришлось написать свою библиотеку `tableflip` не ради забавы.

### tableflip

tableflip это Go'шная библиотека для бесшовного обновления в стиле NGINX. Пример ее использования:

```go
upg, _ := tableflip.New(tableflip.Options{})
defer upg.Stop()

// Do an upgrade on SIGHUP
go func() {
    sig := make(chan os.Signal, 1)
    signal.Notify(sig, syscall.SIGHUP)
    for range sig {
   	    _ = upg.Upgrade()
    }
}()

// Start a HTTP server
ln, _ := upg.Fds.Listen("tcp", "localhost:8080")
server := http.Server{}
go server.Serve(ln)

// Tell the parent we are ready
_ = upg.Ready()

// Wait to be replaced with a new process
<-upg.Exit()

// Wait for connections to drain.
server.Shutdown(context.TODO())
```

Вызов `Upgrader.Upgrade` запускает новый процесс с необходимыми `net.Listener`ами и ждет инициализации нового процесса, чтобы посдать сигнал о завершении инициализации таймауте или кила.

`Upgrader.Fds.Listen` вдохновлен `facebookgo/grace` и позволяет легко наследовать `net.Listener`. За кулисами, `Fds` следит чтобы не используемые унаследованные сокеты были почищены. В том числе и UNIX сокеты коотрые [сложно отсоединить при закрытии](https://golang.org/pkg/net/#UnixListener.SetUnlinkOnClose).

В завершении, `Upgrader.Ready` очищает неиспользуемые файловые дескрипторы и сигнализирует родительскому процессу о завершении инициализации. Родительский процесс завершается.