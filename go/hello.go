// Package hello is a real module the go toolchain must build.
package hello

import "fmt"

// Greet returns a greeting.
func Greet(name string) string {
	return fmt.Sprintf("hello %s", name)
}
