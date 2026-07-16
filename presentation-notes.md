# Stage 1 — Presentation Notes
### Network foundation + MongoDB VM (intentionally misconfigured)

---

## What we built

A **network foundation** and the **database tier** of the two-tier app, entirely in Terraform:

- **Resource group** — the container everything lives in
- **VNet with two subnets** — `public-subnet` (holds the DB VM) and `private-subnet` (/22, reserved for the AKS cluster in Stage 3)
- **NSG + rules** — SSH (22) open to `0.0.0.0/0`; MongoDB (27017) allowed **only** from the private subnet CIDR
- **Public IP + NIC** — makes the VM internet-reachable
- **Linux VM** — Ubuntu 20.04 (deliberately 1+ year outdated), Standard_B2s, RSA 4096 key auth
- **System-assigned managed identity + role assignment** — **Contributor at subscription scope**
- **cloud-init** — installs MongoDB 4.4 (deliberately outdated), binds to `0.0.0.0`, enables auth, creates an app user

**Everything is Infrastructure-as-Code** — repeatable, reviewable, and tears down cleanly with one command.

---

## What each Terraform file does

| File | Plain English |
|---|---|
| `providers.tf` | The wiring. Tells Terraform which cloud to talk to (the `azurerm` provider), which version, and which subscription to deploy into. Nothing gets built without it. |
| `variables.tf` | The input definitions. Declares what can be passed in — subscription ID, SSH key path, DB password — so nothing sensitive is hardcoded. |
| `terraform.tfvars` | The actual values for those variables. **Gitignored** — holds the random DB password and subscription ID. Never reaches GitHub. |
| `network.tf` | The plumbing. Resource group, VNet, both subnets, the NSG and its rules. Defines what can talk to what. |
| `vm.tf` | The database host. Public IP, NIC, the Ubuntu VM, its managed identity, the Contributor role assignment, and the cloud-init that installs MongoDB. |
| `outputs.tf` | The useful values printed after apply — VM public IP, private subnet CIDR — so I don't have to dig through the portal. |
| `.gitignore` | The safety net. Excludes `*.tfvars` and `*.tfstate` so secrets never get committed. |

---

## The three misconfigurations — and the attack

| # | Misconfiguration | Severity alone | Role in the chain |
|---|---|---|---|
| 1 | SSH open to `0.0.0.0/0` | Medium | **The way in** |
| 2 | Contributor-role managed identity | Medium | **The escalation** |
| 3 | Outdated Ubuntu 20.04 + MongoDB 4.4 | Medium | **The exploit** |

**Individually: three mediums. Chained: critical.** That's the whole point.

---

## COLD ANSWER 1 — Why is public SSH dangerous?

> "SSH open to `0.0.0.0/0` means every IP address on the internet can reach the login prompt. In practice, an exposed SSH port is found and probed by automated scanners within **minutes** of coming online — this isn't theoretical, it's constant background noise on the internet.
>
> Now, I configured this one *properly* — RSA 4096 key auth, no password login — so brute-forcing the credential is computationally infeasible. And that's exactly the point I want to make: **the exposure is still critical, and it has nothing to do with weak credentials.**
>
> The real-world consequence is that it removes the network as a control. There's no VPN, no bastion, no jump box, no source-IP restriction — just the host's own defences standing between the internet and a shell. If there's an unpatched CVE in the SSH daemon or the OS, or a key leaks, or a developer copies that key into a repo, there is nothing else in the way. In a real enterprise you'd put this behind a bastion host or Azure Bastion, restrict the source range to corporate IPs, and use just-in-time access so the port is only open when someone actually needs it."

**The "so what":** *The danger isn't the door — it's that the door is the only control, and it opens onto something valuable.*

---

## COLD ANSWER 2 — What can an attacker do with a Contributor-role managed identity?

