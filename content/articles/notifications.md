+++
date = "2020-04-03T11:00:00+03:00"
draft = true
title = "iOS Нотификации. Подписка и рассылка"
tags = ["ios", "swift"]
+++

Все просто, но не очень. В интернете куча статей про нотификации в иос. И в этом проблема - слишком много статей, часть из них уже не актуально и большинство очень поверхностны. Поэтому, я решил добавить еще одну статью и хорошенько во всем разобраться.

Нотификации в приложении генерируются из-за событий в самом приложении(например, по таймеру) или по сообщению с сервера. Первые называются локальными, а вторые -- пуш-нотификациями. 

Пуш-нотификации работают через APNs (Apple Push Notification service). Для отправки сообщения пользователю нужно сформировать запрос к серверу APNs. Это делается разными способами.

- Через [token соединение](https://developer.apple.com/documentation/usernotifications/setting_up_a_remote_notification_server/establishing_a_token-based_connection_to_apns).
- Через [соединение с помощью сертификата](https://developer.apple.com/documentation/usernotifications/setting_up_a_remote_notification_server/establishing_a_certificate-based_connection_to_apns).

Отправка соединений с помощью токена выглядит попроще - ей и займемся.

## Локальные нотификации

Вся логика будет реализована в классе `Notifications`. Перед началом работы с нотификациями импортируем `UserNotifications`

```
import UserNotifications
```

Запрашиваем разрешение у пользователя на отправку нотификаций. Для этого в классе `Notifications` добавляем метод

```
let center = UNUserNotificationCenter.current()

func requestAuthorisation() {
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
        print("Permission granted: \(granted)")
    }
}
```

В классе `AppDelegate` добавим новое свойство `notifications` и вызовем метод `requestAuthorisation` при старте приложения

```
let notifications = Notifications()

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    notifications.requestAuthorisation()

    return true
}
```

Пользователь может поменять настройки уведомлений. Нужно не только запрашивать авторизацию, но и проверять настройки сообщений при старте приложения. Реализуем метод `getNotificationSettings()` и изменим `requestAuthorisation()` - и добавим получение настроек нотификаций, если `requestAuthorization` возвращает `granted == true`

```
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

```
func scheduleNotification(type: String) {
    let content = UNMutableNotificationContent()

    content.title = type
    content.body = "Example notification " + type
    content.sound = .default
    content.badge = 1 // красный бейджик на иконке с кол-вом непрочитанных сообщений
}
```

Для создания уведомления используем класс `UNMutableNotificationContent`. Подробней о возможностях этого класса [документации](https://developer.apple.com/documentation/usernotifications/unmutablenotificationcontent).

Триггер для показа уведомления может срабатывать по времени, календарю или местоположению. Можно отправлять уведомления каждый день в определенное время или раз в неделю.

Мы будем слать уведомления по времени. Создадим соответствующий триггер.

```
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

```
let delegate = UIApplication.shared.delegate as? AppDelegate
```

Добавим кнопку и а обработчике нажатия вызовем нужный метод

```
delegate?.scheduleNotification(type: "local")
```

Если нажать кнопку, то через 5 секунд появится уведомление как на картинке. Не забывайте, что нужно свернуть приложение, чтобы увидеть уведомление.

![](/img/notifications/notifications1.png)

На иконке появился бейджик. Сейчас он не остается на всегда и не пропадает. Давайте это поправим - добавим несколько строчек кода в `AppDelegate`

```
func applicationDidBecomeActive(_ application: UIApplication) {
    UIApplication.shared.applicationIconBadgeNumber = 0
}
```

![](/img/notifications/bage1.png)

При каждом запуске приложения количество непрочитанных уведомлений будет обнуляться.

### Уведомления когда приложение не в бекграунде

Есть возможность получать уведомления, даже когда приложение на переднем плане. Для этого надо реализовать протокол `UNUserNotificationCenterDelegate`. Для этого добавим новый экстеншен.

В [документации по протоколу](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate) `UNUserNotificationCenterDelegate` сказано

> Use the methods of the UNUserNotificationCenterDelegate protocol to handle user-selected actions from notifications, and to process notifications that arrive when your app is running in the foreground.

Нам нужно использовать метод `func userNotificationCenter(UNUserNotificationCenter, willPresent: UNNotification, withCompletionHandler: (UNNotificationPresentationOptions) -> Void)` про который написано

> Asks the delegate how to handle a notification that arrived while the app was running in the foreground.

Это как раз то, чего мы хотим добиться. Подпишем класс `Notifications` под протокол `UNUserNotificationCenterDelegate`.

```
extension Notifications: UNUserNotificationCenterDelegate {
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> ()) {
        completionHandler([.alert, .sound])
    }
}
```

И укажем делегат перед вызовом метода `requestAuthorisation()` в классе `AppDelegate`.

```
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    notifications.requestAuthorisation()
    notifications.center.delegate = notifications // не самый лучший код, но для примера сгодится
    return true
}
```

### Обработка уведомлений

При тапе на уведомление открывается приложение. Это поведение по умолчанию. Чтобы мы могли как-то реагировать на нажатия по уведомлениям - нужно реализовать еще один метод протокола `UNUserNotificationCenterDelegate`.

```
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

```
let snoozeAction = UNNotificationAction(identifier: "snooze", title: "Snooze")
let deleteAction = UNNotificationAction(identifier: "delete", title: "Delete", options: [.destructive])
```

Теперь создаем категорию с уникальным идентификатором.

```
let userAction = "User Action"

let category = UNNotificationCategory(
                identifier: userAction,
                actions: [snoozeAction, deleteAction],
                intentIdentifiers: [])

notifications.setNotificationCategories([category])
```

Метод `setNotificationCategories()` регистрирует нашу новую категорию в центре уведомлений.

Осталось указать категорию при создании нашего уведомления. В месте где мы создаем экземпляр класса `UNMutableNotificationContent` нужно установить параметр `categoryIdentifier`.

```
content.sound = .default
content.badge = 1 // красный бейджик на иконке с кол-вом непрочитанных сообщений
content.categoryIdentifier = userAction
```

У нас появились кастомные действия. Их будет видно, если потянуть уведомление вниз. Но они пока ничего не делают.

![](/img/notifications/notifications2.png)

Добавим обработку стандартных и кастомных действий в экстеншене.

```
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

```
let category = UNNotificationCategory(
        identifier: userAction,
        actions: [snoozeAction, deleteAction],
        intentIdentifiers: [],
        options: .customDismissAction)
```

На сайте документации есть две статьи по теме кастомных действий:

- [Handling Notifications and Notification-Related Actions](https://developer.apple.com/documentation/usernotifications/handling_notifications_and_notification-related_actions)
- [Declaring Your Actionable Notification Types](https://developer.apple.com/documentation/usernotifications/declaring_your_actionable_notification_types)

### Пользовательский контент

## Пуш-нотификации

## Отправка нотификаций с сервера

## Ссылки

- Официальная [документация по нотификациям](https://developer.apple.com/documentation/usernotifications).
- [Приложение](https://github.com/onmyway133/PushNotifications) для тестирования нотификаций.
- Курс на [swiftbook.ru](https://swiftbook.ru/content/23-index/).

https://www.raywenderlich.com/8164-push-notifications-tutorial-getting-started
https://medium.com/swifty-tim/push-notification-basics-1-of-2-b953952b0304

