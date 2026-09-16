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

print(shadowedByStruct())
print(notShadowed())
print(shadowedByInt(7))
