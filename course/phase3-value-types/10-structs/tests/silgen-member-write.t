TODO(10h): a member WRITE `p.x = e` takes the field's ADDRESS inside
p's own slot (`struct_element_addr`) and stores through it. `--emit-sil` stops after SILGen.
No program here reads a field (that is the first hole), so this file can go green on its own.

`p.x = 9` on `var p` takes field #0's address from p's slot, then stores through it:

  $ cat > write.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > var p = Point(x: 1, y: 2)
  > p.x = 9
  > EOF
  $ ./lab.exe --emit-sil write.swift | awk '/alloc_stack.*\/\/ p/ { p = $1 } /integer_literal.* 9$/ { nine = $1 } /struct_element_addr/ { field_address = $1; base = $4; gsub(/,/, "", base); field = $5 } /^  store/ { if ($2 == nine && $4 == field_address) stored = "yes" } END { print "base is p:" (base == p ? " yes;" : " no;") " field: " field "; 9 stored through it: " stored }'
  base is p: yes; field: #0; 9 stored through it: yes

`p.y = 5 * 2` produces a multiplication and a field #1 address, then stores the result through
that address:

  $ cat > y.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > var p = Point(x: 1, y: 2)
  > p.y = 5 * 2
  > EOF
  $ ./lab.exe --emit-sil y.swift | awk '/binop "\*"/ { product = $1 } /struct_element_addr/ { field_address = $1; field = $5 } /^  store/ { if ($2 == product && $4 == field_address) stored = "yes" } END { print "multiply:" (product != "" ? " yes;" : " no;") " field: " field "; result stored through it: " stored }'
  multiply: yes; field: #1; result stored through it: yes

Two writes to the same variable both address the SAME slot, each with its own index:

  $ cat > twice.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > var p = Point(x: 1, y: 2)
  > p.x = 10
  > p.y = 20
  > EOF
  $ ./lab.exe --emit-sil twice.swift | awk '/struct_element_addr/ { gsub(/,/, "", $4); if (n++ == 0) base = $4; same = same (base == $4); fields = fields " " $5 } END { print "same slot:" (same == "11" ? " yes;" : " no;") " fields:" fields }'
  same slot: yes; fields: #0 #1

Value semantics in the SIL: after `var q = p`, `q.x = 99` addresses q's slot, not p's — the
copy has its own storage, so the write can never reach p:

  $ cat > copy.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > var p = Point(x: 1, y: 2)
  > var q = p
  > q.x = 99
  > EOF
  $ ./lab.exe --emit-sil copy.swift | awk '/alloc_stack.*\/\/ q/ { q = $1 } /struct_element_addr/ { gsub(/,/, "", $4); print "q slot addressed:" ($4 == q ? " yes" : " no") "; field: " $5 }'
  q slot addressed: yes; field: #0

A Bool field is addressed as field `#1` and stored through that address like any other:

  $ cat > flag.swift <<'EOF'
  > struct Cell {
  >   var n: Int
  >   var alive: Bool
  > }
  > var c = Cell(n: 0, alive: false)
  > c.alive = true
  > EOF
  $ ./lab.exe --emit-sil flag.swift | awk '/integer_literal.*true$/ { true_value = $1 } /struct_element_addr/ { field_address = $1; field = $5 } /^  store/ { if ($2 == true_value && $4 == field_address) stored = "yes" } END { print "field: " field "; true stored through it: " stored }'
  field: #1; true stored through it: yes

A write inside a loop body lands in that body's block, addressing the slot from `bb0`:

  $ cat > loop.swift <<'EOF'
  > struct Point {
  >   var x: Int
  >   var y: Int
  > }
  > var p = Point(x: 0, y: 0)
  > var i = 0
  > while i < 3 {
  >   p.x = i
  >   i = i + 1
  > }
  > EOF
  $ ./lab.exe --emit-sil loop.swift | awk '/^bb[0-9]+:/ { block = $1 } /alloc_stack.*\/\/ p/ { p = $1; p_block = block } /struct_element_addr/ { base = $4; gsub(/,/, "", base); field = $5; write_block = block } END { print "slot in " p_block "; write in " write_block "; base is p:" (base == p ? " yes;" : " no;") " field: " field }'
  slot in bb0:; write in bb2:; base is p: yes; field: #0
