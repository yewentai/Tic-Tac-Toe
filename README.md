# AR Tic-Tac-Toe

AR Tic-Tac-Toe is an augmented reality version of the classic game, developed for iOS using Swift and Apple's ARKit. This app allows players to place a virtual tic-tac-toe board on a horizontal surface and play either against an AI opponent or another human player in the same physical space.

## Features

- **Augmented Reality Integration**: Place a virtual tic-tac-toe board on real-world surfaces.
- **Multiplayer Gameplay**: Play against an AI or a human opponent.
- **Dynamic Board Placement**: Move around to find a plane where the board can be placed.
- **Interactive Game Pieces**: Move and place game pieces via touch and drag gestures.

## Getting Started

### Prerequisites

- iOS 14.0 or later.
- ARKit-compatible device (iPhone 6s and newer).
- Xcode 12 or later.

### Installation

1. Clone the repository:

   ```bash
   git clone https://github.com/your-username/AR-TicTacToe.git
   ```

2. Open `AR-TicTacToe.xcodeproj` in Xcode.
3. Connect your iPhone or an ARKit-compatible device.
4. Build and run the application on your device from Xcode.

### How to Play

- Move the device around to detect a horizontal plane.
- Tap on the detected plane to place the tic-tac-toe board.
- Choose the game mode from the alert that appears (AI vs. Human, Human vs. Human).
- Tap on the board squares to place your X or O.
- The game ends when one player has three of their symbols in a row horizontally, vertically, or diagonally or all squares are filled.

## Architecture

The project is structured as follows:

- `AppDelegate.swift`: Manages app lifecycle.
- `ViewController.swift`: Handles user interactions and AR sessions.
- `Board.swift`: Manages the virtual board display and interactions.
- `GameAI.swift`: Implements the AI for playing against the computer.
- `GameState.swift`: Manages the state of the game.
- `Figure.swift`: Provides the X and O figures used in the game.
- `Dimensions.swift`: Contains the measurements used for the layout of the AR objects.
