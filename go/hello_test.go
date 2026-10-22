package hello

import "testing"

func TestGreet(t *testing.T) {
	if got := Greet("easyblobs"); got != "hello easyblobs" {
		t.Fatalf("got %q", got)
	}
}
