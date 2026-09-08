// Phase 2 / concept 08 — the CAPSTONE for this section: every construct SILGen lowers, in one
// program, doing something rather than demonstrating something.
//
// let/var · arithmetic and remainder · comparisons · && and || · if / else / else-if ·
// while · for over a range · break · continue · nested loops · functions, parameters and
// return · recursion · mutual recursion · an early return from a Void function · Double.
//
// Its SIL is worth reading whole: every basic block in it exists because of one of the above,
// and by the end you should be able to point at each and say which.
//
//   L=_build/default/phase2-types-flow/08-sil-silgen/tests/lab.exe
//   $L --emit-sil tests/programs/controlflow.swift

// --- functions: parameters, a return value, an if that returns from both arms ---------------
func maxOf(_ a: Int, _ b: Int) -> Int {
  if a > b {
    return a
  } else {
    return b
  }
}

// an else-if chain: three arms, and every path returns
func sign(_ n: Int) -> Int {
  if n > 0 {
    return 1
  } else if n < 0 {
    return -1
  } else {
    return 0
  }
}

// a while loop with two variables changing together — Euclid, and the loop a tree cannot hold
func gcd(_ a: Int, _ b: Int) -> Int {
  var x = a
  var y = b
  while y != 0 {
    let t = x % y
    x = y
    y = t
  }
  return x
}

// recursion: the call graph closes on itself
func fib(_ n: Int) -> Int {
  if n < 2 {
    return n
  }
  return fib(n - 1) + fib(n - 2)
}

// mutual recursion: neither can be lowered without the other's signature already collected
func isEven(_ n: Int) -> Bool {
  if n == 0 {
    return true
  }
  return isOdd(n - 1)
}

func isOdd(_ n: Int) -> Bool {
  if n == 0 {
    return false
  }
  return isEven(n - 1)
}

// trial division: a for over a range, an early `break`, and `&&` short-circuiting so that
// `d * d <= n` is checked before the remainder is taken
func isPrime(_ n: Int) -> Bool {
  if n < 2 {
    return false
  }
  var d = 2
  while d * d <= n {
    if n % d == 0 {
      return false
    }
    d = d + 1
  }
  return true
}

// a Void function that returns early: the return has no value, and what follows is unreachable
func announce(_ n: Int) {
  if n == 0 {
    return
  }
  print(n)
}

// --- and the program itself -----------------------------------------------------------------
print(maxOf(3, 9))                  // 9
print(sign(-4))                     // -1
print(sign(0))                      // 0
print(gcd(48, 18))                  // 6
print(fib(10))                      // 55
print(isEven(8))                    // true
print(isOdd(8))                     // false

// `continue` skips the rest of the body but not the increment; `break` leaves the loop
var sum = 0
for i in 0 ..< 20 {
  if i % 3 == 0 {
    continue
  }
  if i > 10 {
    break
  }
  sum = sum + i
}
print(sum)                          // 37

// nested loops, each break and continue naming its OWN loop
var pairs = 0
for i in 0 ..< 5 {
  for j in 0 ..< 5 {
    if j > i {
      break
    }
    if j == 0 {
      continue
    }
    pairs = pairs + 1
  }
}
print(pairs)                        // 10

// the primes under 30, counted with a while loop driving the for's work
var primes = 0
var candidate = 2
while candidate < 30 {
  if isPrime(candidate) {
    primes = primes + 1
  }
  candidate = candidate + 1
}
print(primes)                       // 10

// `||` short-circuits the other way: the second test is skipped once the first decides
let n = 7
if n < 0 || isPrime(n) {
  print(1)                          // 1
}

// Double arithmetic runs through the same lowering with a different operand type.
// (The total is 2.5 rather than a round number on purpose: we print Doubles with `%g`, so a
// whole 2.0 would come out as `2` where swiftc says `2.0` — a documented divergence, and not
// one this program is here to exercise.)
var total = 0.0
for _ in 0 ..< 5 {
  total = total + 0.5
}
print(total)                        // 2.5

announce(0)
announce(42)                        // 42
