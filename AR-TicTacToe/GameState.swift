//
//  GameState.swift
//

import Foundation

typealias GamePosition = (x: Int, y: Int)

enum GamePlayerType: String {
    case human = "human"
    case ai = "ai"
}

enum GameMode: String {
    case put = "put"
    case move = "move"
}

enum GamePlayer: String {
    case x = "x"
    case o = "o"
}

// Represents possible actions in the game, either placing or moving a piece
enum GameAction {
    case put(at: GamePosition)
    case move(from: GamePosition, to: GamePosition)
}

// An immutable implementation of the game state for Tic-Tac-Toe
struct GameState {
    let currentPlayer: GamePlayer
    let mode: GameMode
    let board: [[String]]
    
    // Initializes a new game with default state: random starting player, "put" mode, and empty board
    init() {
        self.init(currentPlayer: arc4random_uniform(2) == 0 ? .x : .o,  // Randomly select starting player
                  mode: .put,  // Start in "put" mode
                  board: [["", "", ""], ["", "", ""], ["", "", ""]])  // Initialize an empty board
    }
    
    // Private initializer to create a new game state
    private init(currentPlayer: GamePlayer,
                 mode: GameMode,
                 board: [[String]]) {
        self.currentPlayer = currentPlayer
        self.mode = mode
        self.board = board
    }
    
    // Performs an action in the game and returns a new game state if successful
    func perform(action: GameAction) -> GameState? {
        switch action {
        case .put(let at):
            // Ensure we are in "put" mode and the destination square is empty
            guard case .put = mode,
                  board[at.x][at.y] == "" else { return nil }
            
            // Generate a new board state
            var newBoard = board
            newBoard[at.x][at.y] = currentPlayer.rawValue
            
            // Count the number of used squares
            let numberOfSquaresUsed = newBoard.reduce(0, {
                return $1.reduce($0, { return $0 + ($1 != "" ? 1 : 0) })
            })
            
            // Return a new game state, switching players and updating the mode if needed
            return GameState(currentPlayer: currentPlayer == .x ? .o : .x,
                             mode: numberOfSquaresUsed >= 6 ? .move : .put,
                             board: newBoard)
            
        case .move(let from, let to):
            // Ensure we are in "move" mode, the "from" piece matches the current player, and the destination is empty
            guard case .move = mode,
                  board[from.x][from.y] == currentPlayer.rawValue,
                  board[to.x][to.y] == "" else { return nil }
            
            // Generate a new board state
            var newBoard = board
            newBoard[from.x][from.y] = ""
            newBoard[to.x][to.y] = currentPlayer.rawValue
            
            // Return a new game state, switching players and staying in "move" mode
            return GameState(currentPlayer: currentPlayer == .x ? .o : .x,
                             mode: .move,
                             board: newBoard)
        }
    }
    
    // Determines if there is a winner and returns the winning player if any
    var currentWinner: GamePlayer? {
        // Check for horizontal, vertical, and diagonal wins
        for l in 0..<3 {
            if board[l][0] != "" &&
                board[l][0] == board[l][1] && board[l][0] == board[l][2] {
                // Horizontal line victory
                return GamePlayer(rawValue: board[l][0])
            }
            if board[0][l] != "" &&
                board[0][l] == board[1][l] && board[0][l] == board[2][l] {
                // Vertical line victory
                return GamePlayer(rawValue: board[0][l])
            }
        }
        // Check for diagonal wins
        if board[0][0] != "" &&
            board[0][0] == board[1][1] && board[0][0] == board[2][2] {
            // Top left to bottom right victory
            return GamePlayer(rawValue: board[0][0])
        }
        if board[0][2] != "" &&
            board[0][2] == board[1][1] && board[0][2] == board[2][0] {
            // Top right to bottom left victory
            return GamePlayer(rawValue: board[0][2])
        }
        return nil
    }
}
