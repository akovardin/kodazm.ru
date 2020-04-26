+++
date = "2020-04-26T12:00:00+03:00"
draft = false
title = "Core Data"
tags = ["ios", "swift", "swiftui"]
+++

![](/img/core-data/main.png)

Core Data - фреймворк для работы с базой дынных в приложениях. С его помощью можно хранить и управлять данными. Я не часто его использовал, и у меня никак не было времени, чтобы разобраться с ним. Но на этих выходных время пришло.

Чтобы разобраться в принципах работы с Core Data, я хочу написать небольшое туду приложение. Звучит банально, но в этом приложении список дел можно будет сохранять как изображение и делать его заставкой на экране.

<!--more-->

### Новый проект

Начну с создания нового проекта. Желательно, отметить галочку как указано на картинке. В этом случае в файлах _AppDelegate.swift_ и _SceneDelegate.swift`_ сгенерируется дополнительный код и добавится специальный файл _Memo.xcdatamodeld_. Memo - это название моего проекта.

![](/img/core-data/create.png)

В файле _SceneDelegate.swift_ в функции `scene` появилась новая строчка

```
// Get the managed object context from the shared persistent container.
let context = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext
```

Эта функция возвращает контекст управляемого объекта(managed object context). Контекст управляемого объекта похож на блокнот, который хранится в оперативной памяти. Это место, где объекты создаются, выбираются, обновляются, удаляются и сохраняются обратно в постоянное хранилище на устройстве.

Ниже еше одна интересная строчка кода:

```
// Add `@Environment(\.managedObjectContext)` in the views that will need the context.
let contentView = ContentView().environment(\.managedObjectContext, context)
```

Тут создается `ContentView`, который потом передается в конструктор контроллера. Но что это за `environment`?

Перед тем, как запустится, наше корневое представление `ContentView` - в окружении установится новый параметр `managedObjectContext` с контекстом, который мы только что создали. Окружение - это место где хранятся различные системны параметры, например локаль календаря, цветовая схема и т.д. Все эти параметры хранятся по разным ключам. И теперь наш контекст тоже хранится там по ключу `managedObjectContext`.

Теперь каждое представление может использовать "блокнот" для работы с объектами.

Определимся со структурой данных которыми буду манипулировать в приложении. Для этого в файл _Memo.xcdatamodeld_ добавлю новую сущность `Todo`. Для этого надо кликнуть на большой жирный плюс _Add Entity_

![](/img/core-data/generate5.png)

Теперь к новой сущности добавляем нужные аттрибуты. Для простого туду достаточно добавить `text`, `done` и поля `id` с типом UUID(это поле будет использоваться как уникальный идентификатор объекта).

![](/img/core-data/generate0.png)

Генерировать код в ручную не обязательно. Можно оставить значение _Class Definition_ в поле _Codegen_ и успокоится. Но я выберу _Manual/None_ - это позволит сгенерировать файлы в папке проекта и посмотреть что там будет.

![](/img/core-data/generate4.png)

Теперь генерирую файлы.

![](/img/core-data/generate1.png)

![](/img/core-data/generate2.png)

Получается пара новый файлов в проекте: `Memo+CoreDataClass.swift` и `Memo+CoreDataProperties.swift`. В `Memo+CoreDataClass.swift` описан сам объект. А в `Memo+CoreDataClass.swift` описываются его свойства.

Замечу, что еще один плюс генерации классов в ручную - возможность вносить разные дополнения, которые недоступны при работе только через интерфейс для `.xcdatamodeld`. Например, можно сделать нужные поля как `enum`. Или добавить реализацию нужного интерфейса.

![](/img/core-data/generate3.png)

### Интерфейс

Нужно убедиться, что блок предпросмотра имеет доступ к параметру окружения `managedObjectContext` как и все приложение.

```
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        
        let context = (UIApplication.shared.delegate as! AppDelegate).persistentContainer.viewContext
        
        return ContentView().environment(\.managedObjectContext, context)
    }
}
```

Теперь к интерфейсу самого приложения. Делать его буду стильно, модно и молодежно с помощью SwidtUI. Нужен заголовок, список с задачами, текстовое поле и кнопка для добавления новых задач. В `ContentView` добавил такой код:

```
import SwiftUI
import CoreData

struct ContentView: View {
    @State var todo = ""
    
