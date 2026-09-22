# arel_where

Write composable Arel predicates directly inside Active Record hash conditions.

## Installation and setup

Add the gem to your Rails application's Gemfile, then run `bundle install`:

```ruby
gem "arel_where"
```

Or:

```sh
bundle add arel_where
```

Requires Ruby 3.1+ and Active Record 7.0 through 8.x. The suite runs green on Active Record 7.0, 7.1, 7.2, 8.0, and 8.1.

Requiring the gem (which Bundler does for you) patches `ActiveRecord::PredicateBuilder`
once, application wide. It does not activate the bare-word refinement; you opt into that
per file. See [What loading the gem changes](#what-loading-the-gem-changes).

## Usage

Start with `AW` to build a predicate for the column in a hash condition:

```ruby
User.where(first_name: AW.eq("Alice").or(AW.eq("Bob")))
```

For shorter calls, activate `ArelWhereRefine` at the top of a file or inside a module:

```ruby
using ArelWhereRefine

User.where(first_name: eq("Alice").or(eq("Bob")))
```

The refinement only affects that lexical scope. The gem loads it but never activates it for
you. The examples below use the refinement for lexical bare words; `AW.build` and
`AW.context` are available when a block is a better fit, and every form has an explicit `AW`
equivalent.

### Predicates

Each predicate applies to the column named in the hash:

```ruby
User.where(first_name: eq("Alice"))
User.where(first_name: matches("Ali%"))
User.where(date_of_birth: lt(18.years.ago.to_date))
User.where(last_name: not_eq(nil))
```

Chains accept every method in `Arel::Predications`, the SQL function helpers below, and
`function`. Any other name raises `NoMethodError` where you wrote it, so a typo fails at
the call site rather than deep inside query building:

```ruby
User.where(first_name: AW.mathces("Ali%")) # => NoMethodError: undefined method `mathces'
```

### Combining predicates

Use `and` and `or` to combine conditions on the same column:

```ruby
User.where(first_name: eq("Alice").or(eq("Bob")))
User.where(date_of_birth: gteq(Date.new(1990)).and(lt(Date.new(2000))))
```

### SQL functions

Use `lower` and `upper` for case conversion:

```ruby
User.where(first_name: lower.eq("alice"))
User.where(last_name: upper.matches("SM%"))
```

Other built-in helpers are `length`, `trim`, `coalesce`, `concat`, `replace`, `abs`, `round`, `ceil`, and `floor`:

```ruby
User.where(first_name: length.gt(3))
User.where(first_name: coalesce("Anonymous").eq("Anonymous"))
User.where(first_name: trim.lower.eq("alice"))
User.where(first_name: replace("-", " ").eq("Mary Jane"))
```

The column (or preceding function result) is the first argument; additional arguments follow it. Function availability and accepted argument types depend on your database.

### Extending ArelWhere

Call any other named SQL function with `function`:

```ruby
User.where(first_name: function("UNACCENT").lower.eq("jose"))
```

This example requires PostgreSQL's `unaccent` extension. For a frequently used expression, add your own helper to `AW`:

```ruby
# config/initializers/arel_where.rb
module AW
  def self.normalized_name
    function("UNACCENT").trim.lower
  end
end
```

```ruby
User.where(first_name: AW.normalized_name.eq("jose"))
```

Custom helpers return ordinary ArelWhere expressions, so predicates and boolean combinations still work. They use the explicit `AW` prefix; defining a helper does not add it to `ArelWhereRefine`.

### Building predicates in a block

`AW.build` makes the known predicate and function helpers available as bare words to
the receiver of the block. It preserves that receiver as `self`, including its instance
variables:

```ruby
class UserFilter
  def initialize(pattern)
    @pattern = pattern
  end

  def results
    AW.build { User.where(first_name: lower.matches(pattern)) }
  end

  private

  def pattern
    @pattern
  end
end
```

The block can call the receiver's private application methods as usual. By default,
`AW.build` rejects a receiver that already has one of the built-in helper names as a public,
protected, or private method, raising `AW::HelperCollisionError`. This includes methods
provided through the receiver's singleton class. Pass `override: true` when the block is
deliberately meant to override those methods for its duration:

```ruby
AW.build(override: true) { gt(18) }
```

Both builders return the block's result, including a relation that can be executed later.
Nested builds on the same receiver reuse the installed helpers; the original methods and
their visibility are restored when the outermost block exits, including when it raises.
Frozen receivers or singleton classes are rejected. Helpers defined by modules prepended
to the singleton class cannot be overridden, so those collisions raise even with
`override: true`. Do not freeze the receiver or change its helper methods during a build;
doing so can prevent restoration.

Helpers apply to the receiver for the whole execution of the block, including methods
called by the block and other code that uses that receiver concurrently. Overlapping builds
from another thread or fiber on the same receiver raise `AW::ContextInUseError`. Use
`AW.context` or explicit `AW` calls if receiver-wide scope is not acceptable.

Use `AW.context` when you want a separate helper receiver instead of changing the block's
receiver. The block then runs with a minimal `BasicObject`-based context:

```ruby
predicate = AW.context { gt(18).and(lt(65)) }
```

`AW.context` therefore does not expose the caller's `self` or instance variables. Both
builders expose the built-in helper set; custom helpers remain explicit `AW` calls.

### Other Arel expressions

Apply a predicate to an Arel column when building a query outside hash conditions:

```ruby
predicate = eq("Alice").or(eq("Bob"))
User.where(predicate.apply_to(User.arel_table[:first_name]))
```

## What loading the gem changes

### The PredicateBuilder patch

On load the gem prepends a module to `ActiveRecord::PredicateBuilder` that registers two
handlers:

- `AW::Expr` — the chains and junctions described above.
- `Proc` — a lambda receives the Arel attribute and returns a node.

The `Proc` handler is not scoped to this gem. Once the gem is loaded, every `where` in the
application accepts a lambda on the value side:

```ruby
Email.where(address: ->(attr) { attr.matches("%@example.com") })
```

If your application already passes a `Proc` as a `where` value for some other reason, that
value now builds a predicate instead of being quoted.

### The refinement is opt-in, and it refines Object

`ArelWhereRefine` is defined at load time but never activated for you. Where you do write
`using ArelWhereRefine`, note two things.

It refines `Object`. Inside that lexical scope, any receiver that does not already define a
refined method answers it with an `AW::Chain` rather than raising `NoMethodError`:

```ruby
using ArelWhereRefine

42.matches("x")   # => AW::Chain, not NoMethodError
"abc".overlaps(x) # => AW::Chain, not NoMethodError
```

Refinements lose to a receiver's own methods, so a class that defines `eq` or `lower` keeps
its own. The risk is the objects that define neither.

The refined method list is computed at load time from `Arel::Predications.instance_methods`
plus the function helpers and `function`. A predication added to Arel after this gem loads
is not in the list.

Ruby keeps a refinement on methods defined in the lexical scope where `using` appears. An
inherited method defined under `using ArelWhereRefine` therefore keeps the refinement when
called on a subclass. A method newly defined in that subclass, or in a reopened class scope,
does not acquire it automatically. A subclass's own method still wins over the refined
`Object` method.

### Namespace

The gem defines a top-level two-letter constant, `AW`, chosen so the hash values stay short
to read. It also defines `ArelWhereRefine`. If your application already owns a constant named
`AW`, this gem will collide with it.

## Comparison with wharel and baby_squeel

All three let you write Arel without building the nodes by hand. They differ in where the
Arel goes.

| | Form | Scope of the patch |
| --- | --- | --- |
| [wharel](https://github.com/shioyama/wharel) | Block DSL for relation clauses such as `where { age.gt(18) }`, plus `order`, `select`, `group`, `having`, `pluck`, and `pick` blocks | Adds block handling to the corresponding relation methods |
| [baby_squeel](https://github.com/rzane/baby_squeel) | Full block DSL, covering associations, joins, functions, and grouping | Extends relations, associations, and query building |
| arel_where | Ordinary hash condition, with a composable predicate on the value side: `where(age: AW.gt(18))` | Prepends one module to `ActiveRecord::PredicateBuilder` |

The practical differences:

- **The query keeps its hash shape.** `where(first_name: AW.matches("Ali%"))` merges, chains,
  and reads like the `where` next to it. `AW.build` and `AW.context` are optional builders
  for code that benefits from bare helper calls.
- **The patch surface is one class.** arel_where prepends `ActiveRecord::PredicateBuilder` and
  nothing else. wharel adds block handling to relation methods, while baby_squeel reaches
  further into relation, association, and grouping internals.
- **Bare words have explicit entry points.** `matches("Ali%")` without the `AW` prefix works
  in a file or module using `ArelWhereRefine`, or inside an `AW.build`/`AW.context` block.
- **Associations are out of scope.** baby_squeel can express joins and conditions across
  associations; arel_where deliberately stops at one column's predicate. Use ordinary Active
  Record joins, or `Relation#or`, for cross-column and cross-table logic.

### Using arel_where with wharel

wharel is optional and is not required by arel_where. The [published wharel 1.0.0
metadata](https://rubygems.org/gems/wharel) and the [upstream gemspec](https://github.com/shioyama/wharel/blob/master/wharel.gemspec)
currently target Active Record versions below 7, while arel_where supports Active Record 7
through 8. The examples below describe source-level interoperability; use a maintained
wharel fork or a future wharel release that supports your Active Record version before
adding it to an application. Pointing Bundler at the current upstream Git branch does not
resolve the dependency conflict.

```ruby
pattern = "Ali%"

AW.build do
  User.where(first_name: lower.matches(pattern))
      .order { first_name.lower.asc }
end

User.group { organisation_id }
    .having { id.count.gt(1) }
```

The outer `AW.build` block supplies value-side helpers while wharel's inner block supplies
Arel columns. For example, `lower` in the hash is an arel_where helper, whereas
`first_name.lower` in the ordering is an Arel expression. The inner block has its own
receiver and does not inherit the outer block's bare helpers. Ordinary hash calls to
`where` and `having` continue through arel_where's predicate handlers.

When changing the block's `self` is undesirable, pass the relation row explicitly. This
form keeps the surrounding caller context:

```ruby
User.order { |row| row.first_name.lower.asc }
```

## Development

Clone the repository, run `bundle install`, then `bundle exec rspec`. The suite needs a
PostgreSQL server; set `TEST_DATABASE_URL` if the default `postgresql:///postgres` is not
right for your machine.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/NicolasJJensen/arel_where.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
