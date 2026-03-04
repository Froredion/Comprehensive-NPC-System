# NPC Testers — SuperbulletAI Marketplace Assets

Pre-built test environments for the NPC System, hosted on the **SuperbulletAI Marketplace** ([superbullet.ai](https://superbullet.ai/)).

## How Asset IDs Work

Each tester has a **SuperbulletAI Asset ID** (UUID). When a user requests a tester through SuperbulletAI, the platform uses this ID to automatically **retrieve, unpack, and upload** the corresponding test scripts and environment into the user's Roblox game — no manual setup required.

## Available Testers

### Default NPC Tester (Recommended)

| Asset ID | `734ddd0c-3dab-478f-bc26-b050728805e4` |
|----------|----------------------------------------|

The default tester bundle. Includes the core test scripts for general NPC spawning, mass stress testing, and jump/pathfinding debugging.

### Specialized Testers

| Tester        | Name                     | Asset ID                               | Description                                                                                             |
|---------------|--------------------------|----------------------------------------|---------------------------------------------------------------------------------------------------------|
| Flee Mode     | NPC Flee Mode Tester     | `4d0838ba-5c9d-4575-bc12-76371c7d48ab` | Test environment for NPC flee behavior, demonstrating NPCs that run away from players or threats.       |
| Mass Spawn    | NPC Mass Spawn Tester    | `242acba3-992e-4be2-b18c-23a4c247d77c` | Stress test environment for spawning large quantities of NPCs to evaluate performance and optimization. |
| Tower Defense | NPC Tower Defense Tester | `e5639640-f17a-47a5-89d2-6170615faca1` | Test environment for tower defense NPC waves, demonstrating path-following enemies and wave spawning.   |
