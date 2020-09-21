+++
date = "2020-04-04T11:00:00+03:00"
draft = false
title = "iOS Нотификации. Подписка и рассылка"
tags = ["ios", "swift", "go"]
+++

![](/img/notifications/main.png)

Все просто, но не очень. В интернете куча статей про нотификации в иос. И в этом проблема - слишком много статей, часть из них уже не актуальны и большинство очень поверхностны. Поэтому, я решил добавить еще одну статью и хорошенько во всем разобраться.

Нотификации в приложении генерируются из-за событий в самом приложении (например, по таймеру) или по сообщению с сервера. Первые называются локальными, а вторые -- пуш-нотификациями. 

<!--more-->

Пуш-нотификации работают через APNs (Apple Push Notification service). Для отправки сообщения пользователю нужно сформировать запрос к серверу APNs. Это делается разными способами.

- Через [token соединение](https://developer.apple.com/documentation/usernotifications/setting_up_a_remote_notification_server/establishing_a_token-based_connection_to_apns).
- Через [соединение с помощью сертификата](https://developer.apple.com/documentation/usernotifications/setting_up_a_remote_notification_server/establishing_a_certificate-based_connection_to_apns).

Отправка соединений с помощью токена выглядит попроще - ей и займемся.

## Локальные нотификации

Вся логика будет реализована в классе `Notifications`. Перед началом работы с нотификациями импортируем `UserNotifications`

```swift
import UserNotifications
```

Запрашиваем разрешение у пользователя на отправку нотификаций. Для этого в классе `Notifications` добавляем метод

```swift
let center = UNUserNotificationCenter.current()

func requestAuthorisation() {
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
        print("Permission granted: \(granted)")
    }
}
```

В классе `AppDelegate` добавим новое свойство `notifications` и вызовем метод `requestAuthorisation` при старте приложения

```swift
let notifications = Notifications()

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    notifications.requestAuthorisation()

    return true
}
```

Пользователь может поменять настройки уведомлений. Нужно не только запрашивать авторизацию, но и проверять настройки сообщений при старте приложения. Реализуем метод `getNotificationSettings()` и изменим `requestAuthorisation()` - и добавим получение настроек нотификаций, если `requestAuthorization` возвращает `granted == true`

```swift
func requestAuthorisation() {
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
        print("Permission granted: \(granted)")

        guard granted else {
            return
        }

        self.getNotificationSettings()
    }
}

func getNotificationSettings() {
    center.getNotificationSettings { settings in
        print("Notification settings : \(settings)")
    }
}
```

Создадим локальное уведомление. Для этого добавим метод `scheduleNotification()` в классе AppDelegate`. В нем будем задавать нотификации по расписанию.

```swift
func scheduleNotification(type: String) {
    let content = UNMutableNotificationContent()

    content.title = type
    content.body = "Example notification " + type
    content.sound = .default
    content.badge = 1 // красный бейджик на иконке с кол-вом непрочитанных сообщений
}
```

Для создания уведомления используем класс `UNMutableNotificationContent`. Подробней о возможностях этого класса в [документации](https://developer.apple.com/documentation/usernotifications/unmutablenotificationcontent).

Триггер для показа уведомления может срабатывать по времени, календарю или местоположению. Можно отправлять уведомления каждый день в определенное время или раз в неделю.

Мы будем слать уведомления по времени. Создадим соответствующий триггер.

```swift
content.sound = .default
content.badge = 1 // красный бейджик на иконке с кол-вом непрочитанных сообщений

let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
let id = "Local Notification #1"

let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)

notifications.add(request) { error in
    if let error = error {
        print("Error \(error.localizedDescription)")
    }
}
```

Сначала создаем `trigger` - триггер, который будет срабатывать через 5 секунд. Задаем идентификатор для нашего уведомления `id`. Он должен быть уникальным для каждого уведомления.

Теперь у нас есть все, чтобы создать запрос на показ уведомления и добавить его в центр уведомлений `UNUserNotificationCenter`. Для этого делаем вызов `notifications.add(request)`

Осталось вызвать метод `scheduleNotification(type: String)`. В любой контроллер добавим делегат:

```swift
let delegate = UIApplication.shared.delegate as? AppDelegate
```

Добавим кнопку и по нажатию вызовем нужный метод

```swift
delegate?.scheduleNotification(type: "local")
```

Если нажать кнопку, то через 5 секунд появится уведомление как на картинке. Не забывайте, что нужно свернуть приложение, чтобы увидеть уведомление.

![](/img/notifications/notifications1.png)

На иконке появился бейджик. Сейчас он остается на всегда и не пропадает. Давайте это поправим - добавим несколько строчек кода в `AppDelegate`

```swift
func applicationDidBecomeActive(_ application: UIApplication) {
    UIApplication.shared.applicationIconBadgeNumber = 0
}
```

![](/img/notifications/bage1.png)

При каждом запуске приложения количество непрочитанных уведомлений будет обнуляться.

### Уведомления когда приложение не в бекграунде

Есть возможность получать уведомления, даже когда приложение на переднем плане. Реализуем протокол `UNUserNotificationCenterDelegate`. Для этого добавим новый экстеншен.

В [документации по протоколу](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate) `UNUserNotificationCenterDelegate` сказано

> Use the methods of the UNUserNotificationCenterDelegate protocol to handle user-selected actions from notifications, and to process notifications that arrive when your app is running in the foreground.

Нам нужно использовать метод `func userNotificationCenter(UNUserNotificationCenter, willPresent: UNNotification, withCompletionHandler: (UNNotificationPresentationOptions) -> Void)` про который написано

> Asks the delegate how to handle a notification that arrived while the app was running in the foreground.

Это как раз то, чего мы хотим добиться. Подпишем класс `Notifications` под протокол `UNUserNotificationCenterDelegate`.

```swift
extension Notifications: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> ()) {
        completionHandler([.alert, .sound])
    }
}
```

И укажем делегат перед вызовом метода `requestAuthorisation()` в классе `AppDelegate`.

```swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    notifications.requestAuthorisation()
    notifications.center.delegate = notifications // не самый лучший код, но для примера сгодится
    return true
}
```

### Обработка уведомлений

При тапе на уведомление открывается приложение. Это поведение по умолчанию. Чтобы мы могли как-то реагировать на нажатия по уведомлениям - нужно реализовать еще один метод протокола `UNUserNotificationCenterDelegate`.

```swift
public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> ()) {
    if response.notification.request.identifier == "Local Notification #1" {
        print("Received notification Local Notification #1")
    }

    completionHandler()
}
```

### Действия для уведомлений

Чтобы добавить кастомные действий в уведомлениях, сначала нужно нужно добавить категории уведомлений. 

Добавляем кастомные экшены в методе `scheduleNotification()`.

```swift
let snoozeAction = UNNotificationAction(identifier: "snooze", title: "Snooze")
let deleteAction = UNNotificationAction(identifier: "delete", title: "Delete", options: [.destructive])
```

Теперь создаем категорию с уникальным идентификатором.

```swift
let userAction = "User Action"

