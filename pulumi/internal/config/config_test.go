package config

import (
	"strings"
	"testing"
)

func TestSecretTargetNamespace(t *testing.T) {
	if got := (Secret{}).TargetNamespace(); got != defaultSecretNamespace {
		t.Fatalf("default namespace = %q, want %q", got, defaultSecretNamespace)
	}

	if got := (Secret{Namespace: "custom"}).TargetNamespace(); got != "custom" {
		t.Fatalf("custom namespace = %q, want custom", got)
	}
}

func TestConfigValidate(t *testing.T) {
	tests := map[string]struct {
		cfg  Config
		want string
	}{
		"missing secret name": {
			cfg: Config{
				Secrets: []Secret{{Data: map[string]string{"PASSWORD": "value"}}},
			},
			want: "secrets entries must include name",
		},
		"empty secret data": {
			cfg: Config{
				Secrets: []Secret{{Name: "immich.db"}},
			},
			want: `secret "immich.db" must include at least one data key`,
		},
		"empty secret key": {
			cfg: Config{
				Secrets: []Secret{{Name: "immich.db", Data: map[string]string{" ": "value"}}},
			},
			want: `secret "immich.db" contains an empty data key`,
		},
		"valid": {
			cfg: Config{
				Secrets: []Secret{
					{Name: "immich.db", Data: map[string]string{"POSTGRES_PASSWORD": "value"}},
				},
			},
		},
	}

	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			err := tt.cfg.validate()
			if tt.want == "" {
				if err != nil {
					t.Fatalf("Validate() returned error: %v", err)
				}
				return
			}
			if err == nil {
				t.Fatalf("Validate() returned nil, want %q", tt.want)
			}
			if !strings.Contains(err.Error(), tt.want) {
				t.Fatalf("Validate() = %q, want substring %q", err.Error(), tt.want)
			}
		})
	}
}
