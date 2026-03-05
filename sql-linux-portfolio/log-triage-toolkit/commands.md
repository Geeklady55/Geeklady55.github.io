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