let category = UNNotificationCategory(
                identifier: userAction,
                actions: [snoozeAction, deleteAction],
                intentIdentifiers: [])

notifications.setNotificationCategories([category])
```

Метод `setNotificationCategories()` регистрирует нашу новую категорию в центре уведомлений.

Осталось указать категорию при создании нашего уведомления. В месте, где мы создаем экземпляр класса `UNMutableNotificationContent`, нужно установить параметр `categoryIdentifier`.

```swift
content.sound = .default
content.badge = 1 // красный бейджик на иконке с кол-вом непрочитанных сообщений
content.categoryIdentifier = userAction
```

У нас появились кастомные действия. Их будет видно, если потянуть уведомление вниз. Но они пока ничего не делают.

![](/img/notifications/notifications2.png)

Добавим обработку стандартных и кастомных действий в экстеншене.

```swift
public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> ()) {
    if response.notification.request.identifier == "Local Notification #1" {
        print("Received notification Local Notification #1")
    }

    print(response.actionIdentifier)

    switch response.actionIdentifier {
    case UNNotificationDismissActionIdentifier:
        print("Dismiss action")
    case UNNotificationDefaultActionIdentifier:
        print("Default action")
    case "snooze":
        print("snooze")
        scheduleNotification(type: "Reminder")
    case "delete":
        print("delete")
    default:
        print("undefined")
    }

    completionHandler()
}
```

`UNNotificationDefaultActionIdentifier` - срабатывает при нажатии по уведомлению. `UNNotificationDismissActionIdentifier` - срабатывает, когда мы смахиваем уведомление вниз. С _Dismiss_ есть один неочевидный момент - он не будет работать, если при создании категории не указать опцию `.customDismissAction`:

```swift
let category = UNNotificationCategory(identifier: userAction,
                                        actions: [snoozeAction, deleteAction],
                                        intentIdentifiers: [],
                                        options: .customDismissAction)
