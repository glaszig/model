# frozen_string_literal: true

require "rom/configuration"
require "hanami/utils/blank"
require "hanami/model/repository_configurer"

module Hanami
  module Model
    # Configuration for the framework, models and adapters.
    #
    # Hanami::Model has its own global configuration that can be manipulated
    # via `Hanami::Model.configure`.
    #
    # @since 0.2.0
    class Configuration
      # @since 0.7.0
      # @api private
      attr_reader :mappings

      # @since 0.7.0
      # @api private
      attr_reader :entities

      # @since 1.0.0
      # @api private
      attr_reader :logger

      # @since 1.0.0
      # @api private
      attr_reader :migrations_logger

      # @since x.x.x
      # @api private
      attr_reader :inflector

      # @since 0.2.0
      # @api private
      def initialize(configurator) # rubocop:disable Metrics/MethodLength
        @backend = configurator.backend
        @url = configurator.url
        @container         = nil
        @migrations        = configurator._migrations
        @schema            = configurator._schema
        @gateway_config    = configurator._gateway
        @logger            = configurator._logger
        @migrations_logger = configurator.migrations_logger
        @inflector         = configurator.inflector
        @mappings          = {}
        @entities          = {}
      end

      def container
        @container or raise "not loaded"
      end

      # NOTE: This must be changed when we want to support several adapters at the time
      #
      # @raise [Hanami::Model::UnknownDatabaseAdapterError] if @url is blank
      #
      # @since 0.7.0
      # @api private
      def url
        raise Hanami::Model::UnknownDatabaseAdapterError.new(@url) if Utils::Blank.blank?(@url)

        @url
      end

      # NOTE: This must be changed when we want to support several adapters at the time
      #
      # @raise [Hanami::Model::UnknownDatabaseAdapterError] if `url` is blank,
      #   or it uses an unknown adapter.
      #
      # @since 0.7.0
      # @api private
      def connection
        gateway.connection
      end

      # NOTE: This must be changed when we want to support several adapters at the time
      #
      # @raise [Hanami::Model::UnknownDatabaseAdapterError] if `url` is blank,
      #   or it uses an unknown adapter.
      #
      # @since 0.7.0
      # @api private
      def gateway
        gateways[:default]
      end

      # Root directory
      #
      # @since 0.4.0
      # @api private
      def root
        Hanami.respond_to?(:root) ? Hanami.root : Pathname.pwd
      end

      # Migrations directory
      #
      # @since 0.4.0
      def migrations
        (@migrations.nil? ? root : root.join(@migrations)).realpath
      end

      # Path for schema dump file
      #
      # @since 0.4.0
      def schema
        @schema.nil? ? root : root.join(@schema)
      end

      # @since 0.7.0
      # @api private
      def define_mappings(root, &blk)
        @mappings[root] = Mapping.new(&blk)
      end

      # @since 0.7.0
      # @api private
      def register_entity(plural, singular, klass)
        @entities[plural]   = klass
        @entities[singular] = klass
      end

      # @since 0.7.0
      # @api private
      def define_entities_mappings(container, repositories)
        return unless defined?(Sql::Entity::Schema)

        repositories.each do |r|
          relation = r.relation
          entity   = r.entity

          entity.schema = Sql::Entity::Schema.new(entities, container.relations[relation], mappings.fetch(relation))
        end
      end

      # @since 1.0.0
      # @api private
      def configure_gateway
        @gateway_config&.call(gateway)
      end

      # @since 1.0.0
      # @api private
      def logger=(value)
        return if value.nil?

        gateway.use_logger(@logger = value)
      end

      # @raise [Hanami::Model::UnknownDatabaseAdapterError] if `url` is blank,
      #   or it uses an unknown adapter.
      #
      # @since 1.0.0
      # @api private
      def rom
        @rom ||= ROM::Configuration.new(@backend, url)
      end

      # @raise [Hanami::Model::UnknownDatabaseAdapterError] if `url` is blank,
      #   or it uses an unknown adapter.
      #
      # @since 1.0.0
      # @api private
      #
      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/MethodLength
      def load!(repositories, &blk)
        rom.setup.auto_registration(config.directory.to_s) unless config.directory.nil?
        rom.instance_eval(&blk)                            if     block_given?
        configure_gateway
        configure_repositories(repositories)
        self.logger = logger

        # FIXME: without "touching" the db, inferrer crashes on sqlite, wtf?
        gateway.connection.tables

        @container = ROM.container(rom)
        define_entities_mappings(@container, repositories)
        @container
      rescue => e
        raise Hanami::Model::Error.for(e)
      end
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/AbcSize

      # @since x.x.x
      # @api private
      def configure_repositories(repositories)
        repositories.each do |repository|
          RepositoryConfigurer.call(repository, self)
        end
      end

      # @since 1.0.0
      # @api private
      def method_missing(method_name, *args, &blk)
        if rom.respond_to?(method_name)
          rom.__send__(method_name, *args, &blk)
        else
          super
        end
      end

      # @since 1.1.0
      # @api private
      def respond_to_missing?(method_name, include_all)
        rom.respond_to?(method_name, include_all)
      end
    end
  end
end
