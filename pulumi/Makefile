GOCACHE ?= /private/tmp/go-build
GOMODCACHE ?= /private/tmp/go-mod

export GOCACHE
export GOMODCACHE

.PHONY: preview up refresh destroy test render-secrets set-secrets

test:
	go test ./...

render-secrets:
	@test -n "$(FILE)"
	python3 ./scripts/render-secrets-config.py "$(FILE)"

set-secrets:
	@test -n "$(FILE)"
	pulumi config set --secret homelab:secrets "$$(python3 ./scripts/render-secrets-config.py "$(FILE)")"

preview:
	pulumi preview

up:
	pulumi up

refresh:
	pulumi refresh

destroy:
	pulumi destroy
