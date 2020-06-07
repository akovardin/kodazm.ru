+++
date = "2020-06-07T11:00:00+03:00"
draft = false
title = "MVVM для iOS с Combine и SwiftUI"
tags = ["ios", "swift", "swiftui", "combine"]
+++

![](/img/mvvm/main.png)

Разработка под iOS постоянно развивается. Сравнительно не давно появился Swift. Разработчики пришли к выводу, что для сложных приложений обычной MVC архитектуры не достаточно. Разработка через storyboard не настолько гибкая как хотелось бы. Со временем, пришли к VIPER архитектуре - одной из вариаций чистой архитектуры.

<!--more-->

Параллельно с этим, развивалась и совершенствовалась фронтенд разработка. Реактивная архитектура, однонаправленный поток данных и вот это все.

Потом появился SwiftUI и Combine, которые должны сделать жизнь iOS разработчика лучше. Со временем это станет стандартом разработки под iOS. И сейчас самое время, чо бы начать разбираться с этими хипстерскими технологиями.

В этой статье будем экспериментировать с [superhero-api](https://akabab.github.io/superhero-api/api/) и сделаем приложение со списком супер героев.

## Combine

Combine можно использовать когда у вас есть запросы за данными. С его помощью можно управлять потоками данных внутри вашего приложения.

Работу этого фреймворка можно сравнить с конвейером. Есть три основных элемента: паблишеры, операторы и сабскрайберы. В связке они работают так: сабскрайбер запрашивает у паблишера данные, паблишер отправляет данные сабскрайберу, по пути данные проходят через операторы. 

### Паблишеры

Если совсем просто - то пабоишеры предоставляют данные при необходимости. Данные доставляются как определенные нами объекты. Кроме этого, мы можем обрабатывать ошибки. Есть два типа паблишеров.

- `Just` - предоставляет только результат
- `Future` - предоставляет замыкание, которое в итоге возвращает ожидаемое значение или неудачно завершается.

`Subject` - особый вид паблишера, который используется для отправки данных одному или сразу нескольким подписчикам. Есть два вида встроенных subject в Combine: `CurrentValueSubject` и `PassthroughSubject`. Они очень похожи, но `CurrentValueSubject` должен инициализироваться с начальным значением. 

### Сабскрайберы

Подписчик запрашивает у паблишера данные. Он может отменить запрос, если это необходимо. Это прекратит подписку и завершит всю потоковую обработку данных от паблишера. Есть лва встроенных типа сабскрайберов, встроенных в Combine: `Assign` и `Sink`. `Assign` присваивает значения объектам напрямую, а  `Sink` определяет замыкание, аргументы которого это данные отправленные паблишером.

### Операторы

Оператор работает как прослойка между паблишером и сабскрайбером. Когда паблишер общается с оператором, он действует как сабскрайбер, а когда сабскрайбер общается с оператором, он действует как паблишер. Операторы нужны для изменения данных внутри конвейера. Например, нам нужно отфильтровать nil значения, указать метку времени, отформатировать данные и тд. Операторами могут быть функции `.map`, `.filter`, `.reduce` и другие.

## Приступаем

Теперь мы немного знаем про Combine и попробуем создать реактивное приложение.

Создаем новый проект, называем его SuperHero и выбираем SwiftUI вместо Storyboard.

![](/img/mvvm/create.png)

Начнем с самого главного - модели, которую будем заполнять данными из АПИ. Список всех героев получаем по URL `https://cdn.rawgit.com/akabab/superhero-api/0.2.0/api/all.json`. Для каждого героя отдается много информации, мы пока будем использовать только самую важную - id и name

```swift
import Foundation

struct Hero: Codable, Identifiable {
    let id: Int
    let name: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
    }
}
```

Enum `CodingKeys` нам пока не нужен - он понадобится когда названия полей в JSON будут отличаться от параметров в структуре. Но мне хочется поэкспериментировать с `CodingKey`

Теперь нужна заготовка `ViewModel`. Самый удобный паттерн для создания приложений все еще MVVM.  И мы будем его реализовывать, но уже с помощью Combine. А пока просто заглушка:

```swift
import Foundation

class HeroesViewModel: ObservableObject {
    @Published var heroes: [Hero] = []
}
```

Врапер `@Published` позволяет Swift следить за любыми изменениями этой переменной. Если что-то поменяется, то все свойства `body` во всех представлениях, где используется переменная `heroes` будут обновлены.

И теперь сделаем заготовочку для нашего `HeroesView`

```swift
import SwiftUI

struct HeroesView: View {
    @ObservedObject var viewModel = HeroesViewModel()
    
    var body: some View {
        List(viewModel.heroes) { hero in
            HStack {
                VStack(alignment: .leading) {
                    Text(hero.name).font(.headline)
                }
            }
        }
    }
}

struct HeroesView_Previews: PreviewProvider {
    static var previews: some View {
        HeroesView()
    }
}
```

Добавляем врапер `@ObservedObject` чтобы отлавливать все изменения объекта `viewModel`. Вот тут ` List(viewModel.heroes) { movie in` мы пробегаем по всему списку с героями. Позже, этот список будет сам престраиваться, при получении данных по сети.

Обратите внимание, что я переименовал стандартный `ContentView` в `HeroesView`. И надо не забыть поменять код в `SceneDelegate`:

```swift
let contentView = HeroesView().environment(\.managedObjectContext, context)
```

## Сетевые запросы

Воспользуемся _Alamofire_ для запросов. Для этого установим _Alamofire_ через _pods_. 

```
# Uncomment the next line to define a global platform for your project
# platform :ios, '9.0'

target 'SuperHero' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!

  # Pods for SuperHero
  pod 'Alamofire', '~> 5.2'

end
```

И делаем сервис, который будет получать данные из API

```swift
import Foundation
import Alamofire
import Combine

class HeroesService {
    let url = "https://cdn.rawgit.com/akabab/superhero-api/0.2.0/api/"
    
    func fetch() -> AnyPublisher<[Hero], AFError> {
        let publisher = AF.request(url + "all.json").publishDecodable(type: [Hero].self)
        return publisher.value() // value publisher
    }
}
```

Alamofire с 5 версии [стала поддерживать Combine](https://github.com/Alamofire/Alamofire/blob/master/Documentation/AdvancedUsage.md#using-alamofire-with-combine), что очень радует. 

В коде выше мы сначала создаем паблишера. Обратите внимание на возвращаемый тип: `AnyPublisher<[Hero], AFError>` - это и есть наш паблишер(если я ничего не напутал). Дальше мы модем подписаться на него и получать данные уже в ViewModel

```swift
class HeroesViewModel: ObservableObject {
    
    @Published var heroes: [Hero] = []
    var cancellation: AnyCancellable?
    let service = HeroesService()
    
    init() {
        fetchHeroes()
    }
    
    func fetchHeroes() {
        cancellation = service.fetch()
        .mapError({ (error) -> Error in
            print(error)
            return error
        })
        .sink(receiveCompletion: { _ in }, receiveValue: { heroes in
                self.heroes = heroes
        })
    }
}
```

`.sink` - тот самый сабскрайбер, который получает значения через замыкания. `self.heroes = heroes` - присваивает значение переменной, помеченной `@Published`. В View эти изменения заставят обновиться `var body: some View` и отрендерить новые данные.

## Навигация

Отлично, у нас есть список всех героев. Теперь сделаем детальный просмотр каждого героя. А для этого нам нужна навигация. Добави `NavigationView` в `HeroesView`. При тапе на имя будем переходить на детальное представление. Поэтому добавим `NavigationLink`

```swift
struct HeroesView: View {
    @ObservedObject var viewModel = HeroesViewModel()
    
    var body: some View {
        NavigationView {
            List(viewModel.heroes) { hero in
                HStack {
                    VStack(alignment: .leading) {
                        
                        NavigationLink(destination: HeroView(id: hero.id)) {
                           Text(hero.name)
                        }
                        
                    }
                }
            }
        }
        .navigationBarTitle("Navigation", displayMode: .inline)
    }
}
```

`HeroView` можно объявить в отдельном файле, но мне лень, поэтому я описал все в одном.

```swift
struct HeroView: View {
    var id: Int?
    
    @ObservedObject var viewModel = HeroViewModel()
    
    var body: some View {
        HStack {
            Text(viewModel.hero?.name ?? "")
        }.onAppear {
            self.viewModel.getHero(id: self.id ?? 0)
        }
        
    }
}

```

Как видно, мы передаем `id` при создании `HeroView(id: hero.id)`. А дальше получаем данные по герою используя его `id`. Для этого у нас есть отдельная `HeroViewModel`

```swift
import Foundation
import Combine

class HeroViewModel: ObservableObject {

    @Published var hero: Hero?
    var cancellation: AnyCancellable?
    let service = HeroesService()
   
    func getHero(id: Int) {
       cancellation = service.get(id: id)
       .mapError({ (error) -> Error in
           print(error)
           return error
       })
       .sink(receiveCompletion: { _ in },
             receiveValue: { hero in
               self.hero = hero
       })
   }
}
```

Один в один как `HeroesViewModel` но тут мв получаем данные только по одному герою, по его id и нам не нужно делать запросы при инициализации самой модели. Вместо этого, запрос за данными будет происходить по событию `.onAppear` в `HeroView`

И последний штрих - загрузка картинки по URL. К сожалению, SwiftUI не умеет делать это сам(не умеет делать это просто). Воспользуемся сторонней библиотекой `URLImage`. Сама либа [доступна на гитхаб](https://github.com/dmytro-anokhin/url-image).

Сделаем небольшую обертку для ее использования:

```swift
struct Image: View {
    var url: String?

    var body: some View {
        guard let u = URL(string: url ?? "") else {
            return AnyView(Text("Loading..."))
        }
        return AnyView(URLImage(u))
    }
}
```

И теперь используем эту обертку в нашей детальной вьюхе.

```swift
struct HeroView: View {
    var id: Int?
    
    @ObservedObject var viewModel = HeroViewModel()
    
    var body: some View {
        VStack {
            Text(viewModel.hero?.name ?? "")
            Image(url: viewModel.hero?.images?.large ?? "")
        }.onAppear {
            self.viewModel.getHero(id: self.id ?? 0)
        }
        
    }

```

Что должно получится:

![](/img/mvvm/result.gif)

На этом краткое введение в использование Combine закончено. Больше информации по ссылкам.

## Ссылки 

Откуда я брал информацию и идеи.

- Проект на [гитхабе](https://github.com/horechek/super-heroes)
- Официальная [документация по Combine](https://developer.apple.com/documentation/combine)
- Большущая статья про Combine, SwiftUI и как надо делать приложения под iOS. Я понял не все, но я стараюсь: [Modern MVVM iOS App Architecture with Combine and SwiftUI](https://www.vadimbulavin.com/modern-mvvm-ios-app-architecture-with-combine-and-swiftui/)
- [Навигация в SwiftUI](https://www.hackingwithswift.com/articles/216/complete-guide-to-navigationview-in-swiftui). Туториал от hackingwithswift.
- Еще одна статья про Combine, но уже попроще: [Combine networking with a hint of SwiftUI](https://engineering.nodesagency.com/categories/ios/2020/03/16/Combine-networking-with-a-hint-of-swiftUI)