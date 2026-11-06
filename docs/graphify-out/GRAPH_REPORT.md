# Graph Report - docs  (2026-11-04)

## Corpus Check
- 6 files · ~171,241 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 65 nodes · 63 edges · 9 communities (8 shown, 1 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `f62faa93`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Security
- AeroDrive Backend API
- AeroDrive Architecture
- Compliance
- Share Links
- setBarHeight
- AeroDrive Website Image Assets Guide
- animateCursor

## God Nodes (most connected - your core abstractions)
1. `AeroDrive Backend API` - 9 edges
2. `AeroDrive Architecture` - 7 edges
3. `Compliance` - 6 edges
4. `Security` - 6 edges
5. `Share Links` - 5 edges
6. `Threat Model` - 4 edges
7. `Encryption Architecture` - 4 edges
8. `setBarHeight()` - 3 edges
9. `updateCalculator()` - 3 edges
10. `AeroDrive Website Image Assets Guide` - 3 edges

## Surprising Connections (you probably didn't know these)
- None detected - all connections are within the same source files.

## Import Cycles
- None detected.

## Communities (9 total, 1 thin omitted)

### Community 0 - "Security"
Cohesion: 0.15
Nodes (12): Assets Protected, Attack Scenarios & Mitigations, Cryptographic Primitives, Encryption Architecture, Key Hierarchy, Master Key (MK) Derivation, Per-File Encryption, Security (+4 more)

### Community 1 - "AeroDrive Backend API"
Cohesion: 0.18
Nodes (10): AeroDrive Backend API, Authentication, Base URL, CORS, Error Responses, GET /health, Health, POST /auth/token (+2 more)

### Community 3 - "AeroDrive Architecture"
Cohesion: 0.25
Nodes (7): AeroDrive Architecture, Data Flow: Download, Data Flow: Upload, Directory Structure, Key Design Decisions, Overview, System Layers

### Community 4 - "Compliance"
Cohesion: 0.29
Nodes (6): Compliance, Data Protection Regulations (GDPR, CCPA, etc.), Export Controls, Open Source License (AGPL-3.0), Telegram Terms of Service, Third-Party Dependencies

### Community 5 - "Share Links"
Cohesion: 0.40
Nodes (5): DELETE /share-links/:id, GET /s/:token, GET /share-links, POST /share-links, Share Links

### Community 6 - "setBarHeight"
Cohesion: 0.50
Nodes (4): clamp(), computeCosts(), setBarHeight(), updateCalculator()

### Community 7 - "AeroDrive Website Image Assets Guide"
Cohesion: 0.50
Nodes (3): AeroDrive Website Image Assets Guide, How to Replace with Your Custom Screenshots, Replaceable Image Inventory

## Knowledge Gaps
- **33 isolated node(s):** `Base URL`, `POST /auth/token`, `POST /share-links`, `GET /share-links`, `DELETE /share-links/:id` (+28 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **1 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `AeroDrive Backend API` connect `AeroDrive Backend API` to `Share Links`?**
  _High betweenness centrality (0.046) - this node is a cross-community bridge._
- **Why does `Share Links` connect `Share Links` to `AeroDrive Backend API`?**
  _High betweenness centrality (0.025) - this node is a cross-community bridge._
- **What connects `Base URL`, `POST /auth/token`, `POST /share-links` to the rest of the system?**
  _33 weakly-connected nodes found - possible documentation gaps or missing edges._