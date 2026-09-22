require "arel_where/helpers"

module AW
  module DSL
    include Helpers

    def self.included(base)
      base.extend(Helpers)
    end
  end
end
