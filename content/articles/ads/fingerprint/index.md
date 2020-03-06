+++
date = "2019-03-10"
title = "Библиотеки для fingerprint. Цифровой отпечаток устройства"
categories = [ "Инструменты" ]
tags = [ "Id", "Fingerprints", "Browser" ]
draft = true

[image]
  caption = "Изображение: Pixel Privacy"
  focal_point = "Smart"
  preview_only = false
+++

Fingerprint дословно переводится как отпечатки пальцев. Эти отпечатки используются для идентификации людей. Похожим образом используются цифровые отпечатки - идентифицируют браузеры и устройства для трекинга пользователей в социальных сетях, интернет рекламе, системах аналитики.

С помощью цифровых отпечатков отличают один браузер от другого или различают устройства. В первом случае у вас поменяется отпечаток если вы начнете использовать другой браузер, например фаерфокс вместо хрома. Во втором случае, даже если вы перейдете в режим инкогнито или откроете другой браузер, отпечаток не поменяется.

Идентификация пользователей это очень важная тема для рекламной индустрии. Вся персональная информация, профили, аудиторные таргетинги привязываются к некоторым уникальным идентификаторам. Чем надежнее эти идентификаторы, тем более подходящую рекламу видит пользователь.

Почему не подходят обычные cookies? Их можно очистить, они не работают в анонимных вкладках и они не помогут идентифицировать пользователей между браузерами на одном устройстве.

## Как работают цифровые отпечатки

Браузерные отпечатки проще - можно использовать меньше параметров и не нужно учитывать различия между браузерами. Отпечатки устройства сложнее - сложно добраться до информации о операционной системе или устройстве.

Цифровые отпечатки это закодированная информация о различных параметрах, например о максимальном разрешение, установленных шрифта и плагинах. Полученная информация кешируется и результат кеширования используется как идентификатор пользователя.

Системы трекинга постоянно развиваются. Условно различают три поколения таких систем.

* Первое поколение. Идентификаторы генерируются на стороне сервера и сохраняются в cookies браузера.
* Второе поколение. Цифровые отпечатки браузеров. Для их генерации используется информация о разрешении экрана, установленных шрифтах, вся информация из юзер агента браузера, информация о видео и аудио кодеках, canvas и webgl рендеринг. Часто второе поколение комбинируется с первым. Идентификаторы генерируются с помощью JS на клиентской стороне, сохраняются в cookie и передаются на сервер. Для большей надежности, вместо сохранения в cookies используют evercookie - технология сохранения идентификаторов так, чтобы их было сложно удалить.
* Третье поколение. Цифровые отпечатки устройств. Они тоже генерируются с помощью JS на клиентской стороне. Но используется информация о операционной системе и устройстве, а не о браузере. Некоторые параметры, например webgl рендеринг или информация о кодеках, используются и для идентификации браузеров, и для идентификации устройств.

