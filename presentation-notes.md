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

---

# Stage 4 — Presentation Notes
### CI/CD auth, VCS security controls, and the IaC deploy pipeline

---

## What we built

**4a — Secure CI/CD auth + repo security controls:**
- `github-oidc.tf` — an Azure AD app registration + service principal for GitHub Actions, with **two federated identity credentials** (one trusting `main`-branch pushes, one trusting pull requests) instead of any stored client secret
- Three scoped role assignments for that identity: **Contributor** on `wiz-rg` only (not subscription-wide — direct contrast with Stage 1), **AcrPush** on the registry, and **AKS Cluster User Role** on the cluster
- Repo made **public**, then all four VCS security controls enabled: **branch protection** on `main` (1 required approval, admins enforced, force-push/deletion blocked), **secret scanning**, **push protection**, and **Dependabot alerts**

**4b — The IaC deploy pipeline + remote state:**
- `.github/workflows/iac-deploy.yml` — Checkov scans the Terraform on every push/PR (`soft_fail: true`, findings uploaded as SARIF to the Security tab), then a Terraform job that authenticates via OIDC, plans on PRs (posting the plan as a PR comment), and applies on pushes to `main` using the exact saved plan file
- Migrated Terraform state from local-on-laptop to a **remote Azure Storage backend** (`wiz-tfstate-rg` / `wiztfstateadb7f2` / container `tfstate`) — required because a GitHub-hosted runner has no access to a state file sitting on my Mac
- That state storage account authenticates via **Entra ID only** (`use_azuread_auth = true`, `shared_access_key_enabled = false`) — no storage account key exists to steal, same philosophy as the GitHub OIDC piece

**Status: 4a's Terraform is written and validated but not yet applied** — blocked on a tenant permission issue (see below), currently being escalated. Everything else (repo controls, workflow file, state migration) is live.

---

## COLD ANSWER 1 — Why does OIDC beat a stored service-principal secret?

> "A traditional service principal secret is a long-lived password sitting in GitHub Secrets. It doesn't expire on its own, it works from anywhere — not just my CI — and if it leaks, whoever has it can authenticate as that identity until someone manually rotates it.
>
> With OIDC, there's no stored credential at all. GitHub mints a short-lived, signed token for each individual workflow run, carrying claims like 'this is repo X, branch main, run Y.' Azure AD has a federated credential that says 'trust GitHub's tokens, but only if the subject claim matches this exact string.' Azure verifies the signature and the claims, and if they match, issues a short-lived Azure token back — good for that one job, then gone.
>
> I went further than a single trust rule: there are **two separate federated credentials** — one for pushes to `main`, one for pull requests — so a workflow run on a fork or a random branch can't obtain a token at all, only runs that match those exact conditions can."

**The "so what":** *There's nothing sitting in GitHub Secrets to leak, log, or paste into the wrong Slack channel — the credential doesn't exist between workflow runs, only for the seconds each run needs it.*

---

## COLD ANSWER 2 — Why make the repo public, and wasn't that a risk?

> "Branch protection and secret scanning/push protection are gated behind GitHub Pro for private repos on a free plan — the API told me that outright when I checked. My first instinct wasn't 'flip it public and move on,' though — it was to check whether that was actually safe.
>
> I searched the full git history — every commit, not just the current working tree — for `terraform.tfvars`, any `.tfstate` file, SSH keys, and the literal database password string. All clean. That distinction matters: `.gitignore` only protects what you commit *going forward*. A file committed once and gitignored later is still sitting in every clone, forever. Since nothing sensitive had ever touched history, going public didn't expose anything real, and it got me the complete set of VCS controls for free instead of a partial set behind a paywall."

**The "so what":** *`.gitignore` is not retroactive. The diligence that matters is checking history, not just the current file tree — and doing that check before flipping visibility, not after.*

---

## COLD ANSWER 3 — Why do you need a remote state backend at all?

> "Terraform state is the map of what it thinks exists in the cloud. Locally, that map was a file on my laptop. A GitHub Actions runner is a brand-new, empty container for every single run — it has no access to my laptop's filesystem. If CI ran `terraform apply` against local state, it would see no prior state, assume nothing exists, and try to create every resource in `wiz-rg` a second time — colliding with everything already there.
>
> A remote backend — an Azure Storage blob — fixes that: my laptop and every CI run read and write the exact same state, over the network, with locking so two applies can't corrupt it by running at once."

