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

The refinement only affects that lexical scope. The gem loads it but never activates it for you. The examples below use the refinement; you can always use the equivalent `AW` calls instead.

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

### Namespace

The gem defines a top-level two-letter constant, `AW`, chosen so the hash values stay short
to read. It also defines `ArelWhereRefine`. If your application already owns a constant named
`AW`, this gem will collide with it.

## Comparison with wharel and baby_squeel

All three let you write Arel without building the nodes by hand. They differ in where the
Arel goes.

| | Form | Scope of the patch |
| --- | --- | --- |
| [wharel](https://github.com/hzamani/wharel) | Block DSL: `where { age > 18 }`, with the model's Arel attributes exposed as bare names inside the block | Adds `where`/`having` block handling to relations |
| [baby_squeel](https://github.com/rzane/baby_squeel) | Full block DSL, covering associations, joins, functions, and grouping | Extends relations, associations, and query building |
| arel_where | Ordinary hash condition, with a composable predicate on the value side: `where(age: AW.gt(18))` | Prepends one module to `ActiveRecord::PredicateBuilder` |

The practical differences:

- **The query keeps its hash shape.** `where(first_name: AW.matches("Ali%"))` merges, chains,
  and reads like the `where` next to it. There is no block, so no separate scope with its own
  rules about what `self` means.
- **The patch surface is one class.** arel_where prepends `ActiveRecord::PredicateBuilder` and
  nothing else. wharel and baby_squeel reach further into relation and association internals.
- **Bare words are opt-in and lexical.** `matches("Ali%")` without the `AW` prefix only works
  where you wrote `using ArelWhereRefine`, and only in that file or module.
- **Associations are out of scope.** baby_squeel can express joins and conditions across
  associations; arel_where deliberately stops at one column's predicate. Use ordinary Active
  Record joins, or `Relation#or`, for cross-column and cross-table logic.

## Development

Clone the repository, run `bundle install`, then `bundle exec rspec`. The suite needs a
PostgreSQL server; set `TEST_DATABASE_URL` if the default `postgresql:///postgres` is not
right for your machine.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/NicolasJJensen/arel_where.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
