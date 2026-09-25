---
name: clean-code
description: Clean code principles reference. Use when you need guidance on function design, naming conventions, managing complexity, or code structure decisions.
tools: Read
model: haiku
---

# Clean Code Principles

Guidance for maintaining clean, readable code that respects human cognitive limits.

## Core Principle: Limited Working Memory

Humans can hold approximately **4-7 items** in working memory at once. Code must be written with this constraint in mind. Every function, module, and abstraction should minimize the mental load required to understand it.

## Function Design

### Keep Functions Small and Focused

A function should do **one thing** and fit in your head:
- **Max 20-30 lines** as a soft guideline
- **Max 3-4 parameters** - more indicates the function does too much
- **Single level of abstraction** - don't mix high-level logic with low-level details

```lua
-- BAD: Mixed abstraction levels, too much happening
function process_pod(pod)
  local name = pod.metadata.name
  local ns = pod.metadata.namespace
  local status = pod.status.phase
  if status == "Running" then
    local containers = pod.spec.containers
    for _, c in ipairs(containers) do
      -- 50 more lines of container processing...
    end
  end
  -- format output, handle errors, update state...
end

-- GOOD: Each function handles one concern
function process_pod(pod)
  local info = extract_pod_info(pod)
  if is_running(info) then
    process_containers(pod.spec.containers)
  end
  return format_output(info)
end
```

### Descriptive Names Over Comments

Names should reveal intent. If you need a comment to explain what code does, rename it instead:

```rust
// BAD
let t = 86400; // seconds in a day

// GOOD
let seconds_per_day = 86400;

// BAD
fn proc(d: &Data) -> Result  // processes the data

// GOOD
fn validate_and_transform_resource(resource: &Resource) -> Result
```

### Early Returns to Reduce Nesting

Deep nesting forces the reader to track multiple conditions. Use early returns:

```lua
-- BAD: Reader must track 3 levels of conditions
function handle_request(req)
  if req then
    if req.valid then
      if req.authorized then
        -- actual logic here, 3 levels deep
      end
    end
  end
end

-- GOOD: Flat structure, exit early
function handle_request(req)
  if not req then return nil end
  if not req.valid then return nil, "invalid" end
  if not req.authorized then return nil, "unauthorized" end

  -- actual logic here, at top level
end
```

## Module Organization

### One Concept Per File

Each file should represent a single cohesive concept. If you're explaining a file and use "and", consider splitting it.

### Predictable Structure

Readers should know where to find things:
1. Imports/requires at top
2. Constants and types
3. Private helpers (in order of first use)
4. Public API at bottom (or clearly marked section)

### Limit Module Dependencies

A module that imports 15 other modules is hard to understand in isolation. Aim for:
- **Max 5-7 direct dependencies** for most modules
- Use dependency injection for testability and clarity

## Naming Conventions

### Be Specific and Consistent

```lua
-- BAD: Vague, inconsistent
local data = get()
local info = fetch()
local result = process(data)

-- GOOD: Specific, reveals type and purpose
local pod_list = fetch_pods()
local filtered_pods = filter_by_namespace(pod_list, namespace)
local formatted_rows = format_for_display(filtered_pods)
```

### Avoid Abbreviations (Except Universal Ones)

```rust
// BAD
fn proc_cfg_upd(cfg: &Cfg) -> Res

// GOOD
fn process_config_update(config: &Config) -> Result

// OK: Universal abbreviations
let ns = namespace;  // common in k8s domain
let ctx = context;   // widely understood
```

### Boolean Names Should Read as Questions

```lua
-- BAD
local running = check_pod(pod)
local valid = pod.status

-- GOOD
local is_running = check_pod_status(pod)
local has_valid_status = pod.status ~= nil
```

## Managing Complexity

### Extract When You See Patterns

If you find yourself copying logic, extract it. But don't pre-extract - wait until you see the pattern twice.

### Limit Branching

Each `if/else` doubles the mental paths to track:
- **Max 2-3 branches** in a single function
- Extract complex conditionals into named functions
- Use lookup tables instead of long switch/match statements

```lua
-- BAD: Reader tracks 5 branches
if resource == "pods" then
  -- ...
elseif resource == "deployments" then
  -- ...
elseif resource == "services" then
  -- ...
-- ...more branches
end

-- GOOD: Lookup table, single mental model
local handlers = {
  pods = handle_pods,
  deployments = handle_deployments,
  services = handle_services,
}
local handler = handlers[resource]
if handler then handler() end
```

### Keep State Localized

Global/shared state multiplies what a reader must track. Prefer:
- Pass data explicitly as parameters
- Return new values instead of mutating
- If state is necessary, contain it in one clearly-defined place

## Code Review Checklist

Before submitting code, verify:

- [ ] Can each function be understood without scrolling?
- [ ] Do names clearly describe purpose without needing comments?
- [ ] Is nesting depth <= 2-3 levels?
- [ ] Does each module have a single, clear responsibility?
- [ ] Would a new team member understand this in one read?

## Anti-Patterns to Avoid

### Clever Code

```rust
// BAD: Clever one-liner that requires careful parsing
let x = (a > b) as i32 * c + (a <= b) as i32 * d;

// GOOD: Clear intent, easy to verify
let x = if a > b { c } else { d };
```

### Hidden Side Effects

Functions should do what their name says and nothing more. If `get_pods()` also updates a cache, that's a hidden side effect that will confuse readers.

### Deep Inheritance/Trait Hierarchies

Deeply nested abstractions require readers to hold multiple levels in mind. Prefer composition over inheritance, and flat trait structures over deep hierarchies.

### Magic Numbers and Strings

```lua
-- BAD: What does 5 mean?
if #items > 5 then paginate() end

-- GOOD: Named constant reveals intent
local MAX_ITEMS_BEFORE_PAGINATION = 5
if #items > MAX_ITEMS_BEFORE_PAGINATION then paginate() end
```

## When to Break These Rules

These are guidelines, not laws. Break them when:
- Performance requires it (with a comment explaining why)
- The alternative is genuinely more confusing
- Domain conventions expect different patterns

But always ask: "Will the next reader thank me or curse me?"
