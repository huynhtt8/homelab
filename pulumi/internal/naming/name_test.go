package naming

import "testing"

func TestResource(t *testing.T) {
	tests := map[string]string{
		"hub":            "dns-hub",
		"photos_example": "dns-photos-example",
		"*.example.com":  "dns-wildcard-example-com",
		"immich.db":      "dns-immich-db",
	}

	for input, want := range tests {
		if got := Resource("dns", input); got != want {
			t.Fatalf("Resource(%q) = %q, want %q", input, got, want)
		}
	}
}
