require "active_record"
require "arel_where/core"

module AW
  module PredicateBuilderPatch
    def initialize(table)
      super
      register_handler(AW::Expr, ->(arel_attr, expr) { expr.apply_to(arel_attr) })
      register_handler(Proc, ->(arel_attr, fn) { fn.call(arel_attr) })
    end
  end
end

ActiveSupport.on_load(:active_record) do
  ActiveRecord::PredicateBuilder.prepend(AW::PredicateBuilderPatch)
end
