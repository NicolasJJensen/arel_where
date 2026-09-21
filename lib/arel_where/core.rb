# Arel predicates inside where hashes
#
# Usage (see README.md for details):
#   User.where(age: AW.gt(18).and(AW.lt(65)))
#   using ArelWhereRefine; User.where(status: eq('active').or(eq('pending')))
#
# Notes:
# - `and`/`or` combine expressions over the same attribute. Passing a raw
#   Arel node for another column “works” but is discouraged; prefer top‑level
#   Arel or `Relation#or` for cross‑column logic.
# - Non‑Arel arguments are safely quoted via Arel.
require "active_record"

module AW
  FUNCTIONS = %i[lower upper length trim coalesce concat replace abs round ceil floor].freeze

  # The only names a chain may hold. Computed once at load time, so a predication
  # added to Arel after this file loads is not reachable. Unknown names raise at
  # the call site instead of building a chain that fails later inside `apply_to`.
  KNOWN_METHODS = (Arel::Predications.instance_methods(true) + FUNCTIONS + [:function]).uniq.freeze

  module_function

    def quote(v)
      v.is_a?(Arel::Nodes::Node) ? v : Arel::Nodes.build_quoted(v)
    end

  # Base expr type for handler
  class Expr
    # boolean combinators (work with other chains/exprs)
    def and(other) = Junction.new(:and, self, AW.to_expr(other))
    def or(other)  = Junction.new(:or,  self, AW.to_expr(other))
  end

  # Captures a chain of method calls to be applied to the attribute later
    class Chain < Expr
      def initialize(steps = []) = (@steps = steps.freeze)

      Arel::Predications.instance_methods(true).each do |name|
        define_method(name) { |*args| Chain.new(@steps + [[name, args]]) }
      end

      def method_missing(name, *args, &block)
        return super unless KNOWN_METHODS.include?(name)
        Chain.new(@steps + [[name, args]])
      end
      def function(name, *arguments)
        unless name.to_s.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
          raise ArgumentError, "function name must be a SQL identifier"
        end
        Chain.new(@steps + [[:__function__, [name.to_s, *arguments]]])
      end

      FUNCTIONS.each do |name|
        define_method(name) { |*arguments| function(name.to_s.upcase, *arguments) }
      end

      def respond_to_missing?(name, include_private = false)
        KNOWN_METHODS.include?(name) || super
      end

      # Guard against AR probing values with `.id` (treat as no-op)
      def id = self

      def apply_to(attr)
        node = attr
        @steps.each do |(name, args)|
          # Pass raw args through to Arel/AR for proper casting/binding.
          node = if name == :__function__
            function_name, *arguments = args
            operands = arguments.map { |value| value.is_a?(Expr) ? value.apply_to(attr) : Arel::Nodes.build_quoted(value) }
            Arel::Nodes::NamedFunction.new(function_name, [node, *operands])
          else
            node.public_send(name, *args)
          end
        end
        node
      end

    # nice to have if someone does &Chain
    def to_proc = ->(attr) { apply_to(attr) }
  end

  # Represents (left AND/OR right) over the **same** attribute
    class Junction < Expr
    def initialize(op, left, right)
      @op, @left, @right = op, left, right
    end

      def apply_to(attr)
        l = @left.apply_to(attr)
        r = @right.apply_to(attr)
        case @op
        when :and then Arel::Nodes::And.new([l, r])
        when :or  then l.or(r)
        end
      end
    end

  def function(name, *arguments) = Chain.new.function(name, *arguments)
  FUNCTIONS.each do |name|
    define_method(name) { |*arguments| Chain.new.function(name.to_s.upcase, *arguments) }
    module_function name
  end

  # Start a chain for any known predication (lt, gt, eq, matches, overlaps, ...)
  def method_missing(name, *args, &block)
    return super unless KNOWN_METHODS.include?(name)
    Chain.new([[name, args]])
  end
  def respond_to_missing?(name, include_private = false)
    KNOWN_METHODS.include?(name) || super
  end

  # Coerce helper for boolean combinators
  def to_expr(obj)
    case obj
    when Expr                 then obj
    when Proc                 then ProcExpr.new(obj) # optional (see below)
    when Arel::Nodes::Node    then NodeExpr.new(obj) # optional
    else                            Chain.new([[:eq, [obj]]]) # fallback equality
    end
  end

  # Optional: allow composing with arbitrary procs or ready-made Arel nodes
  class ProcExpr < Expr
    def initialize(pr) = (@pr = pr)
    def apply_to(attr) = @pr.call(attr)
  end

  class NodeExpr < Expr
    def initialize(node) = (@node = node)
    # If it doesn't depend on the attribute, just return the node
    def apply_to(_attr) = @node
  end
end
