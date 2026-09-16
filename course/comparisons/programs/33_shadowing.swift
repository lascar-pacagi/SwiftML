// A local binding may shadow a type name. Swift resolves the name to the VALUE, so a member
// access on it is an ordinary member of that value's type — not enum-case construction.
// Both Sema and SILGen have to ask about the binding before they ask the enum registry.

enum Color { case red, green }
struct Box { var red: Int }

func shadowedByStruct() -> Int {
  let Color = Box(red: 42)
  return Color.red              // a struct field, not Color.red the enum case
}

func notShadowed() -> Bool {
  return Color.red == Color.red // still the enum case out here
}

func shadowedByInt(_ n: Int) -> Int {
  let Color = n
  return Color + 1              // the value, plainly
}

// From concept 25 on, methods exist, so a shadowed name can legitimately be a method RECEIVER.
// Sema resolves `E.a()` to C's method; SILGen must not read it as `E.a` the enum case.
class Counter {
  var v: Int
  init(_ n: Int) { v = n }
  func red() -> Int { return v }
}

func shadowedByClass() -> Int {
  let Color = Counter(7)
  return Color.red()            // a method call, not Color.red the enum case
}

print(shadowedByStruct())
print(shadowedByClass())
print(notShadowed())
print(shadowedByInt(7))