**The "so what":** *State isn't a side effect of running Terraform — it's the shared source of truth that makes 'my laptop' and 'CI' the same deployment instead of two competing ones.*

---

## COLD ANSWER 4 — How did you lock down the state storage account, and why is it publicly reachable at all?

> "It's the deliberate opposite of Stage 2's public backup container, and the contrast is the point: 'reachable over the internet' and 'anonymously accessible' are two different axes. Stage 2 collapsed them into one misconfig on purpose. Here I needed the first without the second — GitHub-hosted runners aren't inside my VNet, so the storage account has to accept public network traffic, or CI can't reach it at all. But `allow_blob_public_access` is off, and critically, `allow_shared_key_access` is off too — the storage account keys, a bearer-secret-like credential, are disabled entirely. The only way in, for me or for CI, is an Azure AD identity with an explicit `Storage Blob Data Contributor` role assignment. I also turned on blob versioning and 30-day soft delete, so a bad write or an accidental delete is recoverable, not catastrophic."

**The "so what":** *Public network reachability and anonymous public access are not the same setting. Stage 2 shows what happens when you conflate them; this shows what it looks like to need one without the other.*

---

## COLD ANSWER 5 — `soft_fail: true` on Checkov — doesn't that defeat the point of scanning?

> "For this exercise, yes, deliberately — and I documented that directly in the workflow file, not just in my head. This repo's Terraform *contains* intentional misconfigurations as its entire premise. If Checkov hard-failed the build on them, this pipeline could never deploy the infrastructure the exercise exists to build and later remediate.
>
> The findings aren't suppressed, though — they still run, still get uploaded as SARIF, still show up in the Security tab. `soft_fail` only controls whether they *block* the merge or deploy, not whether they're visible. In a real production pipeline, I would not set this — I'd hard-fail on CRITICAL/HIGH findings, because the whole value of shifting scanning left is stopping bad config before it reaches the cloud, not just logging it afterward."

**The "so what":** *Scanning that can't block anything is just a dashboard. `soft_fail` is the right call for a lab that studies misconfigurations on purpose — and the wrong default everywhere else.*

---

## COLD ANSWER 6 — Walk me through the `oidc_issuer_enabled` drift you found

> "`terraform plan` kept showing the AKS cluster wanting to flip `oidc_issuer_enabled` from `true` to unset, even though my own `aks.tf` never touched that attribute. Rather than guess, I checked the Azure Activity Log for the cluster — there's exactly one `Create or Update Managed Cluster` event in its entire history, the original creation itself. No later manual `az aks update` call. So this wasn't someone toggling a setting behind my back.
>
> Cross-referencing Microsoft's own AKS docs confirmed it: OIDC issuer is enabled by default on new AKS Standard clusters running Kubernetes 1.34 or later. My cluster came up on 1.35.6 — because `aks.tf` deliberately leaves `kubernetes_version` unset to track whatever's current, a choice I'd made back in Stage 3a. Azure's own default just filled in a value my config never specified.
>
> The decision to codify rather than revert wasn't really a style choice, either — Microsoft's docs state plainly that **you can't disable the OIDC issuer once it's enabled**. Trying to revert it would have meant `terraform apply` attempting something Azure's API would simply reject, likely failing mid-pipeline in CI. So I added `oidc_issuer_enabled = true` explicitly, matching config to reality."

**The "so what":** *Don't assume drift means someone touched something — check the activity log and the platform's actual default behavior before deciding whether to fight it or codify it. Here, one of those two options wasn't even possible.*

---

## COLD ANSWER 7 — You hit a permission error applying the OIDC Terraform. Walk me through what happened.

