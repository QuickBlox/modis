# frozen_string_literal: true

module Modis
  module Attribute
    TYPES = { string: [String],
              integer: [0.class],
              float: [Float],
              timestamp: [Time],
              hash: [Hash],
              array: [Array],
              boolean: [TrueClass, FalseClass] }.freeze

    def self.included(base)
      base.extend ClassMethods
      base.instance_eval do
        bootstrap_attributes

        define_method(:attributes) do
          attrs = {}
          self.class.attributes.each_key do |key|
            attrs[key] = instance_variable_get("@#{key}")
          end
          attrs
        end
      end
    end

    module ClassMethods
      def bootstrap_attributes(parent = nil)

        class << self
          attr_accessor :attributes, :attributes_with_defaults
        end

        self.attributes = parent ? parent.attributes.dup : {}
        self.attributes_with_defaults = parent ? parent.attributes_with_defaults.dup : {}

        attribute :id, :integer unless parent
      end

      def attribute(name, type, options = {})
        name = name.to_s
        raise AttributeError, "Attribute with name '#{name}' has already been specified." if @attributes.key?(name)

        type_classes = Array(type).map do |t|
          raise UnsupportedAttributeType, t unless TYPES.key?(t)
          TYPES[t]
        end.flatten

        @attributes[name] = options.update(type: type)
        @attributes_with_defaults[name] = options[:default]
        define_attribute_methods([name])

        value_coercion = type == :timestamp ? 'value = Time.new(*value) if value && value.is_a?(Array) && value.count == 7' : nil
        predicate = type_classes.map { |cls| "value.is_a?(#{cls.name})" }.join(' || ')

        type_check = <<-RUBY
        if value && !(#{predicate})
          raise Modis::AttributeCoercionError, "Received value of type '\#{value.class}', expected '#{type_classes.join("', '")}' for attribute '#{name}'."
        end
        RUBY

        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def #{name}
            @#{name}
          end

          def #{name}=(value)
            #{value_coercion}

            # ActiveSupport's Time#<=> does not perform well when comparing with NilClass.
            if (value.nil? ^ @#{name}.nil?) || (value != @#{name})
              #{type_check}
              #{name}_will_change!
              @#{name} = value
            end
          end
        RUBY
      end
    end

    def assign_attributes(hash)
      hash.each do |key, value|
        instance_variable_set("@#{key}", value)
      end
    end

    def write_attribute(key, value)
      instance_variable_set("@#{key}", value)
    end

    def read_attribute(key)
      instance_variable_get("@#{key}")
    end

    protected

    def set_sti_type
      return unless self.class.sti_child?
      write_attribute(:type, self.class.name)
    end

    def reset_changes
      @changed_attributes = nil
    end

    def apply_defaults
      self.class.attributes_with_defaults.each do |key, value|
        instance_variable_set("@#{key}", value)
      end
    end
  end
end
