CLUSTER_NAME := demo
DATA_DIR := $(HOME)/demo-data
REGISTRY_CONFIG := $(HOME)/k3d-registries.yaml
INFISICAL_PROJECT_ID := f6ad0777-3421-478b-afef-95925a8f5e55
ARGO_INSTALL_URL := https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

.PHONY: up down cycle deploy undeploy unit-test integration-test test data cluster argo listmonk-secrets

up: data cluster argo listmonk-secrets
	kubectl apply -f bootstrap/root.yaml

down:
	k3d cluster delete $(CLUSTER_NAME)

cycle: down up

data:
	test -f $(DATA_DIR)/media/index.html || (mkdir -p $(DATA_DIR)/media && cp -R testdata/media/. $(DATA_DIR)/media/)

cluster:
	k3d cluster get $(CLUSTER_NAME) >/dev/null 2>&1 || k3d cluster create $(CLUSTER_NAME) \
	  -p "8080:80@loadbalancer" \
	  -v "$(DATA_DIR):/data@server:0" \
	  --k3s-arg "--node-label=storage/media=true@server:0" \
	  --k3s-arg "--node-label=storage/listmonk=true@server:0" \
	  $(if $(wildcard $(REGISTRY_CONFIG)),--registry-config $(REGISTRY_CONFIG)) \
	  --k3s-arg '--kubelet-arg=eviction-hard=imagefs.available<2%,nodefs.available<2%@server:*' \
	  --k3s-arg '--kubelet-arg=eviction-minimum-reclaim=imagefs.available=1%,nodefs.available=1%@server:*'

argo:
	kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
	kubectl apply -n argocd --server-side -f $(ARGO_INSTALL_URL)
	kubectl -n argocd rollout status deploy/argocd-server
	kubectl -n argocd rollout status deploy/argocd-repo-server
	kubectl -n argocd get secret github-token >/dev/null 2>&1 || kubectl -n argocd create secret generic github-token --from-literal=token="$$(gh auth token)"

listmonk-secrets:
	kubectl create namespace listmonk --dry-run=client -o yaml | kubectl apply -f -
	infisical run --projectId=$(INFISICAL_PROJECT_ID) --env=dev --path=/listmonk --silent -- sh -c 'kubectl -n listmonk create secret generic listmonk-secrets --from-literal=LISTMONK_DB_PASSWORD="$$LISTMONK_DB_PASSWORD" --from-literal=LISTMONK_ADMIN_PASSWORD="$$LISTMONK_ADMIN_PASSWORD" --dry-run=client -o yaml | kubectl apply -f -'

deploy:
	@echo "deploy: no remote infrastructure yet"

undeploy:
	@echo "undeploy: no remote infrastructure yet"

unit-test:
	@echo "unit-test: no unit tests yet"

integration-test: up
	curl -fsS --retry 30 --retry-delay 10 --retry-all-errors http://files.demo.localhost:8080 | grep -q "Served from a folder"
	test -s $(DATA_DIR)/media/writer.log
	curl -fsS --retry 30 --retry-delay 10 --retry-all-errors http://listmonk.demo.localhost:8080/health

test: unit-test integration-test
