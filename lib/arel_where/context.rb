require "arel_where/helpers"

module AW
  class HelperCollisionError < ArgumentError; end
  class ContextInUseError < RuntimeError; end

  class Context < BasicObject
    include ::AW::Helpers
    public(*::AW::KNOWN_METHODS)
  end

  class HelperScope
    @active = {}.compare_by_identity
    @mutex = Mutex.new

    class << self
      def enter(receiver, override:)
        @mutex.synchronize do
          if (scope = @active[receiver])
            unless scope.owner == [Thread.current, Fiber.current]
              raise ContextInUseError, "AW.with_helpers is already active on this receiver in another thread or fiber"
            end
            scope.depth += 1
          else
            scope = new(receiver, override: override)
            scope.install
            @active[receiver] = scope
          end
          scope
        end
      end

      def leave(receiver, scope)
        @mutex.synchronize do
          scope.depth -= 1
          if scope.depth.zero?
            begin
              scope.restore
            ensure
              @active.delete(receiver)
            end
          end
        end
      end
    end

    attr_reader :owner
    attr_accessor :depth

    def initialize(receiver, override:)
      raise FrozenError, "AW.with_helpers cannot install helpers on a frozen receiver" if receiver.frozen?

      @singleton = receiver.singleton_class
      raise FrozenError, "AW.with_helpers cannot install helpers on a frozen singleton class" if @singleton.frozen?

      @owner = [Thread.current, Fiber.current]
      @depth = 1
      @installed = []
      @originals = {}

      collisions = KNOWN_METHODS.select do |name|
        @singleton.method_defined?(name) || @singleton.private_method_defined?(name) || receiver.respond_to?(name, true)
      end
      unless override || collisions.empty?
        raise HelperCollisionError, "AW.with_helpers helpers already exist: #{collisions.sort.join(', ')}; use override: true or AW.build"
      end

      # Singleton methods cannot override modules prepended ahead of the singleton class.
      prepended = @singleton.ancestors.take_while { |ancestor| ancestor != @singleton }
      if prepended.any? { |mod| KNOWN_METHODS.any? { |name| mod.method_defined?(name) || mod.private_method_defined?(name) } }
        raise HelperCollisionError, "AW.with_helpers cannot override prepended helpers; use AW.build"
      end

      KNOWN_METHODS.each do |name|
        visibility = %i[public protected private].find do |access|
          @singleton.public_send("#{access}_instance_methods", false).include?(name)
        end
        method = begin
          @singleton.instance_method(name)
        rescue NameError
          nil
        end
        @originals[name] = [visibility, method]
      end
    end

    def install
      KNOWN_METHODS.each do |name|
        @installed << name
        @singleton.define_method(name, Helpers.instance_method(name))
        @singleton.__send__(:public, name)
      end
    rescue Exception
      restore
      raise
    end

    def restore
      @installed.reverse_each do |name|
        visibility, method = @originals.fetch(name)
        if visibility
          @singleton.define_method(name, method)
          @singleton.__send__(visibility, name)
        else
          @singleton.remove_method(name)
          # Preserve an undef_method barrier rather than exposing an inherited method.
          if method.nil? && (@singleton.method_defined?(name) || @singleton.private_method_defined?(name))
            @singleton.undef_method(name)
          end
        end
      end
      @installed.clear
    end
  end

  private_constant :Context, :HelperScope

  def self.with_helpers(override: false, &block)
    raise ArgumentError, "AW.with_helpers requires a block" unless block

    receiver = block.binding.receiver
    scope = HelperScope.enter(receiver, override: override)
    begin
      block.call
    ensure
      HelperScope.leave(receiver, scope)
    end
  end

  def self.build(&block)
    raise ArgumentError, "AW.build requires a block" unless block

    context = Context.new
    block.arity.zero? ? context.instance_exec(&block) : block.call(context)
  end
end