```

На сайте документации есть две статьи по теме кастомных действий:

- [Handling Notifications and Notification-Related Actions](https://developer.apple.com/documentation/usernotifications/handling_notifications_and_notification-related_actions)
- [Declaring Your Actionable Notification Types](https://developer.apple.com/documentation/usernotifications/declaring_your_actionable_notification_types)

### Пользовательский контент

Для уведомлений можно устанавливать кастомные изображения. Добавим его в методе `scheduleNotification(type: String)`

```swift
guard let icon = Bundle.main.url(forResource: "icon", withExtension: "png") else {
    print("Path error")
    return
}

do {
    let attach = try UNNotificationAttachment(identifier: "icon", url: icon)
    content.attachments = [attach]
} catch {
    print("Attachment error")
}
```

Картинка должна быть в файлах проекта, не в папке _Assets.xcassets_. Иначе, метод `Bundle.main.url` вернет `nil`. Если все сделано правильно -- уведомление будет выглядеть как-то так: 

![](/img/notifications/notifications3.png)

На этом с локальными уведомлениями все.

## Пуш-уведомления

Для работы с такими уведомлениями вам нужен платный аккаунт разработчика.

Пуш-уведомления отправляются с сервера через APNs. Уведомления приходят на разные девайсы, APNs сам маршрутизирует сообщения. Разработчик сам решает, когда отправить уведомление. 

![](/img/notifications/push1.png)

Для отправки пуш-уведомлений необходимо выполнить дополнительные манипуляции. Схема ниже показывает нужные шаги.

![](/img/notifications/push2.jpg)

1. Приложение регистрируется для отправки сообщений.
2. Девайс получает специальный токен с APNs сервера.
3. Токен передается в приложение.
4. Приложение отправляет токен провайдеру(например, нашему бэкенду)
5. Теперь провайдер может слать уведомления через APNs с использованием токена, который сохранили на 4 шаге.

Существует 2 вида пуш-уведомлений: тестовые(sandbox) и реальные(production). Для разных видов уведомлений используются разные APNs сервера.

Чтобы приложение могло зарегистрироваться для оправки соединения - нужно включить поддержку поддержку пуш-уведомлений. Проще всего это сделать с помощью Xcode. Раньше это был довольно замороченный процесс, но сейчас достаточно выбрать _Push Notifications_. 

![](/img/notifications/push3.png)

И сразу добавьте поддержку бэкграунд обработку задач. Должно быть как на картинке.

![](/img/notifications/push6.png)

За кадром сгенерируется новый идентификатор приложения, обновится Provisioning Profile. Идентификатор моего приложения _ru.4gophers.Notifications_. Его можно найти на страничке [https://developer.apple.com/account/resources/identifiers/list](https://developer.apple.com/account/resources/identifiers/list)

![](/img/notifications/push4.png)

В настройках этого идентификатора уже должна быть указана поддержка пуш-уведомлений.

![](/img/notifications/push5.png)

И в проекте появляется новый файл _Notifications.entitlements_. Этот файл имеет расширение _.entitlements_ и называется как и проект.

### Сертификаты

Теперь нам нужно создать CertificateSigningRequest для генерации SSL сертификата пуш-уведомлений. Это делается с помощью программы Keychain Access

![](/img/notifications/keychain1.png)

Сгенерированный файл _CertificateSigningRequest.certSigningRequest_ сохраните на диск. Теперь с его помощью генерируем SSL сертификаты для отправки пуш-уведомлений. Для этого на страничке [https://developer.apple.com/account/resources/identifiers/list](https://developer.apple.com/account/resources/identifiers/list) выберите ваш идентификатор, в разделе Push Notifications нажмите кнопку _Сonfigure_ и сгенерируйте новый Development SSL сертификат с помощью файла _CertificateSigningRequest_.

![](/img/notifications/keychain2.png)

Скачайте сгенерированный сертификат и установите его в системе(просто кликните по нему). В программе Keychain Access должен показаться этот серт:

![](/img/notifications/keychain3.png)

Отлично! Теперь экспортируем сертификат с помощью все той же программы Keychain Access. Нажимаем правой кнопкой по сертификату и выбираем экспорт:

![](/img/notifications/keychain4.png)

При экспорте нужно выбрать расширение файла _.p12_. Этот экспортированный сертификат понадобится нам в будущем.

Пуш-уведомления можно тестировать только на реальных устройствах. Девайс должен быть зарегистрирован в [https://developer.apple.com/account/resources/devices/list](https://developer.apple.com/account/resources/devices/list) и у вас должен быть рабочий сертификат разработчика.

Осталось добавить ключ для пуш-уведомлений. Для этого на страничке [https://developer.apple.com/account/resources/authkeys/list](https://developer.apple.com/account/resources/authkeys/list) нажимаем + добавляем новый ключ:

![](/img/notifications/keychain5.png)

Я назову ключ Push Notification Key. После создания ключа, обязательно скачайте его, нажав на кнопку _Done_

![](/img/notifications/keychain6.png)

### Получение пуш-уведомлений

С подготовкой закончили, вернемся к коду. В методе `getNotificationSettings()` регистрируем наше приложение в APNs для получения пуш-уведомлений.

```swift
func getNotificationSettings() {
    center.getNotificationSettings { settings in
        print("Notification settings : \(settings)")

        guard settings.authorizationStatus == .authorized else {
            return
        }

        // регистрироваться необходимо в основном потоке
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
}
```

Теперь в классе `AppDelegate` нужно добавить пару методов. Получаем девайс токен:

```swift
func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let parts = deviceToken.map { data in
        return String(format: "%02.2hhx", data)
    }

    let token = parts.joined()
    print("Device token: \(token)")
}
```

Этот токен нам нужен для отправки уведомлений. Он работает как адрес приложения. В реальном приложении мы отправим его наш бекенд и сохраним в базе.

Обработаем ситуацию когда что-то пошло не так и нам не получилось зарегистрироваться в APNs.

```swift
func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("Failed registration: \(error.localizedDescription)")
}
```

Забавно, но у меня ничего не заработало сразу. Ни метод `didRegisterForRemoteNotificationsWithDeviceToken`, ни `didFailToRegisterForRemoteNotificationsWithError` не срабатывали. Я потратил на поиск проблемы несколько часов, пока случайно не наткнулся на это [обсуждение](https://github.com/OneSignal/OneSignal-iOS-SDK/issues/514#issuecomment-582680117). Выключите и включите вай-фай. Да. Не спрашивайте. 

## Отправка нотификаций

Все готово для отправки и получения уведомлений. Давайте протестируем. 

### Десктопное приложение

Приложений для тестирования уведомлений целая куча, но мне больше всего нравится [PushNotifications](https://github.com/onmyway133/PushNotifications). Переключитесь на вкладку _TOKEN_ и укажите нужные данные.

![](/img/notifications/send1.png)

Сначала попробуем отправить сообщение с помощью ключа _Push Notification Key_.

* **f6c10036b6203ebf40a246ce5a741c3b17778063c78aa1016c6474d3dfef46e2** -- Токен, который мы получаем при запуске приложения. Он выводится в консоль.
* **YYS33CP3HU** -- Идентификатор ключа, который мы сгенерировали выше и назвали _Push Notification Key_
* **25K6PDW2HY** -- Team ID, идентификатор аккаунта разработчика

Тело самого уведомления - обычный JSON

```json
{
    "aps": {
        "alert": "Hello2" // это тело уведомления
    },
    "yourCustomKey": "1" // любые кастомные данные
}
```

`alert` может быть объектом с заголовком и телом. В уведомление можно указывать звук, бейдж. `thread-id` позволяет группировать уведомления. Ключ `category` позволяет использовать кастомные экшены. `content-available` обозначает досупность обновления для уведомления в бэкграунд режиме.

```json
{
    "aps": {
        "alert": {
            "title": "Hello", 
            "body": "Тут можно много всего написать"
        },
        "sound": "default",
        "badge": 10,
        "thread-id": 1,
        "category": "User Action",
        "content-available": 1
    },
    "yourCustomKey": "1"
}
```

Для отправки нотификаций можно использовать не только _.p8_ ключ, но и наш SSL сертификат, который мы сгенерировали ранее. Для этого в приложении PushNotifications есть вкладка _CERTIFICATE_. Она работает точно так же, только нужно использовать сертификат _.p12_, указать пароль и не нужно указывать Team ID.

### Обработка кастоиных параметров

Для получения данных из пуш-уведомления нужно реализовать метод в `AppDelegate`.

```swift
func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) {
    print(userInfo)
}
```

Но этот метод позволяет получить данные уже после показа уведомления. А в iOS есть возможность кастомизировать контент уведомления с помощью экстеншенов. Например, можно задавать кастомную картинку для каждого уведомления. Для этого нужно создать расширение _[Notification Content Extension](https://developer.apple.com/documentation/usernotificationsui/customizing_the_appearance_of_notifications)_ как показано на скриншотах.

![](/img/notifications/service1.png)
![](/img/notifications/service2.png)
![](/img/notifications/service3.png)

Также, можно менять данные в нотификациях перед их показом с помощью _Notification Service Extension_. Но тема создания таких расширений слишком обширна и тянет на отдельную статью.

### Используем Go библиотеку

И теперь самое простое - отправка уведомлений с использованием Go. Уже есть множество готовых библиотек, нам нужно выбрать самую удобную и научится с ней работать.

Мне больше всего понравился пакет [APNS/2](https://github.com/sideshow/apns2). В этом пакете уже есть готовая консольная утилита для отправки уведомлений. И у него очень простое АПИ.

Создаем клиент, который будет отправлять сообщения с помощью _.p8_ ключа.

```go
package main

