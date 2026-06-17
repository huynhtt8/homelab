package stack

import (
	stackconfig "github.com/huynhtt8/homelab/pulumi/internal/config"
	"github.com/huynhtt8/homelab/pulumi/internal/secrets"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func Run(ctx *pulumi.Context) error {
	cfg, err := stackconfig.Load(ctx)
	if err != nil {
		return err
	}

	if err := secrets.Create(ctx, cfg.Secrets); err != nil {
		return err
	}

	return nil
}