> "This is the multiplier — the hop that turns a host problem into a **cloud breach**.
>
> The VM has a system-assigned managed identity with **Contributor at subscription scope**. Critically, a managed identity isn't a password sitting in a config file — it's a token retrievable from the **Instance Metadata Service** at `169.254.169.254`. Any process on that box can simply *ask* for it. No credentials needed. **Being on the box IS the credential.**
>
> So the moment an attacker gets shell — one curl command and they hold Contributor rights over the entire subscription. Not 'access to a VM'. Cloud admin.
>
> With Contributor they can: create VMs for crypto-mining or persistence, read **every** storage account in the subscription — including my public backup bucket — modify NSGs to open more doors, enumerate and pivot to every other resource, and create new identities to persist even after the VM is cleaned up.
>
> The fix is least privilege. This VM's job is to run a database and write backups to one storage account. It needs a narrowly-scoped role on *that one resource* — not Contributor on everything."

**The "so what":** *The exposure gives you the box. The box gives you the token. The token gives you the subscription.*

**Bonus — the live demo moment:** pull the token on-screen with the IMDS curl. Nothing lands harder than showing it takes one command and zero credentials.

---

## COLD ANSWER 3 — Why does an outdated MongoDB matter beyond "it's old"?

> "Three reasons — and none of them are 'old is bad'.
>
> **First, it's out of support.** MongoDB 4.4 is past end-of-life, which means no security patches. Any CVE disclosed from here on is permanent. It's not that it *has* known vulnerabilities — it's that it will accumulate them forever with no fix path.
>
> **Second, auth doesn't save you.** And this is the interesting part of this build: the database layer is actually configured *to spec* — authentication is enabled, and network access is restricted to the Kubernetes subnet only. A compliance checklist **passes this database**. But an exploit against an unpatched daemon bypasses the login entirely — you don't need a password if you can exploit the process that checks passwords.
>
> **Third, and most importantly — the host undermines the database.** The attacker never touches the Mongo login. They SSH in, and as root on the box they can read the data files straight off disk, pull the app's connection string out of the environment, or just turn auth off and restart the service. The database's own controls are irrelevant once you own the machine underneath it.
>
> Same for the OS — Ubuntu 20.04 is 1+ year outdated, so the host itself is carrying unpatched CVEs that are the most likely route to that shell in the first place."

**The "so what":** *Auth 'on' is a compliance answer, not a security answer. This database passes a checklist and is still critically at risk — because security isn't a property of one component, it's a property of the path.*

---

## THE ENTERPRISE PROBLEM (Tom's #1 ask — land this hard)

> "Here's what a large organisation actually faces. Every one of these is a **medium** on its own, and every scanner on the market will report them separately: 'SSH exposed' — medium. 'Over-permissioned identity' — medium. 'Outdated package' — medium. Across 10,000 VMs that's tens of thousands of findings, all with severity labels, none with relationships.
>
> Nobody can eyeball which single VM has **all three**. And that's the one that ends your cloud.
>
> The problem isn't detection — everyone can detect these. The problem is **context and prioritisation**: seeing that this exposure connects to this identity which reaches this data. You're not looking for a longer list of findings; you're looking for the handful of *paths* where individually-tolerable issues chain into a breach.
>
> That's what I'll demonstrate in the security stage — moving from thousands of alerts to the two or three that actually matter."

---

## Challenges & adaptations (the doc explicitly asks for these)

- **Ed25519 → RSA 4096.** Defaulted to ed25519 as the modern standard; hit an Azure provider constraint — `azurerm_linux_virtual_machine` only supports RSA for `admin_ssh_key`. Regenerated as RSA 4096. Small thing, but a reminder that cloud provider constraints don't always follow current best practice.
- **Secret handling.** Random 24-char generated DB password, held in `terraform.tfvars`, gitignored alongside `*.tfstate` — state files store secrets in plaintext too, which is a classic real-world leak people miss. Injected into the app as a Kubernetes env var in Stage 3, never baked into the image.

---

## Panel-proofing: the likely follow-ups

- **"How would you fix the identity?"** → Least privilege: a custom role scoped to just the backup storage account, not Contributor on the subscription.
- **"How would you fix the SSH exposure?"** → Azure Bastion or a jump box, source-range restriction to corporate IPs, and just-in-time access.
- **"So which one do you fix first?"** → The identity. It's the multiplier — it's what converts every other issue from 'a bad day' into 'a breach'. Remove Contributor and the same SSH exposure is a contained problem.

