# arel_where

Build filters inside ordinary Active Record hashes, then use Arel blocks for ordering,
selection, grouping, and other query clauses.

## Installation

Add the gem to your application's Gemfile and run `bundle install`:

```ruby
gem "arel_where"
```

Requires Ruby 3.1+ and Active Record 7.0 through 8.x. The test suite covers Active Record
7.0, 7.1, 7.2, 8.0, and 8.1.

Loading the gem enables its query extensions application wide. Two changes to existing
Active Record behavior are worth knowing before using it:

- `relation.select { ... }` builds SQL selection. For Ruby record filtering, use
  `relation.to_a.select { |record| ... }`.
- A `Proc` used as a hash condition's value receives the Arel column and builds a predicate.

Calls without blocks otherwise keep their normal Active Record behavior. The shorthand
options described later are not enabled automatically.

## Quick start

Use `AW` for filters and a block for expressions in other query clauses:

```ruby
User.where(first_name: AW.matches("nic%"))
    .order { first_name.lower.asc }
```

The hash key tells `AW.matches("nic%")` which column to filter. In the ordering block,
`first_name` refers directly to the model's Arel column; `lower.asc` orders by its lowercase
value. These blocks are built into this gem, so no separate wharel installation is needed.

The examples assume your Rails application has the models and columns shown. No optional
helper setup is needed for the examples in the next two sections.

## Filtering with hash conditions

### Predicates

Each `AW` expression applies to the column named by its hash key:

```ruby
User.where(first_name: AW.eq("Alice"))
User.where(first_name: AW.matches("Ali%"))
User.where(date_of_birth: AW.lt(Date.new(2000, 1, 1)))
User.where(last_name: AW.not_eq(nil))
```

The predicate methods come from `Arel::Predications`, including `eq`, `not_eq`, `gt`,
`gteq`, `lt`, `lteq`, `in`, and `matches`. Unknown helper names raise `NoMethodError` at the
call site:

```ruby
User.where(first_name: AW.mathces("Ali%")) # Typo: raises NoMethodError
```

### Combining conditions on one column

Use `and` and `or` to combine predicates for the same hash key:

```ruby
User.where(first_name: AW.eq("Alice").or(AW.eq("Bob")))
User.where(date_of_birth: AW.gteq(Date.new(1990)).and(AW.lt(Date.new(2000))))
```

Different hash keys remain ordinary Active Record conditions joined with AND:

```ruby
User.where(first_name: AW.matches("Ali%"), active: true)
```

### SQL functions

Function helpers transform the column before applying a predicate:

```ruby
User.where(first_name: AW.lower.eq("alice"))
User.where(last_name: AW.upper.matches("SM%"))
User.where(first_name: AW.length.gt(3))
User.where(first_name: AW.trim.lower.eq("alice"))
User.where(first_name: AW.coalesce("Anonymous").eq("Anonymous"))
User.where(first_name: AW.replace("-", " ").eq("Mary Jane"))
```

Built-in function helpers are `lower`, `upper`, `length`, `trim`, `coalesce`, `concat`,
`replace`, `abs`, `round`, `ceil`, and `floor`. The column—or preceding function result—is
the first SQL argument; any supplied arguments follow it. Function availability and
accepted argument types depend on the database.

## Ordering and other Arel query blocks

Inside a query block, column names return actual Arel columns. For example,
`first_name.lower` calls Arel's `lower` method on `User.arel_table[:first_name]`.
This differs from `AW.lower`, which waits for a hash key to supply the column. The built-in
`AW` function list does not imply that every Arel column has those same methods.

```ruby
User.order { first_name.lower.asc }
User.select { first_name.lower.as("normalized_name") }
User.group { organisation_id }.having { id.count.gt(1) }.pluck(:organisation_id)
User.pluck { first_name.lower }
User.pluck { [id, first_name.lower] }
User.order(:id).pick { first_name.lower }
```

