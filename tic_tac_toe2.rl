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

# 架构参考：
# https://rl-language.github.io/language_tour.html#example-ui-for-tic-tac-toe
# https://www.llvm.org/devmtg/2025-04/slides/poster/fioravanti_coroutines.pdf
#
# Board 是数据；play 是可暂停的规则流程；main 是外部演示驱动。
# 新接口：play()、game.mark(row, col)、can apply(action, game)、game.is_done()。
# 原 LoadGame/TicTacToeGame/TicTacToeState/ApplyAction 仿 C++ 层级已移除。

import action
import bounded_arg
import collections.vector
import serialization.print
import string

using Coordinate = BInt<0, 3>

enum CellState:
    kEmpty
    kNought
    kCross

fun PlayerToState(Int player) -> CellState {player == 0 or player == 1}:
    if player == 0:
        return CellState::kCross
    return CellState::kNought

# 玩家 0 = X（先手），玩家 1 = O；棋盘位置 = row * 3 + col。
#   0 1 2
#   3 4 5
#   6 7 8
# 外部可以读取棋盘，但应通过 mark/apply 落子，不直接修改字段。
cls Board:
    CellState[9] slots
    Int current_player
    Int num_moves

    fun init():
        let cell = 0
        while cell < 9:
            self.slots[cell] = CellState::kEmpty
            cell = cell + 1
        self.current_player = 0
        self.num_moves = 0

    fun full() -> Bool:
        return self.num_moves == 9

    # 即使外部直接写入 BInt.value，也在访问数组前检查边界。
    fun empty(Int row, Int col) -> Bool:
        return row >= 0 and row < 3 and col >= 0 and col < 3 and self.slots[row * 3 + col].value == CellState::kEmpty.value

    fun has_line(Int player) -> Bool {player == 0 or player == 1}:
        let c = PlayerToState(player).value
        # 三行
        let row0 = self.slots[0].value == c and self.slots[1].value == c and self.slots[2].value == c
        let row1 = self.slots[3].value == c and self.slots[4].value == c and self.slots[5].value == c
        let row2 = self.slots[6].value == c and self.slots[7].value == c and self.slots[8].value == c
        # 三列
        let col0 = self.slots[0].value == c and self.slots[3].value == c and self.slots[6].value == c
        let col1 = self.slots[1].value == c and self.slots[4].value == c and self.slots[7].value == c
        let col2 = self.slots[2].value == c and self.slots[5].value == c and self.slots[8].value == c
        # 两条对角线
        let diag0 = self.slots[0].value == c and self.slots[4].value == c and self.slots[8].value == c
        let diag1 = self.slots[2].value == c and self.slots[4].value == c and self.slots[6].value == c
        return row0 or row1 or row2 or col0 or col1 or col2 or diag0 or diag1


    fun to_string() -> String:
        let text: String
        let cell = 0
        while cell < 9:
            if self.slots[cell].value == CellState::kCross.value:
                text.append("x")
            else:
                if self.slots[cell].value == CellState::kNought.value:
                    text.append("o")
                else:
                    text.append(".")
            if cell == 2 or cell == 5:
                text.append("\n")
            cell = cell + 1
        return text

# 编译器生成 Game、GameMark 和 AnyGameAction。
# frm 字段跨暂停点保留；调用 play() 后停在第一次 mark，等待外部动作。
# 整个对局的规则仅在此处推进，不依赖 UI、打印或选点策略。
@classes
act play() -> Game:
    frm board: Board
    frm winner = -3
    while !board.full():
        act mark(Coordinate row, Coordinate col) {board.empty(row.value, col.value)}
        board.slots[row.value * 3 + col.value] = PlayerToState(board.current_player)
        board.num_moves = board.num_moves + 1
        if board.has_line(board.current_player):
            winner = board.current_player
            return
        board.current_player = 1 - board.current_player
    # 棋盘满且无人获胜：结束流程，winner 保持 -3。
    # return 会让编译器生成的 is_done() 返回 true。
    return

# 查询层：终局状态来自协程，不再手动维护 IsTerminal 或 resume_index。
fun get_current_player(Game game) -> Int:
    if game.is_done():
        return -4
    return game.board.current_player

fun get_num_players() -> Int:
    return 2

fun is_draw(Game game) -> Bool:
    return game.is_done() and game.winner == -3

fun score(Game game, Int player_id) -> Float {player_id == 0 or player_id == 1}:
    if !game.is_done() or game.winner == -3:
        return 0.0
    if game.winner == player_id:
        return 1.0
    return -1.0

# 对应旧 Returns()，顺序为 [玩家 0, 玩家 1]。
fun returns(Game game) -> Float[2]:
    let rewards: Float[2]
    rewards[0] = score(game, 0)
    rewards[1] = score(game, 1)
    return rewards

# 枚举的是有限动作空间：3 行 × 3 列，共 9 种。
# can apply 同时检查动作前置条件和协程所在阶段；终局自动全部不可用。
# UI 与策略使用同一合法性来源，无须复制“空格/终局”的判断逻辑。
# 使用模板参数接收生成的动作类型，兼容本机编译器的类型生成顺序。
# 调用：let prototype: AnyGameAction; legal_actions(game, prototype)。
fun<T> legal_actions(Game game, T prototype) -> Vector<T>:
    let candidates = enumerate(prototype)
    let legal: Vector<T>
    let i = 0
    while i < candidates.size():
        let candidate = candidates.get(i)
        if candidate is ApplicableTo<Game>:
            if can apply(candidate, game):
                legal.append(candidate)
        i = i + 1
    return legal

# UI 点击入口示例：先验证普通整数，再构造有界坐标，避免转换时截断。
# 非法输入返回 false，状态保持不变；真正的落子仍通过生成的动作执行。
fun try_mark(Game game, Int row, Int col) -> Bool:
    if row < 0 or row >= 3 or col < 0 or col >= 3:
        return false
    let action: GameMark
    action.row = row
    action.col = col
    if can apply(action, game):
        apply(action, game)
        return true
    return false

# 展示层与规则分离，可供终端或外部工具调用。
fun pretty_print(Game game):
    print(game.board.to_string())

# 演示策略：选择枚举顺序中的第一个合法动作。
# 接入真人或 AI 时替换调用方的选点方式，play() 无须修改。
fun<T> select_action(Game game, T prototype) -> T {!game.is_done()}:
    let choices = legal_actions(game, prototype)
    return choices.get(0)

# conda activate rulebook
# cd /Users/dingbingxun/Desktop/rulebook_project/tic_tac_toe_rulebook
# rlc tic_tac_toe.rl -o tic_tac_toe
# ./tic_tac_toe
# 这是自动对局演示，不是图形 UI 或终端交互输入程序。
fun main() -> Int:
    let game = play()
    let prototype: AnyGameAction
    print("New game: player 0 = x, player 1 = o")
    pretty_print(game)
    while !game.is_done():
        print("Current player:")
        print(get_current_player(game))
        print("Legal actions:")
        print(legal_actions(game, prototype))
        let action = select_action(game, prototype)
        print("Selected action:")
        print(action)
        apply(action, game)
        pretty_print(game)
    print("Game over")
    if is_draw(game):
        print("Draw")
    else:
        print("Winner:")
        print(game.winner)
    print("Returns [player 0, player 1]:")
    print(returns(game))
    return 0
