require "active_record"
require "arel_where/core"

module ArelWhereRefine
  refine Object do
    AW::KNOWN_METHODS.each do |method_name|
      if method_name == :function || AW::FUNCTIONS.include?(method_name)
        define_method(method_name) { |*args| AW.public_send(method_name, *args) }
      else
        define_method(method_name) { |*args| AW.__send__(:method_missing, method_name, *args) }
      end
    end
  end
end
