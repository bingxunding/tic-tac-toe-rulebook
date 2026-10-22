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
import serialization.print
import string

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
# 请通过 ApplyAction 更新状态，以保持这些字段一致。
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

    # 检查指定玩家的三行、三列和两条对角线
    fun HasLine(Int player) -> Bool {player == 0 or player == 1}:
        let c = PlayerToState(player).value
        # 三行
        let row0 = self.board[0].value == c and self.board[1].value == c and self.board[2].value == c
        let row1 = self.board[3].value == c and self.board[4].value == c and self.board[5].value == c
        let row2 = self.board[6].value == c and self.board[7].value == c and self.board[8].value == c
        # 三列
        let col0 = self.board[0].value == c and self.board[3].value == c and self.board[6].value == c
        let col1 = self.board[1].value == c and self.board[4].value == c and self.board[7].value == c
        let col2 = self.board[2].value == c and self.board[5].value == c and self.board[8].value == c
        # 两条对角线
        let diag0 = self.board[0].value == c and self.board[4].value == c and self.board[8].value == c
        let diag1 = self.board[2].value == c and self.board[4].value == c and self.board[6].value == c
        return row0 or row1 or row2 or col0 or col1 or col2 or diag0 or diag1


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

    # 对外落子入口，对应截图中的 State::ApplyAction。
    # 本实现仅转发落子；不实现 OpenSpiel 基类的历史记录等附加功能。
    fun ApplyAction(Int move) {self.IsLegalAction(move)}:
        self.DoApplyAction(move)

    # 与原 C++ ToString 一致：三行棋盘，空格为 .，末尾无换行。
    fun ToString() -> String:
        let text: String
        let cell = 0
        while cell < 9:
            if self.board[cell].value == CellState::kCross.value:
                text.append("x")
            else:
                if self.board[cell].value == CellState::kNought.value:
                    text.append("o")
                else:
                    text.append(".")
            if cell == 2 or cell == 5:
                text.append("\n")
            cell = cell + 1
        return text

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

# 游戏定义对象；每次调用方法都会创建独立的新局。
cls TicTacToeGame:
    fun NewInitialState() -> TicTacToeState:
        return NewInitialState()

    fun NumPlayers() -> Int:
        return 2

    fun NumDistinctActions() -> Int:
        return 9

# 单游戏加载入口：只接受 tic_tac_toe，不是 OpenSpiel 的通用注册器。
fun LoadGame(StringLiteral name) -> TicTacToeGame {s(name) == "tic_tac_toe"}:
    let game: TicTacToeGame
    return game

# 示例选手策略：每次选编号最小的合法位置，保证示例可重复运行。
# 若接入真人、随机策略或 AI，只需替换此函数的选点逻辑。
fun SelectAction(TicTacToeState state) -> Int {!state.IsTerminal()}:
    let legal_actions = state.LegalActions()
    return legal_actions.get(0)

# 在 Conda rulebook 环境中编译、运行：
# conda activate rulebook
# cd /Users/dingbingxun/Desktop/rulebook_project/tic_tac_toe_rulebook
# rlc tic_tac_toe.rl -o tic_tac_toe
# ./tic_tac_toe
# 此入口自动演示一整局，不需要终端输入。
fun main() -> Int:
    # 1. 加载游戏定义。
    let game = LoadGame("tic_tac_toe")
    # 2、3. 创建状态，自动调用 TicTacToeState.init()。
    let state = game.NewInitialState()
    print("New game: player 0 = x, player 1 = o")
    print("Board positions: 0 1 2 / 3 4 5 / 6 7 8")
    print(state.ToString())

    # 4、5、6. 获取玩家和合法动作、执行落子、检查终局。
    while !state.IsTerminal():
        let player = state.CurrentPlayer()
        let legal_actions = state.LegalActions()
        print("Current player:")
        print(player)
        print("Legal actions:")
        print(legal_actions)
        let action = SelectAction(state)
        print("Selected action:")
        print(action)
        state.ApplyAction(action)
        print(state.ToString())

    # 终局后不再落子，读取双方收益。
    print("Game over")
    if state.IsDraw():
        print("Draw")
    else:
        print("Winner:")
        print(state.outcome)
    print("Returns [player 0, player 1]:")
    print(state.Returns())
    return 0
