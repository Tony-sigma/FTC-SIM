# Field data

`field_layout.json` and `game_elements.json` are copied unchanged from the **BEE robot simulator**
v1.9 by MariusAndrei123 (https://github.com/MariusAndrei123/bee-simulator), used with the
author's permission. They describe the BIOBUZZ field from Competition Manual TU02, chapters 9-10.

Coordinates in these files: inches on a 144 x 144 field, (0,0) = top-left corner seen from above,
audience at the bottom, red alliance on the left, blue on the right. `scripts/field.gd` converts
them to the simulator's frame (origin at field centre, FTC y = 72 - y).

The files give the floor plan only. Heights and the way flowers and hives move are guesses in
`robot_config.json` under `field` until we check them against the manual.
