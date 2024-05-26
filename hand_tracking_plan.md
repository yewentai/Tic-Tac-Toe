# Component Breakdown

### ViewController
This file likely contains the main interaction logic of your AR scene. It would handle user inputs, place the game board in the AR space, and react to touch events on the screen. For hand tracking, you will need to modify or extend this file to process hand gestures instead of screen taps.

### Figure
The `Figure.swift` file probably defines the "O" and "X" objects in your game, their properties, and possibly their visual representation in the AR space. You will need to understand how these are currently manipulated so you can adapt the code to move them with hand gestures instead of direct touch.

### GameState
This file tracks the state of the game, such as whose turn it is, whether someone has won, and if the game is still in progress. You might need to update this to account for the new interaction mode if the timing or order of play changes with the introduction of hand tracking.

### Extensions
Swift extensions add new functionality to existing classes, structs, or enums. They might be used in your project to add convenient functionality to system types or your own types. This could include touch handling or vector calculations that might be relevant when interpreting hand movements.

### Board
This file likely manages the tic-tac-toe board's logic, such as keeping track of which cells are filled and checking for a win condition. When introducing hand tracking, you will have to interface with this logic to update the board state based on the hand gesture inputs.

### Main.storyboard
The `Main.storyboard` file is where your app's user interface is laid out. While it might not be directly involved with the AR or hand-tracking aspects, it's crucial to understand how the UI elements are presented and how they might need to be updated to provide feedback or instructions to the user for the new hand-tracking feature.

## Adding Hand Tracking Functionality
To add hand tracking, you'll likely need to integrate with an external library or use newer functionalities of ARKit, such as ARKit 3’s Body Tracking, which can be extrapolated to track hands to some extent, or the Vision framework for recognizing specific hand poses. Here's what you can do:

1. **Research ARKit's latest capabilities**: If Apple has introduced hand tracking in a newer version of ARKit after my last update, you would need to study the relevant documentation and update your app to use it.

2. **Integrate an external hand-tracking library**: If ARKit doesn't support hand tracking natively, you may need to integrate a third-party library.

3. **Update the ViewController**: Incorporate the hand-tracking setup and handling into this controller. You will need to process the hand-tracking data and convert it into game moves.

4. **Modify the Board and Figure logic**: You'll have to update how figures are placed on the board. Instead of responding to taps, you'll be moving figures based on the position of the user's hand in the AR space.

5. **Adjust the GameState**: Depending on how the hand-tracking affects gameplay, you might need to adjust how the game state is managed.

6. **Test and Iterate**: With the hand tracking in place, you'll need to thoroughly test the game to ensure the interactions are smooth and intuitive.


# Function Detail Explaination and Insight

Code for each of these components to understand their role in the AR Tic-Tac-Toe game:

### Dimensions.swift
This file defines several constants that will be used throughout the game to maintain consistency and ease of changes to the dimensions of various elements. For instance, `BOARD_GRID_HEIGHT` and `BOARD_GRID_WIDTH` define the thickness of the lines that make up the grid of the tic-tac-toe board, `SQUARE_SIZE` is the size of each square on the board, `FIGURE_RADIUS` is the radius for the "O" and "X" figures, and `DRAG_LIFTOFF` could be used to determine how much an object should be lifted off the board when being dragged.

### Figure.swift
`Figure.swift` contains the definitions for creating 3D models of the "X" and "O" figures using SceneKit's nodes. It defines a `Figure` class that has factory methods to create either an "X" or an "O" figure, represented by 3D geometries (`SCNCylinder` for "X" and `SCNTorus` for "O"). These figures are styled with materials that are set to mimic physical properties such as roughness and metalness, giving them a more realistic appearance in the AR environment. The `xFigure()` method creates two crossed cylinders to form an "X", and the `oFigure()` method creates a torus for the "O".

### Extensions.swift
This file extends existing types to add new functionality. It adds a property to any floating-point number that converts degrees to radians and vice versa, which is a common operation when dealing with 3D transformations since SceneKit operates in radians. It also extends `SCNVector3` to add a method for converting a 4x4 transformation matrix into an `SCNVector3`, which can be useful when working with positions in 3D space.

