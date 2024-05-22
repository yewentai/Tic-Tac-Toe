//
//  GameAI.swift
//

import Foundation

private let MAX_ITERATIONS = 3
private let SCORE_WINNING = 100

// This simple Tic-Tac-Toe AI takes full advantage of the immutable GameState struct.
struct GameAI {
    let game: GameState
    
    // Returns a list of positions on the board that contain pieces belonging to the specified player,
    // or are empty if `player` is nil.
    private func gameSquaresWhere(playerIs player: GamePlayer?) -> [GamePosition] {
        var positions = [GamePosition]()
        
        for x in 0..<game.board.count {
            for y in 0..<game.board[x].count {
                if (player != nil && game.board[x][y] == player!.rawValue) ||
                   (player == nil && game.board[x][y].isEmpty) {
                    positions.append(GamePosition(x: x, y: y))
                }
            }
        }
        
        return positions
    }
    
    // Returns a list of possible actions given the current game state.
    private func possibleActions() -> [GameAction] {
        let emptySquares = gameSquaresWhere(playerIs: nil)
        
        // If in "put" mode, every possible action is to put a piece in any empty square.
        if game.mode == .put {
            return emptySquares.map { GameAction.put(at: $0) }
        }
        
        var actions = [GameAction]()
        
        // If in "move" mode, generate all possible move actions from current player's pieces to empty squares.
        for sourceSquare in gameSquaresWhere(playerIs: game.currentPlayer) {
            for destinationSquare in emptySquares {
                actions.append(.move(from: sourceSquare, to: destinationSquare))
            }
        }
        
        return actions
    }
    
    // Returns a list of scored possible actions given the current game state and a player bias (player who we want to win).
    // Recursively simulates actions and their effects.
    private func scoredPossibleActions(playerBias: GamePlayer, iterationCount: Int = 0) -> [(score: Int, action: GameAction)] {
        var scoredActions = [(score: Int, action: GameAction)]()
        
        for action in possibleActions() {
            var score = 0
            guard let gameStatePostAction = game.perform(action: action) else { fatalError() }
            
            if let winner = gameStatePostAction.currentWinner {
                // If there's a winner, assign a score based on the winner and the iteration count.
                let scoreForWin = SCORE_WINNING - iterationCount
                if winner == playerBias {    // If playerBias wins, it's a positive score.
                    score += scoreForWin
                } else {    // Otherwise, it's a big negative score.
                    score -= scoreForWin * 2
                }
                
            } else {
                // Add the worst follow-up action score if there are further iterations allowed.
                if iterationCount < MAX_ITERATIONS {
                    let followUpActions = GameAI(game: gameStatePostAction).scoredPossibleActions(playerBias: playerBias, iterationCount: iterationCount + 1)
                    var minScoredAction: (score: Int, action: GameAction)? = nil
                    for scoredAction in followUpActions {
                        if minScoredAction == nil || minScoredAction!.score > scoredAction.score {
                            minScoredAction = scoredAction
                        }
                    }
                    score += minScoredAction!.score
                }
            }
            
            scoredActions.append((score: score, action: action))
        }
        
        return scoredActions
    }
    
    // Computes and returns the best possible action for the current player.
    var bestAction: GameAction {
        var topScoredAction: (score: Int, action: GameAction)? = nil
        for scoredAction in scoredPossibleActions(playerBias: game.currentPlayer) {
            if topScoredAction == nil || topScoredAction!.score < scoredAction.score {
                topScoredAction = scoredAction
            }
        }
        return topScoredAction!.action
    }
}
