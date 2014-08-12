package main

import (
  "database/sql"
  "encoding/binary"
  "fmt"
  "io/ioutil"
  "log"
  "math"
  "net/http"
  "os"
  "os/exec"
  "strings"
  "time"

  _ "github.com/mattn/go-sqlite3"
  "github.com/coopernurse/gorp"

  "github.com/go-martini/martini"
  "github.com/martini-contrib/gzip"
  "github.com/martini-contrib/render"

  "code.google.com/p/go.net/websocket"

  "github.com/vincent-petithory/dataurl"
)

type Fragment struct {
  Id                   int64   `db:"id"                     json:"-"`
  Hash                 string  `db:"hash"                   json:"hash"`
  Created              int64   `db:"created"                json:"created"`
  DepthVideoFilename   string  `db:"depth_video_filename"   json:"-"`
  DepthVideoURL        string  `db:"-"                      json:"depth_video_url"`
  PreviewImageFilename string  `db:"preview_image_filename" json:"-"`
  PreviewImageURL      string  `db:"-"                      json:"preview_image_url"`
  PreviewVideoFilename string  `db:"preview_video_filename" json:"-"`
  PreviewVideoURL      string  `db:"-"                      json:"preview_video_url"`
  Time                 float64 `db:time                     json:"time"`
}

var socketChan chan []byte = make(chan []byte)

func readDepth(fifoPath string) {
  log.Printf("Opening Kinect FIFO %s", fifoPath)
  fifo, err := os.Open(fifoPath)

  if err != nil {
    log.Fatal(err)
  }

  const pixelCount = 320 * 240
  const frameSizeUInt16 = pixelCount * 2
  const frameSizeFloat32 = pixelCount * 4
  buffer := make([]byte, frameSizeUInt16)
  decodedFloat32Buffer := make([]byte, frameSizeFloat32)
  for {
    frameBytesRead := 0
    for frameBytesRead < frameSizeUInt16 {
      bytesRead, err := fifo.Read(buffer[frameBytesRead:])
      frameBytesRead += bytesRead
      if err != nil {
        log.Fatal(err)
      }
    }

    if frameBytesRead != frameSizeUInt16 {
      log.Printf("Read %d bytes but expected %d bytes", frameBytesRead, frameSizeUInt16)
      continue
    }

    for i := 0; i < pixelCount; i++ {
      val16 := binary.LittleEndian.Uint16(buffer[2 * i:])
      bits := math.Float32bits(float32(val16) / float32((1 << 11) - 1))
      binary.LittleEndian.PutUint32(decodedFloat32Buffer[4*i:], uint32(bits))
    }

    socketChan <- decodedFloat32Buffer
  }
}

func main() {
  kinectFifo := os.Getenv("KINECT_FIFO")
  if kinectFifo != "" {
    go readDepth(kinectFifo)
  }

  db, err := sql.Open("sqlite3", "db/myfragment.db")
  if err != nil {
    log.Fatal(err)
  }
  defer db.Close()

  dbmap := &gorp.DbMap{Db: db, Dialect: gorp.SqliteDialect{}}
  defer dbmap.Db.Close()
  dbmap.AddTableWithName(Fragment{}, "fragments").SetKeys(true, "Id")
  err = dbmap.CreateTablesIfNotExists()
  if err != nil {
    log.Fatal(err)
  }

  m := martini.Classic()
  m.Map(dbmap)
  m.Use(gzip.All())
  m.Use(render.Renderer(render.Options{
    Layout: "layout",
  }))

  m.Get("/", func(r render.Render) {
    r.HTML(200, "home", nil)
  })

  m.Get("/live", func(r render.Render) {
    r.HTML(200, "live", nil)
  })

  m.Get("/fragment/:fragment_id", func(r render.Render) {
    r.HTML(200, "fragment", nil)
  })

  m.Get("/live-socket", websocket.Handler(func(ws *websocket.Conn) {
    log.Print("Socket connection open")
    for message := range socketChan {
      err := websocket.Message.Send(ws, message)
      if err != nil {
        break
      }
    }
    ws.Close()
    log.Print("Socket connection closed")
  }).ServeHTTP)

  m.Post("/api/upload.json", func(req *http.Request, r render.Render, dbmap *gorp.DbMap) {
    err := req.ParseForm()
    if err != nil {
      log.Print(err)
      r.JSON(400, map[string]interface{}{"success": false})
      return
    }

    imageDataUrls := req.PostForm["images[]"]
    if len(imageDataUrls) != 5 {
      log.Printf("Expected 5 images but found %d", len(imageDataUrls))
      r.JSON(400, map[string]interface{}{"success": false})
      return
    }

    t := time.Now()
    commandString := fmt.Sprintf("../fragment-printer/fragment-printer.py -i ")
    for i := 0; i < len(imageDataUrls); i++ {
      fn := fmt.Sprintf("public/uploads/images/%s_%d.png", t.Format("20060102150405"), i + 1)
      commandString = fmt.Sprintf("%s %s", commandString, fn)
      dataUrl, err := dataurl.DecodeString(imageDataUrls[i])
      if err != nil {
        log.Print(err)
        r.JSON(500, map[string]interface{}{"success": false})
      }
      ioutil.WriteFile(fn, dataUrl.Data, 0644)
    }

    printCmd := exec.Command("sh", "-c", commandString)
    printCmd.Start()

    r.JSON(200, map[string]interface{}{"success": true})
  })

  m.Get("/api/fragments.json", func(req *http.Request, r render.Render) {
    files, err := ioutil.ReadDir("public/uploads/images/")
    if err != nil {
      log.Print(err)
      r.JSON(400, map[string]interface{}{"success": false})
      return
    }

    var urls []string

    for _, v := range files {
      if !strings.HasSuffix(v.Name(), ".png") {
        continue
      }
      urls = append(urls, fmt.Sprintf("http://%s/uploads/images/%s", req.Host, v.Name()))
    }

    r.JSON(200, map[string]interface{}{"success": true, "fragments": urls})
  })

  m.Run()
}