### Board.swift
`Board.swift` is responsible for creating and managing the tic-tac-toe board within the AR space. It defines a `Board` class that creates a 3D representation of the board, including the individual squares and the grid lines. It uses `SCNPlane` for the squares and `SCNBox` for the grid lines. The `Board` class also keeps track of the mapping between the visual nodes (the parts of the 3D model) and their logical positions on the board, which is essential for gameplay logic. It uses dictionaries for this purpose: `nodeToSquare` maps `SCNNode`s to their (row, column) indices, and `squareToPosition` maps square positions to their `SCNVector3` positions in the 3D space.

### GameState.swift
`GameState.swift` defines the data structure and logic to represent the state of the Tic-Tac-Toe game. It handles the board state, current player, and game mode (either placing or moving pieces).

- **GamePosition**: A typealias for a tuple representing an x, y position on the game board.
- **GamePlayerType**: An enum indicating whether the player is human or AI.
- **GameMode**: An enum indicating the current mode of the game, either in the initial placing phase (`put`) or the moving phase (`move`).
- **GamePlayer**: An enum for the players in the game, "x" and "o".
- **GameAction**: An enum representing a game action, which could either be placing a piece on an empty square or moving a piece from one square to another.
- **GameState**: A struct representing the current state of the game. It's immutable, meaning once created, it cannot be altered. This is a common functional programming practice to avoid side effects. When a move is made, a new `GameState` instance is created representing the new state.

  - The `perform` method takes a `GameAction` and applies it to the current `GameState`, returning a new `GameState` if the move is valid.
  - The `currentWinner` computed property checks the board to see if there is a winning condition met.

### GameAI.swift
`GameAI.swift` contains the logic for the artificial intelligence of the game. The AI uses the `GameState` to determine the best move based on a simple scoring system. It is a struct that evaluates the best action for the AI to take.

- **MAX_ITERATIONS** and **SCORE_WINNING**: These constants define the depth of the game tree search and the score for winning a game.
- **gameSquaresWhere**: A private method that returns a list of positions (squares) on the board that match the specified player or are empty.
- **possibleActions**: Determines all possible moves the AI can make given the current `GameState`. If in "put" mode, it includes all empty squares. If in "move" mode, it includes all possible moves from a player's square to an empty square.
- **scoredPossibleActions**: Evaluates possible actions by scoring them. It uses a minimax-like approach, simulating moves ahead and preferring moves that lead to victory while avoiding defeat. If the `GamePlayer` specified by `playerBias` wins, the score is positive; otherwise, it's negative. The function calls itself recursively to evaluate subsequent moves, but only up to `MAX_ITERATIONS`.
- **bestAction**: Selects the best action to perform from the scored actions. The AI uses this method to decide its move.

### ViewController.swift

The `ViewController` in your AR Tic-Tac-Toe game is the central hub where the user interface and game logic come together. It is responsible for handling user interactions, updating the game state, rendering the AR scene, and initiating AI moves.

#### UI Elements and Actions
- **IBOutlet Properties**: Connect UI elements from the storyboard to code, allowing you to update and manage these elements programmatically.
  - `planeSearchLabel`, `planeSearchOverlay`, `gameStateLabel`: Used to give feedback to the user about the game state and AR plane detection status.
  - `sceneView`: The ARSCNView where the AR scene is rendered.
- **IBAction Methods**: Actions that are called when UI elements (like buttons) are interacted with.
  - `didTapStartOver`: Resets the game.

#### State Management
- **Game State Variables**: Hold the current state of the game and other essential properties.
  - `playerType`: A dictionary mapping each player to their type (human or AI).
  - `planeCount`: The number of planes detected by ARKit.
  - `currentPlane`: The current AR plane on which the game is being played.
  - `board`: An instance of the `Board` class which represents the game board in AR space.
  - `game`: The current game state, represented by an instance of `GameState`.
  - `figures`: A dictionary mapping the positions on the board to the corresponding SCNNode for each game piece.
  - `lightNode`, `floorNode`: SCNNode for light and floor to enhance the AR scene.