For `select`, `order`, `group`, `pluck`, and `pick`, return an array to supply multiple
expressions. Pass either normal arguments or a block to a query method; passing both raises
`ArgumentError`. Chain separate calls when both are needed.

Remember that a `select` block builds SQL, even on an already loaded relation. Use
`relation.to_a.select { |record| ... }` to filter records in Ruby.

### Accessing application state inside a query block

With no block parameter, `self` becomes a separate column lookup object, called a virtual
row. Caller instance variables and methods are unavailable, but local variables remain
accessible:

```ruby
pattern = "nic%"
User.where { first_name.lower.matches(pattern) }
```

To keep the caller's `self`, give the block a row parameter and access columns through it:

```ruby
class UserSearch
  def initialize(pattern)
    @pattern = pattern
  end

  def results
    User.where { |row| row.first_name.lower.matches(@pattern) }
  end
end
```

### Filtering with Arel blocks

Hash predicates remain available alongside blocks. Blocks also support `where`,
`where.not`, and `or`, which can be useful for conditions spanning several columns:

```ruby
User.where { first_name.matches("Nic%").or(last_name.matches("Nic%")) }
User.where.not { first_name.eq("Bob") }
User.where(active: true).or { first_name.eq("Nic") }
```

Unknown column names raise an error. Blocks do not create joins or resolve association
names automatically. Cross-table examples are covered under [Advanced usage](#advanced-usage).

## Optional shorthand for hash predicates

Explicit `AW` calls always work without additional setup. The following options let you
shorten those calls in a block, an application class, or a file. Choose the form that fits
where you write queries; you do not need to enable all of them.

### A helper block: AW.build

Without a block parameter, `AW.build` runs against a separate helper object. Bare calls
such as `lower` and `gt` produce the same expressions as `AW.lower` and `AW.gt`:

```ruby
pattern = "nic%"

AW.build do
  User.where(first_name: lower.matches(pattern))
      .order { first_name.lower.asc }
end
```

Local variables remain available, but caller instance variables and methods do not. The
inner `order` block has its own column lookup object: `lower` in the hash is a predicate
helper, while `first_name.lower` in the ordering is an Arel column expression.

Give `AW.build` a block parameter to preserve your original `self` and call the helpers
explicitly on that parameter:

```ruby
class UserFilter
  def initialize(pattern)
    @pattern = pattern
  end

  def results
    AW.build do |aw|
      User.where(first_name: aw.lower.matches(@pattern), id: aw.gt(minimum_id))
    end
  end

  private

  def minimum_id
    0
  end
end
```

Here, `@pattern` and `minimum_id` belong to `UserFilter`, while `aw` supplies the expression
helpers. Neither form installs methods on the caller. Both return the block's result,
including a relation that can be executed later.

### Helpers in application classes

`AW::Helpers` supplies private predicate and function methods. `include` makes them
available inside instance methods, such as controller actions:

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

`extend` makes them available inside class methods, such as model query methods:

```ruby
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  extend AW::Helpers
end

class User < ApplicationRecord
  def self.matching_name(pattern)
    where(first_name: lower.matches(pattern))
  end
end

User.where(active: true).matching_name("nic%")
```

The `def self.matching_name` method runs on the model class, where `lower` is available.
It returns a relation, so it can be chained with other Active Record queries.

To enable both instance and class helpers with one declaration, include `AW::DSL`:

```ruby
class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class
  include AW::DSL
end
```

| Declaration | Helpers available in |
| --- | --- |
| `include AW::Helpers` | Instance methods |
| `extend AW::Helpers` | Class methods |
| `include AW::DSL` | Both |

Both kinds are inherited, including by methods newly defined in subclasses. Helpers stay
private, so they do not become public controller actions. These declarations do not change
`self`, and methods defined directly on the class take precedence over included helpers.

### Model query methods versus Rails scope lambdas

Adding helpers to a model class does not add them to every object used to build its queries.
In particular, Rails runs a `scope` lambda on an `ActiveRecord::Relation`, not on the model
class. That relation does not forward calls to the model's private helpers.

These are two alternative ways to define the same query. A model class method can use the
helpers supplied by `extend AW::Helpers`:

```ruby
class User < ApplicationRecord
  extend AW::Helpers

  def self.matching_name(pattern)
    where(first_name: lower.matches(pattern))
  end
end
```

If you prefer Rails' `scope` declaration, use `AW.lower` explicitly inside the lambda.
This version needs no helper mixin:

```ruby
class User < ApplicationRecord
  scope :matching_name, ->(pattern) {
    where(first_name: AW.lower.matches(pattern))
  }
end
```

Both alternatives support `User.matching_name("nic%")` and can be chained with `where`.
With only model helpers enabled, changing `AW.lower` to bare `lower` in that scope lambda
would raise `NameError`.

### File- or class-scoped helpers: ArelWhereRefine

Ruby refinements provide another way to enable bare calls. Put `using ArelWhereRefine`
at the top of a file or inside a class or module, before the code that needs the helpers:

```ruby
using ArelWhereRefine

User.where(first_name: lower.matches("nic%"))
```

A refinement applies to calls written in that scope; it does not permanently add helpers
to application objects. An inherited method defined in a refined scope keeps that behavior.
A method newly defined in a subclass, or in a reopened class, needs its own enclosing
`using` declaration. Unlike the mixins, refinement activation is not inherited by new code.

### Temporary helpers on the original caller: AW.with_helpers

`AW.with_helpers` keeps the caller's `self` and temporarily installs bare helper methods:

```ruby
class UserFilter
  def initialize(pattern)
    @pattern = pattern
  end

  def results
    AW.with_helpers do
      User.where(first_name: lower.matches(@pattern))
          .order { first_name.lower.asc }
    end
  end
end
```

Existing helper-name methods cause `AW::HelperCollisionError`. Use `override: true` only
when you intend to replace those methods temporarily:

```ruby
AW.with_helpers(override: true) { gt(18) }
```

Original methods are restored when the block exits, including after an exception. During
the block, other code using that same receiver can see the temporary helpers too. This is
a broader effect than the isolated helper object provided by `AW.build`.

| Form | Where helper calls are resolved |
| --- | --- |
| `AW.build { lower }` | A separate helper object |
| `AW.build { \|aw\| aw.lower }` | An explicit helper object; original `self` is retained |
| `AW.with_helpers { lower }` | Temporary methods on the original caller; rejects collisions |
| `AW.with_helpers(override: true) { lower }` | Temporary methods on the original caller; overrides conflicts |

## Advanced usage

### Custom functions and helpers

Use `AW.function` for another named SQL function:

```ruby
User.where(first_name: AW.function("UNACCENT").lower.eq("jose"))
```

This example requires PostgreSQL's `unaccent` extension. For a frequently used expression,
add a helper to `AW`:

```ruby
# config/initializers/arel_where.rb
module AW
  def self.normalized_name
    function("UNACCENT").trim.lower
  end
end

User.where(first_name: AW.normalized_name.eq("jose"))
```

Custom helpers return ordinary expressions, but remain explicit `AW` calls. Adding one
does not automatically add it to the refinement, mixins, or builder helper objects.

### Applying an expression to an Arel column

Use `apply_to` when an existing `AW` expression needs an explicit Arel column:

```ruby
predicate = AW.eq("Alice").or(AW.eq("Bob"))
User.where(predicate.apply_to(User.arel_table[:first_name]))
```

### Conditions across joined tables

Supply joins with ordinary Active Record methods. In this example, assume `Comment`
belongs to `Post` through `:post`. The inner query provides a convenient column lookup
object for the posts table; the returned relation contributes its conditions to the outer
query:

```ruby
Comment.joins(:post).where do |comment|
  Post.where { |post| comment.content.matches(post.title) }
end
```

This compares each joined comment's content with its post's title. It extracts Arel
constraints from the inner relation, rather than creating a subquery or importing the
whole relation. Inner joins, ordering, selection, and limits are not imported. Standard
Active Record structural compatibility rules still apply when combining relations with `or`.

### Global helpers and method precedence

An application can opt into helpers throughout `Object`'s inheritance tree:

```ruby
# config/initializers/arel_where.rb
Object.include(AW::Helpers)
```

This also reaches class objects and affects code throughout the application. Nothing
includes the helpers globally by default.

Normal Ruby method lookup applies: methods defined directly on a class win over an
included module, while included helpers can shadow superclass methods. Use
`prepend AW::Helpers` to intentionally place helpers ahead of methods on that particular
class. A subclass's own methods still take precedence over helpers prepended to its parent.

Mixins have no collision checks or automatic restoration. A receiver that already has
helpers will trigger `AW.with_helpers`' collision check; normally, use its existing helpers
directly instead.

### Temporary helper restrictions

`AW.with_helpers` checks public, protected, and private method names. Nested calls on the
same receiver reuse the installed helpers, restoring original methods and visibility when
the outermost call exits.

Frozen receivers or singleton classes cannot be modified. Helpers in modules prepended to
the singleton class cannot be overridden, even with `override: true`. Do not freeze the
receiver or redefine its helper methods during a block; doing so can prevent restoration.

Overlapping calls from another thread or fiber on the same receiver raise
`AW::ContextInUseError`. Other ordinary code using that receiver concurrently can still see
the temporary helpers. Use `AW.build` or explicit `AW` calls when that scope is unsuitable.
`AW.build` can be used from frozen receivers and does not accept `override: true`.

### Refinement scope and method precedence

`ArelWhereRefine` refines `Object`. Within an enabled scope, unrelated objects without their
own matching method can also resolve predicate helpers:

```ruby
using ArelWhereRefine

42.matches("x") # Returns an AW::Chain
```

Methods on subclasses take precedence over the refinement of `Object`. For example, a
class defining its own `lower` keeps that method. The helper names are computed when the
gem loads from Arel predicates and the built-in functions; predicates added to Arel later
are not automatically included.

### Application-wide integration

On load, the gem prepends handlers to `ActiveRecord::PredicateBuilder` for `AW::Expr`
expressions and `Proc` values. The latter enables callbacks such as:

```ruby
Email.where(address: ->(column) { column.matches("%@example.com") })
```

Any existing `Proc` hash value is consequently interpreted as a predicate callback.
Block handling is also prepended to `ActiveRecord::Base` class methods,
`ActiveRecord::Relation`, and `ActiveRecord::QueryMethods::WhereChain`. This includes the
changed meaning of `select` blocks described during installation.

The gem defines top-level `AW` and `ArelWhereRefine` constants. An application that already
uses either name must resolve that conflict.

## Development

Run `bundle install`, then `bundle exec rspec`. The suite needs PostgreSQL. Set
`TEST_DATABASE_URL` if the default `postgresql:///postgres` is not suitable.

## Contributing

Bug reports and pull requests are welcome at
[the GitHub repository](https://github.com/NicolasJJensen/arel_where).

## Attribution and license

arel_where is available under the [MIT License](LICENSE.txt).

The block query implementation in `lib/arel_where/block_queries.rb` is adapted from
[wharel by Chris Salzberg](https://github.com/shioyama/wharel/tree/3b9079ccb84afdaaeb5dfd9a23017531ab77c8de),
Copyright (c) 2018 Chris Salzberg. Its original MIT license is preserved in
[licenses/wharel-MIT.txt](licenses/wharel-MIT.txt) and included in the packaged gem.
Wharel is not a runtime dependency and should not also be loaded for this functionality.
