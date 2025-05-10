//go:build cgo
// +build cgo

package main

/*
#include <stdlib.h>
*/
import "C"
import "unsafe"

// cString allocates C memory; Rust must free it via libc::free().
func cString(s string) *C.char { return C.CString(s) }

// appease linters: we intentionally reference unsafe for CGO
var _ unsafe.Pointer

func main() {}
