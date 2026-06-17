// Phase 1 corpus: integer arithmetic + precedence + parens + unary minus.
// `swiftml build arith.swift && ./arith` must print the same as swiftc.
print(1 + 2 * 3)        // 7  — precedence
print((1 + 2) * 3)      // 9  — parentheses
print(10 - 4 - 3)       // 3  — left associativity
print(20 / 6)           // 3  — integer division
print(20 % 6)           // 2  — remainder
print(-5 + 8)           // 3  — unary minus
