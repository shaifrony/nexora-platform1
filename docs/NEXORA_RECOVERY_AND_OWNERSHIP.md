# NEXORA Recovery, Backup & Ownership Guide

Updated: 2026-11-15

## Purpose

NEXORA must remain recoverable if the owner's phone or computer is lost, stolen, damaged, or replaced. The Git repository is the source of truth for application code; Supabase is the intended source of truth for live application data once a hosted environment is approved and configured. A ChatGPT conversation or a single device must never be the only copy of project decisions or work.

## Current verified position

- Development code is stored in the GitHub repository `shaifrony/nexora-platform1`, on `nexora-development`.
- The latest verified Development CI run at this guide's creation was successful: run #43662876833, commit `9280dcabebf237391de03feadf8934eb852ce074`.
- `main` is a separate branch. Development work must not be pushed to `main` without explicit approval.
- The repository currently reports public visibility. Treat all committed source as publicly readable. Never commit passwords, API secrets, service-role keys, private customer data, OTPs, recovery codes, or production environment files. If a secret is ever committed, rotate/revoke it; deleting the visible line alone is insufficient.
- Hosted Supabase backup configuration, live database restore testing, and production deployment are not confirmed complete. Do not imply that live customer data is backed up until those steps are configured and verified.

## What survives device loss

| Asset | Where it is held | Recovery condition |
|---|---|---|
| Application source and commit history | GitHub repository | Owner can recover GitHub account |
| Project decisions and architecture | Versioned repository docs | Keep tracker/design docs committed |
| Live users, orders, messages and other records | Supabase project, once hosted | Supabase account access plus configured backups |
| Uploaded images/files | Supabase Storage, once hosted | Storage backup/export plan required |
| Domain registration | Registrar account, when purchased | Registrar account and recovery email |
| Deployment configuration | Vercel project, when configured | Vercel account and environment configuration |
| Secrets and API credentials | Password manager / secure offline recovery record | Must not be stored in Git or ordinary chat |

## Owner setup checklist (one-time)

1. Secure the GitHub owner account with a unique password and two-factor authentication (2FA).
2. Save GitHub recovery codes offline in a physically secure place. Do not keep the only copy on the phone.
3. Secure the primary recovery email with its own unique password and 2FA.
4. Use a reputable password manager for account credentials. Keep its recovery method offline and separate from the phone.
5. Keep the Supabase, Vercel and domain registrar accounts under the owner's control. Add a recovery email and 2FA where supported.
6. Do not share account passwords or recovery codes with developers, support staff, or in ChatGPT.
7. Keep at least one encrypted offline backup of repository source (including Git history) on a computer or USB drive, updated after meaningful milestones. Keep the encryption key separately.

## Routine source backup

- GitHub is the primary remote source repository.
- At each meaningful milestone, ensure all intended work is committed and pushed to `nexora-development`.
- Periodically create an encrypted full Git mirror/clone on a separate device or encrypted drive. A ZIP download is not a full history backup.
- Verify a backup by cloning it into a clean folder and checking out `nexora-development`.
- Never put `.env`, service-role keys, access tokens, private customer exports, or unredacted logs in the repository backup unless they are separately encrypted and explicitly required; normally exclude them.

Example commands for a trusted computer:

```bash
git clone --mirror https://github.com/shaifrony/nexora-platform1.git nexora-platform1.git
git -C nexora-platform1.git fsck --full
git clone nexora-platform1.git nexora-restore-check
git -C nexora-restore-check checkout nexora-development
```

Because the repository is public today, the clone can be read without a login. Changes still require authorized GitHub access.

## Database and uploaded-file backup gate (before real customers)

Before launching with real customer data:

1. Confirm the Supabase project owner and billing plan.
2. Configure the available automated database backup/PITR retention for the selected plan; document the exact retention and recovery-point limits.
3. Create a separate, encrypted export/backup of critical database data on a schedule appropriate to transaction volume.
4. Define a separate backup/export process for Supabase Storage objects; a database dump alone does not back up uploaded files.
5. Store backups outside the same Supabase project/account where feasible, with restricted access and encryption.
6. Run a restore rehearsal into a disposable, isolated project/database. Verify users, orders, product records, delivery records, permissions/RLS and file references.
7. Record the backup date, restore test date, recovery point objective (RPO), recovery time objective (RTO), and responsible owner.
8. Do not run restore drills against Production or NEXORA-TEST without explicit authorization.

## If the phone is lost or stolen

1. From a trusted replacement device, secure the primary email account first.
2. Sign in to GitHub using the password manager and offline 2FA recovery method. Revoke lost-device sessions/tokens and rotate any credentials that may have been exposed.
3. Secure Supabase, Vercel and domain registrar sessions in the same way, if those accounts are configured.
4. If the SIM was stolen, contact the mobile operator to block/reissue it; do not rely on SMS as the only account recovery factor.
5. Restore the source from GitHub or the encrypted Git mirror. Check out `nexora-development`, not `main`.
6. Recreate local environment configuration from the secure password manager/recovery record. Never retrieve secrets from Git history or commit them.
7. Verify the latest CI status before continuing development.
8. If any account compromise is suspected, pause deployments and rotate affected credentials before resuming.

## If ChatGPT access or a conversation is lost

The repository's tracker and architecture documents are the durable project record. Start from `README.md`, `docs/NEXORA_WORK_TRACKER.md`, and the linked design documents. Chat history is helpful context, not the only project backup.

## Release and safety rules

- Development work stays on `nexora-development`.
- No hosted Supabase migration, Production deployment, DNS/public alias change, or `main` change without explicit owner approval.
- A successful source/fixture CI run is not proof of a hosted database backup or successful restore.
- Never claim NEXORA is fully recoverable until the owner account recovery, encrypted off-device source backup, hosted database backup, Storage backup, and restore rehearsal have each been verified.
