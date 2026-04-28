# Compliance posture

> Sibling docs: [`PRIVACY.md`](../PRIVACY.md) · [`SECURITY.md`](../SECURITY.md) · [`THREAT_MODEL.md`](THREAT_MODEL.md) · [`legal/DPA-template.md`](legal/DPA-template.md)

## TL;DR

OpenVoiceFlow is a free, MIT-licensed, single-developer macOS dictation tool. It is a **self-managed personal-productivity utility**, not a SaaS. It is **not certified** for any compliance regime (SOC 2, ISO 27001, HIPAA, FedRAMP, PCI-DSS, etc.) and is **not designed for regulated environments**. It uses a **bring-your-own-key (BYOK)** model: when you pick a cloud LLM backend, *you* contract directly with that provider — OpenVoiceFlow is not a controller, processor, or sub-processor on your behalf. If you need a vendor with auditable controls and a real contractual layer, this is not that vendor.

---

## What we are NOT

| Regime | What it would mean | Why we don't qualify |
|---|---|---|
| **SOC 2 Type I / Type II** | An independent auditor attests that the vendor's controls are designed (Type I) and operated over time (Type II) against the AICPA Trust Services Criteria. | No vendor-side service exists, no controls program, no auditor engagement. |
| **ISO 27001 / 27701** | Certified information-security (27001) or privacy (27701) management system, with documented risk treatment, internal audits, and management review. | No ISMS, no certification body engagement, no defined scope statement. |
| **HIPAA-covered** | The vendor has signed a Business Associate Agreement (BAA) and meets the HIPAA Security and Privacy Rules for handling Protected Health Information (PHI). | We do not sign BAAs. The project earns $0 and cannot take on PHI liability. |
| **FedRAMP** | Authorization to operate within US federal cloud environments at Low / Moderate / High impact levels. | Not a hosted service; no ATO; no agency sponsor. |
| **PCI-DSS** | Controls for handling cardholder data. | We never see, store, or transmit cardholder data — and you should not dictate it into any LLM. |
| **GDPR controller / processor (on your behalf)** | A formal Article 28 processor relationship with a DPA, sub-processor list, and breach-notification commitments. | We hold no personal data on a server (there is no server). Your dictated data flows from your Mac to the LLM provider you chose; we are not in that path. |

---

## What we ARE

- **Open source, MIT-licensed.** Every line is auditable on GitHub: <https://github.com/shimoverse/openvoiceflow>.
- **Transparent.** Build scripts, install scripts, and CI workflows are in-tree. There is no hidden server-side component.
- **BYOK.** You bring your own key for whichever LLM provider you choose; the contract is between you and that provider.
- **Local-first transcription.** Audio is processed on-device by `whisper.cpp`. The audio never leaves your Mac.
- **User-owned data, on user-owned hardware.** Profile, dictionary, snippets, optional logs — all live under `~/.openvoiceflow/`. We don't sync, mirror, back up, or telemeter.

---

## GDPR considerations (EU users)

When you choose a cloud LLM backend (Gemini, OpenAI, Anthropic, Groq), the cleaned transcripts you send for cleanup become **personal data being processed by that provider** under their terms.

