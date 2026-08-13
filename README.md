# cicd-demo

A deliberately tiny Python app (`hello.py`) wrapped in a **comprehensive
CI/CD pipeline** that demonstrates:

- Automated testing (pytest, multi-version matrix)
- Multi-format container builds: **Docker/OCI** and **Apptainer/Singularity**
- Container **vulnerability scanning** (Trivy) with reports and a GitHub
  Security tab integration
- Publishing images to **both** Docker Hub **and** GitHub Container
  Registry (GHCR)
- **SSH deployment**: copying/loading the built image on an upstream server
- Publishing the Python package itself to **PyPI** on release

The application code is intentionally trivial — the pipeline is the point.

```
cicd-demo/
├── hello.py                        # the app
├── test_hello.py                   # unit tests
├── requirements.txt                # runtime deps (numpy)
├── requirements-dev.txt            # + pytest, flake8
├── pyproject.toml                  # PyPI packaging metadata
├── Dockerfile                      # Debian + curl + python3 + numpy
├── apptainer.def                   # Apptainer/Singularity definition
├── .dockerignore
├── .gitignore
├── LICENSE
└── .github/workflows/
    ├── ci.yml                      # lint + test on every push/PR
    ├── containers.yml              # build/scan/push/deploy containers
    └── publish-pypi.yml            # build + publish to PyPI on release
```

---

## 1. The app

`hello.py` prints a greeting and runs a trivial numpy calculation, so the
container images have a real (small) third-party dependency to install,
scan, and ship — not just a bare `print("hello")`.

Run locally:

```bash
python -m venv venv
source venv/bin/activate
pip install -r requirements-dev.txt
python hello.py CHESS_USER
pytest
```

---

## 2. The container image

### Dockerfile

Base image: **`debian:bookworm-slim`**, with:

| Package             | Why |
|---------------------|-----|
| `curl`               | demonstrates a non-Python tool baked into the image; also used by the `HEALTHCHECK` |
| `ca-certificates`     | required for curl/pip HTTPS |
| `python3`, `python3-pip`, `python3-venv` | runtime for `hello.py` |
| `numpy` (via pip, in a venv) | example third-party Python library |

Notes on the Dockerfile:

- Debian 12 marks the system Python as "externally managed" (PEP 668), so
  dependencies are installed into a virtualenv at `/opt/venv` rather than
  with `pip install --break-system-packages`.
- The image runs as an unprivileged `appuser`, not root.
- A `HEALTHCHECK` uses `curl` to confirm outbound HTTPS works.
- OCI labels are set for provenance (`org.opencontainers.image.*`).

Build and run it yourself:

```bash
docker build -t cicd-demo:local .
docker run --rm cicd-demo:local CHESS_USER
```

If we do not have native apptainer we may save docker image to a archive
and rebuild apptainer image with it, e.g.

```
# ensure that we rebuild image for proper architecture
docker buildx build --platform linux/amd64 -t cicd-demo:linux-amd64 .

# verify that we indeed using proper arcitecture
docker inspect cicd-demo:linux-amd64 | grep Architecture

# save docker image to tarball
docker save cicd-demo:linux-amd64 -o cicd-demo.tar

# copy your tarball to remote linux node
scp cicd-demo.tar user@host:/tmp/cicd-demo.tar

# convert image tarball into apptainer image
apptainer build /tmp/cicd-demo.sif docker-archive:/tmp/cicd-demo.tar
```

### Apptainer / Singularity image

`apptainer.def` builds the equivalent environment as a **`.sif`** image —
useful for HPC / shared-cluster environments where Docker daemons aren't
available but Apptainer is. It bootstraps from the same `debian:bookworm-slim`
Docker base so the two images stay consistent.

```bash
sudo apt-get install -y apptainer   # or see apptainer.org for your OS
sudo apptainer build cicd-demo.sif apptainer.def
apptainer run cicd-demo.sif CHESS_USER
```

### Usefull commands

