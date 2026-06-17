// Phase 1 corpus (edge cases): negatives, unary minus, deep precedence, and the
// sign rules for integer / and % — all must match swiftc byte-for-byte.
print(2 + 3 * 4 - 10 / 2)   // 9
let n = 2 + 3
print(-n)                   // -5  — unary minus on a binding
print(3 - 10)               // -7  — negative result
print(-7 % 3)               // -1  — remainder takes the sign of the dividend
print(7 % -3)               // 1
print(-7 / 2)               // -3  — division truncates toward zero (not floored)
print(2 * -3 + 1)           // -5  — unary binds tighter than *
