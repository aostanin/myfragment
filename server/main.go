package main

import (
  "database/sql"
  "io"
  "io/ioutil"
  "log"
  "net/http"

  _ "github.com/mattn/go-sqlite3"
  "github.com/coopernurse/gorp"

  "github.com/go-martini/martini"
  "github.com/martini-contrib/gzip"
  "github.com/martini-contrib/render"
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

func main() {
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

  m.Get("/fragment/:fragment_id", func(r render.Render) {
    r.HTML(200, "fragment", nil)
  })

  m.Post("/api/upload.json", func(req *http.Request, r render.Render, dbmap *gorp.DbMap) {
    depthFile, _, err := req.FormFile("depth")
    if err != nil {
      r.JSON(400, map[string]interface{}{"success": false})
      return;
    }
    defer depthFile.Close()

    outputDepthFile, err := ioutil.TempFile("public/uploads/depth", "")
    if err != nil {
      log.Print(err)
      r.JSON(400, map[string]interface{}{"success": false})
      return;
    }
    defer outputDepthFile.Close()

    _, err = io.Copy(outputDepthFile, depthFile)
    if err != nil {
      log.Print(err)
      r.JSON(500, map[string]interface{}{"success": false})
      return;
    }

    fragment := &Fragment{
      Hash: "xxx",
      Created: 0,
      DepthVideoFilename: "depth",
      PreviewImageFilename: "preview_img",
      PreviewVideoFilename: "preview_vid",
      Time: 0,
    }
    err = dbmap.Insert(fragment)
    if err != nil {
      log.Print(err)
      r.JSON(500, map[string]interface{}{"success": false})
      return;
    }

    r.JSON(200, map[string]interface{}{"success": true})
  })

  m.Run()
}
