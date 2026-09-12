enum State: Int {
  case first, second, third, fourth
}

func next(_ state: State) -> State {
  if state == State.first { return State.second }
  if state == State.second { return State.third }
  if state == State.third { return State.fourth }
  return State.first
}

var state = State.first
var checksum = 0
for _ in 0 ..< 20000000 {
  state = next(state)
  checksum = checksum + state.rawValue
}
print(checksum)