---

# Stage 2 — Presentation Notes
### Automated MongoDB backups + public storage container (intentionally misconfigured)

---

## What we built

Automated backups for the database tier, entirely in Terraform + a shell script:

- **Storage account** (`storage.tf`) — `azurerm_storage_account.backups`, random 6-char suffix for global uniqueness, LRS replication
- **`allow_nested_items_to_be_public = true`** — overrides Azure's *default* guardrail, which normally blocks anonymous access account-wide on new storage accounts
- **Blob container** — `mongo-backups`, `container_access_type = "container"`, which grants **anonymous read AND list**
- **Least-privilege identity, done right this time** — the VM's managed identity gets `Storage Blob Data Contributor` scoped to just *this one storage account* (contrast with Stage 1's subscription-wide Contributor grant — this is the fix pattern applied)
- **`backup-mongo.sh.tpl`** — cron job, runs daily at 02:00: `mongodump` → tar.gz → pulls an IMDS token for the VM's identity, scoped to `storage.azure.com` → `PUT`s the archive straight to blob storage over the REST API, no stored key anywhere
- **Outputs** — `storage_account_name` and `backup_container_url`, so the public URL is printed right after `apply` (a nice "look how easy this is to find" demo beat)

---

## The misconfiguration

| Misconfig | Severity alone | Role in the chain |
|---|---|---|
| Public **read + list** on the backup container | Critical | **The exfil path that skips the database entirely** |

---

## COLD ANSWER — Why does a public backup container matter more than it sounds?

> "The database itself is configured properly in this build — auth is on, network access is restricted. But none of that matters, because the backups **bypass it completely**. An attacker doesn't need the database — the backups *are* the data, sitting on the open internet with zero authentication.
>
> And the dangerous part isn't just 'public read.' It's that this container also grants **public list**. That means an attacker doesn't have to guess filenames or brute-force a timestamp pattern — they can enumerate the entire container and see every backup that's ever been written, then just pull whichever one they want. Read plus list turns 'maybe you get lucky' into 'here's the full inventory, help yourself.'
>
> This is also the classic blind spot: **'it's just a backup bucket.'** Backups get treated as an operational afterthought — a thing ops sets up for disaster recovery — not as a copy of the crown jewels that deserves the same controls as the primary database. In practice, the crown jewels don't leak through the front door. They leak through the copy nobody was watching."

**The "so what":** *An attacker doesn't need to breach the database if the backup of the database is sitting in the open. The copy is the data.*

---

## THE ENTERPRISE PROBLEM

> "For a financial-services organisation, this container isn't holding abstract 'data' — it's holding customer financial records, unauthenticated, discoverable by anyone who finds the storage account name. That's not a hypothetical risk, that's a **direct regulatory breach**: GDPR if there's EU customer data, DORA if this is a regulated EU financial entity's ICT infrastructure. Either way, this is the kind of exposure that triggers mandatory breach notification, not just an internal ticket.
>
> And notice the chain this stage adds: I *fixed* the identity problem from Stage 1 — the VM's role here is scoped to just this one storage account, not subscription-wide Contributor. That's the textbook remediation. But it doesn't matter, because the container's own access policy makes identity irrelevant. You don't need the VM's token, you don't need any credential at all — anonymous HTTP GET is enough. **Least-privilege identity doesn't help you if the resource itself is configured to hand the data to anyone who asks.**"

**The "so what":** *Identity and network controls are necessary but not sufficient — a public resource policy defeats them both from underneath.*

---

## The fix