> "`terraform apply` failed creating the Azure AD application with `403 Authorization_RequestDenied: Insufficient privileges`. Rather than assume it was a config bug, I checked the tenant directly via Microsoft Graph: the tenant-wide policy `allowedToCreateApps` is set to `false`, and my account holds **zero** directory roles — not active, not even PIM-eligible. I confirmed the same thing in the Entra portal itself: My Roles showed nothing active or eligible, and the 'Users can register applications' setting was greyed out, meaning I can't self-service my way around it.
>
> That's a real, legitimate enterprise control, not a bug — letting any authenticated user self-register Azure AD applications is a genuine shadow-IT and attack-surface risk, and a lot of well-run tenants gate it behind an admin role for exactly that reason. This also looks like a provisioned training/lab tenant (`odl_user_NNNNN@...` is the standard naming pattern for those), which typically has no self-service admin path by design.
>
> Rather than work around it insecurely, I escalated properly: emailed the lab's support team with the exact error, the tenant policy I'd confirmed, and the specific minimum role (`Application Developer`) that would unblock me — and looped in the hiring manager for visibility given the timeline. Everything else in the pipeline that doesn't depend on this one resource — repo security controls, the workflow file, state migration — is unaffected and already live."

**The "so what":** *Hitting an access wall and correctly diagnosing it as "this requires an admin, not a workaround" is itself the security-minded response — the alternative (finding a way around `allowedToCreateApps=false`) would be demonstrating exactly the instinct that control exists to prevent.*

---

## THE ENTERPRISE PROBLEM

> "Everything in Stage 4 is really one theme: **make the deploy path attributable and revocable, end to end.** No stored Azure credential in GitHub. No stored registry password. No storage account key for state. Every identity involved — GitHub Actions, me — authenticates as *itself*, momentarily, via a token that expires, rather than a shared secret that doesn't.
>
> And the permission wall I hit fits the same theme from the other direction: a well-run tenant doesn't let arbitrary users mint new Azure AD identities either. The same instinct that says 'don't leave a stored secret lying around' also says 'don't let anyone self-register an application that can hold role assignments.' Both are access control decisions about who gets to create new identity, not just who gets to use existing identity."

---

## Challenges & adaptations

- **`gh api` field syntax under zsh.** `-f security_and_analysis[secret_scanning][status]=enabled` was interpreted as a glob by zsh and silently expanded to nothing. Fix: single-quote the whole `-f` argument.
- **`az storage account check-name`, not `check-name-availability`.** Wrong command name from memory; corrected against the actual CLI help output rather than guessing twice.
- **`--public-network-access`, not `--public-network-access-enabled`.** Same lesson — checked `az storage account create --help` rather than assume a flag name.
- **RBAC propagation delay.** Role assignments take up to ~60 seconds to actually take effect. Creating the `tfstate` container immediately after granting myself `Storage Blob Data Contributor` needed a short retry loop rather than a fixed sleep.
- **`terraform init -migrate-state` needs `-force-copy` for non-interactive use.** The default flow prompts for a `yes` confirmation, which has nothing to answer it in an automated shell — `-force-copy` is the non-interactive equivalent.
- **The AKS OIDC drift and the app-registration wall** — both above — are really the same discipline: when Terraform (or Azure) does something you didn't ask for, check the activity log / API / docs before deciding whether it's a bug, an unchangeable platform default, or a policy that needs a human to fix.

---

## Panel-proofing: the likely follow-ups

- **"Why two federated credentials instead of one broad trust rule?"** → Least privilege applied to trust conditions, not just role assignments — this was the design before the pivot below; the principle still applies to how I scoped the fallback's role assignments.
- **"Isn't `wiz-tfstate-rg` a single point of failure for all your infrastructure?"** → It's a deliberately separate resource group precisely so its lifecycle doesn't couple to `wiz-rg` — tearing down the app infrastructure can never take the state store down with it, and versioning + soft delete protect against a bad write.

---

## Stage 4 — Resolution: OIDC blocked, pivoted to a provided service principal secret

The lab support escalation came back with a decision, not just an explanation: use a pre-provisioned service principal's client secret instead of OIDC, because self-service Azure AD app-registration creation is restricted in this tenant for a specific, real reason — not just "policy says no."

## COLD ANSWER — Why does restricting app-registration creation matter, and why pivot instead of pushing back?

> "Support's exact words were that OIDC app registrations 'create Enterprise Apps that have privilege escalation paths.' That's not vague caution — it maps to a documented Entra ID risk: anyone who can create or own an app registration can add new credentials to it, or consent to Microsoft Graph permissions on its behalf. If that app later gets a privileged role assignment, whoever controls the app registration effectively controls that privilege too. Letting any developer self-register apps means any developer can eventually mint themselves a path to whatever that app can reach. Gating app-registration creation behind an admin role is a real, if inconvenient, mitigation for a real escalation path — the same category of finding as everything else in this project, just one level up the stack, in identity governance rather than infrastructure config.
>
> So I didn't try to work around it. I took the guidance, used the pre-provisioned service principal support gave me, and kept every other control from the original design intact: the same three scoped role assignments (Contributor on just `wiz-rg`, AcrPush on just the registry, AKS Cluster User on just the cluster), just authenticating with a client secret instead of a federated token."

