# Copyright 2019 DeepMind Technologies Limited (original OpenSpiel code).
# Adapted to Rulebook from the supplied tic_tac_toe.h and tic_tac_toe.cc.
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#     https://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import collections.vector

# 与 OpenSpiel 的枚举顺序一致：空格、O、X。
enum CellState:
    kEmpty
    kNought
    kCross

fun PlayerToState(Int player) -> CellState {player == 0 or player == 1}:
    if player == 0:
        return CellState::kCross
    return CellState::kNought

# 棋盘按行存储，位置编号为 row * 3 + column：
#   0 1 2
#   3 4 5
#   6 7 8
# 玩家 0 使用 X 并先手，玩家 1 使用 O。
# 请通过 DoApplyAction 更新状态，以保持这些字段一致。
cls TicTacToeState:
    CellState[9] board
    Int current_player
    Int outcome
    Int num_moves

    fun init():
        let cell = 0
        while cell < 9:
            self.board[cell] = CellState::kEmpty
            cell = cell + 1
        self.current_player = 0
        # OpenSpiel 的 kInvalidPlayer = -3，表示尚无获胜玩家。
        # 平局时也保留 -3，由棋盘是否已满区分。
        self.outcome = -3
        self.num_moves = 0

    # 检查指定玩家的三行、三列和两条对角线。
    fun HasLine(Int player) -> Bool {player == 0 or player == 1}:
        let mark = PlayerToState(player)
        let i = 0
        while i < 3:
            let row = i * 3
            if self.board[row].value == mark.value and self.board[row + 1].value == mark.value and self.board[row + 2].value == mark.value:
                return true
            if self.board[i].value == mark.value and self.board[i + 3].value == mark.value and self.board[i + 6].value == mark.value:
                return true
            i = i + 1
        if self.board[0].value == mark.value and self.board[4].value == mark.value and self.board[8].value == mark.value:
            return true
        return self.board[2].value == mark.value and self.board[4].value == mark.value and self.board[6].value == mark.value

    fun IsFull() -> Bool:
        return self.num_moves == 9

    fun IsTerminal() -> Bool:
        return self.outcome != -3 or self.IsFull()

    fun IsDraw() -> Bool:
        return self.outcome == -3 and self.IsFull()

    # 终局返回 OpenSpiel 的 kTerminalPlayerId = -4。
    fun CurrentPlayer() -> Int:
        if self.IsTerminal():
            return -4
        return self.current_player

    # and 短路求值，先检查范围，再访问数组。
    fun IsLegalAction(Int move) -> Bool:
        return !self.IsTerminal() and move >= 0 and move < 9 and self.board[move].value == CellState::kEmpty.value

    # 升序返回所有可落子位置；终局返回空列表。
    # 使用方式：moves.size()、moves.get(i)。
    fun LegalActions() -> Vector<Int>:
        let moves: Vector<Int>
        if self.IsTerminal():
            return moves
        let cell = 0
        while cell < 9:
            if self.board[cell].value == CellState::kEmpty.value:
                moves.append(cell)
            cell = cell + 1
        return moves

    # 前置条件拒绝越界、占用位置和终局后的动作。
    # 可用 can state.DoApplyAction(move) 检查是否允许调用。
    fun DoApplyAction(Int move) {self.IsLegalAction(move)}:
        self.board[move] = PlayerToState(self.current_player)
        if self.HasLine(self.current_player):
            self.outcome = self.current_player
        # 与原实现一致：即使本步结束游戏，也更新内部轮次和步数。
        self.current_player = 1 - self.current_player
        self.num_moves = self.num_moves + 1

    # 返回顺序为 [玩家 0 的收益, 玩家 1 的收益]。
    # X 胜：[1.0, -1.0]；O 胜：[-1.0, 1.0]；
    # 平局或尚未分出胜负：[0.0, 0.0]。
    fun Returns() -> Float[2]:
        let rewards: Float[2]
        rewards[0] = 0.0
        rewards[1] = 0.0
        if self.HasLine(0):
            rewards[0] = 1.0
            rewards[1] = -1.0
        else:
            if self.HasLine(1):
                rewards[0] = -1.0
                rewards[1] = 1.0
        return rewards

# 对应无参数 TicTacToeGame::NewInitialState()。
# 每次返回独立状态，构造时自动调用 init()。
fun NewInitialState() -> TicTacToeState:
    let state: TicTacToeState
    return state

# 调用示例：
# let state = NewInitialState()
# let moves = state.LegalActions()
# state.DoApplyAction(4)
# let next_player = state.CurrentPlayer()
# let finished = state.IsTerminal()
# let rewards = state.Returns()