- **Private by default** — `container_access_type = "private"`, and don't set `allow_nested_items_to_be_public` at the account level; let Azure's default guardrail do its job instead of overriding it
- **Encryption** — enable/confirm encryption at rest (Storage Service Encryption, on by default) and enforce HTTPS-only transfer
- **Access via identity, not anonymity** — the VM already has a scoped managed identity; reads for restore should go through that identity or short-lived SAS tokens, never anonymous access
- **Detection tooling** — this is exactly the class of finding Microsoft Defender for Cloud / Defender for Storage flags automatically: public storage accounts, and (with sensitive data discovery enabled) public storage that *also* contains sensitive data gets escalated in severity — because "public bucket" and "public bucket full of financial records" are very different risk levels

---

## Panel-proofing: the likely follow-ups

- **"How would you fix this?"** → Flip `container_access_type` to `private`, remove the account-level override, and route restores through the VM's existing scoped managed identity or short-lived SAS tokens instead of anonymous access.
- **"Isn't Storage Blob Data Contributor scoped to one account good enough?"** → It's necessary but not sufficient — it governs the *identity's* access, not the *container's* access policy. A public container is readable by anyone with zero credentials, so scoping the identity doesn't close the hole.
- **"Why is public list worse than public read alone?"** → Read without list still requires knowing or guessing exact filenames. List turns the container into a directory anyone can browse — the attacker gets the full inventory for free.
- **"How would Defender for Cloud actually catch this?"** → It flags public storage accounts as a standing posture finding, and with sensitive data discovery enabled, it correlates *what's* in the container — customer/financial data — to bump the severity, which is exactly the "context over raw finding count" theme from Stage 1.

---

# Stage 3 — Presentation Notes
### AKS cluster + ACR (application tier)

---

## Notes

**3a — Public API server, private nodes.** Cluster nodes sit in `private-subnet` (good practice, per spec). The AKS **API server** is left publicly reachable (`private_cluster_enabled = false`) so `kubectl` works directly from a laptop — a deliberate simplification, not an oversight. In production I'd set `private_cluster_enabled = true` and put a bastion/jump box (or VPN) inside the VNet to reach the API server at all, the same pattern as the Stage 1 SSH fix. Worth stating proactively so the panel sees I know the tradeoff, rather than waiting to be asked "isn't the API server exposed?"

# Stage 3b — Presentation Notes
### Container build, image validation, and registry push

---

## What we built

- A minimal **Node.js/Express todo app** that reads its MongoDB connection string from an **environment variable** (`MONGODB_URI`) — never hardcoded, because Kubernetes injects it at deploy time per the spec
- A **Dockerfile** that builds the app image and `COPY`s **`wizexercise.txt`** (containing my name) into it
- Image built for **`linux/amd64`**, validated locally, tagged and pushed to **Azure Container Registry**
- AKS pulls from ACR via **managed identity** (`AcrPull` role) — no registry credentials anywhere

---

## Required demonstration: how `wizexercise.txt` got in, and proof it's there

**How it got in:** a `COPY` instruction in the Dockerfile — so it's baked into the image at **build time**, as an immutable layer.

**Proof it's in the image:**
```bash
docker run --rm --platform linux/amd64 todo-app:v1 cat /app/wizexercise.txt
# → Adon Blackwood
```
*(In 3d, same proof from inside the running pod via `kubectl exec`.)*

**Why validate at all?** There's a difference between a file being *on my laptop* and a file being *inside the image*. This proves the `COPY` actually worked — evidence, not assumption.

---

## COLD ANSWER 1 — "If someone deleted `wizexercise.txt` and rebuilt right now?"

> "**The build would fail immediately** — `COPY` is a build-time instruction reading from the local build context. No file on disk, no image. Hard error, not a warning.
>
> But here's the important part: **the existing `todo-app:v1` image would be completely unaffected**. Images are **immutable**. Once built, that file is a permanent layer — not a link to my filesystem. I could wipe this laptop entirely and any machine that pulls `v1` would still print my name.
>
> That immutability cuts both ways, and it's the security point. It's *good*: what I tested is exactly what runs in production — no drift, no surprises. It's also *why image scanning matters*: a vulnerable library baked in at build time stays vulnerable in **every running copy, forever**, until someone rebuilds. You can't patch an image in place. You rebuild and redeploy — which means your pipeline, not your ops team, is your patching mechanism."

