+++
date = "2018-11-08T18:05:09+03:00"
draft = true
title = "Профилирование"
+++

Ссылки для вдохновения:

* [https://rakyll.org/profiler-labels/](https://rakyll.org/profiler-labels/)
* [https://www.integralist.co.uk/posts/profiling-go/](https://www.integralist.co.uk/posts/profiling-go/)
* [https://habr.com/company/badoo/blog/301990/](https://habr.com/company/badoo/blog/301990/)
* [https://rakyll.org/pprof-ui/](https://rakyll.org/pprof-ui/)
* [http://www.brendangregg.com/flamegraphs.html](http://www.brendangregg.com/flamegraphs.html)
* [https://artem.krylysov.com/blog/2017/03/13/profiling-and-optimizing-go-web-applications/](https://artem.krylysov.com/blog/2017/03/13/profiling-and-optimizing-go-web-applications/)
* [https://medium.com/@cep21/using-go-1-10-new-trace-features-to-debug-an-integration-test-1dc39e4e812d](https://medium.com/@cep21/using-go-1-10-new-trace-features-to-debug-an-integration-test-1dc39e4e812d)

Самое простое пофилирование:

```
go tool pprof http://127.0.0.1:2112/debug/pprof/profile
```

На моем маке была ошибка:

```
Failed to execute dot. Is Graphviz installed? Error: exec: "dot": executable file not found in $PATH
```

Чтобы починить нужно установит Graphviz:

```
brew install graphviz
```

Для запуска веб интерфейса:

```
go tool pprof -http=:8080 http://127.0.0.1:2112/debug/pprof/profile
```

Флаг -http=:8080 запускает веб-интерфейс на 8080 порту.

Список горутин:

http://mcalc03.rtty.in/debug/pprof/goroutine?debug=1