```
docker history cicd-demo:linux-amd64
IMAGE          CREATED         CREATED BY                                      SIZE      COMMENT
a3e284b92b8b   7 minutes ago   LABEL org.opencontainers.image.title=cicd-de…   0B        buildkit.dockerfile.v0
<missing>      7 minutes ago   CMD ["World"]                                   0B        buildkit.dockerfile.v0
<missing>      7 minutes ago   ENTRYPOINT ["python3" "hello.py"]               0B        buildkit.dockerfile.v0
<missing>      7 minutes ago   HEALTHCHECK {Test:[CMD-SHELL curl -fsS https…   0B        buildkit.dockerfile.v0
<missing>      7 minutes ago   USER appuser                                    0B        buildkit.dockerfile.v0
<missing>      7 minutes ago   RUN /bin/sh -c chown -R appuser:appuser /app…   0B        buildkit.dockerfile.v0
<missing>      7 minutes ago   COPY hello.py ./ # buildkit                     0B        buildkit.dockerfile.v0
<missing>      7 minutes ago   ENV PATH=/opt/venv/bin:/usr/local/sbin:/usr/…   0B        buildkit.dockerfile.v0
<missing>      7 minutes ago   RUN /bin/sh -c python3 -m venv /opt/venv    …   0B        buildkit.dockerfile.v0
<missing>      7 minutes ago   COPY requirements.txt ./ # buildkit             0B        buildkit.dockerfile.v0
<missing>      7 minutes ago   RUN /bin/sh -c useradd --create-home --shell…   0B        buildkit.dockerfile.v0
<missing>      7 minutes ago   WORKDIR /app                                    0B        buildkit.dockerfile.v0
<missing>      7 minutes ago   RUN /bin/sh -c apt-get update     && apt-get…   0B        buildkit.dockerfile.v0
<missing>      7 minutes ago   ENV DEBIAN_FRONTEND=noninteractive PYTHONDON…   0B        buildkit.dockerfile.v0
<missing>      9 days ago      # debian.sh --arch 'amd64' out/ 'bookworm' '…   85.3MB    debuerreotype 0.17

# login to the container
docker run --rm -it cicd-demo:local /bin/bash
# if your container is already running, then use
docker exec -it container_name_or_id /bin/bash


# for apptainer
apptainer inspect /tmp/cicd-demo.sif
org.label-schema.build-arch: amd64
org.label-schema.build-date: Wednesday_12_August_2026_16:3:47_EDT
org.label-schema.schema-version: 1.0
org.label-schema.usage.apptainer.version: 1.2.5-1.el9
org.label-schema.usage.singularity.deffile.bootstrap: docker-archive
org.label-schema.usage.singularity.deffile.from: /tmp/cicd-demo.tar
org.opencontainers.image.description: Minimal demo app: Debian + curl + python3 + numpy
org.opencontainers.image.licenses: MIT
org.opencontainers.image.source: https://github.com/vkuznet/cicd-demo
org.opencontainers.image.title: cicd-demo

# get apptainer shell
apptainer shell /tmp/cicd-demo.sif

```

---

## 3. CI/CD pipeline (GitHub Actions)

### `ci.yml` — fast feedback on every push/PR

- Matrix-tests against Python 3.10 / 3.11 / 3.12
- `flake8` lint
- `pytest` with coverage, coverage report uploaded as a build artifact

### `containers.yml` — build, scan, push, deploy

Triggered on push to `main`, on version tags (`v*.*.*`), and on PRs
(build/scan only — no push/deploy on PRs).

1. **`test`** — re-runs the unit tests as a gate before spending time on
   container builds.
2. **`docker`** —
   - Builds a multi-arch-capable image with Buildx (QEMU set up for
     cross-arch builds).
   - Tags are derived automatically (`latest` on `main`, branch name,
     PR number, semver from tags, short SHA) via `docker/metadata-action`.
   - Loads the image locally and scans it with **Trivy**:
     - a human-readable `trivy-report.txt` (uploaded as a build artifact)
     - a `trivy-results.sarif` uploaded to the repo's **Security → Code
       scanning** tab
   - On push/tag events (not PRs): pushes the image to **both**
     `docker.io/<DOCKERHUB_USERNAME>/cicd-demo` and
     `ghcr.io/vkuznet/cicd-demo`.
   - Saves the pushed image as a `.tar` and uploads it as a build
     artifact for the deploy job.
