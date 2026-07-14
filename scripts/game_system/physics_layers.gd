class_name PhysicsLayers
extends Object
## Именованные bit-маски CollisionObject2D (Layer N в редакторе = 1 << (N-1)).

## Layer 1 — CharacterBody юнитов. Area (обзор/выделение/снаряды) видят их по mask.
const UNITS: int = 1
## Layer 3 — статика карты (TileSet physics). Юниты сталкиваются только с ней.
const WORLD: int = 4
## Layer 10 — FOB только для mouse-pick; collision_mask FOB = 0 (юниты сквозь FOB).
const FOB_PICK: int = 512
