
# PREPL

A Game-REPL for Chicken Scheme. PREPL is a poll-based remote REPL that
allows you to integrate a REPL into your game or some event-loop.

If you need to control exactly when a REPL evaluates its input,
`prepl` may be useful. It processes all of its input on explicit calls
only. If you want a REPL to run asynchronously in its own thread,
`prepl` is probably not for you.

`prepl` runs over a tcp network. Here's an example:

```scheme
(define REPL (make-prepl 9898)) ;; repl on tcp port 9898
(let game-loop ()
  (REPL) ;; process all repl input
  (process-all-events)
  (draw-scene)
  (game-loop))
```