**The "so what":** *A restriction that costs you convenience isn't automatically wrong — sometimes the friction is the point. The right response to hitting a well-reasoned security control is to work within it, not engineer around it.*

## What actually changed

- `github-oidc.tf` → renamed `github-ci-auth.tf`. The `azuread_application`, `azuread_service_principal`, and both federated identity credential resources are gone — replaced with a single `data "azuread_service_principal"` lookup against the provided app ID. The three role assignments are byte-for-byte the same scoping as the original design.
- The workflow's `azure/login` step and the Terraform steps' `ARM_*` env vars switched from OIDC (`ARM_USE_OIDC`) to client-secret auth (`ARM_CLIENT_SECRET`).
- `id-token: write` removed from the workflow's `permissions` block entirely — nothing mints an OIDC token anymore, so the permission is gone rather than left granted-but-unused.
- Secret handling: the client secret went straight into `gh secret set AZURE_CLIENT_SECRET` via stdin (never as a `--body` CLI argument, so it never touched shell history), and is referenced in the workflow only as `${{ secrets.AZURE_CLIENT_SECRET }}` — it does not appear in any file this repo tracks.

## How I'd do this better in a real production environment (the talking point Tom explicitly invited)

> "I wouldn't conclude that OIDC is wrong and stored secrets are the answer — I'd conclude that *unrestricted self-service* app-registration creation is the actual problem, and OIDC is still the right end-state. In a real org, I'd want a platform or identity team to own a governed path for creating federated app registrations — gated behind an admin role that's PIM-eligible (activated just-in-time, not standing), with the federated credential's trust conditions reviewed the same way you'd review a firewall rule change. That gets you OIDC's actual benefit — no long-lived credential in CI — without every developer being able to self-register an app that could become a privilege-escalation path. The tenant I'm in chose the blunter mitigation — block it outright, fall back to a managed secret — which is a completely reasonable call for a shared training tenant with hundreds of transient users, but not the end state I'd design for a real production org with a stable identity team."

**The "so what":** *The lab's restriction and a mature production setup are solving the same problem at different levels of maturity — one blocks the risky action outright, the other governs who can take it and under what conditions. Knowing which one you're looking at, and why, is the actual signal of understanding the control rather than just following it.*

---

# Stage 5 — Presentation Notes
### Microsoft Defender for Cloud — enablement, gaps, and first real findings

---

## What we built

- Enabled Defender for Cloud at **Standard tier** for exactly the plans matching what's actually deployed: **VirtualMachines** (the DB VM), **StorageAccounts** (both storage accounts, with Sensitive Data Discovery auto-included), **Containers** (AKS + ACR — the modern consolidated plan; the older separate `KubernetesService`/`ContainerRegistry` plan names stay `Free` on purpose), **Arm** (control-plane/IAM activity), and **CloudPosture** — the plan that does attack-path/context analysis across chained findings, i.e. the actual tooling behind Stage 1's "three mediums chain into a critical" story
- Found and fixed a subscription-level gap: the **"ASC Default" / Microsoft cloud security benchmark Azure Policy initiative** wasn't assigned at all, which meant almost every Defender recommendation was stuck reporting `NotApplicable`
- Enabled the **AKS Azure Policy Add-on** and the **Defender for Containers cluster sensor** via Terraform (`aks.tf`), pointed at a purpose-created Log Analytics workspace instead of Azure's auto-generated default one
- Triggered an on-demand Azure Policy compliance scan and pulled 37 real `NonCompliant` findings directly from the policy layer, faster than waiting for Defender's own recommendation UI to sync

---

## COLD ANSWER 1 — Why were almost all your findings `NotApplicable` at first?

