+++
date = "2020-06-15T11:00:00+03:00"
draft = true
title = "iOS видео чат"
tags = ["ios", "swift", "swiftui", "golang"]
+++

Сначала идея была в том, чтобы написать свой видео чат с нуля. Но всегда есть азиат, который сделает это лучше. Вот некто tkmn0 написал https://github.com/tkmn0/SimpleWebRTCExample_iOS - отличный пример работы с WebRTC в Swift. Поэтому просто разберемся что есть в этом проекте и как он работает.

## Сигнальный сервер

### Деплой на heroku

Чтоб не запариваться с хостингом для такой мелочи - используем старый добрый [heroku](https://www.heroku.com/go)

Первым делом регистрируемся и [устанавливаем консольную утилиту](https://devcenter.heroku.com/articles/getting-started-with-go#set-up)

```
brew install heroku/brew/heroku
```

Логинимся в аккаунт и [подготавливаем приложение](https://devcenter.heroku.com/articles/getting-started-with-go#prepare-the-app) 

```
git clone https://github.com/heroku/go-getting-started.git signal
```


- https://devcenter.heroku.com/articles/getting-started-with-go#deploy-the-app


Для обновления всего - коммитим изменения и пушим их в отдельный ремоут

```
git push heroku master
```

Немножно ждем и смотрим что получилось



Частые команды 

```
heroku logs --tail
heroku ps:restart web
```

### Сервер

https://pkg.go.dev/golang.org/x/net/websocket?tab=doc

Сам сигнальный сервер

```go
import (
	"log"
	"net"
	"net/http"
	"os"

	"github.com/gorilla/websocket"
	"github.com/pkg/errors"
	_ "github.com/heroku/x/hmetrics/onload"
)

var upgrader = websocket.Upgrader{
	CheckOrigin: func(r *http.Request) bool {
		return true
	},
} // use default options
var clients = []*websocket.Conn{}

func main() {
	port := os.Getenv("PORT")

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		conn, err := upgrader.Upgrade(w, r, nil)
		if err != nil {
			log.Println("error on es connect", err)
			return
		}
		conn.SetCloseHandler(func(code int, text string) error {
			remove(conn)

			return nil
		})

		if !exits(conn) {
			clients = append(clients, conn)
		}

		if err != nil {
			log.Print("upgrade:", err)
			return
		}
		defer conn.Close()
		for {
			mt, message, err := conn.ReadMessage()

			if err != nil {
				log.Println("read:", err)
				break
			}
			log.Printf("recv: %s", message)

			for _, c := range clients {
				if c != conn {
					err = c.WriteMessage(mt, message)
					if err != nil {
						log.Println("write:", err)
						break
					}
				}
			}

		}
	})

	log.Fatal(http.ListenAndServe(":"+port, nil))
}

func exits(conn *websocket.Conn) bool {
	for _, c := range clients {
		if c == conn {
			return true
		}
	}

	return false
}

func remove(conn *websocket.Conn) {
	for i, c := range clients {
		if c == conn {
			clients[i] = clients[len(clients)-1] // Copy last element to index i.
			clients[len(clients)-1] = nil        // Erase last element (write zero value).
			clients = clients[:len(clients)-1]
			return
		}
	}

}
```



- [How to Use Websockets in Golang: Best Tools and Step-by-Step Guide](https://yalantis.com/blog/how-to-build-websockets-in-go/)
- [Gorilla WebSocket](https://github.com/gorilla/websocket)
- [WebRTC-iOS](https://github.com/stasel/WebRTC-iOS)
- [SimpleWebRTCExample_iOS](https://github.com/horechek/SimpleWebRTCExample_iOS)
- [GoogleWebRTC](https://cocoapods.org/pods/GoogleWebRTC)
- [Starscream](https://github.com/daltoniam/starscream)
- [Working with WebRTC](https://dev.to/sadmansamee/working-with-webrtc-on-android-ios-465c)
- [Requesting Authorization for Media Capture on iOS](https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture/requesting_authorization_for_media_capture_on_ios)
- [AVCam: Building a Camera App](https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture/avcam_building_a_camera_app)
- [Setting Up a Capture Session](https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture/setting_up_a_capture_session)
- [Cameras and Media Capture](https://developer.apple.com/documentation/avfoundation/cameras_and_media_capture/)
- [How to Use Camera and Library to Take Photos in SwiftUI](https://www.iosapptemplates.com/blog/swiftui/photo-camera-swiftui)
- [Voice Recorder App In SwiftUI – #1 Implementing The Audio Recorde](https://blckbirds.com/post/voice-recorder-app-in-swiftui-1/)
- [Create a camera app with SwiftUI](https://medium.com/@gaspard.rosay/create-a-camera-app-with-swiftui-60876fcb9118)
- [Building a Full Screen Camera App Using AVFoundation](https://www.appcoda.com/avfoundation-swift-guide/)