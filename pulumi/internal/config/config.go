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
	Secrets []Secret
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

	stack := &Config{
		Secrets: secrets,
	}

	if err := stack.validate(); err != nil {
		return nil, err
	}

	return stack, nil
}

func (cfg Config) validate() error {
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

func (secret Secret) TargetNamespace() string {
	if secret.Namespace != "" {
		return secret.Namespace
	}
	return defaultSecretNamespace
}