- **Gesture Recognizers**: Handle user gestures such as taps and pans in the AR scene.
  - `didTap`: Recognizes tap gestures to place the game board or a game piece.
  - `didPan`: Recognizes pan gestures for moving game pieces.

#### Game Flow
- **reset**: Presents an alert to let users choose the type of game (human vs. AI, human vs. human, or AI vs. AI) and begins a new game.
- **newTurn**: If the current player is AI, the AI's move is calculated in a background thread and then performed.
- **beginNewGame**: Resets the game state and figures.
- **removeAllFigures**: Removes all the game pieces from the AR scene.

#### ARKit and SceneKit Integration
- **ARSCNViewDelegate Methods**: These methods respond to changes in the AR scene, such as the addition or removal of planes.
- **enableEnvironmentMapWithIntensity**: Sets up lighting for the scene based on ambient light estimates.
- **ARWorldTrackingConfiguration**: Configures the AR session with horizontal plane detection and light estimation.

#### Gesture Handlers and Game Piece Manipulation
- **didPan**: Handles the dragging of game pieces for player moves.
- **didTap**: Places the game board or game pieces onto the AR scene based on user taps.
- **move**: Handles the animation and logic for moving game pieces.
- **put**: Handles the animation and logic for placing new game pieces on the board.

#### Renderer Methods
- **renderer(_:updateAtTime:)**: Updates the lighting environment at each frame.
- **renderer(_:didAdd:for:)**: Detects when a new plane is added to the scene and updates `planeCount`.
- **renderer(_:didRemove:for:)**: Detects when a plane is removed from the scene and performs cleanup if necessary.


## Modification Desired for Hand Tracking:
### Integration of **Dimension, Figure, Extensions, and Board** for Hand Gesture Functionality

1. **Dimensions**: You may need to adjust dimensions based on how the hand-tracking input changes the scale or interaction area in the AR space.

2. **Figure**: You'll need to make these figures interactable with the hand-tracking gestures, potentially adding animations or transformations based on the user's hand movements.

3. **Extensions**: You might need to add more extensions or modify existing ones to convert hand position data into SceneKit compatible formats.

4. **Board**: You'll update the logic to recognize when a hand gesture is indicating a move on the board, and to move figures accordingly.

For the hand-tracking functionality, you will likely need to use additional APIs that can recognize hand gestures in real-time and then map these gestures to actions in your game. You'll integrate this logic within your `ViewController`, where most of the AR session management takes place.

### Integration of **GameState and GameAI** for Hand Gesture Functionality
Understanding `GameState` and `GameAI` is essential because they form the logic behind the game's operation. When implementing hand gesture control, you will use the `GameState` to update the game based on the user's physical interactions. You'll interact with these two components in the following way:

1. **Detecting Hand Gestures**: When you detect a hand gesture that represents a move, you will create a corresponding `GameAction` (either `.put` or `.move`).

2. **Updating GameState**: You'll pass the `GameAction` to the `perform` method of `GameState` to get a new `GameState` that reflects the move made by the hand gesture.

3. **AI Response**: After the `GameState` is updated with the player's move, you will use `GameAI` to determine the AI's response, which will also be a `GameAction`.

4. **Winning Condition**: After each move (player's and AI's), you'll check `GameState.currentWinner` to determine if there's a winner.

For the actual hand tracking, you'll be capturing hand gesture data (using ARKit or another library), interpreting it to define the game actions, and then using these components to update the game logic.

### Integration of **ViewController** for Hand Gesture Functionality
Understanding this `ViewController` is essential for making enhancements to the game. If you want to add hand tracking to move game pieces, you would need to integrate hand gesture detection possibly using ARKit's or a third-party library's capabilities and use it to perform game actions instead of or in addition to the existing tap and pan gesture recognizers. The detected hand movements would trigger `GameAction`s, updating the `game` state accordingly, much like how tap and pan gestures currently do.