    var body: some View {
        NavigationView {
            VStack {
                // форма для создания нового таска
                HStack {
                    TextField("Task",text: $todo).padding(.all, 20)
                    Button(action: {
                       
                    }){
                        Text("Add Task")
                    }.padding(.all, 20)
                }
                // список всех задач
                List {
                    HStack {
                        Text("Hello, World!")
                        Spacer() в
                        Button(action: {
                           
                        }){
                            Text("Complete")
                            .foregroundColor(.blue)
                        }
                    }
                    HStack {
                        Text("Hello, World!")
                        Spacer()
                        Button(action: {
                           
                        }){
                            Text("Complete")
                            .foregroundColor(.blue)
                        }
                    }
                }
            }.navigationBarTitle(Text("Tasks")
                .font(.largeTitle))
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
```

Теперь подружу интерфейс с Core Data.

### Сохраняем данные

Пока у меня ничего не сохранятся и не выводится. Чтобы сохранить новую задачу, нужно иметь доступ к контексту управляемого объекта. И тут становится понятным, зачем мы добавляли контекст в окружение. К нему можно получить доступ, используя свойство `@Environment` внутри нашего `ContentView`.

```
@Environment(\.managedObjectContext) var managedObjectContext

@State var todo = ""
```

И теперь можем написать код, который создает новый объект `Task`. Этот код нужно поместить в экшене кнопки `"Add Task"`

```
Button(action: {
                       
    guard self.todo != "" else {return}
    
    let todo = Todo(context: self.managedObjectContext)
    todo.text = self.todo
    todo.done = false
    todo.id = UUID()
    
}){
    Text("Add Task")
}.padding(.all, 20)
```

И теперь с помощью managedObjectContext сохраняем данные на устройстве.

### Читаем данные

Чтобы прочитать сохраненные данные из хранилища, воспользуюсь свойством `@FetchRequest`, которое добавлю в `ContentView`. С помощью этого свойства очень легко манипулировать сохраненными данными.

```
@FetchRequest(entity: Todo.entity(), sortDescriptors: []) var todos: FetchedResults<Todo>
```

Это, конечно, круто что можно одной строчкой объявить переменную и сразу указать что она заполнится данными их хранилища. Но как пом не, это не очень очевидно и читать такие объявления в чужом коде - самая настоящая боль. И это еще не используется параметр `predicate` в свойстве `@FetchRequest` который может сделать все объявление нечитаемым.

Теперь отредактирую отображение списка задач, добавлю цикл по `todos` с помощью `ForEach`

```
ForEach(todos) { todo in
    HStack {
        Text(todo.text!)
        Spacer()
        Button(action: {
            
        }){
            Text("Complete")
            .foregroundColor(.blue)
        }
    }
}
```

Этот код у меня не захотел сразу работать

![](/img/core-data/code0.png)

Чтобы избавиться от этих ошибок - нужно добавить интерфейс `Identifiable` для класса `Todo` в файле `Todo+CoreDataProperties.swift`

```
extension Todo: Identifiable {
    // ...
}
```

У нас уже есть аттрибут `id`, поэтому после добавления интерфейса все заработает как нужно.

Запускаем эмулятор и добавляем новые задачи.

![](/img/core-data/code1.png)

### Редактирование и удаление

Отлично! Можно добавлять новые задачи. Осталось добавить возможность помечать их как выполненными и удалять. Для этого изменю блок с кнопкой - добавлю условие и сделаю две кнопки.

```
HStack {
    Text(todo.text!)
    Spacer()
    if todo.done {
        Button(action: {
            
        }){
            Text("Remove")
            .foregroundColor(.blue)
        }
    } else {
        Button(action: {
            
        }){
            Text("Complete")
            .foregroundColor(.blue)
        }
    }
}
```

Теперь в несколько строчек реализуем выполнение задачи

```
Button(action: {
    todo.done = true
    
    do {
        try self.managedObjectContext.save()
    } catch {
        print(error.localizedDescription)
    }
    
}){
    Text("Complete")
    .foregroundColor(.blue)
}
```

И удаление

```
Button(action: {
    self.managedObjectContext.delete(todo)
}){
    Text("Remove")
    .foregroundColor(.blue)
}
```

### Заключение

В приложениях на SwiftUI стало еще проще использовать Core Data. Всю основную магию за вас делает свойство `@FetchRequest`. Но если вы новичек в Swift и iOS, то вам стоит подробнее изучить как работает выборка объектов из хранилища и что такое предикаты.

Код из статьи [доступен на GitHub](https://github.com/horechek/memo).

Ссылки по теме:

- [Core Data в деталях](https://habr.com/ru/post/436510/)
- [Core Data: Часть 1](https://swiftbook.ru/post/tutorials/core-data-chast-1/)
- [Core Data: Часть 2. Lightweight Миграции](https://swiftbook.ru/post/tutorials/core-data-chast-2-lightweight-migracii/)
- [Introduction to using Core Data with SwiftUI](https://www.hackingwithswift.com/quick-start/swiftui/introduction-to-using-core-data-with-swiftui)
- [How to make a task list using SwiftUI and Core Data](https://dev.to/maeganwilson_/how-to-make-a-task-list-using-swiftui-and-core-data-513a)