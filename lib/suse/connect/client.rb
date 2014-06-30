require 'net/http'
require 'suse/toolkit/utilities'

module SUSE
  module Connect
    # Client to interact with API
    class Client

      include SUSE::Toolkit::Utilities
      include Logger

      DEFAULT_URL = 'https://scc.suse.com'

      attr_reader :options, :url, :api

      def initialize(opts)
        @config = Config.new

        @options            = opts
        init_url(opts)
        @config.insecure    = opts[:insecure] if opts[:insecure]
        @options[:debug]    = !!opts[:debug]
        @options[:language] = opts[:language] || @config.language
        @options[:token]    = opts[:token] || @config.regcode
        @options[:product]  = opts[:product]
        @api                = Api.new(self)
        log.debug "Merged options: #{@options}"
      end

      def init_url(opts)
        if opts[:url]
          @url = @config.url = opts[:url]
        elsif @config.url
          @url = @config.url
        else
          @url = DEFAULT_URL
        end
      end

      # Activates a product and writes credentials file if the system was not yet announced
      def register!
        announce_if_not_yet
        product = @options[:product] || Zypper.base_product
        service = activate_product(product, @options[:email])
        System.add_service(service)
      end

      # @returns: Empty body and 204 status code
      def deregister!
        @api.deregister(basic_auth)
        System.remove_credentials
      end

      # Announce system via SCC/Registration Proxy
      #
      # @returns: [Array] login, password tuple. Those credentials are given by SCC/Registration Proxy
      def announce_system(distro_target = nil, instance_data_file = nil)
        if instance_data_file
          file_path = SUSE::Connect::System.prefix_path(instance_data_file)
          log.debug "Reading instance data from: #{file_path}"
          raise FileError unless File.file?(file_path) && File.readable?(file_path)
          instance_data = File.read(file_path)
        end
        response = @api.announce_system(token_auth(@options[:token]), distro_target, instance_data)
        [response.body['login'], response.body['password']]
      end

      # Activate a product
      #
      # @param product [SUSE::Connect::Zypper::Product]
      # @returns: Service for this product
      def activate_product(product, email = nil)
        result = @api.activate_product(basic_auth, product, email).body
        Remote::Service.new(result)
      end

      # Upgrade a product
      # System upgrade (eg SLES11 -> SLES12) without regcode
      #
      # @param product [Remote::Product] desired product to be upgraded
      # @returns: Service for this product
      def upgrade_product(product)
        result = @api.upgrade_product(basic_auth, product).body
        Remote::Service.new(result)
      end

      # @param product [Remote::Product] product to query extensions for
      def show_product(product)
        result = @api.show_product(basic_auth, product).body
        Remote::Product.new(result)
      end

      # writes the config file
      def write_config
        @config.write
      end

      # @returns: body described in https://github.com/SUSE/connect/wiki/SCC-API-(Implemented)#response-12 and
      # 200 status code
      def system_services
        @api.system_services(basic_auth)
      end

      # @returns: body described in https://github.com/SUSE/connect/wiki/SCC-API-(Implemented)#response-13 and
      # 200 status code
      def system_subscriptions
        @api.system_subscriptions(basic_auth)
      end

      # @returns: body described in https://github.com/SUSE/connect/wiki/SCC-API-(Implemented)#response-14 and
      # 200 status code
      def system_activations
        @api.system_activations(basic_auth)
      end

      private

      def announce_if_not_yet
        unless System.announced?
          login, password = announce_system(nil, @options[:instance_data_file])
          Credentials.new(login, password, Credentials.system_credentials_file).write
        end
      end

    end

  end

end
