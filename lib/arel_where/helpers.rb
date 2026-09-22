require "arel_where/core"

module AW
  module Helpers
    KNOWN_METHODS.each do |name|
      if name == :function || FUNCTIONS.include?(name)
        define_method(name) { |*args| AW.public_send(name, *args) }
      else
        # Global inclusion also gives AW these methods; dispatch predicates directly.
        define_method(name) { |*args| Chain.new.public_send(name, *args) }
      end
    end

    private(*KNOWN_METHODS)
  end
end
