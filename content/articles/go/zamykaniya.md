+++
date = "2016-04-12T15:25:03+03:00"
draft = false
title = "Замыкания"

+++

<p>Перевод статьи "<a href="http://keshavabharadwaj.com/2016/03/31/closure_golang/">Closures in golang</a>"</p>

<p>Замыкания - это такие функции, которые вы можете создавать в рантайме и им будет доступно текущее окружение, в рамках которого они были созданы. Другими словами, функции, определенные как замыкания, "запоминают" окружение, в котором они были созданы.</p>

<p>Перед тем как мы начнем разбираться с замыканиями, давайте определимся с функциями и анонимными функциями.</p>

<h3>Анонимные функции</h3>

<p>Функции, у которых есть имя - это именованные функции. Функции, которые могут быть созданы без указания имени - это анонимные функции. Все просто :) Как можно видет в приведенном ниже коде, можно создать анонимную функцию и непосредственно вызвать или можно присвоить функцию некоторой переменной и вызвать с указанием этой переменной. В общем случае, для замыканий используются анонимные функции. В Go у вас есть возможность создать анонимную функцию и передать ее как параметр в другую функцию, таким образом мы используем функции высшего порядка.</p>

<p>Функция <code>getPrintMessage</code> создает анонимную функцию и возвращает ее. В <code>printfunc</code> сохраняется анонимная функция, которая затем вызывается.</p>

<pre><code>package main

import "fmt"

func printMessage(message string) {
    fmt.Println(message)
}

func getPrintMessage() func(string) {
    // Возвращаем анонимную функцию
    return func(message string) {
        fmt.Println(message)
    }
}

func main() {
    // Именованная функция
    printMessage("Hello function!")

    // Анонимная фукция объявляется и вызывается
    func(message string) {
        fmt.Println(message)
    }("Hello anonymous function!")

    // Получаем анонимную функцию и вызываем ее
    printfunc := getPrintMessage()
    printfunc("Hello anonymous function using caller!")

}
</code></pre>

<h3>Замыкания</h3>

<p>Ниже, функция <code>foo</code> это внутренняя функция и у нее есть доступ к переменной <code>text</code>, определенной за рамками функции <code>foo</code> но внутри функции <code>outer</code>. Вот эта функция <code>foo</code> и называется замыканием. Она как бы замыкает переменные из внешней области видимости. Внутри нашего замыкания переменная <code>text</code> будет доступна.</p>

<pre><code>package main

import "fmt"

func outer(name string) {
    // переменная из внешней функции
    text := "Modified " + name

    // foo это внутренняя функция и из нее есть доступ к переменной `text`
    // у замыкания есть доступ к этим переменным даже после выхода из блока 
    foo := func() {
        fmt.Println(text)
    }

    // вызываем замыкание
    foo()
}

func main() {
    outer("hello")
}
</code></pre>

<h3>Возвращаем замыкание и используем его снаружи</h3>

<p>В этом примере покажем как можно возвращать замыкание из функции, в которой оно было определено. <code>foo</code> это замыкание, которое возвращается в главную функцию когда внешняя функции вызывается. А вызов самого замыкания происходит в момент, когда используются <code>()</code>. Этот код выводит сообщение "Modified hello". Таким образом, в замыкании <code>foo</code> все еще доступна переменная <code>text</code>, хотя мы уже вышли из внешней функции.</p>

<pre><code>package main

import "fmt"

func outer(name string) func() {
    // переменная
    text := "Modified " + name

    // замыкание. у функции есть доступ к переменной text даже 
    // после выхода за пределы блока
    foo := func() {
        fmt.Println(text)
    }

    // возвращаем замыкание
    return foo
}

func main() {
    // foo это наше замыкание
    foo := outer("hello")

    // вызов замыкания
    foo()
}
</code></pre>

<h3>Замыкание и состояние</h3>

<p>Замыкания сохраняют состояние. Это означает, что состояние переменных содержится в замыкании в момент декларации. Что это значит:</p>

<ul>
<li>Состояние(ссылки на переменные) такие же как и в момент создания замыкания. Все замыкания созданные вместе имеют общее состояние.</li>
<li>Состояния будут разными если замыкания создавались по разному.</li>
</ul>

<p>Давайте посмотрим на код ниже. Мы реализуем функцию, которая принимает начальное значение и возвращает два замыкания: <code>counter(str)</code> и <code>incrementer(incr)</code>. И в этом случае, состояние(переменная <code>start</code>) будет одинаковым для обоих замыканий. После следующего вызова функции <code>counter</code>, мы получим еще два замыкания с уже новым состоянием.</p>

