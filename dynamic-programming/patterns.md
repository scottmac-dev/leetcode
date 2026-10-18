# Main DP Patterns / Use Cases

General recipe: 
- define the state 
- write the transition 
- set base cases 
- pick an iteration order where dependencies are already computed

---

## 1D Linear DP

- Each step builds on prior ones and can rely on earlier states / results.
- e.g. `dp[i]` only needs `dp[i-1]`, `dp[i-2]`, or a scan of all `j < i`.
- **Also covers:** LIS (`dp[i]` = best ending at `i`), state machine DP (several 1D arrays, one per state, e.g. holding / not holding a stock).

**Example: House Robber** (can't take adjacent elements)

```python
# dp[i] = max(skip i, take i)
def rob(nums):
    dp = [0] * (len(nums) + 2)
    for i in range(len(nums)):
        dp[i + 2] = max(dp[i + 1], dp[i] + nums[i])
    return dp[-1]
```

---

## 2D Grid DP

- `dp[i][j]` is derived from its neighbouring cells (usually up / left).
- Common in path problems: min path, unique paths, etc.
- **Also covers:** two-sequence DP, where the "grid" is prefix `i` of string A vs prefix `j` of string B (LCS, edit distance).

**Example: Min Path Sum** (move only right or down) - See 64

**Example: Longest Common Subsequence** (two sequences as a grid) - See 1143

---

## Knapsack

- Take or skip each item based on a constraint like a budget or capacity.
- Common for subset selection or target-sum sets.
- `dp[t]` = best / possible / count for capacity `t`.
- **Key detail:** loop capacity **backwards** = each item used once (0/1). Loop **forwards** = items reusable (unbounded).

**Example: Coin Change** (unbounded, min coins)

```python
def coin_change(coins, amount):
    dp = [0] + [float("inf")] * amount
    for c in coins:
        for t in range(c, amount + 1):  # forwards
            dp[t] = min(dp[t], dp[t - c] + 1)
    return dp[amount] if dp[amount] != float("inf") else -1
```

---

## Intervals

- Cover a sub-range `dp[l][r]` by splitting on an index `k`.
- Common when the optimal answer depends on how a list is split or merged, reusing known values of smaller ranges.
- **Key detail:** iterate by **range length** (short to long) so the smaller ranges are always solved first.
- **Also covers:** palindrome DP (`dp[l][r]` from `dp[l+1][r-1]`).

**Example: Longest Palindromic Subsequence** - See 5
**Example: Unique BSTs** - See 96

---

## Other State Shapes (same idea, different state)

- **Bitmask:** `dp[mask][i]`, set of visited items as bits. For n ≤ ~20 (TSP, assignment).
- **Tree:** DFS returns `(take, skip)` per subtree (House Robber III, max path sum).
- **Game / minimax:** `dp[state]` = best score difference for the player to move.

## General Techniques

- **Memoisation (top-down):** recursion + cache. Easiest to write.
- **Tabulation (bottom-up):** fill a table in dependency order. Better constants, allows space optimisation.
- **Space optimisation:** if a row only needs the previous row (or last few values), roll the array.