**The "so what":** *Immutability means your build is your production reality. Whatever you didn't catch at build time, you're running everywhere.*

---

## COLD ANSWER 2 — "Why `COPY package*.json` + `npm install` before `COPY server.js`?"

> "**Layer caching.** Docker builds in layers, one per instruction, and caches each. On rebuild it reuses cached layers until it hits the first change — and once a layer is invalidated, **everything after it rebuilds too**.
>
> If I copied everything at once, then `npm install`, one line changed in `server.js` would invalidate the COPY layer, which invalidates `npm install`, and I'd re-download the entire dependency tree. Every build. Every commit.
>
> By copying the **dependency manifest first** and installing, that expensive layer stays cached across all my code edits. Only the last layer rebuilds.
>
> **The rule:** order instructions from least-likely-to-change to most-likely-to-change. Dependencies change rarely; code changes constantly.
>
> In a CI/CD pipeline that's the difference between a 20-second build and a 3-minute one — on every single commit, across every developer. It compounds fast."

**The "so what":** *Build speed is a security control. Slow pipelines get bypassed, and bypassed pipelines skip scanning.*

---

## COLD ANSWER 3 — "`az acr login` didn't ask for credentials. What identity did it use, and why is that better than `admin_enabled = true`?"

> "It used my **Entra ID identity** from the earlier `az login`. The CLI exchanged my existing Entra token for a **short-lived registry refresh token** and handed that to Docker. No username, no password — because I was already authenticated as *me*.
>
> Compare that to ACR admin credentials:

| | Entra ID (what I used) | ACR admin user |
|---|---|---|
| Credential | Short-lived token, auto-expires | Static password, lives forever |
| Who is it? | *Me* — attributable | Shared account — anonymous |
| Permissions | RBAC-scoped (`AcrPull` vs `AcrPush`) | All-or-nothing full admin |
| Revocation | Disable the user | Rotate key + update every consumer |
| Audit trail | "Adon pushed this image" | "Someone pushed this image" |
| MFA / conditional access | ✅ | ❌ |

> "The core problem with admin creds is that they're a **shared, long-lived, non-attributable secret with full rights** — and shared secrets go where secrets go: a pipeline variable, a `.env` file, a Slack message.
>
> And the blast radius isn't 'someone reads my images.' Admin means **push**. A leaked admin credential means an attacker plants a **backdoored image** that every node in my cluster pulls and runs. That's **supply-chain compromise** — and it's near-invisible, because the cluster is behaving exactly as designed.
>
> Better still: **AKS pulls from ACR using its own managed identity** with `AcrPull`. There is no credential in the cluster at all — nothing to leak, nothing to rotate."

**The "so what":** *Identity-based auth beats shared secrets because you can attribute it, scope it, expire it, and revoke it. A static registry password is a supply-chain backdoor waiting to be pasted somewhere.*

---

## The contrast worth drawing (ties the whole story together)

**This stage is what "done right" looks like — deliberately.**

- Stage 1: root on the VM hands an attacker the DB password **and** an IMDS token. Secrets to steal.
- Stage 3b: identity-based auth end-to-end. **No secret exists to steal.**

Same principle, opposite outcome. Worth stating explicitly to the panel: it shows the misconfigurations elsewhere are *intentional*, not ignorance.

---

## Challenges & adaptations

**Apple Silicon vs AKS architecture.** I'm building on an arm64 Mac; AKS nodes are x86_64/amd64. So I built explicitly with `--platform linux/amd64`. Running it locally then emits a platform-mismatch warning — that's Docker emulating amd64 on arm64, which is expected and *correct*.

Had I ignored architecture and built arm64, the container would have crash-looped on the cluster with `exec format error` — a genuinely confusing failure to debug. Good example of validating against the **target** environment, not "works on my machine."

---

## Likely follow-ups