> "Enabling the Defender pricing plans turns on the *capability* to generate recommendations — it doesn't by itself assign the Azure Policy initiative that actually drives most of them. I checked `az security assessment list` and saw 8 of 9 results stuck as `NotApplicable`, with the reason spelled out directly: `Missing assignment to ASC Default initiative`.
>
> This is a genuinely different permission story from the GitHub OIDC wall in Stage 4. That one was an Entra ID *directory* role gap — I had nothing. This one is Azure *RBAC* — and checking my own role assignments showed I'm actually **Owner** at the subscription scope. Two completely separate permission systems: Owner controls Azure resources, and app registrations are a directory action Owner has zero say over. Because I had the right kind of permission this time, I could fix it myself — created the missing policy assignment against the built-in benchmark initiative, then triggered an on-demand compliance scan instead of waiting for Azure's ~24-hour default cycle."

**The "so what":** *"Insufficient privileges" isn't one failure mode — Azure RBAC and Entra ID directory roles are separate systems, and which one is blocking you determines whether you can self-serve the fix or need to escalate.*

---

## COLD ANSWER 2 — What did the real findings actually show?

> "Once the policy assignment was in place, 37 `NonCompliant` results came back, and I could map most of the ones that matter directly onto the misconfigurations I built on purpose:
>
> - **SSH open to `0.0.0.0/0`** → four separate policy checks converge on it: NSG port restriction, internet-facing-VM protection, management-port closure, and just-in-time access control.
> - **The public backup container** → a direct, exact hit: *'Storage account public access should be disallowed.'*
> - **No image scanning** — a gap I called out explicitly in my own project notes before ever running a scanner — → *'Azure registry container images should have vulnerabilities resolved'* and *'Container registries should not allow unrestricted network access,'* both flagged on the ACR.
>
> What's more interesting is what *didn't* show up yet: the VM's subscription-wide Contributor identity and the AKS cluster-admin binding. Not because they're subtle — because the tooling needed to see them wasn't deployed. *'Azure Policy Add-on for Kubernetes should be installed'* was itself `NonCompliant` — until that add-on runs inside the cluster, nothing can evaluate in-cluster RBAC objects at all."

**The "so what":** *A partially-configured security tool doesn't fail loudly — it just quietly misses your worst findings. The absence of a capability is itself a finding, and it's usually more dangerous than any single misconfiguration it's failing to catch.*

---

## COLD ANSWER 3 — Walk me through enabling the AKS Policy Add-on and Defender profile.

> "I did this in Terraform, not a raw `az aks update` — after the `oidc_issuer_enabled` drift earlier in this project, I wasn't going to reintroduce the exact same problem by making an out-of-band change to a Terraform-managed cluster. That meant adding a Log Analytics workspace (Defender for Containers needs somewhere to send its findings) and two new attributes on the `azurerm_kubernetes_cluster` resource: `azure_policy_enabled = true` and a `microsoft_defender` block pointing at that workspace.
>
> Applying it surfaced something I hadn't expected: a `409 Conflict` — *'there's an in-progress update managed cluster operation.'* Rather than blindly retry, I checked the activity log. The caller wasn't me — it was the system-assigned identity behind the policy assignment I'd created earlier, which had already started auto-remediating the cluster on its own, via a `DeployIfNotExists` policy effect, racing my own apply. Checking `az aks show` confirmed the Defender profile was already live, pointed at Azure's own auto-created `DefaultWorkspace-...` — Defender for Cloud had auto-provisioned it the moment I enabled the `Containers` plan, before I'd written a line of Terraform for it.
>
> I waited for that operation to clear, then reapplied. The result is arguably better than if there'd been no conflict at all: Terraform now explicitly owns this configuration, pointed at a workspace I named and put in `wiz-rg` — not a hidden auto-generated one Azure quietly manages in a resource group I didn't create."

**The "so what":** *Auto-provisioning isn't a bug to route around — it's a signal that a control plane is already doing part of the job for you. The fix isn't fighting it; it's making the eventual state explicit and Terraform-owned so it's not an invisible dependency on Azure's defaults.*

---

## THE ENTERPRISE PROBLEM

> "This stage is the direct payoff of Stage 1's thesis. A CSPM tool isn't valuable because it finds things — it's valuable because it finds the *chain*. Right now, the raw findings show SSH exposure and public storage clearly. They don't yet show the Contributor-identity-to-subscription-takeover path or the cluster-admin-binding blast radius, because CloudPosture's deeper attack-path analysis needs more time and the in-cluster tooling needs to finish reporting.
>
> That gap is itself the enterprise lesson: turning on Defender for Cloud is not a single action with an instant result. It's a rollout with prerequisites (policy assignment), auto-provisioning races (the AKS conflict), and staged capability (add-on before object-level findings). A large org that assumes 'we enabled Defender for Cloud' means 'we have coverage' on day one is making the same mistake as assuming a scanner with `soft_fail: true` set is providing security — the capability existing and the capability having actually run to completion are different facts."

