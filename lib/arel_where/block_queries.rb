# Adapted from wharel by Chris Salzberg (MIT).
# https://github.com/shioyama/wharel/tree/3b9079ccb84afdaaeb5dfd9a23017531ab77c8de
# See licenses/wharel-MIT.txt for the original copyright and license.
require "active_record"

module AW
  class VirtualRow < BasicObject
    def initialize(model)
      @model = model
    end

    def method_missing(name, *args, &block)
      if args.empty? && !block && @model.column_names.include?(name.to_s)
        @model.arel_table[name]
      else
        super
      end
    end

    def self.build_query(model, &block)
      row = new(model)
      query = block.arity.zero? ? row.instance_exec(&block) : block.call(row)
      ::ActiveRecord::Relation === query ? query.arel.constraints.inject(&:and) : query
    end
  end

  module BlockQueryMethods
    %i[select where order having pluck pick group].each do |name|
      define_method(name) do |*args, **kwargs, &block|
        if block
          unless args.empty? && kwargs.empty?
            raise ArgumentError, "#{name} accepts arguments or an Arel block, not both"
          end
          query = VirtualRow.build_query(self, &block)
          if %i[select order group pluck pick].include?(name) && query.is_a?(Array)
            super(*query, &nil)
          else
            super(query, &nil)
          end
        else
          super(*args, **kwargs, &nil)
        end
      end
    end

    def or(*args, **kwargs, &block)
      return super(*args, **kwargs) unless block
      unless args.empty? && kwargs.empty?
        raise ArgumentError, "or accepts a relation or an Arel block, not both"
      end

      model = is_a?(ActiveRecord::Relation) ? klass : self
      super(model.where(VirtualRow.build_query(self, &block)), &nil)
    end
  end

  module BlockWhereChain
    def not(*args, **kwargs, &block)
      return super(*args, **kwargs) unless block
      unless args.empty? && kwargs.empty?
        raise ArgumentError, "not accepts arguments or an Arel block, not both"
      end

      super(VirtualRow.build_query(@scope, &block), &nil)
    end
  end

  private_constant :VirtualRow
end

ActiveSupport.on_load(:active_record) do
  singleton_class.prepend(AW::BlockQueryMethods)
  ActiveRecord::Relation.prepend(AW::BlockQueryMethods)
  ActiveRecord::QueryMethods::WhereChain.prepend(AW::BlockWhereChain)
end