3. **`apptainer`** — builds `cicd-demo.sif` from `apptainer.def`,
   smoke-tests it (`apptainer run` + `apptainer test`), uploads it as a
   build artifact, and (on push/tag) pushes it to GHCR as an OCI artifact
   via `apptainer push oras://ghcr.io/...`.
4. **`deploy`** — on pushes to `main` only:
   - Downloads the image tar built in step 2.
   - `scp`s it to `DEPLOY_HOST` via `appleboy/scp-action`.
   - SSHes in (`appleboy/ssh-action`) and runs `docker load` +
     `docker run` to (re)start the container on the upstream server.

To make this CI/CD workflow working you **MUST** create new access token on
hub.docker.com and provide it to github repo as secret along with your user
name. Follow these steps:

- Log in to hub.docker.com
- Go to Account Settings → Security → Access Tokens
- Click New Access Token
  - Give it a description (e.g. github-actions-hello-cicd-demo) 
  - Permissions: Read & Write (you need push access)
  - Click Generate and copy the token immediately — Docker Hub only shows it once
- Add both secrets to your GitHub repo
  - In your repo: Settings → Secrets and variables → Actions → New repository secret

#### Published Images
You can find published images on
- docker hub: `https://hub.docker.com/repository/docker/<DOCKERHUB_USERNAME>/cicd-demo/general`
- github repo: `https://github.com/vkuznet?tab=packages`

#### Security report
this workflow generates security reports of the software packages used in
generated images and it can be found in `Security and quality` tab on github,
see direct link:
`https://github.com/vkuznet/py-cicd-demo/security/code-scanning`

### `publish-pypi.yml` — release the Python package

Triggered when you publish a GitHub Release (tag `v*.*.*`):

1. Runs the tests again, builds an sdist + wheel with `python -m build`.
2. Publishes to PyPI using **Trusted Publishing (OIDC)** — no long-lived
   PyPI token needs to live in GitHub Secrets. (A commented-out fallback
   using a classic `PYPI_API_TOKEN` secret is included if you prefer that.)

---

## 4. Required GitHub configuration

### Secrets (`Settings → Secrets and variables → Actions`)

| Secret               | Used by            | Description |
|-----------------------|---------------------|--------------|
| `DOCKERHUB_USERNAME`  | `containers.yml`    | Docker Hub username |
| `DOCKERHUB_TOKEN`     | `containers.yml`    | Docker Hub **access token** (Account Settings → Security), not your password |
| `DEPLOY_HOST`         | `containers.yml`    | Hostname/IP of the upstream server |
| `DEPLOY_USER`         | `containers.yml`    | SSH user on the upstream server |
| `DEPLOY_SSH_KEY`      | `containers.yml`    | Private key with access to `DEPLOY_USER@DEPLOY_HOST` (public key added to that server's `~/.ssh/authorized_keys`) |
| `DEPLOY_PORT`         | `containers.yml`    | *(optional)* SSH port, defaults to `22` |
| `PYPI_API_TOKEN`      | `publish-pypi.yml`  | *(optional)* only if you skip Trusted Publishing |

`GITHUB_TOKEN` (pushing to GHCR, uploading SARIF) is provided
automatically by GitHub Actions — no setup needed, beyond the
`packages: write` / `security-events: write` permissions already
declared in the workflow.

### PyPI Trusted Publishing setup

1. On PyPI, go to your project → **Publishing** → "Add a new trusted publisher".
2. Fill in: GitHub owner/repo, workflow filename `publish-pypi.yml`,
   environment name `pypi`.
3. No token needed afterward — the workflow authenticates via OIDC.

### Upstream deploy server prerequisites

- Docker installed and the `DEPLOY_USER` in the `docker` group.
- `~/deployments/cicd-demo/` directory (or let `scp-action` create it).
- The corresponding public key for `DEPLOY_SSH_KEY` in
  `~/.ssh/authorized_keys` for `DEPLOY_USER`.

---

## 5. Quick reference: pulling the published images

```bash
# Docker Hub
docker pull <dockerhub-username>/cicd-demo:latest

# GHCR
docker pull ghcr.io/vkuznet/cicd-demo:latest

# Apptainer .sif pushed as an OCI artifact to GHCR
apptainer pull oras://ghcr.io/vkuznet/cicd-demo-sif:latest
```

## License

MIT — see [LICENSE](LICENSE).
