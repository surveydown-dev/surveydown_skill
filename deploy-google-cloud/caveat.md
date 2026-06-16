# Google Cloud Run — billing caveat (read once before deploying)

**A payment method (bank card) must be linked to your Google Cloud billing
account — Cloud Run won't deploy without one.** Link it first:
<https://console.cloud.google.com/billing>

## Usually free
A survey **scales to zero** when idle (no sessions → no compute → $0), and
low-traffic use stays inside the monthly always-free tier (2M requests, 360k
vCPU-seconds, 180k GiB-seconds). So a typical survey costs ≈ $0.

## When it can cost money
1. **Always-on** — `min-instances ≥ 1` keeps a container running 24/7.
2. **Heavy traffic** — usage beyond the free tier is billed per use.
3. **Image storage** — Artifact Registry storage past the 0.5 GB free limit (the
   surveydown image is large, so old versions can add a few cents/month).

(Separately, a custom-domain load balancer is ~$18/mo — optional.)

## Protect yourself: set a $1 budget alert
It only emails you — it does not cap or charge anything:
<https://console.cloud.google.com/billing/budgets>