- **"How would you stop someone planting a malicious file this way?"** → Image scanning in the pipeline (Stage 4), signed images / trusted base images, admission control that rejects unsigned or unscanned images, and branch protection so Dockerfile changes need review.
- **"What's in your base image?"** → That's the point of SBOM and scanning — most vulnerabilities come from dependencies and base layers, not code I wrote.
- **"Why env var instead of baking the connection string in?"** → Secrets in an image are permanent and readable by anyone who pulls it. Env var injection at deploy time keeps config out of the artifact — per the spec, and the right pattern regardless.

# Stage 3 — Presentation Notes
### The app on Kubernetes (deploy, expose, and the cluster-admin misconfig)

*(3b — container build, image validation, ACR auth — is in its own notes file. This covers 3a/3c/3d: the platform, the deploy, and the verification.)*

---

## What we built

- **AKS cluster** with nodes in the **private subnet** (per spec), pulling images from ACR via **managed identity** (`AcrPull` — no registry credentials)
- **Deployment** running the todo app image, 2/2 replicas
- **DB access via a Kubernetes Secret → `MONGODB_URI` environment variable** (per spec — not hardcoded), pointing at the Mongo VM's private IP with auth
- **Intentional misconfiguration:** a dedicated ServiceAccount bound to the built-in **`cluster-admin`** ClusterRole
- **Exposure:** app Service (ClusterIP) → **nginx ingress controller** (type LoadBalancer, gets the Azure public IP) → **Ingress** routing rule. Live at `http://4.157.111.117/`
- **Verified end-to-end:** todos added in the browser persist to MongoDB on the VM

---

## The exposure chain (likely panel question — know the layers)

**Internet → Azure Load Balancer → nginx ingress controller → Ingress rule → app ClusterIP Service → pod**

- The app's own Service is **ClusterIP** — internal only, deliberately not public
- The **ingress controller's** Service is type **LoadBalancer** — that's what makes Azure provision the public IP; one front door for the cluster
- The **Ingress resource** is the routing rule tying a path to the app Service

This satisfies the spec exactly: *"exposed via a Kubernetes ingress AND a CSP load balancer."* Both boxes ticked — the Ingress (K8s layer) and the Azure load balancer (CSP layer).

---

## Required demonstrations — all captured

- ✅ **kubectl working** — `kubectl get pods` / `get clusterrolebinding` / `get svc`
- ✅ **App works + data in DB** — browser todo shown, then the same record queried live in MongoDB on the VM (`mongo ... db.todos.find()`)
- ✅ **`wizexercise.txt` in the running pod** — `kubectl exec <pod> -- cat /app/wizexercise.txt` → my name (validates it inside the *running* container, not just the image)
- ✅ **cluster-admin misconfig** — ServiceAccount token mounted in the pod, bound to `cluster-admin`

---

## THE HEADLINE MISCONFIG: cluster-admin ServiceAccount

**What it is:** the todo app's ServiceAccount is bound to `cluster-admin` — god-mode over the entire cluster. A todo app needs permission to do almost nothing; it was given permission to do everything.

### COLD ANSWER — "What could an attacker do with that ServiceAccount token from inside a pod?"

