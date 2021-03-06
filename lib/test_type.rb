#
# == Test type definitions
#
# For each test type, optional callbacks can be specified. Even if no
# callbacks are needed, the test name must be registered and it must 
# have a corresponding database record in the kinds table.
#
# The setup callback is the first step for gathering test data, and is
# intended to be used to set up a form that registers the test. The setup
# callback accepts a single argument: the patient selected by the user
# for the test. The return value doesn't matter.
#
# All other callbacks MUST accept a vendor_test_plan, which should be
# returned by the assign callback. The return value doesn't matter.
#
# All callbacks are currently executed in controller context, so
# calls like redirect_to and params work as you'd expect.
#
class TestType
  attr_reader :name, :callback, :execution_paths
  alias_method :to_s, :name

  class AssignFailure < StandardError; end

  def initialize(name, &block)
    @name = name
    @callback = {}
    @execution_paths = []
    Registration.new(self, &block)
  end

  def to_param
    self.class.normalize_name(@name).gsub('-','_')
  end

  # Implement accessors for individual callbacks, e.g. assign_cb, setup_cb.
  #
  # Users should not use these callback directly. Instead use +perform+,
  # +assign+ or +setup+.
  def method_missing(method_name, *args)
    if method_name.to_s.match(/^(\w+)_cb$/)
      callback[$1.to_sym]
    else
      super
    end
  end

  # Get all of the registered test types.
  def self.all
    test_types.values
  end

  # Get the names of all of the registered test types.
  def self.names
    test_types.values.map(&:name)
  end

  # Define global callbacks by passing a block.
  #
  # Without a block, returns the currently defined global
  # callback registration.
  def self.global(&block)
    if block_given?
      @global_callbacks = new('_global_', &block)
    else
      @global_callbacks
    end
  end

  # Define shared operations by passing a block.
  # 
  # You can define execution steps and operations in a shared block
  # and include them in any test type using +
  def self.shared name, &block
    @shared_operations ||= {}
    if block_given?
      @shared_operations[ normalize_name name ] = block
    else
      @shared_operations[ normalize_name name ]
    end
  end

  # Get a registered test type given a name.
  # If there is no such test registered, returns nil.
  def self.get(type_name)
    test_types[ normalize_name(type_name) ]
  end

  # Register a new type type by passing a name and a Registration block.
  def self.register(name, &block)
    test_types[ normalize_name(name) ] = new(name, &block)
  end

  # Return the Kind instance that corresponds to the current test type.
  # This accessor is available in global callbacks.
  def kind
    @kind ||= Kind.find_by_display_name(name)
  end

  # Return a test type wrapper that automatically uses the included
  # context for non-global (e.g., test type-specific) callbacks. Use
  # it like this:
  #
  #  test_type.with_context(self).setup(vendor_test_plan)
  #
  # This is the preferred way to pass the callback context.
  def with_context(context)
    ActiveSupport::OptionMerger.new(self, :cb_context => context)
  end

  # Execute the setup callback. Accepts the patient selected by the user for
  # the test. This is just a wrapper around +perform+.
  def setup patient, opt = {}
    perform :setup, patient, opt
  end

  # Assign a test, returning a newly created vendor test plan.
  #
  # You must pass an options hash, which will be passed to the
  # global assign callback. Returns the result of that callback.
  #
  # Specify a non-global callback context with the option :cb_context.
  # This option will not be passed to the global callback.
  #
  # NOTE Rather than pass the context explicitly, you should use
  # with_context to create a wrapper that automatically passes
  # the context to every callback.
  def assign(opt)

    context = opt.delete(:cb_context)
    vendor_test_plan = nil

    begin
      Patient.transaction do
        # XXX currently still requires identically-named kinds in the database
        kind = Kind.find_by_display_name(name) || raise("No kind named #{name}")

        raise AssignFailure, "no global assign callback" if self.class.global.nil?

        vendor_test_plan = instance_exec(opt, &self.class.global.assign_cb)

        raise AssignFailure, "global assign returned nil" if vendor_test_plan.nil?
  
        if assign_cb
          if context
            begin
              context.instance_exec(vendor_test_plan, &assign_cb)
            rescue ActionController::DoubleRenderError
              # The controller needs to catch this error in case the second render
              # happens outside the callback, but this means a double render during
              # the callback would be ignored. Raise an AssignFailure instead.
              #
              # We're assuming that the passed context is the controller here.
              raise AssignFailure, "Test assignment failed: double render in callback"
            end
          else
            assign_cb.call(vendor_test_plan)
          end
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      # FIXME should be using record.class.human_name but
      # https://rails.lighthouseapp.com/projects/8994/tickets/2120
      raise AssignFailure, %{
        Failed to create #{e.record.class.name.underscore.humanize}:
        #{e.record.errors.full_messages.join("\n")}
      }
    rescue RuntimeError => e
      raise AssignFailure, "Test assignment failed: #{e}"
    end

    vendor_test_plan
  end

  # The perform method can be used to execute callbacks.
  #
  # Specify a callback context with the option :cb_context.
  #
  # NOTE Rather than pass the context explicitly, you should use
  # with_context to create a wrapper that automatically passes
  # the context to every callback.
  def perform(operation, test_data, opt = {})
    context = opt.delete(:cb_context)
    if callback[operation.to_sym] && !opt[:dry_run]
      if context
        begin
          context.instance_exec(test_data, &callback[operation.to_sym])
        rescue ActionController::DoubleRenderError
          raise AssignFailure, "Test assignment failed: double render in callback"
        end
      else
        callback[operation.to_sym].call(test_data)
      end
    end
  end

  private

  def self.test_types
    @test_types ||= {}
  end

  def self.normalize_name(name)
    name.strip.downcase.gsub('_','-').gsub(/\ba?nd?\b|&/i, '-and-').gsub(/\W+/, '-')
  end

  # Manage test type registration
  class Registration < ActiveSupport::BasicObject
    def initialize(test_type, &block)
      @test_type = test_type
      instance_eval(&block) if block_given?
    end

    def include_shared name
      instance_eval &TestType.shared(name)
    end

    def execution(*callback_names)
      @test_type.execution_paths << callback_names
    end

    def method_missing(method_name, &block)
      @test_type.callback[method_name.to_sym] = block
    end
  end
end

# In development mode this file can be reloaded, wiping the class instance
# var that stores the test_types global. In order to counter this we must
# re-register the test types manually when the TestType class gets reloaded.
load 'test_types.rb'
