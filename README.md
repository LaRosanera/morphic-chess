# Morphic Chess

Chess, but the rules can change from game to game.

Morphic Chess uses a seed to build a chess variant. Piece movement rules can change, additional pieces may appear, and the available promotion choices can vary. Check the in-game Game Information screen to see the rules for your match.

## Gameplay

- Play locally with two players on one device, or create or join an online room.
- Use a daily seed or enter a custom seed.
- Try seeded changes to piece movement, including altered ranges, jumps, and extra movement patterns.
- Play with additional pieces: Amazon, Empress, Princess, Minister, Elephant, Camel, and Man.
- Promote pawns when the game allows it; the available pieces are determined for each game.
- Choose from untimed, bullet, blitz, and rapid clocks, set player names, and flip the board.
- Open **Settings → Game** during a match to review its seed, starting layout, daily modifications, and active movement rules.

The goal is to capture the opposing king. Check and checkmate are not enforced, so this does not implement every rule of standard chess.

## Multiplayer

Local games are played by two people sharing a device. Online games use room codes and Firebase Realtime Database to share match state. Online responsiveness depends on your connection and the service; updates may take a moment.

## Get the game

### Requirements

- Godot Engine 4.7
- Git, if you want to clone the source

### Run from source

Clone the repository:

```bash
git clone https://github.com/LaRosanera/morphic-chess.git
```

In Godot, import the cloned folder by selecting its `project.godot` file, then run the project.

## Development

Morphic Chess is made with Godot Engine 4.7 and GDScript. The game rules and match setup are implemented in the `scripts/` directory, with scenes in `Scenes/`. Online multiplayer communicates with Firebase Realtime Database.

## License

There is currently no `LICENSE` file in this repository. Do not assume the source code or assets are licensed for reuse; contact the project maintainer for permission.

## Repository

[github.com/LaRosanera/morphic-chess](https://github.com/LaRosanera/morphic-chess)