<p>В нашем примере при первом вызове <code>counter(100)</code> мы получаем замыкания <code>ctr</code>, <code>intr</code> в которых сохранен один и тот же указатель на 100.</p>

<pre><code>package main

import "fmt"

func counter(start int) (func() int, func()) {
    // если значение мутирует, то мы получим изменение и в этом замыкании
    ctr := func() int {
        return start
    }

    incr := func() {
        start++
    }

    // и в ctr, и в incr сохраняется указатель на start
    // мы создали замыкания но еще не вызывали
    return ctr, incr
}

func main() {
    // ctr, incr и ctr1, incr1 различаются своим состоянием
    ctr, incr := counter(100)
    ctr1, incr1 := counter(100)
    fmt.Println("counter - ", ctr())
    fmt.Println("counter1 - ", ctr1())
    // увеличиваем на 1
    incr()
    fmt.Println("counter - ", ctr())
    fmt.Println("counter1- ", ctr1())
    // увеличиваем до 2
    incr1()
    incr1()
    fmt.Println("counter - ", ctr())
    fmt.Println("counter1- ", ctr1())
}
</code></pre>

<p>Как видите, изначально оба значение равны 100. И когда мы увеличиваем значение с помощью <code>incr()</code>, замыкание <code>ctr1()</code> выводит старое значение, а <code>ctr()</code> выводит уже 101. Точно так же, если вызывать замыкание <code>incr1()</code>, то <code>ctr()</code> будет всегда выводить 101, а <code>ctr1()</code> будет показывать новые значения.</p>

<pre><code>ctr1() would be 102.
counter -  100
counter1 -  100
counter -  101
counter1-  100
counter -  101
counter1-  102
</code></pre>

<h3>Ловушки</h3>

<p>Одна из самых очевидных ловушек - это создание замыканий в цикле. Рассмотрим пример кода ниже.</p>

<p>Мы создаем 4 замыкания в цикле и возвращаем слайс с замыканиями. Каждое замыкание выполняет одинаковые действия: выводит индекс и значение по этому индексу. Главная функция проходит по слайсу и вызывает все эти замыкания.</p>

<pre><code>package main

import "fmt"

func functions() []func() {
    // ловушка с циклами
    arr := []int{1, 2, 3, 4}
    result := make([]func(), 0)

    // функции не вызываются, только определяются и возвращаются
    // так как функции используют i и arr[i]
    // то они будут работать только с последними значениями i
    for i := range arr {
        result = append(result, func() { fmt.Printf("index - %d, value - %d\n", i, arr[i]) })
    }

    // если такое поведение необходимо, то следует использовать параметры
    //for i := range arr {
    //  result = append(result, func(index, val int) { fmt.Printf("index - %d, value - %d\n", index, val) })
    //}

    return result
}

func main() {
    fns := functions()
    for f := range fns {
        fns[f]()
    }
}
</code></pre>

<p>Посмотрим на результат выполнения скрипта</p>

<pre><code>index - 3, value - 4
index - 3, value - 4
index - 3, value - 4
index - 3, value - 4
</code></pre>

<p>Не очень приятный сюрприз. Давайте разберемся почему. Если мы вернемся на пару шагов назад и вспомним, что замыкания создаются единожды и имеют общее состояние, то проблема начинает проясняться. В нашем случае, все замыкания ссылаются на одни и теже переменные <code>i</code> и <code>arr</code>. Когда замыкания вызываются в главной функции, значение <code>i</code> равно 3 и значение во всех замыканиях мы получаем по ключу <code>arr[3]</code>.</p>

<h3>Что в результате</h3>

<p>Надеюсь, что поле прочтения этой статьи, вы чуть лучше понимаете принципы работы с замыканиями и теперь вам проще читать код в котором используются замыкания.</p>

<p>Для более углубленного понимания рекомендую прочитать две замечательные статьи, указанные ниже. В этих статьях говорится о замыканиях в контексте JavaScript, но для понимания основ это не так важно.</p>

<ul>
<li><a href="https://developer.mozilla.org/en/docs/Web/JavaScript/Closures">О замыканиях в блоге Mozilla</a>.</li>
<li><a href="http://stackoverflow.com/questions/111102/how-do-javascript-closures-work?rq=1">Дискуссия о замыканиях на stackoverflow</a>.</li>
</ul>