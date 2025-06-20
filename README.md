# Fudanmaku
Fudanmaku (**Fu**nctional **Danmaku**) is a simple functional DSL for describing Danmaku (bullet hell) patterns.

[toc]

## Getting Started
Fudanmaku reads source files (conventionally named with `.fdm`), and produces a S-expression based file describing, frame by frame, how bullets shall be placed (we call that the Fudanmaku Transfer Language, `.ftl`).

Fudanmaku itself requires only pure Racket to run. However, to see your output visualized, you need to install the following Python packages:

```
pip3 install pygame sexpdata
```

After that, you may run and visualize your source file as such

```
racket fudanmaku.rkt file.fdm file.ftl
python3 render.py file.ftl
```

The `example` folder contains examples for most current language features, and a replication of Yakumo Yukari's spellcard "Border of Wave and Particle", from *Shoot the Bullet* and later (used by Komeiji Satori in) *Subterranean Animism*. 

## Language Reference

### 1. Overview of Language Design
Fudanmaku is heavily inspired by hardware-description languages. Every object is attached to *frame*s, analogous to the hardware clock in HDLs. The language does not specify the actual timing of frames -- this is left to the renderer's discretion.

The program is made of multiple Top-Level definitions, with each definition being

- either, a `pattern`, which are composable with other patterns and are ultimately composed to make up the `top` pattern;
- or, a `transform`, which is itself not composable, but may be applied to `pattern`s to create new patterns.

When a Fudanmaku program is executed, the evaluator first looks for a `top` pattern as the entry point of the spell card design. It then starts the clock (frame count) and evaluates all patterns as they are composed in a top-down manner.

All patterns ultimately are defined with `bullet`s, which is the unit that all patterns and transforms ultimately operate on.

To make up complex patterns, you compose other patterns, either with the `sequential` instruction, which fires its children one-by-one sequentially (analogous to `always` blocks in Verilog), or with the `parallel` instruction, which fires all its children at the same time (analogous to how you directly `assign` in Verilog).

Bullets are expected to fly as they were created. To change this, you use the `transform` construct. Transforms do not emit new bullets, but `update-bullet!` on every bullet within the pattern that it was applied to.

### 2. Abstract Syntax

#### 2.1 Top-Level Declarations

```ebnf
program       ::= { top-level-form }*
top-level-form
               ::= define-pattern
               |   define-transform

define-pattern
               ::= "(define-pattern"  
                     identifier
                     "(" { identifier }* ")"
                     pattern-expr ")"

define-transform
               ::= "(define-transform"  
                     identifier
                     "(" identifier ")"
                     transform-expr ")"
```

#### 2.2 Pattern Expressions

```ebnf
pattern-expr  ::= bullet-expr
               |   sequential-expr
               |   parallel-expr
               |   wait-expr
               |   repeat-expr
               |   loop-expr
               |   transform-expr
               |   call-pattern
               |   let-expr
               |   set-expr

bullet-expr   ::= "(bullet" { keyword value-expr }+ ")"

sequential-expr
               ::= "(sequential" identifier value-expr "->" value-expr pattern-expr ")"

parallel-expr ::= "(parallel" identifier value-expr "->" value-expr pattern-expr ")"

wait-expr     ::= "(wait" value-expr ")"

repeat-expr   ::= "(repeat" value-expr pattern-expr ")"

loop-expr     ::= "(loop" pattern-expr ")"

transform-expr
               ::= "(transform" identifier modifier pattern-expr ")"

call-pattern  ::= "(" identifier { value-expr }* ")"

let-expr      ::= "(let" "(" { "(" identifier value-expr ")" }+ ")" pattern-expr ")"

set-expr      ::= "(set!" identifier value-expr ")"
```

#### 2.3 Transform Modifiers

```ebnf
modifier      ::= "(after-frame" value-expr ")"
               |   "(every-frame" value-expr ")"
```

#### 2.4 Value Expressions

```ebnf
value-expr    ::= number
               |   identifier
               |   if-expr
               |   add-expr
               |   mul-expr
               |   random-int
               |   random-float
               |   callv-expr
               |   list-expr
               |   quote-expr
               |   sym-lit

if-expr       ::= "(if" value-expr value-expr value-expr ")"

add-expr      ::= "(+" value-expr value-expr ")"

mul-expr      ::= "(*" value-expr value-expr ")"

random-int    ::= "(random" value-expr ")"

random-float  ::= "(random-float" value-expr value-expr ")"

list-expr     ::= "(list" { value-expr }+ ")"

quote-expr    ::= "(quote" identifier ")"

callv-expr    ::= "(" identifier { value-expr }* ")"

sym-lit       ::= "'" identifier
```

### 3. Abstract Data Types (AST nodes)

Defined in `ast.rkt`:

```racket
;; Top-level
(struct pattern-def   (name params body)     #:transparent)
(struct transform-def (name params body)     #:transparent)

;; Pattern-level nodes
(struct bullet-node   (attrs)                #:transparent)
(struct seq-node      (iter-id start end b)  #:transparent)
(struct par-node      (iter-id start end b)  #:transparent)
(struct wait-node     (frames)               #:transparent)
(struct repeat-node   (count b)              #:transparent)
(struct loop-node     (body)                 #:transparent)
(struct trans-node    (xform modifier body)  #:transparent)
(struct call-node     (name args)            #:transparent)
(struct update-node   (b kvs)                #:transparent)
(struct let-expr      (binds body)           #:transparent)
(struct set-expr      (name val)             #:transparent)

;; Bullet attributes
(struct bullet-attr   (key value-expr)       #:transparent)

;; Modifier nodes
(struct modifier-after (n)                    #:transparent)
(struct modifier-every (n)                    #:transparent)
(struct modifier-none  ()                     #:transparent)

;; Value-level nodes
(struct num-lit       (n)                    #:transparent)
(struct id-ref        (sym)                  #:transparent)
(struct if-expr       (cond then else)       #:transparent)
;; note: a work in progress is to simplify these relics into the same `callv` structure
(struct add-expr      (l r)                  #:transparent)
(struct mul-expr      (l r)                  #:transparent)
(struct random-int    (u)                    #:transparent)
(struct random-float  (lo hi)                #:transparent)
(struct callv-expr    (fn args)              #:transparent)
(struct sym-lit       (sym)                  #:transparent)
```

### 4. Semantics

1. **Parsing**: `parser.rkt` turns S-expressions into the AST above.

2. **Evaluation** (`evaluator.rkt`):

   * Maintains a **Scheduler**: a mapping `frame-number => (Listof Bullet)` and a mutable `current-frame` pointer.
   * **`eval-pattern`** binds parameters and calls `eval-expr` on the body.
   * **`eval-expr`**:

     * **`bullet-node`**: Instantiates a fresh `Bullet` record with attributes evaluated via `attrs->hash`, assigns a unique `uid`, and schedules it at `current-frame`.
     * **`seq-node`** / **`par-node`**: Loops over indices, updates `current-frame` appropriately.
     * **`wait-node`**: Advances `current-frame` by N.
     * **`transform`**:

       1. Runs `sub` in a temporary scheduler at the same frame to collect *original* bullets.
       2. For each bullet *b* at frame *f*, schedules *b* at *f* and then applies the transform body:

          * **`update-bullet!`**: Produces zero/one/many modified bullets by copying the attribute hash and updating keys, preserving `uid`.
          * Schedules modified bullets at `f + delay` (for `after-frame`) or loops (for `every-frame`).

3. **Bullet Motion**:

   * A helper `advance-bullet(b, n)` moves *b* forward by *n* frames according to its `direction` and `speed`, producing a new `Bullet`.

### 5. FTL Output

After running `evaluate-program`, the **Scheduler**’s hash table is returned:

```racket
#hash(
  0  => (bullet uid=1 position=(50 0) direction=0   speed=1
         bullet uid=2 position=(–50 0) direction=180 speed=1 ...)
  30 => (bullet uid=1 position=(110 0) direction=30 speed=2 ...)
  …)
```

This is then wrapped into a S-expression based output dump, called the Fudanmaku Transfer Language (FTL)

```scheme
(ftl
  (frame 0   (bullet (uid 1) (position 50 0) (direction 0) (speed 1)) …)
  (frame 30  (bullet (uid 1) (position 110 0) (direction 30) (speed 2)) …)
  …)
```

## Discussion

Fudanmaku is designed around a deterministic evaluation model, rooted in the principles of Hardware Description Languages (HDLs). In this model, all bullet behaviors are scheduled at compile time, and no events in the rendering or execution phase can alter the trajectory or existence of a bullet once emitted.  This design choice offers a powerful advantage: **predictability and reproducibility**. Any Fudanmaku program, once compiled into FTL, will always yield the same bullet pattern, frame by frame, regardless of runtime environment or timing jitter.

This determinism simplifies many aspects of implementation. However, this strict model also imposes a fundamental limitation: **Fudanmaku is non-interactive by design**. Unlike most real-time game scripting engines, it does not support dynamic responses to gameplay state, such as the player’s position or live bullet collisions. As a result, Fudanmaku is best suited for describing cinematic patterns, replayable demonstrations, or autonomous spellcard sequences—but not full-scale interactive game logic.

This is analogous to HDL-based hardware modeling, where input/output behavior must be explicitly routed through clocked logic and state machines. In the same way that hardware cannot spontaneously respond to external stimuli without predefined  control logic, Fudanmaku cannot react to in-game events unless they are pre-scripted into its top-down evaluation tree

A work-in-progress change is to introduce symbolic algebra to Fudanmaku. By preserving special variables like `$playerX` and only allowing them to be resolved at runtime, we may achieve simple interactivity. 

For example, rather than encoding a bullet's direction as a static number:

```
(bullet :direction 90)
```

One might write:

```
(bullet :direction (+ (angle-to $playerX $playerY) 20))
```

This approach bridges the gap between precomputed scheduling and reactive behavior. During evaluation, these symbolic expressions are preserved as *unevaluated expressions*, to be interpreted dynamically by the renderer or engine. This enables limited interactivity, but still has the hazard of generating overly complex and impractical expression trees once logic complicates. This problem remains to be solved.
