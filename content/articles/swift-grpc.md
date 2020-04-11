+++
date = "2020-02-07T12:00:00+03:00"
title = "gRPC на не Go'шном клиенте"
tags = [ "swift", "grpc", "mobile" ]
draft = true
+++

gRPC шагает по планете широкими шагами и все больше языков умеют работать по этому протоколу. C Go все понятно, gRPC для него практически часть инфраструктуры. Если вы разрабатываете сервисы на Go, то взаимодействуют друг с другом они по gRPC.

Но все становится интереснее, когда у вас есть другие клиенты, написанные не на Go. gRPC задумывался как протокол для вызова удаленных процедур независимо от языка, который вы используете. Для JS есть gRPC WEB и даже [туториал на сайте](https://grpc.io/docs/tutorials/basic/web/). C Java и Android [тоже все хорошо](https://grpc.io/docs/tutorials/basic/android/). Еще есть [библиотека для Objective-C](https://grpc.io/docs/tutorials/basic/objective-c/). А под [Swift реализация](https://github.com/grpc/grpc-swift) появилась сравнительно недавно, документации и примеров мало. Попробуем хоть немного восполнить этот пробел.

Начнем с создания проекта.

https://levelup.gitconnected.com/swift-grpc-577ce1a4d1b7
https://github.com/grpc/grpc-swift
https://github.com/apple/swift-protobuf
https://github.com/grpc/grpc-swift/tree/master/Examples