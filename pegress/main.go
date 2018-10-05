package main

import (
	"fmt"
	"net/http"
	"io/ioutil"
	"github.com/gorilla/handlers"
	"os"
)


func main() {
	http.HandleFunc("/", func (w http.ResponseWriter, r *http.Request) {

		resp, err := http.Get("http://www.google.com")
		if err != nil {
			panic(err)
		}
		defer resp.Body.Close()
		body, err := ioutil.ReadAll(resp.Body)
		fmt.Fprintf(w, string(body))
	})

	http.ListenAndServe(":8080", handlers.LoggingHandler(os.Stdout, http.DefaultServeMux))
}