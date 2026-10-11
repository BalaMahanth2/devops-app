# devops-app

![CI](https://github.com/BalaMahanth2/devops-app/actions/workflows/ci.yml/badge.svg?branch=develop)


An end-to-end DevOps & DevSecOps project, built from scratch one phase at a time.

## branch rule

- develop is the default branch
- main is the production branch

## Roadmap

- [x] Phase 1 — Git repository & foundations
- [x] Phase 2 — Static web app running locally
- [x] Phase 3 — Database
- [x] Phase 4 — CI/CD with GitHub Actions
- [x] Phase 5 — Kubernetes (local)
- [x] Phase 6 — AWS: image in ECR, app on EKS
- [ ] Phase 7 — Terraform for AWS + Ansible for VM config
- [ ] Phase 8 — Local production environment
- [ ] Phase 9 — Monitoring (Prometheus + Grafana)
- [ ] Phase 10 — GitOps with ArgoCD
- [ ] Phase 11 — Break it, debug it, harden it

## Run locally

~~~bash
cp -n .env.example .env            # then set a real POSTGRES_PASSWORD
docker compose up -d --build
curl http://localhost:8080/ready
~~~

| URL | Purpose |
| --- | --- |
| <http://localhost:8080> | Web page (counts visits in Postgres) |
| <http://localhost:8080/health> | Liveness: process is up |
| <http://localhost:8080/ready> | Readiness: database reachable |

## Run on AWS

Needs a KodeKloud AWS sandbox session. Terraform creates everything and removes it again at the end.

~~~bash
aws configure --profile kk               # new keys every session, region us-east-1
export AWS_PROFILE=kk                    # again in every new terminal
cd terraform/environments/sandbox
terraform init
terraform apply                          # registry, cluster, nodes: about 10 minutes
cd ../../..
./scripts/aws-deploy.sh                  # image, kubectl, Helm chart
./scripts/aws-status.sh                  # health of everything
cd terraform/environments/sandbox
terraform destroy                        # about 10 minutes
kubectl config use-context kind-devops-app
kubectl config delete-context eks-devops-app
~~~

| Problem | Fix |
| --- | --- |
| `InvalidClientTokenId` | This terminal is missing `export AWS_PROFILE=kk` |
| The addresses answer `000` | Your public address changed: `terraform apply -var allow_cidr=157.50.0.0/16` |
| `terraform destroy` stops with `Unauthorized` | Run `terraform destroy` again; it continues where it stopped |
| New sandbox account, old state file | `rm -f terraform.tfstate terraform.tfstate.backup` in the sandbox folder |

The same result without Terraform: `scripts/aws-up.sh` and `scripts/aws-down.sh`.
