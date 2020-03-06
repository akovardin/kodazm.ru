+++
date = "2020-01-12T12:00:00+03:00"
draft = false
title = "Пишем свой BitTorrent клиент на Go"
tags = ["golang", "torrent", "bittorrent"]
+++

![](/img/bittorrent/main.png)

Перевод "[Building a BitTorrent client from the ground up in Go](https://blog.jse.li/posts/torrent/)"

Что происходит с момента визита на thepiratebay и появлением mp3 файла на вашем компьютере? В этом посте мы реализуем BitTorrent протокол на достаточном для скачивания образа Debian уровне. Можете сразу посмотреть исходный код и пропустить все подробные объяснения. Можете начинать с [исходного кода](https://github.com/veggiedefender/torrent-client/) и потом переходить к подробным объяснениям.

<!--more-->

BitTorrent это протокол для скачивания файлов и распространения их через интернет. В отличие от традиционного клиент-серверного взаимодействия(например, просмотров фильмов на Netflix или загрузка интернет страничек), участники BitTorrent сети, которые называются peer'ами, скачивают части файлов друг с друга. Такое взаимодействие называется peer-to-peer протоколом. Мы разберемся как он работает, и напишем свой собственный клиент, который сможет находить peer'ы и обмениваться с ними данными.

![](/img/bittorrent/client-server-p2p.png)

Последние 20 лет протокол эволюционировал. Различные организации и разработчики расширяли его и добавляли новые функции для шифрования, частных торрентов и новых способов поиска peer'ов. Мы реализуем оригинальный протокол 2001 года, чтобы наш учебный проект оставался маленьким и реализуемым за одни выходные.

Для экспериментов будем использовать [Debian ISO](https://cdimage.debian.org/debian-cd/current/amd64/bt-cd/#indexlist) как подопытного кролика. Это большой файл, но не огромный: 350мб.

## Поиск peer'ов

И так, нам нужно скачать файл с помощью BitTorrent. Но это peer-to-peer протокол и пока мы понятия не имеем, где найти peer'ов для скачивания. Похоже на переезд в новый город и поиск новых друзей: вы можете познакомиться в баре поблизости или на каком ни будь митапе. Эта идея лежит в основе централизованных __трекеров__, которые позволяют peer'ам знакомиться друг с другом. Как правило, это обычные серверы, работающие через HTTP. Например, образ Дебиана есть тут [http://bttracker.debian.org:6969/](http://bttracker.debian.org:6969/)

![](/img/bittorrent/trackers.png)

Такие централизованные серверы подвергаются нападкам со стороны правообладателей. Возиожно, вы читали про трекеры TorrentSpy, Popcorn Time и KickassTorrents, которые были закрыты за распространение нелегального контента. Сегодня уже существуют методы поиска peer'ов без посредников: одноранговый распределенный поиск. Мы не будем реализовывать эти алгоритмы, но если вам интересно - почитайте про  DHT, PEX и магнет ссылки.

### Разбор .torrent файла

В .torrent файле содержится информация о трекере и о самом файле, который нужно скачать. Для начала скачивания этого достаточно. Дебиановский .torrent файл выглядит так:

```
d8:announce41:http://bttracker.debian.org:6969/announce7:comment35:"Debian CD from cdimage.debian.org"13:creation datei1573903810e9:httpseedsl145:https://cdimage.debian.org/cdimage/release/10.2.0//srv/cdbuilder.debian.org/dst/deb-cd/weekly-builds/amd64/iso-cd/debian-10.2.0-amd64-netinst.iso145:https://cdimage.debian.org/cdimage/archive/10.2.0//srv/cdbuilder.debian.org/dst/deb-cd/weekly-builds/amd64/iso-cd/debian-10.2.0-amd64-netinst.isoe4:infod6:lengthi351272960e4:name31:debian-10.2.0-amd64-netinst.iso12:piece lengthi262144e6:pieces26800:(binary blob of the hashes of each piece)ee
```

Данные в .torrent файле закодированы в формате Bencode и нам нужно его декодировать.

В bencode такие же типы как в JSON: строки, числа, списки и словари. Данные в формате bencode, в отичии от JSON, не особо человеко-читаемые. Но такой формат очень удобен для бинарных данных и потокового чтения. Строки начинаются с префикса, в котором указана длина, и выглядят так `4:spam`. Числа начинаются и заканчиваются маркерами, например 7 будет выглядеть как `i7e`. Списки и словари очень похожи: `l4:spami7ee` это `['spam', 7]`, а `d4:spami7ee` означает `{spam: 7}`.

Если отформатировать наш .torrent файл, то все становится намного понятней:

```
d
  8:announce
    41:http://bttracker.debian.org:6969/announce
  7:comment
    35:"Debian CD from cdimage.debian.org"
  13:creation date
    i1573903810e
  4:info
    d
      6:length
        i351272960e
      4:name
        31:debian-10.2.0-amd64-netinst.iso
      12:piece length
        i262144e
      6:pieces
        26800: (binary blob of the hashes of each piece)
    e
e
```

Из этого файла можно узнать URL трекера, имя и размер файла, дату создания(в unix формате), размер частей(piece length) на которые разбит нужный нам файл. Кроме этого, в файле есть большой кусок бинарных данных, в котором содержаться SHA-1 хэши всех частей(pieces). Размер частей для разных торрентов может быть разный, но, как правило, в пределах 256KB и 1MB. Большой файл может состоять из тысяч частей. Нам нужно скачать каждую часть с наших peer'ов, проверить хэши по нашему торрент файлу, собрать эти части вмести и готово!

![](/img/bittorrent/pieces.png)

Такой механизм позволяет проверить отдельно каждую часть файла и защититься от случайного и намеренного повреждения файла. Если злоумышленник не взломал SHA-1, то мы получим тот файл, который ожидаем.

Было бы прикольно написать свой bencode парсер. Но хочется сконцентрироваться на важных вещах, поэтому будем использовать готовый парсер [github.com/jackpal/bencode-go](https://github.com/jackpal/bencode-go). А если вы хотите получше разобраться с bencode форматом - посмотрите [парсер от Fredrik Lundh](https://effbot.org/zone/bencode.htm) в 50 строчек кода.

```go
import (
    "github.com/jackpal/bencode-go"
)

type bencodeInfo struct {
    Pieces      string `bencode:"pieces"`
    PieceLength int    `bencode:"piece length"`
    Length      int    `bencode:"length"`
    Name        string `bencode:"name"`
}

type bencodeTorrent struct {
    Announce string      `bencode:"announce"`
    Info     bencodeInfo `bencode:"info"`
}

// Open parses a torrent file
func Open(r io.Reader) (*bencodeTorrent, error) {
    bto := bencodeTorrent{}
    err := bencode.Unmarshal(r, &bto)
    if err != nil {
        return nil, err
    }
    return &bto, nil
}
```

Я стараюсь оставлять структуры максимально плоскими и отделять структуры сериализации от структур приложения. Поэтому я сделал экспортируемой другую, более плоскую структуру `TorrentFile` и добавил несколько методов для преобразования между ними.

Обратите внимание, я разбил `pieces` (во внутренной структуре это обычная строка) на список хэшей по 20 байт. Так с ними будет проще работать. И вычислил общий SHA-1 хэш всего bencode закодированного словаря info(в котором содержится имя, размер и хэши всех частей). Этот общий хэш будет работать как идентификатор и понадобится для взаимодействия с трекером и peer'ами. Об этом чуть позже.

![](/img/bittorrent/info-hash.png)

```go
type TorrentFile struct {
    Announce    string
    InfoHash    [20]byte
    PieceHashes [][20]byte
    PieceLength int
    Length      int
    Name        string
}

func (bto *bencodeTorrent) toTorrentFile() (*TorrentFile, error) {
    // ...
}
```

### Получаем peer'ов через трекер

Теперь у нас есть информация о файле и трекере, давайте сделаем запрос на сервер чтобы объявить(announce) о нашем присутствии как peer'a и получить список других peer'ов. Для этого нужно сделать GET запрос на `announce` URL трекера с нужными параметрами:

```go
func (t *TorrentFile) buildTrackerURL(peerID [20]byte, port uint16) (string, error) {
    base, err := url.Parse(t.Announce)
    if err != nil {
        return "", err
    }
    params := url.Values{
        "info_hash":  []string{string(t.InfoHash[:])},
        "peer_id":    []string{string(peerID[:])},
        "port":       []string{strconv.Itoa(int(Port))},
        "uploaded":   []string{"0"},
        "downloaded": []string{"0"},
        "compact":    []string{"1"},
        "left":       []string{strconv.Itoa(t.Length)},
    }
    base.RawQuery = params.Encode()
    return base.String(), nil
}
```

Что тут важно:

* `info_hash` - идентифицирует файл, который мы хотим скачать.  Это хэш, который мы вычислили раньше по словарю `info`. Трекеру нужно знать этот хэш, чтобы показать нам правильных peer'ов.
* `peer_id` - 20-ти байтное имя, которое идентифицирует нас на трекере и для других peer'ов. Используем случайно сгенерированную последовательность. Реальные BitTorrent клиенты используют идентификаторы вида `-TR2940-k8hj0wgej6ch`, в котором закодированы используемая программа для скачивания и ее версия. В нашем примере, TR2940 это клиент Transmission версии 2.94.

![](/img/bittorrent/info-hash-peer-id.png)

### Разбираем ответ трекера

В ответе от сервера приходят bencod закодированные данные.

```
d
  8:interval
    i900e
  5:peers
    252:(another long binary blob)
e
```

Поле `interval` указывает как часто мы можем делать запрос на сервер для обновления списка peer'ов. Это значение в секундах(900 секунд = 15 минут).

Поле `peers` - это большой кусок бинарных данных, в котором содержаться IP адреса каждого peer'а. Его нужно разбить на группы по 6 байтов. Первые 4 байта - это IP адрес узла, последние 2 байта - порт(uint16 в big-endian кодировке). Big-endian(или сетевой порядок) означает, что можно интерпритировать целое число как группу байтов, просто составляя их по порядку слева на право. Например, байты 0x1A, 0xE1 будут кодироваться в порядке 0x1AE1 или 6881 в десятичном формате.

![](/img/bittorrent/address.png)

```go
// Peer encodes connection information for a peer
type Peer struct {
    IP   net.IP
    Port uint16
}

// Unmarshal parses peer IP addresses and ports from a buffer
func Unmarshal(peersBin []byte) ([]Peer, error) {
    const peerSize = 6 // 4 for IP, 2 for port
    numPeers := len(peersBin) / peerSize
    if len(peersBin)%peerSize != 0 {
        err := fmt.Errorf("Received malformed peers")
        return nil, err
    }
    peers := make([]Peer, numPeers)
    for i := 0; i < numPeers; i++ {
        offset := i * peerSize
        peers[i].IP = net.IP(peersBin[offset : offset+4])
        peers[i].Port = binary.BigEndian.Uint16(peersBin[offset+4 : offset+6])
    }
    return peers, nil
}
```

## Скачивание с peer'ов

Теперь у нас есть список peer'ов. Настало время соединиться с ними и начать скачивать части файла. Этот процесс можно разбить на несколько этапов. Для каждого peer'а нужно:

1. Начать TCP соединение c peer'ом. Это как начать телефонный разговор.
2. Выполнить двухсторонний BitTorrent хендшейк. _"Hello?" "Hello."_
3. Обмен сообщениями для скачивания частей файла. "Мне нужна часть №231, пожалуйста."

### Начинаем TCP соединение

```go
conn, err := net.DialTimeout("tcp", peer.String(), 3*time.Second)
if err != nil {
    return nil, err
}
```

Тут используется таймаут для соединения, чтобы не зависать долго на попытках подключения к peer'ам.

### Выполняем хендшейк(рукопожатие)

Мы подключились к peer'у, но теперь нежно выполнить рукопожатие, чтобы убедится 

* Peer может взаимодействовать по BitTorrent протоколу
* Может понимать ниши сообщения и отвечать на них
* Знает про файл, который мы хотим скачать

![](/img/bittorrent/handshake.png)

Мой старик отец как-то сказал мне, что секрет хорошего рукопожатия в его крепкость и зрительном контакте. Для хорошего BitTorrent рукопожатия тоже нужно знать несколько секретов:

1. Длина идентификатора протокола всегда 19 (0x13 в hex)
2. Сам идентификатор, который называется pstr, всегда `BitTorrent protocol`
3. Восемь зарезервированных байтов, которые используются для указания расширенных возможностей. В нашем случае - все выставлены в 0.
4. Хэш для идентификации файлов(infohash, инфохэш), который мы вычислили раньше.
5. Идентификатор нашего peer'а.

Собираем все вместе. Наш хендшейк выглядит так:

```
\x13BitTorrent protocol\x00\x00\x00\x00\x00\x00\x00\x00\x86\xd4\xc8\x00\x24\xa4\x69\xbe\x4c\x50\xbc\x5a\x10\x2c\xf7\x17\x80\x31\x00\x74-TR2940-k8hj0wgej6ch
```

После отправки хендшейка, в ответ ожидаем получить аналогичную строку. Инфохэш, который мы получили в ответе, должен совпадать с нашим - так мы будем знать что говорим об одном и том же файле. Если все прошло хорошо, то переходим к следующему этапу. Если нет, то можем повторить, а если ошибки повторяются, то просто разрываем соединение.

Давайте реализуем структуру для хендшэйка и несколько дополнительных методов для сериализации и чтения.

```go
// A Handshake is a special message that a peer uses to identify itself
type Handshake struct {
    Pstr     string
    InfoHash [20]byte
    PeerID   [20]byte
}

// Serialize serializes the handshake to a buffer
func (h *Handshake) Serialize() []byte {
    pstrlen := len(h.Pstr)
    bufLen := 49 + pstrlen
    buf := make([]byte, bufLen)
    buf[0] = byte(pstrlen)
    copy(buf[1:], h.Pstr)
    // Leave 8 reserved bytes
    copy(buf[1+pstrlen+8:], h.InfoHash[:])
    copy(buf[1+pstrlen+8+20:], h.PeerID[:])
    return buf
}

// Read parses a handshake from a stream
func Read(r io.Reader) (*Handshake, error) {
    // Do Serialize(), but backwards
    // ...
}
```

### Отправка и получение сообщений

Как только мы выполнили руопожатие, можем посылать и получать сообщения. Ну не совсем. Пока peer не согласится принимать сообщения, то нет смысла ему что-то отправлять. Сейчс мы считаемся "задушенными"(`choked`) для других peer'ов. Они должны отправить нам сообщение unchoke итолько после этого мы сможем отправлять им сообщения и запрашивать у них данные. По умолчанию, считаем что все драгие peer'ы нас "душат".

Когда нам присылают сообщение `unchoked`, можем начитать отправлять запросы за частями файла и ждать в ответ сообщения с этими частями.

![](/img/bittorrent/choke.png)

### Разбор сообщений

В сообщении содержится длиа, идентификатор и полезная нагрузка. Это выглядит так: 

![](/img/bittorrent/message.png)

Сообщение начинается с указания длины. Это 32-х битное целое число в виде 4 байтов в big-endian кодировке. Следующий байт - ID(идентификатор), который означает какой тип сообщения мы получили. Например, 2 означает тип сообщения "interested". Псоледня часть сообщения содержит полезную нагрузку.

```go
type messageID uint8

const (
    MsgChoke         messageID = 0
    MsgUnchoke       messageID = 1
    MsgInterested    messageID = 2
    MsgNotInterested messageID = 3
    MsgHave          messageID = 4
    MsgBitfield      messageID = 5
    MsgRequest       messageID = 6
    MsgPiece         messageID = 7
    MsgCancel        messageID = 8
)

// Message stores ID and payload of a message
type Message struct {
    ID      messageID
    Payload []byte
}

// Serialize serializes a message into a buffer of the form
// <length prefix><message ID><payload>
// Interprets `nil` as a keep-alive message
func (m *Message) Serialize() []byte {
    if m == nil {
        return make([]byte, 4)
    }
    length := uint32(len(m.Payload) + 1) // +1 for id
    buf := make([]byte, 4+length)
    binary.BigEndian.PutUint32(buf[0:4], length)
    buf[4] = byte(m.ID)
    copy(buf[5:], m.Payload)
    return buf
}
```

Вычитываем сообщение из потока и разбираем его следуя формату. Сначала читаем 4 первых байта и интерпритируем их как `uint32`. Это длина нашего сообщения, которую используем чтобы прочитать все сообщение. Получаем ID(идентификатор) - первый байт и payload(полезеную нагрузку) - остаток сообщения.

```go
// Read parses a message from a stream. Returns `nil` on keep-alive message
func Read(r io.Reader) (*Message, error) {
    lengthBuf := make([]byte, 4)
    _, err := io.ReadFull(r, lengthBuf)
    if err != nil {
        return nil, err
    }
    length := binary.BigEndian.Uint32(lengthBuf)

    // keep-alive message
    if length == 0 {
        return nil, nil
    }

    messageBuf := make([]byte, length)
    _, err = io.ReadFull(r, messageBuf)
    if err != nil {
        return nil, err
    }

    m := Message{
        ID:      messageID(messageBuf[0]),
        Payload: messageBuf[1:],
    }

    return &m, nil
}
```

### Bitfields

Самый интересный тип сообщения - bitfield. Это структура, которую peer'ы используют для эффективного кодирования фрагментов, которые они могут нам отправить. Bitfield работает как массив битов. Биты, выставленные в 1, указывают какие части файлов есть у peer'а. Это похоже на карту локальности кофейни. Начинаем с пустой карты(все биты 0), заканчиваем когда вся карта проштампована(все биты в 1).

![](/img/bittorrent/bitfield.png)

Работа с _битами_ экономичней чем работа с _байтами_, такие структуры намного копмпактней. Мы можем закодировать информацию о 8 частях в одном байте - это размер типа `bool`. Но с такими структурами не так удобно раотать. Самый маленький размер для адресации - байт. Поэтому для работы с битами нужно выполнять дополнительные манипуляции.

```go
// A Bitfield represents the pieces that a peer has
type Bitfield []byte

// HasPiece tells if a bitfield has a particular index set
func (bf Bitfield) HasPiece(index int) bool {
    byteIndex := index / 8
    offset := index % 8
    return bf[byteIndex]>>(7-offset)&1 != 0
}

// SetPiece sets a bit in the bitfield
func (bf Bitfield) SetPiece(index int) {
    byteIndex := index / 8
    offset := index % 8
    bf[byteIndex] |= 1 << (7 - offset)
}
```

## Собираем все вместе

Теперь у нас есть все, чтобы начать скачивать файл: у нас есть список peer'ов с трекера, мы можем общаться с ними по TCP, можем провести рукопожатие, отправлять и получать сообщения. Но нужно учесть, что придется работать с несколькими peer'ами конкурентно и хранить состояния отдельно для каждого peer'а пока мы с ними взаимодействуем. Это непростые задачи.

### Управление конкурентностью: каналы и очереди

В Go принято [разделять память через общение](https://blog.golang.org/share-memory-by-communicating).

Настроим два канала для синхронизации наших воркеров: одни для распараллеливания работы между peer'ами, второй для сбора скаченных частей. Когда загруженные фрагменты попадают в канал с результатами, мы копируем их в буфер для сборки полного файла.

```go
// Init queues for workers to retrieve work and send results
workQueue := make(chan *pieceWork, len(t.PieceHashes))
results := make(chan *pieceResult)
for index, hash := range t.PieceHashes {
    length := t.calculatePieceSize(index)
    workQueue <- &pieceWork{index, hash, length}
}

// Start workers
for _, peer := range t.Peers {
    go t.startDownloadWorker(peer, workQueue, results)
}

// Collect results into a buffer until full
buf := make([]byte, t.Length)
donePieces := 0
for donePieces < len(t.PieceHashes) {
    res := <-results
    begin, end := t.calculateBoundsForPiece(res.index)
    copy(buf[begin:end], res.buf)
    donePieces++
}
close(workQueue)
```

Запускаем воркеры в горутинах для каждого peer'а. В воркерах выполняется соединение, рукопожатие, а потом воркер получает задачи из `workQueue` в которых указаны фрагменты для скачивания, пытается загрузить нужны фрагменты и скидывает их в канал `results`.

![](/img/bittorrent/download.png)

```go
func (t *Torrent) startDownloadWorker(peer peers.Peer, workQueue chan *pieceWork, results chan *pieceResult) {
    c, err := client.New(peer, t.PeerID, t.InfoHash)
    if err != nil {
        log.Printf("Could not handshake with %s. Disconnecting\n", peer.IP)
        return
    }
    defer c.Conn.Close()
    log.Printf("Completed handshake with %s\n", peer.IP)

    c.SendUnchoke()
    c.SendInterested()

    for pw := range workQueue {
        if !c.Bitfield.HasPiece(pw.index) {
            workQueue <- pw // Put piece back on the queue
            continue
        }

        // Download the piece
        buf, err := attemptDownloadPiece(c, pw)
        if err != nil {
            log.Println("Exiting", err)
            workQueue <- pw // Put piece back on the queue
            return
        }

        err = checkIntegrity(pw, buf)
        if err != nil {
            log.Printf("Piece #%d failed integrity check\n", pw.index)
            workQueue <- pw // Put piece back on the queue
            continue
        }

        c.SendHave(pw.index)
        results <- &pieceResult{pw.index, buf}
    }
}
```

### Управление состояниями

Мы будем хранить состояние каждого peer'а и изменять его в зависимости от полученных  сообщений. Для этого сделаем отдельную структуру, в которой будут храниться данные о том, сколько мы загрузили с этого peer'а, сколько мы запрашивали и "задушены" мы или нет. Для больше гибкости, эту логику можно реализовать в виде конечного автомата. Но пока нам достаточно обычного свитча.

```go
type pieceProgress struct {
    index      int
    client     *client.Client
    buf        []byte
    downloaded int
    requested  int
    backlog    int
}

func (state *pieceProgress) readMessage() error {
    msg, err := state.client.Read() // this call blocks
    switch msg.ID {
    case message.MsgUnchoke:
        state.client.Choked = false
    case message.MsgChoke:
        state.client.Choked = true
    case message.MsgHave:
        index, err := message.ParseHave(msg)
        state.client.Bitfield.SetPiece(index)
    case message.MsgPiece:
        n, err := message.ParsePiece(state.index, state.buf, msg)
        state.downloaded += n
        state.backlog--
    }
    return nil
}
```

### Время отправлять запросы!

Файлы, фрагменты и хэши фрагментов - еще не вся история, можно пойти дальше и разюить фрагменты на блоки. Блоки - это части фрагментов и мы можем идентифицировать их по индексу фрагмента в который он входит, смещению внутри фрагмента и длине блока. Когда мы делаем запросы к peer'ам, фактически мы запрашиваем блоки. Обычно блок имеет длину сообщения в 16кб. Это значит, для фрагмента в 256кб может понадобится 16 запросов.

Peer должен разрывать соединение, если получает запрос на блок размером больше 16кб. Но, судя по моему опыти, большинство клиентов прекрасно обрабатывают запросы на блоки до 128кб. Тем не менее, я получил не очень большой прирост скороси при использовании большого размера блока, поэтому лучше придерживаться спецификации.

### Пайплайн

Сетевые запросы довольно дорого стоят. И запросы блоков одного за другим не увеличивают  производительность нашей программы. Поэтому важно распределять запросы так, чтоб в полете постоянно было некоторое кол-во незавершенных запросов. Это может на порядок повысить пропускную способность нашего соединения.

![](/img/bittorrent/pipelining.png)

Классические BitTorrent клиенты держат очередь из 5 пайплайновых запросов. Мы тоже так поступим. Поэксперементировав с этим значением, я обнаружил, что можно в два раза увеличить скорость загрузки. Современные клиенты поддерживают [адаптивный](https://luminarys.com/posts/writing-a-bittorrent-client.html) размер очереди для лучшей утилизации сети. Сделаем это настраиваемым параметром и оставим это место для будующей оптимизации.

```go
// MaxBlockSize is the largest number of bytes a request can ask for
const MaxBlockSize = 16384

// MaxBacklog is the number of unfulfilled requests a client can have in its pipeline
const MaxBacklog = 5

func attemptDownloadPiece(c *client.Client, pw *pieceWork) ([]byte, error) {
    state := pieceProgress{
        index:  pw.index,
        client: c,
        buf:    make([]byte, pw.length),
    }

    // Setting a deadline helps get unresponsive peers unstuck.
    // 30 seconds is more than enough time to download a 262 KB piece
    c.Conn.SetDeadline(time.Now().Add(30 * time.Second))
    defer c.Conn.SetDeadline(time.Time{}) // Disable the deadline

    for state.downloaded < pw.length {
        // If unchoked, send requests until we have enough unfulfilled requests
        if !state.client.Choked {
            for state.backlog < MaxBacklog && state.requested < pw.length {
                blockSize := MaxBlockSize
                // Last block might be shorter than the typical block
                if pw.length-state.requested < blockSize {
                    blockSize = pw.length - state.requested
                }

                err := c.SendRequest(pw.index, state.requested, blockSize)
                if err != nil {
                    return nil, err
                }
                state.backlog++
                state.requested += blockSize
            }
        }

        err := state.readMessage()
        if err != nil {
            return nil, err
        }
    }

    return state.buf, nil
}
```

### main.go

Это очень просто. Мы почти закончили

```go
package main

import (
    "log"
    "os"

    "github.com/veggiedefender/torrent-client/torrentfile"
)

func main() {
    inPath := os.Args[1]
    outPath := os.Args[2]

    tf, err := torrentfile.Open(inPath)
    if err != nil {
        log.Fatal(err)
    }

    err = tf.DownloadToFile(outPath)
    if err != nil {
        log.Fatal(err)
    }
}
```

<script id="asciicast-xqRSB0Jec8RN91Zt89rbb9PcL" src="https://asciinema.org/a/xqRSB0Jec8RN91Zt89rbb9PcL.js" async></script>

## Это еще не все

Для краткости я фключил только несколько важных фрагментов кода. Я опусти весь код для синтаксического анализа, тестов и другие скучные части. Полный код можно [посмотреть на гитхабе](https://github.com/veggiedefender/torrent-client).