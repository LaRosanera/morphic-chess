"# Morphic Chess
### Adaptive Intelligence Chess Simulation

Morphic Chess is a chess simulation built with **Godot Engine 4**, focused on modular architecture, configurable gameplay, and the foundations for adaptive intelligence.

The project aims to provide a flexible chess environment where game configurations, board layouts, and movement rules can be customized and expanded.

## Features

### Game Configuration
- **Local Multiplayer:** Two players can play on the same device.
- **Custom Player Names:** Configure names for White (Player 1) and Black (Player 2).
- **Configurable Time Controls:** Select from untimed, bullet, blitz, and rapid presets, including increment-based options. Clock functionality may depend on the current game implementation.
- **Board Orientation:** Choose whether White or Black appears at the bottom.
- **Seeded Sessions:** Enter a custom seed or use the daily seed. The selected seed initializes the game's random number generator.
- **Persistent Settings:** Game configuration is passed from the title screen into the chess session.

### Chess System
- **Modular Movement Rules:** Individual `MoveRule` nodes define movement behavior for different piece types.
- **Dynamic Piece Generation:** Chess pieces are instantiated and positioned programmatically.
- **Board Presets:** Load custom board configurations from JSON files.
- **Piece Promotion:** Promote pawns when they reach the opposite end of the board.
- **Move Visualization:** Highlight selected pieces, available moves, and capture targets.
- **Move Logging:** Record moves, captures, turns, and game results.

### Architecture
- Scene-based organization using Godot's node system.
- Separate scripts for board management, movement rules, and game configuration.
- Programmatically generated chess pieces.
- Configurable piece scenes and sprite animations.
- Extensible board layouts and movement behavior.

## Current Ruleset

Morphic Chess currently uses a simplified chess ruleset:

- White moves first.
- Players alternate turns between White and Black.
- Pieces follow their configured movement rules.
- Capturing the opposing king ends the game.
- Check and checkmate are not currently enforced as end-of-game rules.

This is an intentionally simplified ruleset. It should not be assumed to implement every rule of standard chess.

## Getting Started

### Requirements
- Godot Engine 4.x
- Git (optional, for cloning the repository)

### Installation

Clone the repository:

```bash
git clone https://github.com/LaRosanera/morphic-chess.git
```

Then:

1. Open Godot.
2. Select **Import**.
3. Navigate to the cloned `morphic-chess` directory.
4. Select `project.godot`.
5. Open the project and run it.

## Project Direction

Morphic Chess is an ongoing project. Its architecture is intended to support additional chess mechanics, configurable game modes, and future intelligent systems.

The long-term direction is to explore adaptive intelligence within a chess simulation, building on the existing movement-rule architecture and configurable game environment. Adaptive learning or an AI opponent should not be considered an implemented feature unless it is added in a future release.

## License

Morphic Chess is distributed under the **Morphic Chess Non-Commercial Use License (MCNC-1.0)**.

You may use, study, modify, and share the project under the conditions in the [`LICENSE`](LICENSE) file. Commercial use, marketing, and commercial distribution are restricted.

## Repository

[github.com/LaRosanera/morphic-chess](https://github.com/LaRosanera/morphic-chess)
"""

license_text = """MORPHIC CHESS NON-COMMERCIAL USE LICENSE
Version 1.0

Copyright (c) 2026 LaRosanera

1. DEFINITIONS

"Software" means the Morphic Chess project, including its source code, assets,
documentation, and other materials distributed with this license.

"Derivative Work" means a modified version of the Software or a work based
substantially on the Software.

"Commercial Use" means using, distributing, or making the Software or a
Derivative Work available primarily for commercial advantage or monetary
compensation. This includes selling copies, offering paid access, bundling it
with a paid product or service, or using it as part of a paid product or
service.

"Marketing" means advertising, promoting, endorsing, or commercially
positioning the Software or a Derivative Work as a product, service, or
commercial offering. This includes paid promotion and using the Software or a
Derivative Work to attract customers to a commercial offering.

2. PERMISSION GRANT

Subject to the terms of this license, the copyright holder grants you a
worldwide, non-exclusive, non-transferable, royalty-free license to:

- Use and run the Software for personal, educational, and other
  non-commercial purposes.
- Study and inspect the Software.
- Copy and modify the Software.
- Create Derivative Works for non-commercial purposes.
- Share unmodified copies and Derivative Works for non-commercial purposes,
  provided you include this license and preserve applicable copyright notices.

3. RESTRICTIONS

You may not:

- Sell the Software or a Derivative Work.
- Make the Software or a Derivative Work available as part of a paid product,
  paid service, subscription, or other commercial offering.
- Use the Software or a Derivative Work for Commercial Use.
- Market, advertise, or commercially promote the Software or a Derivative
  Work.
- Present the Software or a Derivative Work as your own original project or
  remove its copyright and attribution notices.
- Sublicense the Software or grant rights broader than those provided by this
  license.

Sharing the Software or a Derivative Work free of charge for non-commercial
purposes is permitted if this license and the applicable attribution notices
are retained.

4. ATTRIBUTION

When you share the Software or a Derivative Work, you must:

- Retain the copyright notice and this license.
- Clearly identify that your version is based on Morphic Chess.
- Identify significant modifications you made, where reasonably practical.
- Include a link to the original repository:
  https://github.com/LaRosanera/morphic-chess

5. OWNERSHIP

The Software is licensed, not sold. The copyright holder retains ownership
of the Software and all rights not expressly granted by this license.
This license does not transfer ownership of the Software to you.

6. THIRD-PARTY MATERIALS

This license applies only to material for which the Morphic Chess copyright
holder has the right to grant permission. Third-party libraries, fonts,
artwork, audio, and other assets may be subject to separate licenses.
You are responsible for complying with those separate terms.

7. TERMINATION

Your rights under this license terminate automatically if you violate its
terms. If your rights terminate, you must stop using and distributing the
Software and any copies or Derivative Works in your possession. Rights may
be reinstated only with written permission from the copyright holder.

8. NO WARRANTY

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE, AND NONINFRINGEMENT. IN NO EVENT SHALL THE
COPYRIGHT HOLDER BE LIABLE FOR ANY CLAIM, DAMAGES, OR OTHER LIABILITY
ARISING FROM, OUT OF, OR IN CONNECTION WITH THE SOFTWARE OR ITS USE.

9. OTHER TERMS

This license does not grant permission to use the copyright holder's name,
branding, or trademarks to imply endorsement of your use or modified version.

If you want to use the Software in a way this license does not permit,
you must obtain separate written permission from the copyright holder.
"""
