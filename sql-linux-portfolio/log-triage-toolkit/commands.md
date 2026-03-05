# Incident Triage Toolkit — Command Walkthrough

This document explains the Linux commands used by `triage.sh` to collect system evidence during troubleshooting or incident response.

The goal is to gather enough system context to diagnose common production issues such as high load, disk exhaustion, networking failures, or service crashes.

---

## 1. System Identity

These commands collect basic host information.

```bash
uname -a
hostname
uptime
<-- Purpose:
	•	Verify OS kernel
	•	Confirm host identity
	•	Determine system uptime and load averages. -->
Linux prod-web-01 6.2.0-39-generic x86_64 GNU/Linux
 14:22:01 up 12 days,  3:14,  2 users,  load average: 0.33, 0.41, 0.40

2. Memory Analysis

Check memory usage and detect possible memory pressure.

free -m
vmstat 1 5

Key signals:
	•	Low available memory
	•	High swap usage
	•	High IO wait

Example:
free -m
              total        used        free
Mem:           7876        6200         890
Swap:          2047         120        1927

3. Disk Usage

Disk exhaustion is one of the most common production incidents.
df -h
lsblk
Key signals:
	•	Filesystem > 85% full
	•	Unexpected mounted volumes

Example:
Filesystem      Size  Used Avail Use%
/dev/sda1        80G   72G   5G  93%

Severity rule used by toolkit:
if disk > 85% → WARNING
if disk > 95% → CRITICAL

4. CPU & Load Investigation

CPU pressure and runaway processes can cause service instability.
top -b -n1 | head -20
ps aux --sort=-%cpu | head

Purpose:
	•	Identify CPU-heavy processes
	•	Capture system load snapshot

5. Networking Diagnostics

Verify interfaces, routing, and listening ports.

ip a
ip r
ss -tulpn

These commands reveal:
	•	network interfaces
	•	routing table
	•	open ports and services
Example:
ss -tulpn
tcp LISTEN 0 128 0.0.0.0:22 users:(("sshd",pid=832))

6. Kernel & Hardware Signals

Kernel logs can reveal driver failures or system crashes.

dmesg | tail -50
Look for:
	•	OOM killer events
	•	disk errors
	•	hardware faults

Example:
Out of memory: Kill process 1345 (java)

⸻

7. Service Failure Analysis

Inspect systemd logs.
journalctl -xe | tail -200
Purpose:
	•	identify repeated service restarts
	•	detect dependency failures

⸻

8. Security Signals

Look for suspicious last -n 10
grep "Failed password" /var/log/auth.log

Detect:
	•	brute-force SSH attempts
	•	unexpected user logins

Example:
Failed password for root from 185.220.101.1

⸻

9. Report Generation

The toolkit generates two outputs:

Markdown Report
report.md
Human readable diagnostic summary.

JSON Report
report.json
Machine readable data for automation or monitoring pipelines.

⸻

10. Evidence Bundle

All artifacts are archived for investigation.
tar -czf triage-evidence.tar.gz reports logs

Contents include:
	•	system snapshot
	•	logs
	•	networking data
	•	process list

⸻

Summary

This toolkit demonstrates practical SRE troubleshooting methodology:
	1.	Collect system context
	2.	Detect anomalies
	3.	Preserve evidence
	4.	Produce structured reports

The goal is to accelerate incident response and provide reproducible diagnostics.

---

## Why this matters for your portfolio
This shows employers you understand:

- Linux troubleshooting methodology
- incident triage workflow
- system observability
- automation with bash
- evidence collection and reporting

Which aligns **exactly with SRE / support engineer / platform roles**.

---

If you'd like, I can also generate **three additional Linux projects for this portfolio** that will make it look like a **senior systems / SRE portfolio instead of a single script demo**.

