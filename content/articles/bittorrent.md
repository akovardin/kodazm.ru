+++
date = "2020-01-12T11:00:00+03:00"
draft = true
title = "Пишем свой BitTorrent клиент на Go"
tags = ["golang", "torrent", "bittorrent"]
+++

Перевод "[Building a BitTorrent client from the ground up in Go](https://blog.jse.li/posts/torrent/)"

tl;dr: Что происходит с момента визита на thepiratebay и появлением mp3 файла на вашем компьютере? В этом посте мы реализуем BitTorrent протокол на уровне, достаточным для скачивания образа Debian. Можете сразу [посмотреть исходный код](https://github.com/veggiedefender/torrent-client/) и [пропустить](https://blog.jse.li/posts/torrent#putting-it-all-together) все подробные объяснения.

BitTorrent это протокол для скачивания файлов и распространения их через интернет. В отличие от традиционного клиент-серверного взаимодействия(например, просмотров фильмов на Netflix или загрузка интернет страничек), участники BitTorrent сети, которые называются peer'ами, скачивают части файлов друг с друга. Такое взаимодействие называется peer-to-peer протоколом.