> "The token is auto-mounted at a predictable path — `/var/run/secrets/kubernetes.io/serviceaccount/token`. Because that ServiceAccount is `cluster-admin`, that token IS god-mode for the whole cluster.
>
> The most concrete thing: **read every Secret in every namespace.**
> ```
> kubectl --token=$(cat /var/run/.../token) get secrets --all-namespaces -o yaml
> ```
> Secrets are only base64-encoded, so decoding is trivial. Now the attacker has every credential any team ever stored in the cluster.
>
> With cluster-admin they can also: launch a privileged pod that mounts the host filesystem (that's the container-escape → node hop), read other applications' secrets (lateral movement across teams), delete or tamper with any workload (ransomware), and create their own persistent admin identity to survive the pod being killed."

---

## THE FULL ATTACK CHAIN — the centrepiece narrative (ties Stages 1–3 together)

**This is the single most powerful story in the exercise. Lead the security section with it.**

> "Follow one compromised todo pod. The way in is the attack path I showed earlier — internet-facing app, container escape. Normally that gets you *one pod*.
>
> But this pod's ServiceAccount is **cluster-admin** — so instantly they own the whole cluster and can read every Secret in it.
>
> One of those Secrets is the **Mongo connection string**, pointing at the database VM.
>
> That VM's managed identity is **Contributor on the subscription** (Stage 1), retrievable with a single credential-free call to the metadata service.
>
> So the chain is: **one todo pod → cluster-admin → every secret → the DB VM → the entire Azure subscription.**
>
> Every misconfiguration hands off to the next. Not one of them is 'critical' on a scanner's list. It's the *path* that's critical."

**The "so what":** *This is least privilege inverted. The container-escape risk is universal — you can never fully rule it out — so the control that matters is what the workload's identity can do AFTER a breach. Scope this ServiceAccount to nothing and a compromised pod is a contained incident. Leave it cluster-admin and it's game over for the platform.*

**Enterprise problem (Tom's #1 ask):** *Nobody spots one over-permissioned ServiceAccount in a sea of YAML across hundreds of workloads. That's exactly what posture tooling surfaces — "this internet-facing workload is one escape away from cluster-admin." Context and prioritisation: not a longer list of findings, the one path that ends you.*

---

## The irony worth stating (shows deliberate design, not ignorance)

> "To read this database directly, I had to be *on* the VM — it's private-network only — and I needed credentials. Both controls are correct. But I got the credentials by `sudo cat`-ing the backup script, which embeds them. So the database is locked at the front door and wide open at the side: auth and network controls are individually fine and collectively worthless, because the *backup* is public and the *app's identity* is cluster-admin. Security is a property of the path, not the component."

---

## What "done right" looks like here (contrast for the panel)

Not everything in this stage is broken — and saying so proves the breaks are intentional:

- ✅ Nodes in a **private subnet**
- ✅ DB creds via **Secret → env var**, never baked into the image (per spec)
- ✅ ACR pulls via **managed identity**, no registry credentials
- ❌ ServiceAccount = **cluster-admin** (the one deliberate break)

> "I did the identity and secrets handling properly everywhere it wasn't part of the brief. The cluster-admin binding is the one intentional break — which is the point: I know what least privilege looks like, and I can show you exactly the line of YAML that violates it."

---

## Challenges & adaptations

- **ClusterIP vs LoadBalancer confusion** — initially expected the app's own Service to get a public IP. It shouldn't: the app Service is internal (ClusterIP); the *ingress controller's* Service is the LoadBalancer that gets the Azure IP. Understanding that separation is the exposure model.
- **`mongosh` vs `mongo`** — the VM runs Mongo 4.4, which ships the legacy `mongo` shell, not modern `mongosh`. The outdated version shows up in the tooling, not just the CVE list.

---

## Likely follow-ups

- **"How would you fix the ServiceAccount?"** → Least privilege: a Role scoped to only the namespace and only the verbs the app needs (likely none cluster-wide). Never bind `cluster-admin` to a workload.
- **"How would you detect this in a real cluster?"** → Posture/KSPM flagging ClusterRoleBindings to `cluster-admin` on workload ServiceAccounts, prioritised by whether the workload is internet-exposed.
- **"Are K8s Secrets actually secret?"** → No — base64-encoded, not encrypted at rest by default. Enable encryption at rest / an external secrets store (Key Vault). Good honesty point.
- **"How does the app reach Mongo across subnets?"** → Same VNet; the private subnet routes to the DB VM on 27017, which the NSG allows only from that subnet.

# Stage 3 — Architecture Deep-Dive (addendum)
### The "do you actually understand what you built" questions

*Append to the Stage 3 notes. These are the architecture probes a technical panel uses to separate "ran the commands" from "understands the system."*

---

## COLD ANSWER 4 — "Walk me through the full request path to your app"

> "Trace a browser hitting `http://4.157.111.117/`:
>
> **1. Browser → internet.** No DNS involved — it's a raw IP, so the request goes straight to that address on port 80.
>
> **2. Azure Load Balancer.** That IP belongs to the Azure LB provisioned by the ingress controller's `LoadBalancer` Service. It receives at the cloud edge and forwards into the cluster.
>
> **3. nginx ingress controller pod.** The LB sends traffic here (via NodePort on the nodes). This is a reverse proxy running *inside* the cluster — the single front door.
>
> **4. Ingress rule evaluation.** nginx checks my Ingress resource: does this request match a rule? It does → route to the todo-app Service.
>
> **5. todo-app Service (ClusterIP).** nginx forwards to the app's internal Service address (`10.100.35.161:80`) — a stable internal endpoint that load-balances across pods.
>
> **6. kube-proxy → pod.** The Service picks one of the 2 healthy pods and forwards, translating port 80 → container port 3000.
>
> **7. Node app.** Receives the request, queries Mongo if needed, and the response travels back out the same chain."

**The compressed version:** *Internet → Azure LB → nginx controller → Ingress rule → ClusterIP Service → kube-proxy → pod.*

**Worth noting:** there are **two load-balancing layers** (Azure's, then the Service's) and **one routing layer** (the Ingress) between the user and my code.

---

## COLD ANSWER 5 — "Your Ingress has no `host` set. What does that match, and when would you need one?"

> "With no `host` field, the rule is a **catch-all** — it matches every request reaching the controller, regardless of the hostname it was sent to. `4.157.111.117`, `anything.example.com` pointed at that IP, `foo.bar` — all match, all route to todo-app.
>
> **That's correct here**, deliberately: I'm hitting a raw IP with no DNS, so there's no hostname to match on anyway.
>
> **You'd need `host` when you have multiple apps behind one ingress and one IP.** If `app1.company.com` and `app2.company.com` both resolve to the same load balancer, the controller reads the `Host:` header the browser sends and matches the right rule. That's **name-based virtual hosting** — one IP, one controller, many apps, split by hostname.
>
> So it's a deliberate simplification for a single-app demo, not an oversight."

**The "so what":** *Knowing why the simplification is safe here — and exactly what would change in production — is the difference between copying a manifest and understanding routing.*

---

## COLD ANSWER 6 — "If I deleted your pods right now, would you lose data?"

> "**No — nothing.** Kubernetes would immediately recreate them (the Deployment's job is to keep 2 running), and every todo would still be there.
>
> **Why:** the pods are **stateless**. They hold no data — they're just running copies of my app code. The actual state lives in **MongoDB on the VM**, a separate component with its own persistent disk. The pods *talk to* the database; they don't *contain* it. Killing a pod is like closing a browser tab that's viewing a database — the database doesn't care."

### What this reveals about the architecture

- **The pods are cattle; the database is a pet.** Pods can be destroyed and recreated freely — that's *why* Kubernetes can scale, self-heal, and roll out updates: it assumes workloads are disposable.
- **State is the hard part of any system.** Stateless things are easy — scale them, kill them, replace them. Stateful things need care, persistence, and backups. This is exactly *why* the Stage 2 backup exists.

### The security "so what" — the strongest version of this point

> "The pods are stateless and disposable — I can kill them and lose nothing. That's the point of Kubernetes. But it means **all the value concentrates in the database and its backups**.
>
> So when I think about what an attacker actually wants, it's never the pods — **it's the state**.
>
> That reframes the priorities entirely: the cluster-admin misconfig matters because it's a *path to the data*. The public backup bucket matters because it **is** the data. **Follow the state, and you find what actually needs protecting.**"

**Enterprise angle:** *"Follow the state" is how you cut through a hundred findings to the handful that matter. Most tooling treats every resource as equally important. The workloads are replaceable; the data isn't — so risk should be ranked by proximity to the state, not by CVSS score on a disposable pod.*

---

## Why these three matter together

They're the panel's way of checking whether I understand the **system** or just ran the **commands**:

- **Q4 (request path)** → do I understand the networking layers?
- **Q5 (no host)** → do I know which of my choices are simplifications, and why?
- **Q6 (delete the pods)** → do I understand where value and risk actually live?

The Q6 answer is the one that ladders back to the whole security narrative: *follow the state.*
