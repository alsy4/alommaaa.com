---
title: "Hello, World"
date: 2026-08-04
description: "First post — a quick tour of what this site can render at build time."
tags: ["meta"]
draft: false
---

Welcome. This is the first post on this site, and it doubles as a smoke test
for the build pipeline.

## Math

Inline math like $x^2 + y^2 = z^2$ should render inline with the surrounding
text.

A block equation:

$$
\sum_{i=1}^{n} i = \frac{n(n+1)}{2}
$$

## Code

A few languages, to check Shiki's grammars:

```go
package main

import "fmt"

func main() {
	fmt.Println("hello from go")
}
```

```c
#include <stdio.h>

int main(void) {
    printf("hello from c\n");
    return 0;
}
```

```bash
#!/usr/bin/env bash
echo "hello from bash"
```

```rust
fn main() {
    println!("hello from rust");
}
```