.PHONY: help bootstrap bootstrap-worker teardown validate

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  %-15s %s\n", $$1, $$2}'

bootstrap: ## Install K3s + ArgoCD on the server
	bash bootstrap/bootstrap.sh

bootstrap-worker: ## Join a worker node to the cluster
	K3S_ROLE=agent bash bootstrap/bootstrap.sh

teardown: ## Uninstall K3s completely (keeps service data)
	bash bootstrap/teardown.sh

validate: ## Lint all Helm charts + ArgoCD YAML
	@echo "--- Validating YAML syntax ---"
	@find argocd/ infra/ services/ -name '*.yaml' -exec yq e '.' {} \; 2>/dev/null || true
	@echo "--- Linting Helm charts ---"
	@for chart in infra/*/Chart.yaml services/*/Chart.yaml; do \
		[ -f "$$chart" ] || continue; \
		dir=$$(dirname "$$chart"); \
		helm dependency build "$$dir" 2>/dev/null; \
		helm lint "$$dir"; \
	done
	@echo "All good."
