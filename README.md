# demo-gitops

The smallest possible version of the home-ops flow, to see how the pieces connect.
One tiny app, one local cluster on your Mac, prod + a preview per pull request.

```
 you push ──► GitHub Actions ──► image in GHCR (sha-<commit>)
                    │
                    └─(main only)─► commits new tag to deploy/prod ──┐
                                                                     ▼
 your Mac:  k3d cluster ── Argo CD ── watches this repo ──► deploys what Git says
```

**The one idea:** GitHub never touches your cluster. CI only builds images and
commits to Git. Argo CD, running *inside* the cluster, pulls from Git and makes the
cluster match. Git is the single source of truth.

## The files (that's all of them)

| File | Role |
|---|---|
| `app.py`, `Dockerfile` | The app. Prints its environment and commit |
| `deploy/base/` | The app as plain Kubernetes YAML (Deployment, Service, Ingress) |
| `deploy/prod/` | Prod = base + overrides. **CI edits the image tag here; that commit is the deploy** |
| `argocd/prod.yaml` | Tells Argo: keep `demo-prod` matching `deploy/prod` on `main` |
| `argocd/previews.yaml` | Tells Argo: for every open PR, run that PR's version in `demo-pr-<n>` |
| `.github/workflows/ci.yml` | Builds `sha-<commit>` images; on `main`, commits the new tag |

## Setup (about 10 minutes, all on your MacBook Pro)

1. **Create the repo.** Replace `frankieeder` everywhere
   (`grep -rl frankieeder . | xargs sed -i '' 's/frankieeder/yourname/g'`),
   then push to a **public** GitHub repo named `demo-gitops`.
2. **Let the first build run** (Actions tab). Then on GitHub, open the `demo-gitops` package
   (your profile → Packages) → Package settings → **Change visibility → Public**, so the
   cluster can pull it without credentials.
3. **Create a local cluster** (needs Docker Desktop running):
   ```bash
   brew install k3d kubectl
   k3d cluster create demo -p "8080:80@loadbalancer"
   ```
4. **Install Argo CD:**
   ```bash
   kubectl create namespace argocd
   kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
   kubectl -n argocd rollout status deploy/argocd-server
   ```
5. **Give Argo a GitHub token** (any classic or fine-grained token with public repo read;
   it's only used to list PRs without hitting rate limits):
   ```bash
   kubectl -n argocd create secret generic github-token --from-literal=token=ghp_...
   ```
6. **Point Argo at this repo.** This is the only time you apply anything by hand:
   ```bash
   kubectl apply -f argocd/
   ```
7. **Open the Argo UI** (optional, but it makes everything visible):
   ```bash
   kubectl -n argocd port-forward svc/argocd-server 8081:443
   # https://localhost:8081  user: admin
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
   ```

Prod is at **http://demo.localhost:8080**. (`*.localhost` resolves to your own machine in
Chrome, Firefox and curl. If Safari doesn't, use one of those.)

## Experiments: do these in order

**1. Deploy to prod.** Change `MESSAGE` in `app.py`, commit, push to `main`.
Watch: Actions builds the image → a bot commit "deploy prod: sha-…" appears →
Argo syncs (up to ~3 min, or click **Refresh** in the UI) → the page changes.

**2. Open a PR.** Create a branch, change `MESSAGE` again, push, open a PR.
Within a minute, `demo-pr-<n>` appears in Argo. Visit **http://pr-<n>.demo.localhost:8080**.
Push another commit to the PR: the preview updates on its own.

**3. Merge the PR.** The preview disappears; prod updates through experiment 1's path.

**4. Roll back.** On GitHub, revert the latest "deploy prod" commit. Prod goes back
to the previous version. Nothing else needed.

**5. Break it by hand.** `kubectl -n demo-prod delete deployment demo`. Argo recreates it.
`kubectl -n demo-prod scale deployment demo --replicas=3`. Argo scales it back to 1.
This is "self-healing": the cluster is pulled back to whatever Git says.

**6. Change config, not code.** Edit `replicas` in `deploy/base/demo.yaml` in a PR.
The preview uses the PR's deploy files, so you see the config change before merging.

## How this maps to home-ops

| demo-gitops | home-ops |
|---|---|
| k3d on one Mac | k3s across the iMac VM, Pi, ... over Tailscale |
| `argocd/*.yaml` applied by hand | `bootstrap/root.yaml` applies `kubernetes/argocd/` (pointers) |
| plain YAML + kustomize | bjw-s app-template Helm chart (shorter per-app files) |
| tags committed in the same repo | tags committed into the separate infra repo |
| public image, no secrets | private images, Infisical, backups, hardware |

## Clean up

```bash
k3d cluster delete demo
```
(Preview namespaces stay behind empty after PRs close until you delete them or the cluster.)
