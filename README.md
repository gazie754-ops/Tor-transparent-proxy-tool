# rci-tor – System‑wide Tor transparent proxy for Kali Linux

**Author:** Ertugrul Ghazi  
**Organisation:** Red Cell Intelligence  
**Version:** 1.0.0

---

## What it does

`rci-tor` forces **all TCP traffic and DNS queries** from the local machine through Tor.
It acts as a **kill‑switch**: if Tor goes down, all non‑Tor traffic is dropped.
IPv6 and non‑DNS UDP are blocked to prevent leaks.

It is designed for **authorised penetration‑testing engagements** where you must
not expose the client’s target to your real IP.

> **This tool does not make you invulnerable.**  
> It does not protect against browser fingerprinting, application‑level identity
> leaks, or accounts that are tied to your real identity.

---

## Installation

```bash
git clone <repo> rci-tor
cd rci-tor
sudo make install