Готовых инструментов для идентификации пользователей мало, но они есть. Попробуем выбрать лучший и максимально универсальный. Будем сравнивать [fingerprintjs2](http://valve.github.io/fingerprintjs2/), [clientjs](https://github.com/jackspirou/clientjs), [cross_browser](https://github.com/Song-Li/cross_browser) и [imprintjs](https://github.com/mattbrailsford/imprintjs). Оценивать эти библиотеки будем по удобству использования, скорости работы и насколько хорошо они умеют отличать пользователей.

Для проверки всех этих библиотек я создал отдельную страничку. Код странички [лежит на github](https://github.com/horechek/fingerprint).

## fingerprintjs2

Первая библиотека - [fingerprintjs2](http://valve.github.io/fingerprintjs2/). Она собирает больше 20 параметров для генерации отпечатка. Все эти значения объединяются в один массив данных и вычисляется хеш.  На моем маке список параметров выглядит так:

```
userAgent = Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_3) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/72.0.3
language = ru-RU
colorDepth = 24
deviceMemory = not available
hardwareConcurrency = 4
screenResolution = 2560,1440
availableScreenResolution = 2560,1440
timezoneOffset = -180
timezone = Europe/Moscow
sessionStorage = true
localStorage = true
indexedDb = true
addBehavior = false
openDatabase = true
cpuClass = not available
platform = MacIntel
plugins = Chrome PDF Plugin,Portable Document Format,application/x-google-chrome-pdf,pdf,Chrome PDF Viewer,,ap
canvas = canvas winding:yes,canvas fp:data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAB9AAAADICAYAAACwGnoBAAAgA
webgl = data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAASwAAACWCAYAAABkW7XSAAAM80lEQVR4Xu2dXYgkVxXHT/XMIBJEQU
webglVendorAndRenderer = Intel Inc.~Intel(R) Iris(TM) Plus Graphics 640
adBlock = false
hasLiedLanguages = false
hasLiedResolution = false
hasLiedOs = false
hasLiedBrowser = false
touchSupport = 0,false,false
fonts = Andale Mono,Arial,Arial Black,Arial Hebrew,Arial Narrow,Arial Rounded MT Bold,Arial Unicode MS,Comic
audio = 124.04345808873768
```

Кажется что использовать юзер агент для вычисления хеша неправильно. Например, что будет, если поменялась версия бразера? Будем определять пользователя как нового? Fingerprintjs2 эту проблему решает с пмощью фазихэширования(localsensitivehash или нечеткое хэширование). В таком хешировании, если на входе поменяется некоторый процент входящих данных, результат останется прежним. Есть порог чувствительности.

Fingerprintjs2 старается определить шрифты, которые установленны в системе. Для этого используется site chanel technic. На странице создается элемент с скрытым текстом. Этому элементу задаются шрифт по умолчанию. Измеряется ширина и высота элемента и, соответственно, шрифта. Измерения сохраняются в массив. Затем к скрытому тексту применяется другой шрифт. Если этот шрифт есть в системе, размеры текста поменяются и код, который изменяет высоту и ширину, получит новые значения высоты и ширины. Если он отличается от шрифта по умолчанию, значит этот шрифт установлен.

Еще одна интересная фича - WebGL Fingerprint. Для отпечатков используются Сanvas Fingerprint, но они дают одинаковые результаты на одинаковых устройствах, например для iPhone, iPad. Считается что с помощью WebGL можно получить лучший результат. Для создания отпечатка рисуется 3D фигура. На нее накладываются эффекты, градиент, разная анизотропная фильтрация и т.д. Потом все преобразуется в байтовый массив. Этот байтовый массив будет разный на многих компьютерах. Потом к этому байтовому массиву добавляется информация о платформозависимых константах, которые определены в WebGL.

Если вы хотите больше подробностей про fingerprintjs2, то вот видео с автором Валентином Васильевым. Он рассказывает про устройство своей библиотеки и использования evercookie.

// время работы

<iframe width="950" height="600" src="https://www.youtube.com/embed/zodGHE1d_e0" frameborder="0" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>

## clientjs

[clientjs](https://github.com/jackspirou/clientjs) - самая простая библиотека из всех что мы рассматриваем. Работает на базе fingerprintjs(первой версии) и уступает fingerprintjs2 - тут нет WebGL Fingerprint и хеширование намного проще. Но ее можно использовать для определения браузера, операционной системы и т.д.

Для генерации хеша используется [MurmurHash3](https://en.wikipedia.org/wiki/MurmurHash) и в результате получаем 32-bit хеш. Этого явно недостаточно для большой рекламной сети. В том же fingerprintjs2 используется MurmurHash3 но возвращается 128-bit хеш.

На github есть [полный список параметров](https://github.com/jackspirou/clientjs#available-methods), которые используются в clientjs.

Кажется, что эту библиотеку стоит использовать для определения браузеров или OS, чтобы динамически сформировать контент на сайте. Но для цифровых отпечатков она не подходи

## cross_browser

[cross_browser](https://github.com/Song-Li/cross_browser) умеет не только детектить браузер пользователя, но и идентифицировать пользователя между браузерами. Yinzhi Cao, Song Li и Erik Wijmans написали исследовательскую работу по цифровым отпечаткам и библиотека cross_browser появилась как результат этой работы.

Но если говорить честно, то cross_browser это совсем не библиотека. Да, исходный код на гитхабе есть, но это лапшакод из HTML, набора js с разными детектами и кусок северного кода на питоне котрому нужна база и он просто так не заработает.

Архитектура cross_browser отличается от всего что мы рассмотрели. Код разделен на клиентскую и серверную части. С сервера приходят специальные задачаи(rebdering tasks) а клиент их исполняет. Результат исполнения каждой задачи хешируется и отправляется на сервер. Хеши объединяются и сохраняются в базе отпечатков.

У этого проекта крутая демо страничка, но пользоваться им невозможно. Его нужно привести к нормальному виду. Нужно сделать универсальную серверную часть, избавиться от лишнего HTML и оформить JS в библиотеку. Иначе оно просто не заработает.

## imprintjs

[imprintjs](https://github.com/mattbrailsford/imprintjs) жемчужина нашей коллекции. Она базируется на Fingerprintjs2, clientjs и cross_browser. Можно получить как браузерные отпечатки, так и системные. Список проверок можно указать через настройки.

```js
var browserTests = [
    "audio",
    "availableScreenResolution",
    "canvas",
    "colorDepth",
    "cookies",
    "cpuClass",
    "deviceDpi",
    "doNotTrack",
    "indexedDb",
    "installedFonts",
    "language",
    "localIp",
    "localStorage",
    "pixelRatio",
    "platform",
    "plugins",
    "processorCores",
    "screenResolution",
    "sessionStorage",
    "timezoneOffset",
    "touchSupport",
    "userAgent",
    "webGl"
];

imprint.test(browserTests).then(function(result){
    console.log(result);
});
```

Отдельно можно генерировать браузерные и системные отпечатки. Для системных отпечатков нужно указать другой набор параметров:

```js
var deviceTests = [
    "audio",
    "colorDepth",
    "cpuClass",
    "deviceDpi",
    "localIp",
    "platform",
    "installedFonts",
    "processorCores",
    "publicIp",
    "screenResolution",
    "timezoneOffset"
];
```

На момент написания статьи, imprintjs самая простая и удобная библиотека для цифровых отпечатков.

## Еще по теме

Цифровые отпечатки в онлайн рекламе - больная тема. Появляется все больше борцов за анонимность. Все больше проектов вроде [Panopticlick 3.0](https://www.eff.org/ru/deeplinks/2017/11/panopticlick-30), которые покажут насколько ваш браузер анонимен. Кстати, полезное видео от создателей Panopticlick. Некоторые идеи можно использовать как в разработке fingerprint'ов:

<iframe width="950" height="600" src="https://www.youtube.com/embed/3xQLy6lH5OE" frameborder="0" allow="accelerometer; autoplay; encrypted-media; gyroscope; picture-in-picture" allowfullscreen></iframe>

И еще целая куча ссылок по теме:

* [fingerprintjs2](http://valve.github.io/fingerprintjs2/)
* [clientjs](https://github.com/jackspirou/clientjs)
* [cross_browser](https://github.com/Song-Li/cross_browser)
* [imprintjs](https://github.com/mattbrailsford/imprintjs)
* [Technical analysis of client identification mechanisms](https://sites.google.com/a/chromium.org/dev/Home/chromium-security/client-identification-mechanisms)
* [(Cross-)Browser Fingerprinting via OS and Hardware Level Features](http://yinzhicao.org/TrackingFree/crossbrowsertracking_NDSS17.pdf)
* [evercookie](https://github.com/samyk/evercookie)
* [Browser Fingerprint – анонимная идентификация браузеров](https://habr.com/ru/company/oleg-bunin/blog/321294/)
* [amiunique.org](https://amiunique.org/)
* [Browser Fingerprinting – What You Need to Know](https://restoreprivacy.com/browser-fingerprinting/)
* [Общий регламент по защите данных](https://bit.ly/2I3azy6)
* [Device fingerprint](https://en.wikipedia.org/wiki/Device_fingerprint)
* [Panopticlick 3.0](https://www.eff.org/ru/deeplinks/2017/11/panopticlick-30)
* [Remote physical device fingerprinting](https://homes.cs.washington.edu/~yoshi/papers/PDF/KoBrCl05PDF-lowres.pdf)
* [Browser Fingerprinting](https://pixelprivacy.com/resources/browser-fingerprinting/)
* [Web Browser Uniqueness and Fingerprinting](https://medium.com/@ravielakshmanan/web-browser-uniqueness-and-fingerprinting-7eac3c381805)
* [Browser Fingerprint – анонимная идентификация браузеров](https://habr.com/ru/company/oleg-bunin/blog/321294/)