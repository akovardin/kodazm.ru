+++
date = "2020-05-09T11:00:00+03:00"
draft = false
title = "Дебаг для Alamofire запросов"
tags = ["ios", "swift", "alamofire"]
+++

![](/img/alamofire-debug/main.png)

Alamofire - библиотека, для работы с HTTP написанная на свифте. Она упрощает жизнь разработчикам в разы. 

<!--more-->

Когда пишешь сетевой код, часто возникает вопрос как его подебажить, посмотреть параметры, заголовки и тд. С Alamofire это просто. 

Если у вас в проекте используется версия < 5, то вам нужно написать немного кода. Добавим вспомогательный метод к классу Request в отдельном файле _Request+Debug.swift_

```swift
import Foundation
import Alamofire

extension Request{
    public func debug() -> Self {
        #if DEBUG
        debugPrint(self)
        #endif
        return self
    }
}
```

B при запросе воспользуемся им.

```
Alamofire.request(url).debug()
    .responseJSON( completionHandler: { response in
        debugPrint(response)
    })
```

И в консоле буде ваш запрос в виде cURL.

```
$ curl -v \
	-b "__cfduid=dd963d192e96b1eb5a7eca3f0af0ba8051589034780" \
	-H "Accept-Encoding: gzip;q=1.0, compress;q=0.5" \
	-H "Accept-Language: en;q=1.0, ru-RU;q=0.9" \
	-H "User-Agent: AlamofireMagic/1.0 (ru.4gophers.AlamofireMagic; build:1; iOS 13.4.1) Alamofire/4.9.1" \
	"https://jsonplaceholder.typicode.com/posts/1"
```

На самом деле, все еще проще. С версии 5 в библиотеке уже есть встроенный обработчик. Достаточно написать так:

```swift
AF.request("https://jsonplaceholder.typicode.com/posts/1")
        .cURLDescription { description in
            print(description)
        }
        .responseJSON( completionHandler: { response in
            debugPrint(response)
        })
```

И результат будет точно таким же

## Ссылки

- [Документация](https://github.com/Alamofire/Alamofire/blob/master/Documentation/Usage.md#curl-command-output) по Alamofire
- Отличный [туториал по Alamofire на raywenderlich.com](https://www.raywenderlich.com/35-alamofire-tutorial-getting-started)