---

## Challenges & adaptations

- **Discovering the missing ASC Default assignment.** Traced from `NotApplicable` status codes down to their `cause`/`description` fields rather than treating an empty-looking recommendations list as "nothing to find yet."
- **Choosing on-demand policy compliance state over Defender's own assessment API for speed.** `az policy state trigger-scan` + `az policy state list` surfaced real, resource-mapped results faster than waiting on Defender's own recommendation-sync cycle, which lags behind raw policy evaluation.
- **Resolving 45 policy definition GUIDs to human-readable names.** Batched with a parallel lookup rather than 45 sequential CLI calls (the sequential version timed out) — a small but real lesson in not assuming a loop of API calls will finish inside a reasonable window.
- **The AKS `409 Conflict` mid-apply.** Diagnosed via the activity log rather than assumed to be a Terraform bug or retried blindly — the caller field made it clear this was Defender's own auto-provisioning, not an error.

---

## Panel-proofing: the likely follow-ups

- **"Why not enable every Defender plan?"** → Cost with zero matching coverage — plans like SQL, Cosmos DB, App Services, Key Vault have no corresponding resource in this project, so enabling them would just add spend for nothing to demonstrate.
- **"Isn't triggering an on-demand scan an artificial way to speed up a demo?"** → It's a real, documented Azure Policy feature (`trigger-scan`), not a workaround — the same lever an ops team would pull to get fast feedback after a policy change instead of waiting a day.

---

## COLD ANSWER 4 — Did the cluster-admin binding ever actually get detected?

> "Yes — but not by the default configuration, and that gap is the more important finding. The 'Microsoft cloud security benchmark' initiative — what Defender for Cloud assigns automatically — does **not** include the built-in policy that checks for cluster-admin overuse. I confirmed this directly against Microsoft's own built-in policy catalog: `'Kubernetes clusters should ensure that the cluster-admin role is only used where required'` exists, but as a **standalone** Kubernetes-category policy, not bundled into the default benchmark. Left at Defender's out-of-the-box configuration, this misconfiguration would never have surfaced, no matter how long I waited for scans to finish.
>
> I assigned that specific policy directly, and once the Azure Policy Add-on synced it into the cluster and Gatekeeper completed its first audit pass, it came back with **two** violations, not one:
>
> 1. `app-cluster-admin-binding` — the intentional misconfig from `k8s/02-serviceaccount-rbac.yaml`, exactly as designed.
> 2. `aks-cluster-admin-binding` — one I didn't write. Checking it directly showed it's an **AKS system-managed default** (labeled `addonmanager.kubernetes.io/mode: Reconcile`), binding `cluster-admin` to the `clusterAdmin` and `clusterUser` local Kubernetes users — the identities behind `az aks get-credentials`.
>
> That second one closes a loop from Stage 4a. When writing the GitHub Actions OIDC role assignments, I left a comment predicting that because this cluster has local accounts enabled and no Azure RBAC integration, the kubeconfig `az aks get-credentials` produces would carry full cluster-admin regardless of what role was granted to fetch it. That was a reasoned prediction at the time, based on how AKS local accounts work. This audit is the empirical confirmation — an actual policy engine flagging the actual binding, not me reasoning about what probably happens."

**The "so what":** *A security benchmark's default scope is a design decision, not a ceiling — "Defender for Cloud is enabled" and "Defender for Cloud is checking for the thing I actually care about" are different claims, and the gap between them is exactly where an intentional misconfiguration can hide in plain sight.*

---

## Panel-proofing: the likely follow-ups (continued)