import (
	"fmt"
	"log"

	"github.com/sideshow/apns2"
	"github.com/sideshow/apns2/token"
)

func main() {

	authKey, err := token.AuthKeyFromFile("./AuthKey_YYS33CP3HU.p8")
	if err != nil {
		log.Fatal("token error:", err)
	}

	token := &token.Token{
		AuthKey: authKey,
		KeyID:   "YYS33CP3HU",
		TeamID:  "25K6PDW2HY",
	}

	notification := &apns2.Notification{}
	notification.DeviceToken = "f6c10036b6203ebf40a246ce5a741c3b17778063c78aa1016c6474d3dfef46e2"
	notification.Topic = "ru.4gophers.Notifications"
	notification.Payload = []byte(`{"aps":{"alert":"Hello!"}}`)

	client := apns2.NewTokenClient(token)
	res, err := client.Push(notification)

	if err != nil {
		log.Fatal("Error:", err)
	}

	fmt.Printf("%v %v %v\n", res.StatusCode, res.ApnsID, res.Reason)
}
```

Такой простой код позволяет отправлять сообщения из Go-приложения на iOS телефон. В приложении может быть хендлер, который будет сохранять DeviceToken в базу. И вы сможете рассылать любые уведомления в любое время.

## Ссылки

- [Исходнки к статье на GitHub](https://github.com/horechek/notifications-ios).
- Официальная [документация по нотификациям](https://developer.apple.com/documentation/usernotifications).
- [Приложение](https://github.com/onmyway133/PushNotifications) для тестирования нотификаций.
- Курс на [swiftbook.ru](https://swiftbook.ru/content/23-index/).
- [Push Notifications Tutorial: Getting Started](https://www.raywenderlich.com/8164-push-notifications-tutorial-getting-started).
- Кастомное отображение нотификаций с [помощью расширений](https://developer.apple.com/documentation/usernotificationsui/customizing_the_appearance_of_notifications).
- [APNS/2](https://github.com/sideshow/apns2) - либа для отправки пуш-уведомлений.

