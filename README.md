# Cloud Run to GKE Autopilot Lab

Hands-on lab that deploys a small Node.js service to Cloud Run, then moves it onto a private GKE Autopilot cluster built with Terraform and packaged with Helm. It covers VPC-native networking, least-privilege service accounts, Workload Identity, health probes, graceful shutdown, autoscaling, and common failure modes.

## Architecture

```
                      ┌──────────────────────────── gke-lab-vpc ────────────────────────────┐
                      │  gke-lab-subnet 10.40.0.0/20                                        │
  Artifact Registry   │    pods 10.48.0.0/14 · services 10.52.0.0/20                        │
  (apps/hello-api) ───┼──► GKE Autopilot (private nodes) ── namespace: hello                 │
        ▲             │       Deployment hello-api ── Service (ClusterIP :80) ── HPA ── PDB  │
        │             │       KSA hello-api ──(Workload Identity)──► GSA hello-api           │
   Cloud Build        │                                                                      │
        │             │  Cloud Router + Cloud NAT (egress for private nodes)                 │
        ▼             └──────────────────────────────────────────────────────────────────────┘
   Cloud Run (baseline)
```

## Repository layout

```
.
├── scripts/                 # Setup and teardown automation
│   ├── env.sh               # Shared variables (source this)
│   ├── setup.sh             # Auth, APIs, Artifact Registry, state bucket, build, Cloud Run deploy
│   ├── connect.sh           # kubectl credentials and namespace
│   └── teardown.sh          # Removes everything the lab created
├── hello-api/               # Sample service
│   ├── server.js            # /healthz, /readyz, graceful SIGTERM shutdown
│   └── Dockerfile
├── terraform/               # Platform infrastructure
│   ├── backend.tf           # Remote state in GCS (bucket supplied at init)
│   ├── provider.tf          # Terraform and Google provider configuration
│   ├── variables.tf         # project_id, region
│   ├── network.tf           # VPC, subnet with secondary ranges, Cloud Router, Cloud NAT
│   ├── sa.tf                # Node service account, app service account, Workload Identity binding
│   ├── gke_autopilot.tf     # Private GKE Autopilot cluster
│   ├── import.tf            # Adopts the Artifact Registry repo that setup.sh creates
│   ├── artifact_registry.tf # Docker repository
│   └── outputs.tf           # get-credentials command, app service account email
└── charts/hello-api/        # Helm chart
    ├── Chart.yaml
    ├── values.yaml          # Defaults (dev)
    ├── values-prod.yaml     # Production overrides
    └── templates/           # ServiceAccount, Deployment, Service, HPA, PDB, helpers
```

## Prerequisites

- A GCP project with billing enabled, and Owner (or equivalent IAM admin) access to it, since `setup.sh` grants an IAM role
- `gcloud`, `terraform` (1.6+), `kubectl`, `helm` (3.x)
- `gke-gcloud-auth-plugin`: `gcloud components install gke-gcloud-auth-plugin`
- A browser for the gcloud login prompts (`setup.sh` handles authentication; see step 1)

### Installing the tools on macOS (Homebrew)

```bash
# Google Cloud CLI (gcloud, gsutil, bq). The cask was renamed from google-cloud-sdk.
brew update && brew install --cask gcloud-cli

# kubectl plugin that GKE requires for authentication
gcloud components install gke-gcloud-auth-plugin

# Terraform from HashiCorp's official tap (homebrew-core's terraform is outdated)
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# kubectl and Helm
brew install kubectl helm
```

Verify the installs:

```bash
gcloud --version
terraform -version
kubectl version --client
helm version
gke-gcloud-auth-plugin --version
```

### Installing the tools on Windows

The lab scripts are bash, so they won't run in PowerShell or Command Prompt. Use one of these two setups.

**Option 1: WSL2 with Ubuntu (recommended).** Everything runs in a real Linux environment, exactly as on macOS. From an administrator PowerShell, install WSL and restart when prompted:

```powershell
wsl --install -d Ubuntu
```

Then, inside the Ubuntu terminal:

```bash
sudo apt-get update && sudo apt-get install -y apt-transport-https ca-certificates gnupg curl wget lsb-release

# Google Cloud CLI, the GKE auth plugin, and kubectl (all from Google's apt repository)
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg
echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" \
  | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list
sudo apt-get update && sudo apt-get install -y \
  google-cloud-cli google-cloud-cli-gke-gcloud-auth-plugin kubectl

# Terraform from HashiCorp's apt repository
wget -O- https://apt.releases.hashicorp.com/gpg \
  | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt-get update && sudo apt-get install -y terraform

# Helm 3 via the official install script
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
```

WSL usually can't open a browser for gcloud's login prompts, so log in with the device flow before running `setup.sh`:

```bash
gcloud auth login --no-launch-browser
gcloud auth application-default login --no-launch-browser
```