- **"What's left before this stage is 'done'?"** → The identity over-privilege finding (Stage 1's Contributor grant) should surface via CloudPosture's attack-path/Entra Permissions Management analysis on a longer timeline; the cluster-admin binding is now confirmed end-to-end. Remaining work is remediation of everything found, not further detection.
- **"Why did you have to assign an extra policy manually instead of trusting the default set?"** → Because I checked rather than assumed — cross-referencing Microsoft's built-in policy catalog against what the benchmark initiative actually includes, rather than trusting that "enabled Defender for Cloud" implied "covers RBAC over-privilege."
- **"Is `aks-cluster-admin-binding` itself a misconfiguration you should fix?"** → It's an AKS platform default tied to local accounts being enabled, not something authored in this project's manifests — the real fix is disabling local accounts and requiring Azure AD + Azure RBAC for Kubernetes authorization, which removes this binding's relevance entirely rather than patching it directly.

---

## Stage 4 — The first real CI/CD run: three bugs, found and fixed one at a time

Merging the pipeline for the first time didn't work cleanly, and that's worth presenting honestly rather than glossing over — the debugging process is itself the demonstration of understanding, not a blemish on it.

## COLD ANSWER — Walk me through what actually broke on the first run, and how you found each issue.

> "Three separate, real failures, each diagnosed from the actual error rather than guessed at:
>
> **First: `azure/login@v2` rejected `client-secret` as an input.** I'd assumed that action accepted the same four fields — client ID, secret, tenant, subscription — that the Terraform provider does. It doesn't; its valid inputs are `creds` (a combined JSON blob) or the OIDC-style trio. Because the unrecognized input was silently ignored rather than hard-erroring, the action fell back to attempting an OIDC token fetch — the exact mechanism we'd just removed — and failed. The fix wasn't to reformat the input; it was to remove the step entirely, since nothing in this pipeline actually makes raw `az` CLI calls yet. Terraform's own `ARM_*` env vars authenticate it independently of this action.
>
> **Second: three repo variables from Stage 4b's documentation were never actually set.** `terraform init`'s backend-config flags came back completely empty — `resource_group_name=`, not even a placeholder. I'd written the instructions for `TF_STATE_RESOURCE_GROUP`/`STORAGE_ACCOUNT`/`CONTAINER` back when I first designed the backend, but never actually ran the commands, and it went unnoticed until the first real CI run needed them. Checking `gh variable list` confirmed two more were also missing (`SSH_PUBLIC_KEY`, `DB_APP_PASSWORD`) that Terraform needed to even construct a plan.
>
> **Third: the CI identity could authenticate, but couldn't read the state.** `403 AuthorizationPermissionMismatch` reading the state container. When I bootstrapped the state storage account outside Terraform, I granted `Storage Blob Data Contributor` to my own identity — the CI service principal's grant was part of the original Terraform-based bootstrap design we'd abandoned, and it never got carried over to the new plan.
>
> After each fix, I re-ran the actual pipeline rather than assuming the fix worked — added a `workflow_dispatch` trigger specifically so I could manually re-trigger without needing another commit each time, which let me iterate on the real failure instead of theorizing about it."

**The "so what":** *A CI/CD pipeline's real correctness is only provable by running it — three plausible-looking, individually-reasoned pieces of setup (an action's inputs, a documented-but-unexecuted variable list, a role assignment scoped to the wrong identity) all looked fine in isolation and all failed on contact with a real execution environment. Treat "written and reviewed" and "actually run" as different levels of confidence.*

## Final end-to-end proof

Every stage of the pipeline has now succeeded via a genuine GitHub-triggered event, not a manual dispatch: a real PR triggered Checkov + SARIF upload + `terraform plan` + a posted PR comment; merging that PR triggered a real push to `main` that ran `terraform apply` — `Apply complete! Resources: 0 added, 1 changed, 0 destroyed` (that one change being the same pre-existing, unrelated node-pool drift flagged earlier, not anything new).

## Panel-proofing: the likely follow-ups

- **"Why didn't you catch these before merging?"** → Some of it — the `azure/login` input mismatch — genuinely can't be caught by `terraform validate` or local testing, since it's a GitHub Actions marketplace action's runtime input validation, not Terraform's. The missing variables and role assignment were both catchable in principle; the lesson taken was to treat "documented" and "done" as different states and verify the latter directly, which is exactly what closed out the remaining two.
- **"Doesn't repeatedly loosening branch protection to merge your own PRs undermine having it?"** → Each time, it was a deliberate, minimal, fully-reversed exception — only the review-count requirement changed, only for the duration of one merge, restored immediately after and confirmed via API. The alternative was adding a second GitHub account purely to rubber-stamp solo work, which doesn't actually add review value either.
