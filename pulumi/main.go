package main

import (
	"github.com/huynhtt8/homelab/pulumi/internal/stack"
	"github.com/pulumi/pulumi/sdk/v3/go/pulumi"
)

func main() {
	pulumi.Run(stack.Run)
}
