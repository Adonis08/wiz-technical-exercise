# Wiz Technical Exercise

## What this project is

A two-tier web app deployed on Azure, built in two phases:

1. **Phase 1 — Insecure by design.** Stand up the app with intentional
   misconfigurations (the kind Wiz's CSPM/CWPP would flag: public storage,
   over-permissioned identities, open network security groups, missing pod
   security standards, no image scanning, secrets in plaintext, etc.).
2. **Phase 2 — Remediate.** Use Microsoft Defender for Cloud findings (and
   manual review) to identify and fix those misconfigurations, then show the
   before/after posture.

The end goal is not just a working app — it's being able to explain, to a
Wiz interview panel, *what* was misconfigured, *why* it's a real-world risk,
and *how* the fix works, at the level of someone who did the work personally
rather than copy-pasted it.

## Tech stack

- **Cloud:** Azure
- **IaC:** Terraform
- **Compute:** AKS (Azure Kubernetes Service)
- **Containers:** Docker
- **CI/CD:** GitHub Actions
- **Security posture/scanning:** Microsoft Defender for Cloud

## Working style — read this before doing any work

I am a **novice with Terraform and kubectl**. This project is as much a
learning exercise as a build exercise. When acting as my assistant here:

- **Explain every step simply before/while doing it.** Assume I don't know
  Terraform or kubectl syntax or concepts yet. Don't just run commands —
  say what the command does, why this step is needed, and what the
  resource/block/flag means in plain language.
- **Go slow, in small stages.** Don't dump a whole Terraform module or a
  full k8s manifest set at once without walking through the pieces.
- **Quiz me after each stage.** After we finish a meaningful chunk of work
  (e.g., "provisioned the VNet + NSGs", "deployed AKS cluster", "introduced
  the intentional misconfig", "remediated finding X"), stop and ask me a
  few questions to check I can explain it back — as if I were answering an
  interviewer. Don't just move on to the next stage automatically.
- **Prioritize interview-readiness over speed.** If there's a choice between
  the fastest way to get something working and the way that builds my
  understanding, prefer the latter and say so.
- **Call out the security "why."** For every intentional misconfiguration
  and every fix, explicitly connect it to the real-world risk (e.g., "a
  public storage account like this is how X breach happened" / "this NSG
  rule is CIS Azure benchmark control Y").

## Notes for future sessions

- Repo was empty at project start (2026-07-13) — no existing conventions to
  follow yet. As structure emerges (Terraform module layout, manifest
  locations, CI workflow files), keep this file's high-level intent but
  don't duplicate details that are better derived by reading the code.
- GitHub remote: `Adonis08/wiz-technical-exercise`.
