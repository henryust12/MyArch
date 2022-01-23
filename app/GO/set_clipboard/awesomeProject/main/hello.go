package main

import (
	"os"

	"github.com/atotto/clipboard"
)

/*type in the terminal -> go get github.com/atotto/clipboard*/

func main() {
	repoName := os.Args[1]
	var Username = "henryust12"
	var Token = "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"
	var Url string = "https://" + Username + ":" + Token + "@github.com/henryust12/" + repoName + ".git"
	clipboard.WriteAll(Url)

	/*text, _ := clipboard.ReadAll()*/
	/*fmt.Println(text)*/

}
