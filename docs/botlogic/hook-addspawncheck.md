# Hook: AddSpawnCheck

**Priority:** 400  
**Provider:** lib.spawnutils

## Logic

```mermaid
flowchart TB
    Start[AddSpawnCheck] --> Validate[validateAcmTarget]
    Validate --> Zone{non-combat zone?}
    Zone -->|Yes| End[return]
    Validate --> Engage[clear engageTargetId if spawn dead or corpse]
    Engage --> Build[buildCampMobList]
    Build --> Filter[getSpawnsInArea acleash zradius]
    Filter --> CampFilter[filterSpawnForCamp: area, exclude, FTE, TargetFilter]
    CampFilter --> Assign[rc.MobList = list, rc.MobCount = count]
    Assign --> KillTarget[KillTarget in list or clear global]
    KillTarget --> End2[end]
```

- **validateAcmTarget:** If engageTargetId spawn missing or corpse, clear engageTargetId. If non-combat zone, return false and hook exits.
- **buildCampMobList:** Uses camp center (makecamp if campstatus, else current position). getSpawnsInArea(rc, acleash, zradius); for each spawn, filterSpawnForCamp (in area, not in ExcludeList, not FTE-locked, TargetFilter: 0 = NPC/pet aggressive LOS, 1 = NPC/pet LOS, 2 = not pc/banner/campfire etc.). Sorted by ID; returns list and count.
- **KillTarget:** Global KillTarget is kept in sync: if set and that spawn is not in MobList (e.g. corpse or gone), clear global; if set and not in list, append that spawn to MobList.

MobList and MobCount are used by doMelee, doPull, doHeal, doDebuff, and others. Filter logic: `lib/spawnutils.lua` (filterSpawnForCamp, filterSpawnExcludeAndFTE, filterSpawnTargetFilter).

## See also

- [README](README.md)
- [hook-domelee](hook-domelee.md) — uses MobList, engageTargetId
- [hook-dopull](hook-dopull.md) — uses MobCount, buildPullMobList in spawnutils
