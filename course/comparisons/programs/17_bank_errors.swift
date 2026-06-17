// Classes (reference semantics) + error handling (throws / do-catch).
enum BankError: Error {
  case insufficient
  case negative
}
class Account {
  var balance: Int
  init(_ start: Int) { balance = start }
  func deposit(_ n: Int) throws {
    if n < 0 { throw BankError.negative }
    balance = balance + n
  }
  func withdraw(_ n: Int) throws {
    if n < 0 { throw BankError.negative }
    if n > balance { throw BankError.insufficient }
    balance = balance - n
  }
}
let acct = Account(100)
do {
  try acct.deposit(50)
  try acct.withdraw(30)
  print(acct.balance)
  try acct.withdraw(1000)
  print(999)
} catch BankError.insufficient {
  print(-1)
} catch {
  print(-2)
}
// shared reference: both names see the same object
let alias = acct
do { try alias.deposit(5) } catch { print(-9) }
print(acct.balance)