- **You are the data controller.** You decide why and how the data is processed.
- **Your chosen LLM provider is the data processor.** They run the inference and retain (or don't retain) data per their terms.
- **OpenVoiceFlow is neither.** We hand the request from your Mac to the API you configured and stay out of the path.

The lawful basis for processing is yours to determine. The three most likely to apply for personal/professional dictation:

- **Consent (Art. 6(1)(a))** — you knowingly typed the key in and clicked through onboarding.
- **Legitimate interest (Art. 6(1)(f))** — productivity tooling for your own work.
- **Contract (Art. 6(1)(b))** — performance of a contract you are party to (e.g., dictating a customer email).

If you need a Data Processing Addendum, sign one **with the LLM provider you chose**:

- Anthropic: <https://www.anthropic.com/legal/dpa>
- OpenAI: <https://openai.com/policies/data-processing-addendum>
- Google AI / Gemini API: <https://cloud.google.com/terms/data-processing-addendum>
- Groq: contact Groq for their current DPA.

If your situation makes any external processor unacceptable (legal, contractual, or policy reasons), use the **Ollama** backend or the **`none`** backend — both keep transcripts on the Mac. That is the only way to take *every* third party out of the path.

---

## HIPAA

**Do not use OpenVoiceFlow for any workflow that involves Protected Health Information unless** *both* of the following are true:

1. Your chosen LLM provider offers a HIPAA-eligible service tier, **and**
2. **You** have signed a Business Associate Agreement (BAA) with that provider.

Provider state at time of writing (verify with the provider before relying on this):

- **Anthropic** — enterprise tiers offer BAAs.
- **OpenAI** — enterprise tiers offer BAAs.
- **Google AI / Gemini API** — generally not BAA-covered for the consumer-grade Gemini API; Google Cloud Vertex AI is a different product.
- **Groq** — does not offer BAAs at the time of writing.
- **Ollama** — runs entirely on your Mac; no third party is in the path. Whether that satisfies your covered-entity assessment is a question for your compliance officer.

**OpenVoiceFlow does not sign BAAs.** The project is one developer, not a Business Associate.

---

## For corporate IT teams considering deployment

OpenVoiceFlow can work for low-stakes BYOK-tolerant teams. It is **not** a managed-vendor solution. Before rolling it out:

- **Decide whether the LLM-backend data flow is acceptable** under your DLP, data-residency, and acceptable-use policies. Different employees may pick different backends; the deployment is only as restrictive as the locked configuration.
- **Consider Ollama-only deployments** to keep transcripts on-device. This eliminates the cloud LLM as a sub-processor entirely.
- **Pre-stage `whisper-cpp` and the model file** via your MDM (Jamf, Mosyle) or a `brew bundle` so the bootstrap doesn't pull from external networks at first launch on a managed Mac.
- **Ship a managed config** by writing `~/.openvoiceflow/config.json` during provisioning. For lock-down, pin: `update_check: false`, `log_transcripts: false`, `auto_learn: false`, `llm_backend: "ollama"`. (See [`PRIVACY.md`](../PRIVACY.md) for the full config-key list.)
- **Note that v0.3 DMGs are unsigned.** First launch requires a Gatekeeper override per machine. MDM-aware orgs may want to wrap the install differently (re-sign with an internal Developer ID, ship as a signed `.pkg`, or build from source in-house).
- **There is no enterprise key-management story.** Each employee's API keys land in their own `~/.openvoiceflow/config.json` (mode 600). No central rotation, no SSO, no SCIM.

If any of the above is a deal-breaker, OpenVoiceFlow is not the right fit and you should choose a vendor with a real procurement contract.

---

## Audit trail / observability

There is **no central server**, so there is **nothing to audit centrally**. We cannot produce per-user activity logs, access reports, or admin audit trails because we don't see any of it.

Per-machine, when `log_transcripts: true` is set by the user, daily transcript logs are written to `~/.openvoiceflow/logs/YYYY-MM-DD.{md,jsonl}` as **local plaintext files (mode 600)**. They live on the user's Mac and can be inspected, exported, or deleted by the user (or by an admin with filesystem access on a managed Mac).

---

## Records / retention

We do not have a retention policy because we do not retain anything centrally. On-device:

- Configuration, profile, dictionary, snippets, stats, and logs **exist until the user deletes them**.
- We do not sync, mirror, or back up any of these files. You delete a file, it's gone.
- Each LLM provider has its own retention policy for the transcripts you send through them. Read theirs.

---

## Changes

This document is versioned with the code. Material changes are surfaced under the relevant release in [`CHANGELOG.md`](../CHANGELOG.md). The sibling [`PRIVACY.md`](../PRIVACY.md) carries the matching privacy-side commitments.

---

## Cross-references

- [`PRIVACY.md`](../PRIVACY.md) — what data exists, where it goes, what you can opt out of.
- [`SECURITY.md`](../SECURITY.md) — supported versions, vulnerability reporting, scope.
- [`THREAT_MODEL.md`](THREAT_MODEL.md) — what we defend against and what we explicitly don't.
- [`legal/DPA-template.md`](legal/DPA-template.md) — a fill-in-the-blanks template for documenting an OpenVoiceFlow deployment in your own data-flow inventory.