**Option 2: Native Windows tools with Git Bash.** Install the tools with winget from PowerShell, then run the lab scripts from Git Bash:

```powershell
winget install --id Google.CloudSDK -e
winget install --id Hashicorp.Terraform -e
winget install --id Kubernetes.kubectl -e
winget install --id Helm.Helm -e
winget install --id Git.Git -e        # provides Git Bash for the scripts
```

Close and reopen your terminal so the updated PATH takes effect, then install the GKE auth plugin:

```powershell
gcloud components install gke-gcloud-auth-plugin
```

Git Bash handles most bash scripts well, but path translation between bash and Windows programs can occasionally cause problems (for example, Terraform's `-chdir` path in `teardown.sh`). If a script misbehaves, run that step's commands by hand or switch to WSL.

On either option, confirm the installs with the same version checks as macOS.

## Configuration

All shared settings live in `scripts/env.sh`. Source it (don't execute it) so the variables stay in your shell for the Terraform and Helm commands:

```bash
chmod +x scripts/*.sh          # once, after cloning
export PROJECT_ID=<your-project>
source scripts/env.sh
```

| Variable | Default | Purpose |
| --- | --- | --- |
| `PROJECT_ID` | Current gcloud project | GCP project for all resources |
| `REGION` | `us-west1` | Region for the network, cluster, registry, and Cloud Run |
| `CLUSTER_NAME` | `gke-lab` | GKE cluster name (must match `gke_autopilot.tf`) |
| `NAMESPACE` | `hello` | Kubernetes namespace (must match the Workload Identity binding in `sa.tf`) |
| `APP_NAME` | `hello-api` | Service, image, and Helm release name |
| `REPO_NAME` | `apps` | Artifact Registry repository |
| `IMAGE_TAG` | `v1` | Image tag to build and deploy |
| `TF_STATE_BUCKET` | `<PROJECT_ID>-tfstate` | GCS bucket for Terraform remote state |

Override any default by exporting it before sourcing, for example `export REGION=us-central1`.

`env.sh` also exports `PROJECT_ID`, `REGION`, `CLUSTER_NAME`, `NAMESPACE`, `APP_NAME`, and `REPO_NAME` to Terraform as `TF_VAR_*` variables, so names are defined in one place and the scripts, Helm, and Terraform can't drift apart. Source `env.sh` in every new terminal before running Terraform; there's no need to pass `-var` flags.

Changing `CLUSTER_NAME`, `APP_NAME`, or `REPO_NAME` after the infrastructure exists renames real resources, which Terraform does by destroying and recreating them. Always review `terraform plan` before applying a rename.

## Quick start

### 1. Set up the project and deploy the Cloud Run baseline

```bash
scripts/setup.sh          # or: scripts/setup.sh v2  to build a different tag
```

The script:

1. Checks authentication and prompts only for what's missing: `gcloud auth login` for your user account, and `gcloud auth application-default login` for the Application Default Credentials that Terraform uses.
2. Sets the gcloud project and the ADC quota project.
3. Enables the required APIs.
4. Creates the Artifact Registry repository if it doesn't exist.
5. Creates the Terraform state bucket if it doesn't exist (uniform bucket-level access, public access prevention) and enables object versioning so earlier state can be recovered.
6. Grants `roles/cloudbuild.builds.builder` to the Compute Engine default service account. New projects run Cloud Build as that account, and it no longer gets broad permissions automatically, so without this role builds fail with `does not have storage.objects.get access`.
7. Builds the image with Cloud Build, retrying for a couple of minutes while a new IAM grant takes effect, and deploys the Cloud Run baseline (`--concurrency 80`, `--min-instances 1`, `--max-instances 10`).

It checks state before each step, so it's safe to rerun. On a remote machine without a browser, run `gcloud auth login --no-launch-browser` and `gcloud auth application-default login --no-launch-browser` yourself first; the script will then see you're logged in and skip those prompts.

### 2. Provision the platform with Terraform

Terraform state is stored remotely in the GCS bucket that `setup.sh` created. The bucket name is passed at init time, because backend blocks can't use variables.

```bash
cd terraform
terraform init -backend-config="bucket=$TF_STATE_BUCKET"
terraform plan    # variables come from TF_VAR_* exported by env.sh
terraform apply
cd ..
```

`setup.sh` creates the Artifact Registry repository before Terraform runs (the image has to be pushed for the Cloud Run baseline). The `import` block in `import.tf` adopts that existing repository into Terraform state automatically, so the first `plan` shows it as an import rather than a create, with no manual `terraform import` command. Once it's in state, the block does nothing.

Cluster creation takes several minutes. If GKE asks for a control-plane CIDR, add `master_ipv4_cidr_block = "172.16.0.32/28"` to `private_cluster_config` in `gke_autopilot.tf`.

### 3. Connect kubectl

```bash
scripts/connect.sh
```

Fetches cluster credentials and creates the `hello` namespace if it doesn't exist.

### 4. Deploy with Helm

The image and service account values come from `env.sh`, so `values.yaml` doesn't need editing:

```bash
helm lint charts/hello-api

helm upgrade --install $APP_NAME charts/hello-api -n $NAMESPACE \
  --set image.repository=$IMAGE \
  --set image.tag=$IMAGE_TAG \
  --set serviceAccount.name=$APP_NAME \
  --set serviceAccount.gcpServiceAccount=$APP_NAME@$PROJECT_ID.iam.gserviceaccount.com

# Production values: add  -f charts/hello-api/values-prod.yaml  to the command above
```

### 5. Verify

```bash
kubectl get pods,svc,hpa,pdb -n hello
kubectl port-forward -n hello svc/hello-api 8080:80   # then: curl localhost:8080/

# Workload Identity: should list the hello-api Google service account
kubectl run wi-test -n hello --rm -it --image=google/cloud-sdk:slim \
  --overrides='{"spec":{"serviceAccountName":"hello-api"}}' -- gcloud auth list
```

## Cloud Run to GKE mapping

| Cloud Run | GKE equivalent |
| --- | --- |
| `--concurrency` | No hard cap; HPA scales replicas on CPU or a custom metric |
| `--min-instances` | HPA `minReplicas` (always warm, no cold starts) |
| `--max-instances` | HPA `maxReplicas` |
| `--cpu` / `--memory` | Container resource requests and limits |
| Service identity | Kubernetes service account with Workload Identity |
| Revisions and traffic splitting | Deployment rollouts; Gateway API weights for canaries |
| Request timeout (60 min max) | No platform request timeout |

## Design notes

- **Private nodes with Cloud NAT:** nodes have no public IPs. Egress goes through NAT, and Google APIs through Private Google Access.
- **VPC-native networking:** dedicated secondary ranges for pods and services.
- **Least-privilege node service account:** only `roles/container.defaultNodeServiceAccount` and `roles/artifactregistry.reader`, instead of the default compute service account.
- **Workload Identity:** pods authenticate as a Google service account with no exported keys, bound to the exact namespace and Kubernetes service account (`hello/hello-api`).
- **Zero-downtime rollouts:** readiness probe, SIGTERM drain in the app, `maxUnavailable: 0`, and a PodDisruptionBudget.
- **Lab-only settings:** `deletion_protection = false` and a public control-plane endpoint. In production, enable deletion protection and restrict the endpoint with `master_authorized_networks_config` or a private endpoint.

## Troubleshooting drills

Break the deployment on purpose, diagnose it from evidence, then roll back with `helm rollback $APP_NAME -n $NAMESPACE`. Apply each break with `--reuse-values` so the image and service account settings from step 4 are kept, for example:

```bash
helm upgrade $APP_NAME charts/hello-api -n $NAMESPACE --reuse-values --set image.tag=v9
```

| Drill | How to break it | What to look for |
| --- | --- | --- |
| ImagePullBackOff | `--set image.tag=v9` | `describe` events: image not found; old pods keep serving |
| CrashLoopBackOff | `--set livenessPath=/nope` | Liveness probe failures, rising restart count |
| Readiness | `kubectl rollout restart deployment/hello-api -n hello` | `0/1` until `/readyz` passes; old pods drain on SIGTERM |
| Egress blocked | Apply a deny-all egress NetworkPolicy | Outbound calls and DNS fail; allow port 53 to kube-dns plus needed destinations |
| Unschedulable | `--set resources.requests.cpu=200` | Autopilot admission error or `Pending` with a scheduling event |

Diagnostic loop:

```bash
kubectl get pods -n hello
kubectl describe pod <pod> -n hello
kubectl logs <pod> -n hello --previous
kubectl get events -n hello --sort-by=.lastTimestamp
helm history hello-api -n hello
```

## Teardown

```bash
scripts/teardown.sh        # asks for confirmation; use --yes to skip the prompt
```

Uninstalls the Helm release, deletes the Cloud Run service, and runs `terraform destroy`, which also removes the Artifact Registry repository and its images. Each step skips cleanly if the resource is already gone. To rebuild for the next session, run `scripts/setup.sh`, then repeat steps 2 to 4. The `import` block adopts the recreated repository again automatically.

The Terraform state bucket is deliberately left in place, since it holds the state history. To remove it once you're completely done with the lab:

```bash
gcloud storage rm --recursive gs://$TF_STATE_BUCKET
```

## Cost

Autopilot bills for the CPU and memory pods request, plus a cluster management fee. Cloud NAT and Cloud Run with `--min-instances 1` also incur charges. Tear down after each session; a rebuild takes only a few minutes.