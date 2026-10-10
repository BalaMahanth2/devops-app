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
- [ ] Phase 4 — CI/CD with GitHub Actions
- [ ] Phase 5 — Kubernetes (local)
- [ ] Phase 6 — AWS: image in ECR, app on EKS
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
