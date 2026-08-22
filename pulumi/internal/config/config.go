package config

import (
	"fmt"
	"strings"

	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
	pulumiconfig "github.com/pulumi/pulumi/sdk/v3/go/pulumi/config"
)

const (
	defaultSecretNamespace = "central-secrets"
)

type Config struct {
	Runtime RuntimeConfig `json:"runtime"`
	Secrets []Secret      `json:"secrets"`
}

type RuntimeConfig struct {
	NFSServer         string   `json:"nfsServer"`
	MediaPath         string   `json:"mediaPath,omitempty"`
	RuntimeNamespaces []string `json:"runtimeNamespaces,omitempty"`
}

type Secret struct {
	Name      string            `json:"name"`
	Namespace string            `json:"namespace,omitempty"`
	Data      map[string]string `json:"data"`
}

func Load(ctx *pulumi.Context) (*Config, error) {
	cfg := pulumiconfig.New(ctx, "")

	var secrets []Secret
	if _, err := cfg.GetSecretObject("secrets", &secrets); err != nil {
		return nil, fmt.Errorf("read secrets config: %w", err)
	}

	var runtime RuntimeConfig
	if err := cfg.GetObject("runtime", &runtime); err != nil {
		return nil, fmt.Errorf("read runtime config: %w", err)
	}

	stack := &Config{
		Runtime: runtime,
		Secrets: secrets,
	}

	if err := stack.validate(); err != nil {
		return nil, err
	}

	return stack, nil
}

func (cfg Config) validate() error {
	if strings.TrimSpace(cfg.Runtime.NFSServer) == "" {
		return fmt.Errorf("runtime.nfsServer is required")
	}

	for _, secret := range cfg.Secrets {
		if strings.TrimSpace(secret.Name) == "" {
			return fmt.Errorf("secrets entries must include name")
		}
		if len(secret.Data) == 0 {
			return fmt.Errorf("secret %q must include at least one data key", secret.Name)
		}
		for key := range secret.Data {
			if strings.TrimSpace(key) == "" {
				return fmt.Errorf("secret %q contains an empty data key", secret.Name)
			}
		}
	}

	return nil
}

func (runtime RuntimeConfig) TargetNamespaces() []string {
	if len(runtime.RuntimeNamespaces) > 0 {
		return runtime.RuntimeNamespaces
	}

	return []string{
		"audiobookshelf",
		"bazarr",
		"calibre-web",
		"filebrowser",
		"jellyfin",
		"qbittorrent",
		"radarr",
		"sonarr",
	}
}

func (runtime RuntimeConfig) TargetMediaPath() string {
	if runtime.MediaPath != "" {
		return runtime.MediaPath
	}
	return "/mnt/media"
}

func (secret Secret) TargetNamespace() string {
	if secret.Namespace != "" {
		return secret.Namespace
	}
	return defaultSecretNamespace
}
