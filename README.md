# arel_where

Write composable Arel predicates inside Active Record hash conditions and use Arel blocks for query clauses.

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

Requiring the gem (which Bundler does for you) enables hash predicate handlers and Arel
query blocks application wide. It does not activate the bare-word refinement or include
the helper mixins; those remain opt-in. See [What loading the gem changes](#what-loading-the-gem-changes).

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

Custom helpers return ordinary ArelWhere expressions, so predicates and boolean combinations still work. They use the explicit `AW` prefix; defining a helper does not add it to `ArelWhereRefine` or `AW::Helpers`.

### Including helpers in application classes

Include `AW::Helpers` to make bare predicate and function helpers available in instance
methods, including methods defined in subclasses. This uses normal Ruby inheritance and
does not require a refinement or a builder block:

```ruby
class ApplicationController < ActionController::Base
  include AW::Helpers
end

class UsersController < ApplicationController
  def index
    @users = User.where(first_name: lower.matches("nic%"))
  end
end
```

Use `extend AW::Helpers` for class methods and chainable Active Record query methods.
To enable both instance and class helpers with one declaration, include `AW::DSL`:

```ruby
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  include AW::DSL
end

class User < ApplicationRecord
  def self.matching_name(pattern)
    where(first_name: lower.matches(pattern))
  end
end

User.where(active: true).matching_name("nic%")
```

| Declaration | Helpers available in |
| --- | --- |
| `include AW::Helpers` | Instance methods |
| `extend AW::Helpers` | Class methods |
| `include AW::DSL` | Both instance and class methods |

Both kinds of helpers are inherited, including by methods newly defined in subclasses.
`AW::DSL` uses the same private helpers and normal method lookup as the separate declarations;
it does not change `self`, override methods defined directly on the class, or activate a
refinement. Include it directly in the application base class that needs both kinds of helpers.

Rails evaluates `scope` lambdas on a relation, which does not delegate private model
helpers. Use a class query method as above, or explicit `AW` calls inside a scope lambda:

```ruby
scope :matching_name, ->(pattern) { where(first_name: AW.lower.matches(pattern)) }
```

The helpers are private methods, intended for bare calls; they do not become public
controller actions. Use explicit `AW.lower`, `AW.gt`, etc. when calling from outside the
receiver. Neither module is included automatically. An application can explicitly enable
it globally in an initializer:

```ruby
Object.include(AW::Helpers)
```

Global inclusion makes the helpers available through `Object` inheritance, including to
class objects, and affects code throughout the application. Existing methods follow Ruby's
normal lookup rules: methods defined directly on a class win over an included module;
included helpers can shadow methods from its superclass. Use `prepend AW::Helpers` to
deliberately put helpers ahead of methods on that particular class. A subclass's own methods
still take precedence over helpers prepended to its superclass.

There is no collision check or automatic restoration for this persistent mixin. Once helpers
are included, call them directly; `AW.build` on that receiver detects them as existing
methods and requires `override: true`. The module exposes the same built-in helper set as
the refinement, including `function`; application-defined `AW` helpers remain explicit calls.

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

### Arel query blocks

The gem includes block queries adapted from [wharel](https://github.com/shioyama/wharel).
No separate wharel installation or fork is needed. They work alongside ordinary hash
conditions:

```ruby
User.where(first_name: AW.matches("Nic%"))
    .order { first_name.lower.asc }

User.where { first_name.matches("Nic%").or(last_name.matches("Nic%")) }
User.where.not { first_name.eq("Bob") }
User.where(active: true).or { first_name.eq("Nic") }
```

Blocks are supported by `where`, `where.not`, `or`, `order`, `select`, `group`, `having`,
`pluck`, and `pick`. Return an Arel expression for the receiving clause:

```ruby
User.select { first_name.lower.as("normalized_name") }
User.group { organisation_id }.having { id.count.gt(1) }.pluck(:organisation_id)
User.pluck { first_name.lower }
User.pluck { [id, first_name.lower] }
User.order(:id).pick { first_name.lower }
```

For `select`, `order`, `group`, `pluck`, and `pick`, return an array to supply multiple
expressions.

A block without parameters runs against a virtual row: `first_name` resolves to
`User.arel_table[:first_name]`, and `lower` is then an Arel method on that column. This is
column-based Arel, rather than the value-side `AW` helper API. Unknown column names raise
an error. Blocks do not create joins or resolve association names automatically.

For this zero-argument form, `self` changes, so caller instance variables and methods are
not available. Captured local variables and lexical constants still work. Give the block a
row parameter to preserve the original `self`, instance variables, and application methods:

```ruby
User.where { |row| row.first_name.matches(@pattern) }
User.order { |row| row.first_name.lower.asc }
```

The two block styles can also be combined with the existing helper builders:

```ruby
pattern = "nic%"

AW.build do
  User.where(first_name: lower.matches(pattern))
      .order { first_name.lower.asc }
end
```

The outer block supplies value-side helpers; the inner block supplies columns and has its
own receiver. It does not inherit the outer receiver's bare helpers.

For cross-table conditions, supply the join explicitly. A block can return another
relation, from which the gem extracts and combines the Arel constraints:

```ruby
Comment.joins(:post).where do |comment|
  Post.where { |post| comment.content.matches(post.title) }
end
```

This extracts conditions, not a subquery or the entire relation. The inner relation's joins,
ordering, selection, and limits are not imported. Standard Active Record structural
compatibility rules still apply to `or`.

Pass either normal arguments or a block to each query method. Passing both raises
`ArgumentError`; chain separate calls when both are needed. Calls without blocks continue
through Active Record normally.

`Relation#select` with a block now builds SQL selection rather than filtering Ruby records.
Use `relation.to_a.select { |record| ... }` for Ruby filtering, even if the relation is
already loaded.

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

### The block query patches

The gem prepends block handling to `ActiveRecord::Base` class methods,
`ActiveRecord::Relation`, and `ActiveRecord::QueryMethods::WhereChain`. This enables the
query blocks above application wide, including the changed meaning of `select` blocks.
It does not include `AW::Helpers` in application objects or activate the refinement.

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

## Relationship to wharel and baby_squeel

arel_where combines its value-side hash predicates with a block query interface adapted
from [wharel](https://github.com/shioyama/wharel). The integrated implementation targets
Active Record 7 through 8; wharel is not a runtime dependency and should not also be loaded
for this functionality.

Unlike the broader [baby_squeel](https://github.com/rzane/baby_squeel) association DSL,
these blocks expose the current model's columns. Use ordinary Active Record joins and
explicit Arel references for cross-table queries.

## Development

Clone the repository, run `bundle install`, then `bundle exec rspec`. The suite needs a
PostgreSQL server; set `TEST_DATABASE_URL` if the default `postgresql:///postgres` is not
right for your machine.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/NicolasJJensen/arel_where.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

The block query implementation in `lib/arel_where/block_queries.rb` is adapted from
[wharel by Chris Salzberg](https://github.com/shioyama/wharel/tree/3b9079ccb84afdaaeb5dfd9a23017531ab77c8de),
Copyright (c) 2018 Chris Salzberg. Its original MIT license is preserved in
[licenses/wharel-MIT.txt](licenses/wharel-MIT.txt) and included in the packaged gem.
