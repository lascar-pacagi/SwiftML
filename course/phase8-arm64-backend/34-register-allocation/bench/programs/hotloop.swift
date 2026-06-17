var s = 0
var i = 1
while i < 20000000 { s = s + (i % 13) * (i % 7) - (i % 5); i = i + 1 }
print(s)
