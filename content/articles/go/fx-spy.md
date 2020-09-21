+++
date = "2020-01-12T12:00:00+03:00"
draft = true
title = "Подсмотренно в fx"
tags = ["golang", "torrent", "bittorrent"]
+++

Provide и Invoke - это опции функционального типа.

```go
func Provide(constructors ...interface{}) Option {
	return provideOption{
		Targets: constructors,
		Stack:   fxreflect.CallerStack(1, 0),
	}
}

type provideOption struct {
	Targets []interface{}
	Stack   fxreflect.Stack
}

func (o provideOption) apply(app *App) {
	for _, target := range o.Targets {
		app.provides = append(app.provides, provide{
			Target: target,
			Stack:  o.Stack,
		})
	}
}
```

метод `apply` меняет объект `App`

Под капотом используется dig